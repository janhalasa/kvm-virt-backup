#!/bin/bash
#

# Backs up the oldest folder from $BACKUPSRC/$DOMAIN to $BACKUPDEST/$DOMAIN
# The folder must match a pattern specified later in the script

#BACKUPDEST="$1"
#DOMAIN="$2"
#MAXBACKUPS="$3"

BACKUPSRC="/mnt/backups/windows-main"
BACKUPDEST="/mnt/backups/windows-long"
DOMAIN="Windows2019"
MAXBACKUPS="3"
TARGETS=sda
#DISK=/dev/disk/by-uuid/23CB55D31336F7F3

echo =====================================================================
echo `date`
echo =====================================================================

echo "Starting backup for $DOMAIN"

#
# Generate the backup path
#
BACKUPDOMAIN="$BACKUPDEST/$DOMAIN"
BACKUP="$BACKUPDOMAIN/$BACKUPDATE"

#echo Mounting /mnt/disks/backup
#if grep -qs '/mnt/disks/backup ' /proc/mounts; then
#    echo '...already mounted'
#else
#    mount $DISK /mnt/disks/backup
#fi

#
# Delete backups that are too small - probably erroneus
#

BACKUP_MIN_SIZE_MB=300000
echo Removing unsuccessful backups ...
find "$BACKUPDOMAIN" -mindepth 1 -maxdepth 1 -type d -exec du -ms {} + | awk "\$1 <= $BACKUP_MIN_SIZE_MB" | cut -f 2- | while IFS= read dir; do
    echo Deleting folder $(du -ms $dir)
    rm -rf $dir
done

echo "Searching for the oldest backup in $BACKUPSRC"
OLDESTBACKUP=$(ls -t1 $BACKUPSRC/$DOMAIN | tail -n 1)

OLDESTBACKUP_SIZE=$(du -s --block-size=G $BACKUPSRC/$DOMAIN/$OLDESTBACKUP | sed -E 's/([0-9]*)G.*/\1/')
echo "Oldest backup is $OLDESTBACKUP of size $OLDESTBACKUP_SIZE GB"

SPACE_AVAIL=$(df --output=avail -B 1024000000 $BACKUPDEST | tail -n 1 | sed 's/[ ]*//'g)

#
# Cleanup older backups.
#
echo "Cleaning up older backups if not enough space ($SPACE_AVAIL GB) ..."
while [ $SPACE_AVAIL -lt $OLDESTBACKUP_SIZE ]; do
    LIST=`ls -r1 "$BACKUPDOMAIN" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'`
    i=1
    for b in $LIST; do
        if [ $i -gt "$MAXBACKUPS" ]; then
            DIR_TO_REMOVE="$BACKUPDOMAIN/$b"
            echo "Removing old backup $DIR_TO_REMOVE"
            rm -rf "$DIR_TO_REMOVE"
        fi
        i=$[$i+1]
    done
done

BACKUP_TO_COPY=$BACKUPSRC/$DOMAIN/$OLDESTBACKUP

echo "Copying $BACKUP_TO_COPY to $BACKUPDEST/$DOMAIN"
cp -r $BACKUP_TO_COPY $BACKUPDEST/$DOMAIN

# echo Unmounting /mnt/disks/backup/
# umount /mnt/disks/backup/

echo "Backup finished"
echo ""

