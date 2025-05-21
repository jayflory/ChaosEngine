# Chaos Engine - Storage Nodes

## Overview

The storage nodes are designed to work with two USB drives on each node. They provide the primary read/write storage for the entire cluster.  They run the following services:

| Service | Purpose | Nodes |
| --- | --- | --- |
| Gluster | Storage that can be mounted on the Kubernetes Nodes | etcd1, etcd2, etcd3 |
| etcd | Key/Value store for Kubernetes | etcd1, etcd2, etcd3 |
| Syslog | Receive Syslog network packets from Kubernetes Nodes | etcd3 |

![Storage Nodes](./storagenode.drawio.svg)

## Hardware

The storage nodes each connect two USB external hard drives.  I found that the RaspBerry Pi board would not power the 2.5 inch drives that I am using.  To power the drives, I purchased split USB cables.  The split USB have an "extra" connector that can be connected to an external USB power supply.

Two USB drives:

| Drive | Size | Use |
| --- | --- | --- |
| /dev/sda | 2TB | Storage for Kubernetes.  It is used as part of Gluster services providing storage claims for Kubernetes pods. |
| /dev/sdb | 1TB | Storage for local use and also log data from the cluster. |

## X509 Certificates

Before configuring the storage nodes, it is necessary to create a series of x509 certificates for use by etcd and Kubernetes.  To assist in this step a batch file has been included called CreateCertificates.sh.  It requires the "files" subdirectory and the "openssl.cnf" file.  It will generate the certificates required by the Ansible recipes.

Certificates created:

| Certificate | Key | Type | Use Case |
| --- | --- | --- | --- |
| ca.crt | ca.key | Self signed root certificate. | Used as a root certificate for signing other certificates.  Essentially this is your own self signed root certificate |
| etcd1.cert | etcd1.key | Etcd server key | Used to uniquely define the Etcd service on etcd1 |
| etcd2.cert | etcd2.key | Etcd server key | Used to uniquely define the Etcd service on etcd2 |
| etcd3.cert | etcd3.key | Etcd server key | Used to uniquely define the Etcd service on etcd3 |
| etcd-client.crt | etcd-client.key | Client access | Generic certificate to be included with clients needing to communicate with the Etcd service |

## Ansible

Ansible is used to to automatically configure the nodes.  With all storage nodes listed in the StorageNodes.txt file, run the following command to apply the Ansible configuration:

```bash
ansible-playbook -i StorageNodes.txt -u ubuntu -K StorageNodes.yaml
```

> [!IMPORTANT]
> Before running the Ansible playbook please create the required certificates.  Please read the section on Etcd to create the certificates.

## OS

Each Kubernetes node is loaded with Ubuntu 20.04.6 LTS on a 32 GB Samsung MicroSD.  I selected the basic Ubuntu server model and applied my preferred username password on the nodes.  As above I used the "ubuntu" username for the primary login user.

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

```bash
sudo apt-get remove -y cloud-init apparmor plymouth unattended-upgrades avahi-daemon lvm2 snapd nodemanager
```

The following packages were installed: net-tools, glusterfs-server.

```bash
sudo apt-get install -y net-tools glusterfs-server
```

> [!NOTE]
> The etcd service is installed from a downloaded package and will be installed in a separate step.

### Cron Jobs

The USB drive on Ubuntu will be auto unloaded when the USB drives have not been used for a while.  Unfortunately, this breaks Gluster.  To prevent the USB drives from being unloaded, two entries in /etc/crontab were added.

```text
*/5 *   * * *   root    /bin/touch /dev/sda &> /dev/null
*/5 *   * * *   root    /bin/touch /dev/sdb &> /dev/null
```

Every 5 minutes, Cron will run "touch" against each USB disk.  This keeps the USB driver from unloading.

> [!NOTE]
> I did try to modify the kernel startup as well to prevent the driver from unloading, however this proved to not work.

I found that the "systemd-resolved" service was occasionally stopping.  To ensure it was always running I added the following to /etc/crontab

```text
*/5 *   * * *   root    /usr/bin/systemctl start systemd-resolved.service
```

### Partitions

The following partitions were created on /dev/sdb.

