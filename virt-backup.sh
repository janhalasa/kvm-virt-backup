#!/bin/bash
#

# 
# BACKUP PROCESS:
#
# 1. Mounts a specified disk to a specified folder.
# 2. If the number of already present backups is equal to $MAXBACKUPS, removes the oldest one
# 3. Checks that it has enough disk space (TODO needs improvement)
# 4. Creates snapshots of the disk to be backed up.
# 5. Performs backup
# 6. Commits disk changes since the snapshots were created (blockcommit) and removes diff files
# 7. Backs up the virtual machine XML configuration
#

# Derivated from
# https://gist.github.com/cabal95/e36c06e716d3328b512b

# Path to where the backup disk is to be mounted
BACKUP_MOUNT_DIR="$1"

# Virtual machine name
DOMAIN="$2"

# Max number of backups - older will be deleted before exceeding this number
MAXBACKUPS="$3"

# Disk ID (/dev/disk/by-uuid/*) to mount to the $BACKUP_MOUNT_DIR
DISK="$4"

MIN_DISK_FREE_GB=400

if [ -z "$BACKUP_MOUNT_DIR" -o -z "$DOMAIN" ]; then
    echo "Usage: ./virt-backup <backup-mount-dir> <virt-domain> [max-backups] [disk-id]"
	# Example: ./virt-backup /mnt/disks/backup Windows2019 3 /dev/disk/by-uuid/23CB55D31336F7F3
    exit 1
fi

echo =====================================================================
echo `date`
echo =====================================================================

if [ -z "$MAXBACKUPS" ]; then
    MAXBACKUPS=6
fi

echo "Beginning backup for $DOMAIN"

#
# Generate the backup path
#
BACKUP_TIME=`date "+%Y-%m-%d.%H%M%S"`
DOMAIN_DIR="$BACKUP_MOUNT_DIR/$DOMAIN"
BACKUP_DIR="$DOMAIN_DIR/$BACKUP_TIME"

echo Mounting $BACKUP_MOUNT_DIR
if grep -qs "$BACKUP_MOUNT_DIR " /proc/mounts; then
    echo '...already mounted'
else
    if [ -z "$DISK" ]; then
		mount $BACKUP_MOUNT_DIR
	else
		mount $DISK $BACKUP_MOUNT_DIR
	fi
fi

#
# Delete backups that are too small - probably erroneus
#

BACKUP_MIN_SIZE_MB=100000
echo Removing unsuccessful backups ...
find "$DOMAIN_DIR" -mindepth 1 -maxdepth 1 -type d -exec du -ms {} + | awk "\$1 <= $BACKUP_MIN_SIZE_MB" | cut -f 2- | while IFS= read dir; do
    echo Deleting folder $(du -ms $dir)
    rm -rf $dir
done

#
# Cleanup older backups.
#
echo Cleaning up older backups ...
LIST=`ls -r1 "$DOMAIN_DIR" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'`
i=1
for b in $LIST; do
    if [ $i -gt "$MAXBACKUPS" ]; then
	DIR_TO_REMOVE="$DOMAIN_DIR/$b"
        echo "Removing old backup $DIR_TO_REMOVE"
        rm -rf "$DIR_TO_REMOVE"
    fi

    i=$[$i+1]
done

if [ $(df --output=avail -B 1024000000 $BACKUP_MOUNT_DIR | tail -n 1 | sed 's/[ ]*//'g) -lt $MIN_DISK_FREE_GB ]; then 
    echo There is not enough disk space: $(df -h $DOMAIN_DIR | tail -n 1) $MIN_DISK_FREE_GB GB required
    umount $BACKUP_MOUNT_DIR
    exit 2
fi

echo Creating backup folder $BACKUP_DIR
mkdir -p "$BACKUP_DIR"

#
# Get the list of targets (disks) and the image paths.
#
TARGETS=`virsh domblklist "$DOMAIN" --details | grep file | grep disk | awk '{print $3}'`
IMAGES=`virsh domblklist "$DOMAIN" --details | grep file | grep disk | awk '{print $4}'`

#
# Create the snapshot.
#
DISKSPEC=""
for t in $TARGETS; do
    DISKSPEC="$DISKSPEC --diskspec $t,snapshot=external"
done
# Use --quiesce if you have guest agent running
# virsh dumpxml Windows2019 | grep guest_agent
echo Creating snapshot
echo Diskspec: $DISKSPEC
virsh snapshot-create-as --domain "$DOMAIN" --name backup --no-metadata \
	--atomic --disk-only $DISKSPEC
if [ $? -ne 0 ]; then
    echo "Failed to create snapshot for $DOMAIN"
    umount $BACKUP_MOUNT_DIR
    exit 3
fi

echo Snapshot created

#
# Copy disk images
#
for t in $IMAGES; do
    NAME=`basename "$t"`
    echo Copying image "$t" to "$BACKUP_DIR"/"$NAME"
    cp "$t" "$BACKUP_DIR"/"$NAME"
done
echo Copying finished

#
# Merge changes back.
#
BACKUPIMAGES=`virsh domblklist "$DOMAIN" --details | grep file | grep disk | awk '{print $4}'`
echo Merging backups back
for t in $TARGETS; do
    echo Merging "$t"
    virsh blockcommit "$DOMAIN" "$t" --active --pivot
    if [ $? -ne 0 ]; then
        echo "Could not merge changes for disk $t of $DOMAIN. VM may be in invalid state."
        exit 4
    fi
done
echo Merging finished

#
# Cleanup left over backup images.
#
echo Removing backup images
for t in $BACKUPIMAGES; do
    echo Removing "$t"
    rm -f "$t"
done

#
# Dump the configuration information.
#
echo Dumping XML to "$BACKUP_DIR/$DOMAIN.xml"
virsh dumpxml "$DOMAIN" > "$BACKUP_DIR/$DOMAIN.xml"

echo Unmounting $BACKUP_MOUNT_DIR
umount $BACKUP_MOUNT_DIR

echo "Finished backup"
echo ""
