# Chaos Engine - Work Nodes

## Overview

The work nodes are designed to be the primary nodes for the cluster.  They are designed to run Docker and Kubernetes.

![Kubernetes Work Node](kubenode.drawio.svg)

A primary goal of the design is to preserve the MicroSD cards from excess writes.  As Kubernetes is known to be rather noisy with logs, several steps are taken to redirect log writes away from the nodes themselves. These steps are:

1. Configure the rsyslog daemon to send log traffic to a central log device.
2. Mount a remote Gluster share to /var/log for other logging traffic.

> [!IMPORTANT]
> Kubernetes can quickly wear out your MicroSD cards with excessive log writes

In addition, I have chosen to use a "multi" controller Kubernetes model.  For this to work, I have chosen a single node, node "pi5", to run a Docker container instance of HAProxy.  This will be done to allow load balancing with the controllers.

## Ansible

Ansible is used to to automatically configure the nodes.  There are two Ansible configuration files:

1. KubeNodes.yaml - for all nodes
2. ProxyNode.yaml - for the node running HAProxy

> [!IMPORTANT]
> Before running Ansible, you will need to download the CRI Docker tar ball.  Please reference the section on Docker.  In addition you will need to have generated the Etcd certificates from the Storage Node "readme.md" file.

With all Kubernetes nodes listed in the KubeNodes.txt file, run the following command to apply the Ansible configuration:

```bash
ansible-playbook -i KubeNodes.txt -u ubuntu -K KubeNodes.yaml
```

To apply the configuration for the HAProxy service run the the following command:

```bash
ansible-playbook -i ProxyNode.txt -u ubuntu -K ProxyNode.yaml
```

> [!NOTE]
> Both commands will prompt you for the password to become root.

## OS

Each Kubernetes node is loaded with Ubuntu 24.04.2 LTS on a 32 GB Samsung Endurance MicroSD.  I selected the basic Ubuntu server model and applied my preferred username password on the nodes.  As above I used the "ubuntu" username for the primary login user.

> [!WARNING]
> I tried many MicroSD cards that did not work with the Raspberry Pi 4Bs that I am using.  Please verify compatibility before buying any particular model.

### Packages

Ubuntu comes with many packages that are not needed.

```text
cloud-init
apparmor
plymouth
unattended-upgrades
avahi-daemon
lvm2
snapd
nodemmanager
```

> [!IMPORTANT]
> Though not needed for my small cluster, the "apparmor" package will be reinstalled with the "docker.io" package.  For some reason the "apparmor" package was not where it was supposed to be in the Ubuntu repositories.  You will want to make sure you have a copy of the package rpm as it might be necessary later.  Alternatively, install "docker.io" before removing the "apparmor" package.

```bash
sudo apt-get remove -y cloud-init apparmor plymouth unattended-upgrades avahi-daemon lvm2 snapd nodemanager
```

### Kernel

To run Docker etc, we need to modify the kernel parameters.  On the nodes, we need the following parameters added:

```text
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
```

You will need to add them the kernel line in /boot/firmware/cmdline.  My file looks like:

```text
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory`
```

### Disable the Swap partition

To help preserve the lifetime of the MicroSD, I have chosen to disable the swap partitions permanently.

```bash
sudo systemctl stop swap.target
sudo systemctl disable swap.target
```

## Syslog

The MicroSD cards used in the cluster have a limited write lifetime.  In order to help preserve the lifetime of the cards I have configured the Syslog system to minimize writes to the the MicroSD.

### Daemon rsyslog

First I modified the configuration of the rsyslog daemon such that it does not write to the MicroSD but rather will send all log information over UDP to 192.168.1.42, etcd3.

1. Remove all files in /etc/rsyslog.d/
2. Add file 10-all.conf to /etc/rsyslog.d/

The contents of the file are:

```text
# Forward all messages to the remote log server
*.* @192.168.1.42
```

### Log Mount

In addition, I am mounting a remote Gluster share to /var/log.  Any application or service that writes to /var/log directly will be writing to the remote share.

The Mount is configured as a SystemD service.  A "service" was used instead of a normal mount, to help facilitate the correct startup and mounting procedures.  To create the service create a file /etc/systemd/system/var-log.service and add the following:

```text
[Unit]
Description=Mount unit for var-log over gluster
Requires=network-online.target
After=network-online.target
Before=syslog.service

[Service]
Type=simple
RemainAfterExit=yes
ExecStartPre=/usr/sbin/modprobe fuse
ExecStart=/bin/bash -c '/bin/sleep 4 ; exitCode=1; exitCode="$(/usr/bin/mount -t glusterfs -o log-level=NONE,backup-volfile-servers=etcd2:etcd3 etcd1:/pi1 /var/log)" ; /bin/sleep 4 ; if /bin/grep -q -P "/var/log" /proc/mounts; then exit 0; else exit 1; fi;'
Restart=on-failure
RestartSec=8

