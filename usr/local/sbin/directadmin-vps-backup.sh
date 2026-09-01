#!/usr/bin/env bash
# Back up a DirectAdmin server with Restic and optionally report status to PayRequest.

set -Ee -o pipefail
source /etc/restic/env.sh

BACKUP_TAG="systemd.timer"
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=3
RETENTION_YEARS=0
B2_CONNECTIONS=50
BACKUP_OUTPUT_FILE=$(mktemp)
BACKUP_REPORTED_SUCCESS=0

cleanup() {
    rm -f "$BACKUP_OUTPUT_FILE"
}

report_backup_status() {
    local status="$1"
    local error_message="${2:-}"
    local summary_json="${3:-{}}"
    local snapshot_count="${4:-null}"
    local repository_bytes="${5:-null}"

    if [[ -z "${PAYREQUEST_BACKUP_TOKEN:-}" || -z "${PAYREQUEST_SERVER_IP:-}" ]]; then
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq is required to report backup status to PayRequest." >&2
        return 0
    fi

    local payload
    if ! payload=$(jq -n \
        --arg ip "$PAYREQUEST_SERVER_IP" \
        --arg status "$status" \
        --arg error "$error_message" \
        --arg restic_version "$(restic version 2>/dev/null | awk '{print $2}' || true)" \
        --argjson summary "$summary_json" \
        --argjson snapshot_count "$snapshot_count" \
        --argjson repository_bytes "$repository_bytes" \
        '{
            ip: $ip,
            status: $status,
            snapshot_id: ($summary.snapshot_id // null),
            snapshot_count: $snapshot_count,
            backup_bytes: ($summary.total_bytes_processed // null),
            repository_bytes: $repository_bytes,
            files_processed: ($summary.total_files_processed // null),
            duration_seconds: ($summary.total_duration // null),
            started_at: ($summary.backup_start // null),
            finished_at: ($summary.backup_end // null),
            restic_version: (if $restic_version == "" then null else $restic_version end),
            error: (if $error == "" then null else $error end)
        }'); then
        echo "Warning: Could not create the PayRequest backup status payload." >&2
        return 0
    fi

    local report_url="${PAYREQUEST_BACKUP_URL:-https://payrequest.app/api/v1/subscriptions/backup-status}"
    local response_code
    response_code=$(curl \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 10 \
        --max-time 30 \
        --request PATCH \
        --header "Authorization: Bearer ${PAYREQUEST_BACKUP_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$report_url" || true)

    if [[ ! "$response_code" =~ ^2[0-9][0-9]$ ]]; then
        echo "Warning: PayRequest backup status report returned HTTP ${response_code:-000}." >&2
    fi

    return 0
}

handle_error() {
    local exit_code=$?
    local line_number="$1"

    trap - ERR

    if [[ "$BACKUP_REPORTED_SUCCESS" -eq 0 ]]; then
        report_backup_status \
            "failed" \
            "Backup command failed with exit code ${exit_code} near line ${line_number}." \
            '{}' \
            'null' \
            'null'
    fi

    exit "$exit_code"
}

exit_hook() {
    echo "Backup interrupted; stopping child processes." >&2
    jobs -p | xargs --no-run-if-empty kill || true
    restic unlock || true
    exit 1
}

trap cleanup EXIT
trap 'handle_error $LINENO' ERR
trap exit_hook INT TERM

if [[ -x /usr/local/sbin/directadmin-cleaner.sh ]]; then
    /usr/local/sbin/directadmin-cleaner.sh &
    wait $!
fi

free_space=$(df --output=avail -B1 / | tail -n 1 | tr -d ' ')
required_space=$(du -sB1 /var/lib/mysql | awk '{print $1}')

if (( free_space < required_space )); then
    echo "Error: Not enough disk space. Available: ${free_space} bytes; required: ${required_space} bytes." >&2
    false
fi

BACKUP_PATHS=(/ /boot /home)
[[ -d /mnt/media ]] && BACKUP_PATHS+=(/mnt/media)

BACKUP_EXCLUDES=(--exclude-file /etc/restic/backup_exclude)
for dir in /home/*; do
    if [[ -f "$dir/.backup_exclude" ]]; then
        BACKUP_EXCLUDES+=(--exclude-file "$dir/.backup_exclude")
    fi
done

bash /usr/local/sbin/mysql.sh &
wait $!

restic unlock &
wait $!

restic backup \
    --json \
    --one-file-system \
    --tag "$BACKUP_TAG" \
    --option "b2.connections=${B2_CONNECTIONS}" \
    "${BACKUP_EXCLUDES[@]}" \
    "${BACKUP_PATHS[@]}" | tee "$BACKUP_OUTPUT_FILE" &
wait $!

restic forget \
    --verbose \
    --tag "$BACKUP_TAG" \
    --option "b2.connections=${B2_CONNECTIONS}" \
    --prune \
    --group-by "paths,tags" \
    --keep-daily "$RETENTION_DAYS" \
    --keep-weekly "$RETENTION_WEEKS" \
    --keep-monthly "$RETENTION_MONTHS" \
    --keep-yearly "$RETENTION_YEARS" &
wait $!

SUMMARY_JSON=$(jq -cs 'map(select(.message_type == "summary")) | last // empty' "$BACKUP_OUTPUT_FILE")
if [[ -z "$SUMMARY_JSON" ]]; then
    echo "Error: Restic completed without a readable JSON summary." >&2
    false
fi

SNAPSHOTS_JSON=$(restic snapshots --no-lock --json --tag "$BACKUP_TAG")
SNAPSHOT_COUNT=$(jq 'length' <<<"$SNAPSHOTS_JSON")
STATS_JSON=$(restic stats --json --mode raw-data)
REPOSITORY_BYTES=$(jq '.total_size // null' <<<"$STATS_JSON")

report_backup_status \
    "success" \
    "" \
    "$SUMMARY_JSON" \
    "$SNAPSHOT_COUNT" \
    "$REPOSITORY_BYTES"
BACKUP_REPORTED_SUCCESS=1

echo "Backup $(hostname) finished successfully; ${SNAPSHOT_COUNT} snapshots are available."

if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    if DISCORD_PAYLOAD=$(jq -n \
        --arg content "Backup $(hostname) finished; ${SNAPSHOT_COUNT} backups are available." \
        '{content: $content}'); then
        curl --silent --show-error \
            --header "Content-Type: application/json" \
            --data "$DISCORD_PAYLOAD" \
            "$DISCORD_WEBHOOK_URL" >/dev/null || true
    fi
fi
