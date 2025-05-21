#!/bin/bash
#
# Start the dockerized HAProxy service

# Start docker service if not started
if ! /usr/bin/docker ps | grep -q "haproxy:latest"; then
  # Docker is not already started
  /usr/bin/docker run -d --rm --network lb-network --mac-address 02:42:ac:8f:4c:ff --ip=192.168.1.60 \
    -v /var/log/haproxy/run:/run/haproxy -v /var/log/haproxy:/usr/local/etc/haproxy:ro haproxy:latest
  sleep 4;
  if ! /usr/bin/docker ps | grep -q "haproxy:latest"; then
    # Failed to start the HAProxy service
    echo "Failed to start the Docker container!"
    exit 1
  fi
fi
/bin/sleep 4

# Create the Hair Pin turn around required to talk to the proxy locally
if ! ip link sh foobar > /dev/null 2>&1; then
  /usr/sbin/ip link add foobar link eth0 type macvlan mode bridge;
  /usr/sbin/ip addr add 192.168.1.222/32 dev foobar;
  /usr/sbin/ip link set foobar up;
  /usr/sbin/ip route add 192.168.1.60/32 dev foobar;
  if ! ip link sh foobar > /dev/null 2>&1; then
    echo "Failed to create the IP hairping route!"
    exit 1
  fi
fi

exit 0