[Install]
WantedBy=syslog.service
WantedBy=multi-user.target
```

> [!NOTE]
> In order to vary which gluster node a specific node connects to, within Ansible I am using a template and a dictionary defining which Gluster nodes are secondary and which is primary for any specific work node.

## Docker

Docker was chosen as the containerization system to be used on the nodes.  Basically, I chose the simplest to use and most widely available container system.

### Install and Configure Docker

Install Docker package docker.io:

```bash
sudo apt-get install docker.io
```

> [!NOTE]
> This will reinstall the "apparmor" package.  I had some difficulty with this package as it doesn't appear to be available in the Ubuntu repositories.  After installing "docker.io", you can remove the "apparmor" package.

Modify the /etc/docker/daemon.json file as follows:

```yaml
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
```

### Install CRI-Docker Package

In order to work with Kubernetes, the CRI interface between Docker and Kubernetes must be installed.  This package is not provided in the repositories and must be installed manually.

Download the prebuilt tar [ball](https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.17/cri-dockerd-0.3.17.arm64.tgz)

Unzip the tar ball:

```bash
tar xzvf cri-dockerd-0.3.17.arm64.tgz
cd cri-dockerd
```

Install the package:

```bash
install -o root -g root -m 0755 cri-dockerd /usr/local/bin/cri-dockerd
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket
install cri-docker.service /etc/systemd/system
install cri-docker.socket /etc/systemd/system
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service

systemctl daemon-reload
systemctl enable --now cri-docker.socket
systemctl enable cri-docker
systemctl start cri-docker
systemctl status cri-docker
```

## Kubernetes

And finally we install Kubernetes.

### Add Kubernetes Repository

Before installing Kubernetes, we will need to add the Apt repositories for accessing the official Kubernetes repositories.

Download and install the GPG key

```bash
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Add the repository

```bash
sudo echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### Install Kubernetes

Install Kubernetes packages:  kubelet kubeadm

```bash
sudo apt-get install kubelet kubeadm
```

### Files

The Kubernetes service requires the Etcd client certificates for signing communications with the Etcd services.  The following files are needed.

| Source | Destination | Permissions |
| --- | --- | --- |
| StorageNodes/files/etcd-client.crt | /etc/kubernetes/client.crt | 0644 |
| StorageNodes/files/etcd-client.key | /etc/kubernetes/client.key | 0600 |
| StorageNodes/files/ca.crt | /etc/kubernetes/ca.crt | 0644 |

## HAProxy

The HAProxy service is used to provide a single IP address and load balancing multiple Kubernetes controllers.  I chose to run HAProxy as a container.  This required a bit of configuration for it to run as a separate IP address and MAC address than is used by the Raspberry Pi.  I chose to run this on the Kubernetes node "pi5".

### Docker Network

Add a MacVlan network, name "lb-network" to the Docker configuration:

```bash
sudo docker network create -d macvlan --subnet=192.168.1.0/24 --gateway=192.168.1.1 -o parent=eth0 lb-network
```

### Pull the HAProxy image

While not strictly required, I thought it best to pull the HAProxy image in a separate step.  This avoids any issues with the first time the service starts.

```bash
sudo docker pull haproxy
```

### HAProxy Configuration

The configuration for the proxy server is stored on pi5 in file /var/log/haproxy/run/haproxy.cfg.  This file is create in the Ansible recipe.

### Create a Start Up Script

To easily start the HAProxy and do the house keeping required after startup, I created a script.  The script was saved in /usr/sbin/haproxy_start.sh.  The contents are:

```text
#!/bin/bash
#
# Start the dockerized HAProxy service

# Start docker service if not started
if ! /usr/bin/docker ps | grep -q "haproxy:latest2"; then
  # Docker is not already started
  /usr/bin/docker run -d --rm --network lb-network --mac-address 02:42:ac:8f:4c:ff --ip=192.168.1.60 \
    -v /var/log/haproxy/run:/run/haproxy -v /var/log/haproxy:/usr/local/etc/haproxy:ro haproxy:latest
  sleep 4;
  if ! /usr/bin/docker ps | grep -q "haproxy:latest2"; then
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
```

There are two parts to the script.  The first part starts the Docker container attaching it to the correct "lb-network" and assigning the MAC address and IP address.

The second part of the script creates a "Hair Pin" route on the local node.  This is required in order for the local node to itself reach the proxy.

Please note the mounts used when the Docker container runs:

| Source Directory | Destination Directory |
| --- | --- |
| /var/log/haproxy | /usr/local/etc/haproxy |
| /var/log/haproxy/run | /run/haproxy |

### Configure SystemD service

To automate the startup of the service, I choose to create a SystemD service to start HAProxy automatically. Create a file /etc/systemd/system/docker_haproxy.service:

```text
[Unit]
Description=Start HAProxy container
Requires=docker.service
After=docker.service

[Service]
Type=simple
RemainAfterExit=yes
ExecStart=/usr/sbin/haproxy_start.sh
StandardOutput=null
StandardError=journal
Restart=on-failure
RestartSec=8

[Install]
WantedBy=multi-user.target
```

Finally you can reload SystemD, enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable docker_proxy.service
sudo systemctl start docker_proxy.service
```
