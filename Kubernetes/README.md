# Chaos Engine - Kubernetes

## Overview

The section explores the deployment and configuration of the actual Kubernetes service.  Unfortunately, I have chosen no to automate with Ansible as the deployment doesn't necessarily lend itself to easy automation.

![Kubernetes](kubernetes.drawio.svg)

## Kubernetes

In this section I document the steps to initiate Kubernetes.  I have found that initiation is necessarily a trial and error process, it is likely that you will start over multiple times.  There are many variables to take into account when initiating your cluster.

### Etcd

Before initializing your cluster, I recommend that you clear your Etcd service

Setup your local workstation to work with Etcd

```bash
alias e='etcdctl --endpoints 192.168.1.40:2379,192.168.1.41:2379,192.168.1.42:2379 --cert {{ Your Project Dir }}/StorageNodes/files/etcd-client.crt --key {{ Your Project Dir }}//StorageNodes/files/etcd-client.key --cacert {{ Your Project Dir }}//StorageNodes/files/ca.crt'
```

Clear any previous settings

```bash
e del "" --prefix
```

> [!NOTE]
> The controllers need to match the controllers for your HAProxy configuration.  My controllers are pi1, pi4 and pi7.

### Configuration file

During the installation process I chose to use a configuration file, Kubernetes/files/kube2.yaml, instead of a long list of command line options.  There are several important parameters in the file that require special attention.

| Parameter | Value | Purpose |
| --- | --- | --- |
| localAPIEndpoint:advertiseAddress | 192.168.1.56 | This represents the first control plane node that you bring online.  I chose to use "pi7" as the first controller |
| nodeRegistration:criSocket | unix:///var/run/cri-dockerd.sock | This value tells Kubernetes to use Docker for containerization |
| nodeRegistration:name | pi7 | The hostname of the first control plane node |
| controlPlaneEndpoint | k8s.jayflory.net | The DNS name for your HAProxy address |
| controllerManager:extraArgs:node-cidr-mask-size | 24 | This number determines the CIDR for the IP addresses assigned to each node for your pods.  This must be larger pod subnet or Flannel will fail on your nodes. |
| etcd:external:caFile | /etc/kubernetes/etcd/ca.crt | The root CA for the Etcd service |
| etcd:external:certFile | /etc/kubernetes/etcd/client.crt | The client certificate needed to access the Etcd service |
| etcd:external:keyFile | /etc/kubernetes/etcd/client.key | The client key needed to authenticate to the Etcd service  |
| etcd:external:endpoints | https://192.168.1.40:2379,https://192.168.1.41:2379,https://192.168.1.42:2379 | The Etcd servers |
| kubernetesVersion | 1.28.0 | The version string for Kubernetes |
| networking:podSubnet | 10.244.0.0/16 | The sub range of IP addresses from which Pod subnets will be assigned.  In our case Kubernetes will assign a /24 from this range to each node. |

### Initialization

With the above configuration copied to "pi7", it is time to do the first part to initialize the cluster.

```bash
sudo kubeadm init --config kube2.yaml --upload-certs
```

When the above command is complete, it will print two commands you will need to initialize your other nodes, one for the other controllers and one for the rest of the cluster nodes.

Copy the required configuration to your ~/.kube folder.

