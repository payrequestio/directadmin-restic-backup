#!/bin/bash

USER="da_admin"
PASSWORD="$(grep passwd= /usr/local/directadmin/conf/mysql.conf | cut -d= -f2)"
BACKUP_RETAIN_DAYS=0   ## Number of days to keep local backup copy
DB_BACKUP_PATH='/home/mysqlbackups'
TODAY=$(date +"%Y%m%d")

#OUTPUT="/Users/rabino/DBs"

if [[ ! -e ${DB_BACKUP_PATH} ]]; then
    mkdir ${DB_BACKUP_PATH}
elif [[ ! -d ${DB_BACKUP_PATH} ]]; then
    echo "${DB_BACKUP_PATH} already exists but is not a directory" 1>&2
fi

find ${DB_BACKUP_PATH} -name '*.zst' -type f -mtime +${BACKUP_RETAIN_DAYS} -exec rm -f {} \;

databases=$(mysql -u "$USER" -p"$PASSWORD" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)

for db in $databases; do
    if [[ "$db" != "information_schema" ]] && [[ "$db" != "performance_schema" ]] && [[ "$db" != "mysql" ]] && [[ "$db" != _* ]] ; then
        echo "Dumping database: $db"
        #mysqldump -u "$USER" -p"$PASSWORD" --databases "$db" | gzip > "${DB_BACKUP_PATH}/${TODAY}.${db}.sql.gz"
        mysqldump -u "$USER" -p"$PASSWORD" --databases "$db" | zstd > "${DB_BACKUP_PATH}/${TODAY}.${db}.sql.zst"
    fi
done
