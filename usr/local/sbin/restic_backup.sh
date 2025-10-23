#!/usr/bin/env bash
# Backup script using restic
# This script is typically run by: /etc/systemd/system/directadmin-vps-backup.{service,timer}

# Set all environment variables like
# B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY etc.
source /etc/restic/env.sh

# Run Daily MySQL Backups
bash /usr/local/sbin/mysql.sh &
wait $!

# NOTE start all commands in background and wait for them to finish.
# Reason: bash ignores any signals while child process is executing and thus my trap exit hook is not triggered.
# However if put in subprocesses, wait(1) waits until the process finishes OR signal is received.
# Reference: https://unix.stackexchange.com/questions/146756/forward-sigterm-to-child-in-bash

# Remove locks from other stale processes to keep the automated backup running.
restic unlock &
wait $!

# Do the backup!
# See restic-backup(1) or http://restic.readthedocs.io/en/latest/040_backup.html
# --one-file-system makes sure we only backup exactly those mounted file systems specified in $BACKUP_PATHS, and thus not directories like /dev, /sys etc.
# --tag lets us reference these backups later when doing restic-forget.
restic backup \
        --verbose \
        --one-file-system \
        --tag "$BACKUP_TAG" \
        $BACKUP_EXCLUDES \
        $BACKUP_PATHS &
wait $!

# Dereference and delete/prune old backups.
# See restic-forget(1) or http://restic.readthedocs.io/en/latest/060_forget.html
# --group-by only the tag and path, and not by hostname. This is because I create a B2 Bucket per host, and if this hostname accidentially change some time, there would now be multiple backup sets.
restic forget \
        --verbose \
        --tag "$BACKUP_TAG" \
        --prune \
        --group-by "paths,tags" \
        --keep-daily "$RETENTION_DAYS" \
        --keep-weekly "$RETENTION_WEEKS" \
        --keep-monthly "$RETENTION_MONTHS" \
        --keep-yearly "$RETENTION_YEARS" &
wait $!

# Check repository for errors.
# NOTE this takes much time (and data transfer from remote repo?), do this in a separate systemd.timer which is run less often.
#restic check &
#wait $!

RESTICOUTPUT=$(restic snapshots --repo "${RESTIC_REPOSITORY}")
HOSTNAME=$(hostname)
# Configure email recipient in env.sh by setting BACKUP_EMAIL variable
# Example: export BACKUP_EMAIL="admin@example.com"
if [ -n "${BACKUP_EMAIL:-}" ]; then
    printf "Backup %s has finished, we keep %s each day.\n\n%s" "${HOSTNAME}" "${RETENTION_DAYS}" "${RESTICOUTPUT}" | mail -s "Backup done ${HOSTNAME}" "${BACKUP_EMAIL}"
fi
