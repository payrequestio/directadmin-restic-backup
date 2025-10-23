#!/usr/bin/env bash
# Wrapper script for systemd-email to handle environment variables
# This ensures SYSTEMD_EMAIL is properly set before sending notifications

# Validate required argument
if [ -z "$1" ]; then
    echo "Error: Unit name required" >&2
    exit 1
fi

# Source environment if available
if [ -f /etc/restic/env.sh ]; then
    . /etc/restic/env.sh
fi

# Use SYSTEMD_EMAIL from environment, or fall back to default
EMAIL="${SYSTEMD_EMAIL:-admin@example.com}"
UNIT="$1"

# Call the actual systemd-email script
exec /usr/local/sbin/systemd-email "$EMAIL" "$UNIT"