```bash
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verify that your cluster has very basic functionality:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

> [!NOTE]
> At this point your node list will consist of a single node that is "NotReady".  We will need to install the "Flannel" CNI plugin before the nodes become "Ready".

## Flannel

To initialize Flannel, we will be using the file Kubernetes\kube-flannel.yaml.  Before initializing review the file and adjust the following parameters as required:

| Parameter | Value | Purpose |
| --- | --- | --- |
| etcd-endpoints | http://192.168.1.40:2379,http://192.168.1.41:2379,http://192.168.1.42:2379 | Defines the endpoints of Etcd for Flannel |
| etcd-keyfile | "/etc/kubernetes/pki/etcd-client.key" | The Etcd client certificate key |
| etcd-certfile | "/etc/kubernetes/pki/etcd-client.crt" | The Etcd client certificate for communicating with the Etcd service |
| etcd-cafile | "/etc/kubernetes/pki/etcd/ca.crt" | The root CA for the Etcd service |

Initialize Flannel:

```bash
kubectl create -f kube-flannel.yaml
```

Check your node:

```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel
```

> [!NOTE]
> Core DNS probably won't start until we add the other nodes.

## Add Nodes

You are now ready to join the remaining nodes to the cluster.

### Add Control Plane Nodes

From when you initialized Kubernetes, copy the join command for control planes.  Before running the command add the string "--cri-socket unix:///var/run/cri-dockerd.sock" to the end of the command and run it on the other control plane nodes.

### Remove Taints

Kubernetes will automatically add "Taints" to the control plane nodes.  These taints will normally prevent normal pods from running on the control plane nodes.  However, as the cluster is relatively small, I chose to remove the taints.

```bash
kubectl taint nodes pi7 node-role.kubernetes.io/master:NoSchedule-
kubectl taint nodes pi1 node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes pi4 node-role.kubernetes.io/control-plane:NoSchedule-
```

> [!NOTE]
> The taint for pi7 is slightly different.  Pi7 was the first node installed, your configuration may differ slightly depending on the first node you installed.

### Add Remaining Work Nodes

From when you initialized Kubernetes, copy the join command for non control plane nodes.  Before running the command add the string "--cri-socket unix:///var/run/cri-dockerd.sock" to the end of the command and run it on the other control plane nodes.

## Load Balancer

I chose the MetalLB load balancer for the cluster.  For more details about the installation please see:  [Install](https://metallb.io/installation/).

Modify the kube-proxy config map:

```bash
kubectl edit configmap -n kube-system kube-proxy
```

Setting:

```text
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
  strictARP: true
```

Download the configuration Yaml:

```bash
wget https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
```

Install MetalLB

```bash
kubectl apply -f metallb-native.yaml
```

Before the load balancer configuration can work, you will need to create in IP Pool.  Modify the "files/ip-pool.yaml" file specify the desired range of addresses to use with the load balancer.

Apply the IP pool:

```bash
kubectl apply -f ip-pool.yaml
```

## Ingress Controller

As a basic ingress controller, I chose the latest NGINX Ingress controller.

Download:

```bash
wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/cloud/deploy.yaml
mv deploy.yaml ingress-nginx.yaml
```

Install the controller:

```bash
kubectl create -f ingress-nginx.yaml
```

When the ingress controller comes online, it should grab an IP address from the MetalLB load balancer configuration.  You should see the service come online.

```text
$ kubectl get svc -n ingress-nginx

NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.102.123.28   192.168.1.21   80:31020/TCP,443:31578/TCP   4d23h
ingress-nginx-controller-admission   ClusterIP      10.103.74.34    <none>         443/TCP                      4d23h```
```

## Pod Storage

I chose to use the Kadalu project to provide storage to the cluster.  To configure storage:

Ensure that the Gluster volume KubeStorage is running on the Gluster storage nodes.

```bash
sudo gluster volume status KubeStorage
```

Download the Kadalu install script:

```bash
wget wget https://github.com/kadalu/kadalu/releases/latest/download/install.sh
```

Install Kadalu on your local workstation:

```bash
sudo ./install.sh
```

Install Kadalu to your cluster:

```bash
kubectl create namespace kadalu
kubectl create secret generic glusterquota-ssh-secret --from-literal=glusterquota-ssh-username=ubuntu --from-file=ssh-privatekey=/home/jayflory/.ssh/id_rsa -n kadalu
kubectl kadalu install
```

Create the storage class:

```bash
kubectl create -f storageclass.yaml```
```

I chose to use Kadalu with the external Gluster nodes already configured.  Please check the Kadalu [documentation](https://github.com/kadalu/kadalu/tree/devel/doc) for details.

## Testing

The final step is to test and ensure that your configuration is correct.  I have included the "test.yaml" file which builds a 2 POD deployment with ingress services.

Create the Test:

```bash
kubectl create -f test.yaml
```

However, the configuration creates an empty share for the Apache configuration.  You will need to copy the the /usr/local/apache2 directory in the normal httpd container to your new share.

From a work node, mount the remote share locally:

```bash
sudo mount -t glusterfs etcd1:/KubeStorage /mnt
```

Create a temporary container:

```bash
sudo docker run -it --rm -v /mnt:/mnt httpd /bin/bash
```

Copy the directory:

``` bash
cd /usr/local/apache2
cp -a * /mnt
```

At this point you should be able to restart the pods to read the configuration file and you should now have access to your new Ingress services.
