## DirectAdmin Restic Backup using S3 Block Storage

# Requirements
* `restic` (latest stable version recommended, minimum v0.9.6)
* `zstd` for MySQL backups
* `git` for installation

## Required: Install Restic

[restic](https://restic.net/) is a command-line tool for making backups.

Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y restic zstd git
```

CentOS/RHEL:
```bash
sudo yum install -y epel-release
sudo yum install -y restic zstd git
```

For the latest version, you can download from the [official releases page](https://github.com/restic/restic/releases).

## Installation Guide for DirectAdmin VPS Backup

The following steps will install the backup scripts and configuration files to system directories.

```bash
git clone https://github.com/payrequestio/directadmin-restic-backup.git
cd directadmin-restic-backup
sudo make install
```


### 1. Configure S3 credentials
Edit `/etc/restic/env.sh` with your S3 bucket settings. The installation will create this file from the template if it doesn't exist.

Required configuration:
* `AWS_ACCESS_KEY_ID`: Your S3 access key
* `AWS_SECRET_ACCESS_KEY`: Your S3 secret key
* `RESTIC_PASSWORD`: Password for encrypting backups
* `RESTIC_REPOSITORY`: S3 repository URL (e.g., `s3:https://s3.amazonaws.com/your-bucket-name`)

Optional configuration:
* `BACKUP_EMAIL`: Email address for backup notifications (used by restic_backup.sh)
* `DISCORD_WEBHOOK`: Discord webhook URL for notifications (used by directadmin-vps-backup.sh)

Once configured, you can source the file to use restic commands easily:
```bash
source /etc/restic/env.sh
restic snapshots    # You don't have to supply all parameters like --repo, as they are now in your environment!
```

### 2. Initialize remote repo
Now we must initialize the repository on the remote end:
```bash
source /etc/restic/env.sh && restic init
```

### 3. Configure backup settings
The installation places these files:
* `/usr/local/sbin/directadmin-vps-backup.sh`: Main backup script. Edit this to customize:
  - Backup paths (default: `/`, `/boot`, `/home`)
  - Retention policy (default: 7 days, 4 weeks, 3 months, 0 years)
  - Discord notifications
* `/etc/restic/backup_exclude`: File patterns to exclude from backups (cache, logs, temporary files, etc.)

You can also create per-user exclusion files at `$HOME/.backup_exclude` for each user.


### 4. Run first backup & verify
Test the backup to ensure everything works:

```bash
/usr/local/sbin/directadmin-vps-backup.sh
source /etc/restic/env.sh
restic snapshots
```

### 5. Enable automatic backups with systemd
The installation includes systemd service and timer units:
* `directadmin-vps-backup.service`: Service that executes the backup script
* `directadmin-vps-backup.timer`: Timer that runs backups daily
* `directadmin-vps-backup-check.service`: Service for checking backup integrity
* `directadmin-vps-backup-check.timer`: Timer that runs checks monthly

Enable and start the backup timer:
```bash
systemctl daemon-reload
systemctl enable --now directadmin-vps-backup.timer
systemctl enable --now directadmin-vps-backup-check.timer
```

### 6. Managing backups

View scheduled backup times:
```bash
systemctl list-timers | grep directadmin-vps-backup
```

Check backup status:
```bash
systemctl status directadmin-vps-backup
```

Start a backup manually:
```bash
systemctl start directadmin-vps-backup
```

View backup logs in real-time:
```bash
journalctl -f -u directadmin-vps-backup.service
```

View all backup logs:
```bash
journalctl -u directadmin-vps-backup.service
```

## Additional Scripts

This repository includes additional helper scripts:
* `restic_backup.sh`: Alternative backup script with email notifications
* `restic_check.sh`: Repository integrity check script
* `mysql.sh`: MySQL database backup script (dumps to `/home/mysqlbackups` with zstd compression)

## Troubleshooting

If you encounter issues:
1. Check that restic is properly installed: `restic version`
2. Verify your S3 credentials in `/etc/restic/env.sh`
3. Test repository access: `source /etc/restic/env.sh && restic snapshots`
4. Review service logs: `journalctl -u directadmin-vps-backup.service`
5. Ensure sufficient disk space for MySQL dumps and temporary files

