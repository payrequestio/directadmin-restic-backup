## Directadmin Restic Backup using S3 Block Storage

# Requirements
* `restic >=v0.17.0` (JSON summaries and repository statistics)
* `zstd:  for mysql backups`
* `jq`: parses Restic JSON output and creates status reports
* `curl`: sends optional PayRequest and Discord status reports

## Required: Install Restic

[restic](https://restic.net/) is a command-line tool for making backups.

Ubuntu:
```bash
$ apt-get install restic git jq curl zstd

sudo apt-get update && sudo apt-get install -y software-properties-common && sudo add-apt-repository -y ppa:copart/restic && sudo apt-get update && sudo apt-get install -y restic git jq curl zstd
````

CentOS:
```bash
$ yum install yum-plugin-copr jq curl zstd && yum copr enable copart/restic && yum install restic git

sudo apt-get update && sudo apt-get install -y software-properties-common && sudo add-apt-repository -y ppa:copart/restic && sudo apt-get update && sudo apt-get install -y restic git jq curl zstd
````

## Installguide Directadmin VPS Backup

Tip: The steps in this section will instruct you to copy files from this repo to system directories.

```bash
$ git clone https://github.com/payrequestio/directadmin-restic-backup.git
$ cd directadmin-restic-backup
$ sudo make install
````


### 1. Configure S3 credentials
Put these files in `/etc/restic/`:
* `env.sh`: Fill this file out with your S3 bucket settings. The reason for putting these in a separate file is that it can be used also for you to simply source, when you want to issue some restic commands. For example:
```bash
$ source /etc/restic/env.sh
$ restic snapshots    # You don't have to supply all parameters like --repo, as they are now in your environment!
````

#### Optional: report backup status to PayRequest

Create a personal API token in PayRequest with only the `backups.write` scope. The server IP must match a unique `ip`, `IP`, `ip_address`, or `server_ip` custom field on one of your subscriptions.

Add these values to `/etc/restic/env.sh`:

```bash
export PAYREQUEST_BACKUP_TOKEN="your-token"
export PAYREQUEST_SERVER_IP="203.0.113.10"
export PAYREQUEST_BACKUP_URL="https://payrequest.app/api/v1/subscriptions/backup-status"
```

After every run, the script reports the result, latest snapshot size, retained snapshot count, repository size, file count, and duration. Reporting is optional and non-blocking: an unavailable PayRequest API does not fail the Restic backup.

Never commit the populated `/etc/restic/env.sh` file or expose its API token in logs.

### 2. Initialize remote repo
Now we must initialize the repository on the remote end:
```bash
source /etc/restic/env.sh && restic init
```

### 3. Script for doing the backup
Put this file in `/usr/local/sbin`:
* `directadmin-vps-backup.sh`: A script that defines how to run the backup. Edit this file to respect your needs in terms of backup which paths to backup, retention (number of backups to save), etc.

Put this file in `/`:
* `.backup_exclude`: A list of file pattern paths to exclude from you backups, files that just occupy storage space, backup-time, network and money.


### 4. Make first backup & verify
Now see if the backup itself works, by running

```bash
$ /usr/local/sbin/directadmin-vps-backup.sh
$ restic snapshots
````

### 5. Backup automatically; systemd service + timer
Now we can do the modern version of a cron-job, a systemd service + timer, to run the backup every day!


Put these files in `/etc/systemd/system/`:
* `directadmin-vps-backup.service`: A service that calls the backup script.
* `directadmin-vps-backup.timer`: A timer that starts the backup every day.


Now simply enable the timer with:
```bash
$ systemctl start directadmin-vps-backup.timer
$ systemctl enable directadmin-vps-backup.timer
````

You can see when your next backup is scheduled to run with
```bash
$ systemctl list-timers | grep directadmin-vps-backup
```

and see the status of a currently running backup with

```bash
$ systemctl status directadmin-vps-backup
```

or start a backup manually

```bash
$ systemctl start directadmin-vps-backup
```

You can follow the backup stdout output live as backup is running with:

```bash
$ journalctl -f -u directadmin-vps-backup.service
````

(skip `-f` to see all backups that has run)
