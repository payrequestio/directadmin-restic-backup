# S3 ID & KEY
export AWS_ACCESS_KEY_ID="ID"
export AWS_SECRET_ACCESS_KEY="Key"

# Password
export RESTIC_PASSWORD="password"

# Repo
export RESTIC_REPOSITORY="s3:https://ams1.vultrobjects.com/m"

# Optional PayRequest backup status reporting.
# Create a PayRequest API token with only the backups.write scope.
export PAYREQUEST_BACKUP_TOKEN=""
export PAYREQUEST_SERVER_IP=""
export PAYREQUEST_BACKUP_URL="https://payrequest.app/api/v1/subscriptions/backup-status"

# Optional Discord success notification.
export DISCORD_WEBHOOK_URL=""
