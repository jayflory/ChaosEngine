#!/bin/bash
#
# Mount the USB partitions.

/usr/bin/mount /dev/sdb1 /home
/usr/bin/mount /dev/sdb2 /var/log
/usr/bin/mount /dev/sdb3 /var/lib/docker
/usr/bin/mount /dev/sdb4 /var/lib/etcd

exit 0
