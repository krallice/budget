#!/bin/bash

# Our database to backup:
dbName="navua.db"
dbPath="../html/$dbName"

# Datestamp to append on the end of the backup:
dateStamp=$(date "+%Y%m%d")

# Backup filename:
backupName="../backup/${dbName}.${dateStamp}"

# Copy:
cp -p "$dbPath" "$backupName"

# GZIP:
tar cvfz "${backupName}.tar.gz" "$backupName"
rm -rf "$backupName"

# Purge files older than 6 months:
find "../backup/" -iname "*tar.gz" -mtime +180 | xargs -I{} rm -rf {}
