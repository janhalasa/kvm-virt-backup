# kvm-virt-backup
Bash script for backing up KVM virtual machines

## Backup process

1. Mounts a specified disk to a specified folder.
2. If the number of already present backups is equal to $MAXBACKUPS, removes the oldest one
3. Checks that it has enough disk space (TODO needs improvement)
4. Creates snapshots of the disk to be backed up.
5. Performs backup
6. Commits disk changes since the snapshots were created (blockcommit) and removes diff files
7. Backs up the virtual machine XML configuration