| Partition | Mount Point | Size | Use Case |
| --- | --- | --- | --- |
| /dev/sdb1 | /home | 100GB | For anything needed by local users.  This is often useful for staging files. |
| /dev/sdb2 | /var/log | 100GB | This should be mounted prior to the Syslog service being started.  This helps preserve the MicroSD |
| /dev/sdb3 | /var/lib/docker | 100GB | Stores docker containers if you use Docker on the node. |
| /dev/sdb4 | /var/lib/etcd | 100GB | Storage for the Etcd service.  Helps prevent wear on the MicroSD |
| /dev/sdb5 |  | LVM | LVM physical volume. |
| /dev/sda1 | /var/log/KubeStorage | Full Disk | Used to provide the storage for Kadalu StorageClass |

You can use "parted" to create the partitions, however it is beyond the scope of this document to describe the process of creating partitions.

Details:

1. Disk Label:  GPT
2. All partitions are Primary.
3. Partitions 1 through 4 are formatted with ext4
4. Partition /dev/sda1 is formatted with XFS

> [!NOTE]
> The /dev/sda disk is not partitioned as it will be used directly with LVM as a physical volume.

### Volume Groups

The following logical volumes were created:

| Logical Volume | Size | Name | Use |
| --- | --- | --- | --- |
| /dev/sdb5 | 600GB | pi_logs | Used to provide shares for Kubernetes node logs |

To create the pi_logs physical volume:

```bash
pvcreate /dev/sdb5
```

> [!NOTE]
> The /dev/sda1 partition will be the primary storage for Kubernetes Pods

### Logical Volumes

The following 25GB logical volumes are created on the pi_logs volume group:

| Volume | Kubernetes Node |
| --- | --- |
| brick1 | Node pi1 |
| brick2 | Node pi2 |
| brick3 | Node pi3 |
| brick4 | Node pi4 |
| brick5 | Node pi5 |
| brick6 | Node pi6 |
| brick7 | Node pi7 |
| brick8 | Node pi8 |
| brick9 | Node pi9 |
| brick10 | Node pi10 |

To create them and format the volumes with ext4:

```bash
for i in {1..10}; do lvcreate --size 25g -n brick$i pi_logs; done;
for i in {1..10}; do mkfs.ext4 /dev/pi_logs/brick$i; done;
```

### Mounting Services

I chose to implement the mounting of the various directories as SystemD services rather than "mounts".  This gave me control over the process and allowed me to use some automated scripts.  Each of the mounting services checks to ensure that the usb_storage module is loaded before the mounting script runs.  In addition they are configured to start before dependent services can start.

| Service | Script | Before | Purpose |
| --- | --- | --- | --- |
| basic-mounts | /usr/sbin/basic-mounts.sh | glusterd.service etcd.service syslog.service | Mounts /home /var/log /var/lib/docker /var/lib/etcd |
| log-mounts | /usr/sbin/log-mounts.sh | glusterd.service etcd.service | Mounts all of the bricks for use with Kubernetes Nodes logs |
| kadalu-mounts | | glusterd.service | Mounts the brick for Kadalu shares used by Kubernetes to provide pod storage |

## ETCD

### Installation

Installing the Etcd service requires a multi-step process.

Ansible:

1. Download Etcd.
2. Store it in the StorageNodes/files directory for use with Ansible.
3. Set the version in the Ansible recipe.

Manual:

1. Download Etcd.
2. Decompress the archive.
3. Find the etcd and etcdctl executable files and copy them to /usr/local/bin on each of the storage nodes.

Commands to download etcd:

```bash
ETCD_VER=v3.4.37
DOWNLOAD_URL=https://storage.googleapis.com/etcd
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-arm64.tar.gz -o ./etcd-${ETCD_VER}-linux-arm64.tar.gz
```

### User

Create an etcd group

```bash
groupadd --system etcd -g 998
```

Create an etcd user

```bash
useradd -s /sbin/nologin --system -g etcd -u 18407 etcd
```

### Directories

I have chosen to use the following directories with the Etcd service:

| Directory | Purpose |
| --- | --- |
| /home/etcd | The security certificates |
| /var/lib/etcd | The Etcd database files for the key/value store |

### Files

Each node requires several X509 certificates.  The following certificates are needed.

