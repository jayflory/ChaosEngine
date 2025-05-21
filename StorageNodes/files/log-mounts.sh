#!/bin/bash
#
# Mount the LVS log mounts

for i in {1..10}; do 
  mkdir -p /var/logs/pi_logs/brick$i
  /usr/bin/mount /dev/pi_logs/brick$i /var/logs/pi_logs/brick$i
done;
exit 0