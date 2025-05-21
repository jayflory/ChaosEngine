# Chaos Engine

## Introduction

The Chaos Engine is a Kubernetes setup designed around Raspberry Pis.  The goal of the design is to have a useful system to be used as a home laboratory.  Not only are we studying Kubernetes, but the cluster will actually be useful for studying Linux and other topics using Kubernetes.

The design of the cluster is divided into three parts, two hardware and then the Kubernetes configuration itself.  As this is a layered approach, it is necessary to complete each layer of the design in order starting with the storage systems.

![Chaos Engine](chaosengine.drawio.svg)

A primary goal of the design is to preserve the MicroSD storage used in the Raspberry Pis.  A significant part of the design is moving the logs away from being stored locally to the storage nodes.

Nodes:

| Nodes | Names | Count |
| --- | --- | --- |
| Storage Nodes | etcd[1-3] | 3 |
| Work Nodes | pi[1-10] | 10 |

> [!NOTE]
> While the etcd service is installed on the storage nodes, it's configuration will be covered as part of documentation on Kubernetes.

The documentation, or "md" files, in the each sections describes how the nodes are configured.  You will find specific commands, descriptions and some code to help you reproduce the design.  Where appropriate, Ansible configuration files are included to help automate the deployment of specific nodes.

## Storage

The storage nodes provide file storage to the whole cluster.  Each storage node is connected with two USB external hard drives.  These nodes provide the following services to cluster:

| Service | Nodes | Notes |
| --- | --- | --- |
| Gluster | All Nodes | Primary remote file system.  The processing nodes will use these for log files.  Kubernetes with Heketi will use Gluster for providing file shares to containers. |
| etcd | Three Nodes | Provides storage for the Kubernetes configuration and state database. |
| Syslog | Single node. | Provides a log storage that is stored on the USB drives. |

> [!IMPORTANT]
> The USB drives I used required a special "split" cable to power properly.  This is because the Raspberry Pis could not power the 2.5 inch USB drives.

## Work Nodes

These nodes provide the primary nodes that Kubernetes will run on.  As they rely on storage being available, the storage nodes will need to be up and running before the work nodes can be started.

I also chose to host a simple HAProxy load balancer on a single work node.  The load balancer is used to connect to the three Kubernetes controllers.

## Kubernetes

The Kubernetes configuration consists of the 10 nodes. The services running:

| Service | Nodes |
| --- | --- |
| Kubernetes | pi[1-10] |
| HAProxy | pi5 |
| Etcd | etcd[1-3] |

Kubernetes Components

| Component | col2 | col3 |
| --- | --- | --- |
|  Controllers | pi1, pi4, pi7 | These are the primary controllers for the cluster.  I chose the redundancy even on this small cluster. |
| CNI - Plugin | ? | To be chosen |
| Heketi | ? | The storage add on that allows Kubernetes to talk to Gluster on the storage nodes.  This implements the standard storage semantics so that you can create and use storage with Kubernetes. |
| Ingress Controller | ? | The Web ingress controller. |
| Load Balancer | ? | In addition the the Ingress controller, I am using an internal Load Balancer for use with services other than Web Services. |