| File | Type | Use |
| --- | --- | --- |
| ca.crt | Root Certificate | Self signed root certificate used to authenticate other certificates |
| etcd{{ NODE }}.crt | Service certificate | The unique certificate that identifies the Etcd service on the node |
| etcd{{ NODE }}.key | Service certificate Key | The key for the Etcd certificate |
| etcd-client.crt | Client certificate | A general client certificate that can be used by etcdctl or Kubernetes to query the Etcd service |
| etcd-client.key | Client certificate key | The certificate key for the general client certificate |

To create the certificates run:

```bash
cd {{ directory where you downloaded the Git project }}
./StorageNodes/CreateCertificates.sh
```

The above script will place the certificates in the StorageNodes/files subdirectory.

1. Copy the ca.crt file to all of the storage nodes in /home/etcd
2. Copy both the etcd-client.crt and etcd-client.key to all of the storage nodes in /home/etcd
3. Copy the node specific etcd{{ NODE }}.crt and etcd{{ NODE }}.key to the specific nodes in /home/etcd.

Verify that the file permissions are correct in the /home/etcd directory:

| File | owner:group | Permissions |
| --- | --- | --- |
| ca.crt | etcd:etcd | 0644 |
| etcd{{ NODE }}.crt | etcd:etcd | 0644 |
| etcd{{ NODE }}.key | etcd:etcd | 0400 |
| etcd-client.crt | ubuntu:ubuntu | 0644 |
| etcd-client.key | ubuntu:ubuntu | 0400 |

Next set the ownership in the /var/lib/etcd directory:

```bash
chmod -R etcd:etcd /var/lib/etcd
```

### Service

The Etcd service is configured to be started by SystemD.  The service is started under the "etcd" user with some environment variables set.

| Environment Variable | Setting | Notes |
| --- | --- | --- |
| ETCD_DATA_DIR | /var/lib/etcd | Defines where the etcd data is stored |
| ETCD_NAME | etcd{{ NODE }} | Defines the local services node name |
| ETCD_UNSUPPORTED_ARCH | arm64 | Allows Etcd to run in "unsupported" mode on the Raspberry Pi |

The start up command is:

```text
/usr/local/bin/etcd \
 --initial-advertise-peer-urls=https://{{ Local IP }}:2380 \
 --listen-peer-urls=https://{{ Local IP }}:2380 \
 --listen-client-urls=https://{{ Local IP }}:2379 \
 --advertise-client-urls=https://{{ Local IP }}:2379 \
 --initial-cluster-token=etcd-cluster-1 \
 --initial-cluster etcd1=https://192.168.1.40:2380,etcd2=https://192.168.1.41:2380,etcd3=https://192.168.1.42:2380 \
 --client-cert-auth --trusted-ca-file=/home/etcd/ca.crt \
 --cert-file=/home/etcd/etcd{{ NODE }}.crt --key-file=/home/etcd/etcd{{ NODE }}.key \
 --peer-client-cert-auth --peer-trusted-ca-file=/home/etcd/ca.crt \
 --peer-cert-file=/home/etcd/etcd{{ NODE }}.crt --peer-key-file=/home/etcd/etcd{{ NODE }}.key \
 --initial-cluster-state=new \
 --heartbeat-interval=1000 \
 --election-timeout=5000
```

## Gluster

The Gluster service is relatively simple and doesn't require modifications.  The only configuration needed is to create the volumes.

To create the log volumes:

```bash
for i in {1..10}; do gluster volume create pi$i replica 3 transport tcp etcd1:/var/logs/pi_logs/brick$i etcd2:/var/logs/pi_logs/brick$i etcd3:/var/logs/pi_logs/brick$i force; gluster volume start etcd$i; done;
```

To create the KubeStorage volume:

```bash
gluster volume create KubeStorage replica 3 transport tcp etcd1:/var/logs/KubeStorage etcd2:/var/logs/KubeStorage etcd2:/var/logs/KubeStorage force
gluster volume start KubeStorage
gluster volume quota KubeStorage enable
```

> [!NOTE]
> The "force" parameter is used allow Gluster to use the direct mount point.  The Kadalu storage class needs the quota system enabled on the volume.
