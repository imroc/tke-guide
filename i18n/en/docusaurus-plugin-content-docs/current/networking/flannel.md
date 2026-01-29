# Flannel on TKE

:::warning[Warning]

This is a non-standard solution for self-managing Flannel container network on TKE. It is not officially supported by TKE and comes with no technical support or SLA guarantees. Please use with caution.

Basic functionality has been verified, but it has not undergone other testing or production validation.

:::

## Overview

If you need to use TKE registered nodes to manage third-party nodes with container networking (Pod IP allocation), but don't want to use the CiliumOverlay network plugin (Cilium has many limitations, introduces additional complexity, and may put pressure on the apiserver in large-scale scenarios), you can self-manage Flannel CNI on TKE to allocate Pod IPs for registered nodes.

This article describes how to self-manage Flannel CNI on TKE.

## Prepare TKE Cluster

Create a TKE cluster in the [TKE Console](https://console.cloud.tencent.com/tke2/cluster), noting the following key options:

- Network Mode: Select VPC-CNI.
- Nodes: Do not add any standard nodes or native nodes to the cluster before installation to avoid residual rules and configurations. Add nodes after installation is complete.
- Basic Components: Uncheck ip-masq-agent installation (this component is optional in VPC-CNI network mode. Since we need to install flannel, pod IPs can only be accessed within the cluster, and outbound traffic must be SNATed - this functionality is built into flannel, so ip-masq-agent is not needed).

After the cluster is created, you need to enable cluster access to expose the cluster's apiserver for subsequent helm commands to operate on the TKE cluster. See [How to Enable Cluster Access](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4).

Based on your situation, choose whether to enable private network access or public network access, depending on whether the network environment where the helm command runs can communicate with the VPC where the TKE cluster is located:

1. If communication is possible, enable private network access.
2. If communication is not possible, enable public network access. Currently, enabling public network access requires deploying the `kubernetes-proxy` component to the cluster as a relay, which depends on nodes existing in the cluster (this dependency may be removed in the future, but currently it's required). If you want to use public network access, it's recommended to first add a super node to the cluster so that the `kubernetes-proxy` pod can be scheduled normally. After flannel installation is complete, you can delete the super node.

## Enable Registered Node Capability

1. Go to the TKE cluster basic information page.
2. Click the **Basic Information** tab.
3. Enable **Registered Node Capability**: Check **Direct Connect**, select the subnet for the proxy ENI (used to proxy registered nodes' access to cloud resources), and click **Confirm Enable**.

## Plan Cluster CIDR

Before installing flannel, you need to determine the cluster CIDR (Pod CIDR). This CIDR will be used to allocate IP addresses for all Pods. Note the following when planning:

- The CIDR must not conflict with the VPC CIDR, otherwise Pods may not be able to access resources outside the cluster (such as databases).
- The CIDR size determines the number of Pod IPs that can be allocated in the cluster (e.g., /16 can allocate approximately 65,534 IPs).
- It's not recommended to change after determination, so reserve enough space based on your business scale.

## Prepare Installation Tools

Ensure [helm](https://helm.sh/docs/intro/install/) and [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) are installed, and configure kubeconfig to connect to the cluster (see [Connect to Cluster](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)).

Since the installation depends on helm chart packages on GitHub, ensure the network environment where the tools are located can access GitHub.

## Uninstall TKE Network Components

To install and run Flannel CNI on the TKE cluster, we need to uninstall some TKE built-in network components to avoid conflicts:

```bash
# Uninstall VPC-CNI related network components
kubectl -n kube-system patch daemonset tke-eni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch deployment tke-eni-ipamd -p '{"spec":{"replicas":0,"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch deployment tke-eni-ip-scheduler -p '{"spec":{"replicas":0,"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io add-pod-eni-ip-limit-webhook

# Clean up automatically created pods and rs before uninstallation
kubectl -n kube-system delete pod --all
kubectl -n kube-system delete replicasets.apps --all

# Keep tke-cni-agent for copying basic CNI binaries (such as loopback) to the CNI binary directory for flannel use,
# but disable generating TKE's CNI configuration file to avoid conflicts with flannel's CNI configuration file
kubectl patch configmap tke-cni-agent-conf -n kube-system --type='json' -p='[{"op": "remove", "path": "/data"}]'
```

## Install podcidr-controller

In TKE VPC-CNI mode, there is no cluster CIDR concept, and kube-controller-manager does not automatically allocate podCIDR to nodes, nor can this be achieved through custom parameters. By default, flannel depends on kube-controller-manager to first allocate podCIDR to nodes, then flannel allocates Pod IPs based on the current node's allocated podCIDR. Flannel also supports using etcd to store network configuration and IP allocation information, but this introduces additional etcd with higher maintenance costs.

To solve this problem, you can use the lightweight [podcidr-controller](https://github.com/imroc/podcidr-controller) to automatically allocate podCIDR to nodes.

Install with the following command:

```bash
helm repo add podcidr-controller https://imroc.github.io/podcidr-controller
helm repo update podcidr-controller

helm upgrade --install podcidr-controller podcidr-controller/podcidr-controller \
  -n kube-system \
  --set clusterCIDR="10.244.0.0/16" \
  --set nodeCIDRMaskSize=24 \
  --set removeTaints[0]=tke.cloud.tencent.com/eni-ip-unavailable \
  --set tolerations[0].key=tke.cloud.tencent.com/eni-ip-unavailable \
  --set tolerations[0].operator=Exists \
  --set tolerations[1].key=node-role.kubernetes.io/master \
  --set tolerations[1].operator=Exists \
  --set tolerations[2].key=tke.cloud.tencent.com/uninitialized \
  --set tolerations[2].operator=Exists \
  --set tolerations[3].key=node.cloudprovider.kubernetes.io/uninitialized \
  --set tolerations[3].operator=Exists
```

Parameter description:

- `clusterCIDR`: Cluster CIDR, must match the `podCidr` when installing flannel later.
- `nodeCIDRMaskSize`: Subnet mask size allocated to each node. Setting it to 24 means each node can allocate 254 Pod IPs.
- `removeTaints`: Automatically remove node taints. If adding standard nodes or native nodes (not registered nodes) to the TKE cluster, the `tke.cloud.tencent.com/eni-ip-unavailable` taint is added to nodes by default, which is automatically removed after VPC-CNI related components are ready on the node. Since we need to use flannel to completely replace TKE's built-in network plugin, this taint won't be automatically removed, so we use this component to automatically remove the taint to prevent Pods from being unschedulable.
- `tolerations`: Configure taint tolerations for podcidr-controller. Since Flannel CNI depends on this component to allocate podCIDR to nodes, and node initialization also depends on CNI being ready, this component has high priority and needs to tolerate some taints.

## Install Flannel

Flannel uses vxlan-based overlay network by default and requires specifying a cluster CIDR (podCidr parameter). All Pod IPs in the cluster are allocated from this CIDR. Configure the podCidr parameter according to your needs.

Use the following command to install flannel:

```bash
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

helm repo add flannel https://flannel-io.github.io/flannel/
helm upgrade --install flannel --namespace kube-flannel flannel/flannel \
  --set podCidr="10.244.0.0/16" \
  --set flannel.image.repository="docker.io/flannel/flannel" \
  --set flannel.image_cni.repository="docker.io/flannel/flannel-cni-plugin"
```

Parameter description:

- `podCidr`: Cluster CIDR, must match the `clusterCIDR` in podcidr-controller.
- `flannel.image.repository` and `flannel.image_cni.repository`: Specify flannel related image addresses. The default uses `ghcr.io`, which has network requirements for nodes. Changing to dockerhub mirror addresses enables image acceleration in TKE environment (including registered nodes), allowing direct internal network image pulls.

## Use Registered Nodes to Manage Third-Party Machines

Use the following method to manage third-party machines in the TKE cluster through registered nodes:

1. Go to the TKE cluster **Node Management** page.
2. Click the **Node Pools** tab.
3. Click **Create**.
4. Select **Registered Node** and click **Create**.
5. Configure according to your situation and click **Create Node Pool**.
6. Go to the node pool details page.
7. Click **Create Node**.
8. Select **Private Network** for node initialization method.
9. Follow the prompts to use the registration script to manage third-party machines in the TKE cluster.

:::tip[Note]

The registration script will validate the current machine. If it doesn't meet the requirements, there will be warning messages, and the registration will not succeed.

Since flannel is used as the CNI plugin, OS and kernel requirements are low. If you don't want strict validation, you can modify the registration script to comment out the `check_os` and `check_kernel` functions in the `check` function.

:::

## FAQ

### br_netfilter Kernel Module Not Loaded

Flannel depends on the br_netfilter kernel module. If not loaded, flannel will not work properly:

```txt
E0127 04:42:47.627500       1 main.go:278] Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory
```

Solution:

```bash
# Load kernel module
modprobe br_netfilter

# Set to load automatically on boot
echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
```

## Related Links

- [flannel Project](https://github.com/flannel-io/flannel)
- [podcidr-controller Project](https://github.com/imroc/podcidr-controller)
