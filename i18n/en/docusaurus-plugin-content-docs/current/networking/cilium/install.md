# Install Cilium

This document describes how to install Cilium on TKE clusters.

## Prerequisites

### Prepare TKE Cluster

:::info[Note]

Installing Cilium is a major change to the cluster. It is not recommended to install it on clusters running production workloads, as it may affect online services during installation. It is recommended to install Cilium on newly created TKE clusters.

:::

Create a TKE cluster in the [TKE Console](https://console.cloud.tencent.com/tke2/cluster), paying attention to the following key options:
- Cluster Type: Managed Cluster
- Kubernetes Version: Not lower than 1.30.0, latest version recommended (refer to [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)).
- Operating System: TencentOS 4 or Ubuntu >= 22.04.
- Container Network Plugin: VPC-CNI with shared ENI multiple IPs.
- Nodes: Do not add any general nodes or native nodes to the cluster before installation to avoid residual rules and configurations. Add them after installation is complete.
- Basic Components: Uncheck ip-masq-agent to avoid conflicts.
- Enhanced Components: If you want to use Karpenter node pools, check to install the Karpenter component; otherwise, leave it unchecked (refer to the node pool selection below).

After the cluster is created successfully, enable cluster access to expose the cluster's apiserver so that the helm command can operate the TKE cluster properly when installing Cilium. Refer to [How to Enable Cluster Access](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4).

Depending on your situation, choose to enable private network access or public network access, mainly depending on whether the network environment where the helm command is located can communicate with the VPC where the TKE cluster is located:
1. If it can communicate, enable private network access.
2. If it cannot communicate, enable public network access. Currently, enabling public network access requires deploying the `kubernetes-proxy` component to the cluster as a relay, which depends on the existence of nodes in the cluster (this dependency may be removed in the future, but currently it is required). If you want to use public network access, it is recommended to add a serverless node to the cluster first so that the `kubernetes-proxy` pod can be scheduled normally, and then delete the serverless node after Cilium installation is complete.

If you use Terraform to create the cluster, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  # Managed Cluster
  cluster_deploy_type = "MANAGED_CLUSTER"
  # Kubernetes version >= 1.30.0
  cluster_version = "1.32.2"
  # OS, TencentOS 4 image ID, currently using this image requires submitting a ticket
  cluster_os = "img-gqmik24x" 
  # Container network plugin: VPC-CNI
  network_type = "VPC-CNI"
  # Enable cluster APIServer access
  cluster_internet = true
  # Expose APIServer via internal CLB, need to specify CLB subnet ID
  cluster_intranet_subnet_id = "subnet-xxx" 
  # Do not install ip-masq-agent (disable_addons requires tencentcloud provider version 1.82.33+)
  disable_addons = ["ip-masq-agent"]
  # Omit other necessary but irrelevant configurations
}
```

### Prepare Helm Environment

1. Ensure [helm](https://helm.sh/zh/docs/intro/install/) and [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) are installed, and configure kubeconfig to connect to the cluster (refer to [Connecting to Cluster](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)).
2. Add Cilium helm repo:
    ```bash
    helm repo add cilium https://helm.cilium.io/
    ```

## Install Cilium

### Upgrade tke-eni-agent

Since Cilium uses routing table IDs 2004 and 2005, which may conflict with the routing table IDs used by TKE's VPC-CNI network mode, the new version of VPC-CNI network mode will adjust the routing table ID generation algorithm to avoid conflicts with Cilium's routing table IDs. However, it has not been officially released yet (v3.8.0 version), so here we can manually upgrade the image version to v3.8.0 rc version first.

Upgrade the tke-eni-agent image version with the following script:

:::info[Note]

After the eniipamd component officially releases v3.8.0, you can upgrade eniipamd in the component management.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031120006.png)

:::

<Tabs>
  <TabItem value="1" label="bash">

   ```bash
   # Get current image
   CURRENT_IMAGE=$(kubectl get daemonset tke-eni-agent -n kube-system \
     -o jsonpath='{.spec.template.spec.containers[0].image}')

   # Construct new image name (keep repository path, replace tag)
   REPOSITORY=${CURRENT_IMAGE%%:*}
   NEW_IMAGE="${REPOSITORY}:v3.8.0-rc.0"

   # Upgrade tke-eni-agent image
   kubectl patch daemonset tke-eni-agent -n kube-system \
     --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'"${NEW_IMAGE}"'"}]'
   ```

  </TabItem>
  <TabItem value="2" label="fish">

   ```bash
   # Get current image
   set -l current_image (kubectl get daemonset tke-eni-agent -n kube-system \
     -o jsonpath="{.spec.template.spec.containers[0].image}")
   
   # Extract repository path (remove tag part)
   set -l repository (echo $current_image | awk -F: '{print $1}')
   
   # Construct new image name
   set -l new_image "$repository:v3.8.0-rc.0"
   
   # Upgrade tke-eni-agent image
   kubectl patch daemonset tke-eni-agent -n kube-system \
     --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$new_image'"}]'   
   ```

  </TabItem>
</Tabs>


### Configure CNI

Prepare CNI configuration ConfigMap `cni-config.yaml` for Cilium:

```yaml title="cni-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-config
  namespace: kube-system
data:
  cni-config: |-
    {
      "cniVersion": "0.3.1",
      "name": "generic-veth",
      "plugins": [
        {
          "type": "tke-route-eni",
          "routeTable": 1,
          "disableIPv6": true,
          "mtu": 1500,
          "ipam": {
            "type": "tke-eni-ipamc",
            "backend": "127.0.0.1:61677"
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
```

Create CNI ConfigMap:

```bash
kubectl apply -f cni-config.yaml
```

### Install Cilium with Helm

Execute installation with helm:

:::info[Note]

`k8sServiceHost` is the apiserver address, obtained dynamically through command.

:::

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

:::tip[Description]

Below is the `values.yaml` with parameter explanations:

```yaml showLineNumbers title="values.yaml"
# Replace cilium, cilium-envoy and cilium-operator images with TKE mirror repository addresses that can be pulled directly
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
# Use native routing, Pods directly use VPC IP routing without overlay, refer to native routing: https://docs.cilium.io/en/stable/network/concepts/routing/#native-routing
routingMode: "native" 
endpointRoutes:
  # When using native routing, this option must be set to true. It means forwarding Pod traffic directly to veth device without going through cilium_host interface
  enabled: true 
ipam:
  # TKE Pod IP allocation is handled by tke-eni-ipamd component, Cilium does not need to handle Pod IP allocation
  mode: "delegated-plugin"
# No IP masquerading needed when using VPC-CNI
enableIPv4Masquerade: false
# All eth-prefixed interfaces on TKE nodes may carry traffic (Pod traffic goes through secondary interfaces, eth1, eth2 ...), use this parameter to attach Cilium ebpf programs to all eth-prefixed interfaces,
# so that packets can be properly reverse NAT'd based on conntrack, otherwise network connectivity may fail in some scenarios (such as cross-node access to HostPort)
devices: eth+
cni:
  # Use generic-veth for CNI Chaining with VPC-CNI, refer to: https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/
  chainingMode: generic-veth
  # CNI configuration is fully customized
  customConf: true
  # ConfigMap name storing CNI configuration
  configMap: cni-configuration
  # VPC-CNI will automatically configure Pod routes, Cilium does not need to configure
  externalRouting: true
operator:
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: Exists
  - key: "node-role.kubernetes.io/master"
    operator: Exists
  - key: "node.kubernetes.io/not-ready"
    operator: Exists
  - key: "node.cloudprovider.kubernetes.io/uninitialized"
    operator: Exists
  # Tolerate TKE taints to avoid circular dependencies during initial installation
  - key: "tke.cloud.tencent.com/uninitialized" 
    operator: Exists
  - key: "tke.cloud.tencent.com/eni-ip-unavailable" 
    operator: Exists
extraConfig:
  # Cilium does not handle Pod IP allocation, need to manually specify a conflict-free IP address as the cilium_host virtual interface IP address on each node
  local-router-ipv4: 169.254.32.16
# Enable CiliumLocalRedirectPolicy capability, refer to https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/
localRedirectPolicies:
  enabled: true
# Replace kube-proxy, including ClusterIP forwarding, NodePort forwarding, and also comes with HostPort forwarding capability
kubeProxyReplacement: "true"
# Note: Replace with actual apiserver address, get method: kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112 
k8sServicePort: 60002
```

For production environment deployment, it is recommended to save parameters to `values.yaml`, then execute the following command during installation or update (replace `--version` if upgrading):

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml
```

If you have many custom configurations, it is recommended to split them into multiple yaml files, for example, put image address replacement configuration in `image-values.yaml`, configuration for enabling Egress Gateway in `egress-values.yaml`, configuration for container requests and limits in `resources-values.yaml`. When updating configuration, merge multiple yaml files by adding multiple `-f` parameters:

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml \
  -f image-values.yaml \
  -f egress-values.yaml \
  -f resources-values.yaml
```

:::

Ensure Cilium-related pods are running normally:

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/part-of=cilium
NAME                              READY   STATUS    RESTARTS   AGE
cilium-5rfrk                      1/1     Running   0          1m
cilium-9mntb                      1/1     Running   0          1m
cilium-envoy-4r4x9                1/1     Running   0          1m
cilium-envoy-kl5cz                1/1     Running   0          1m
cilium-envoy-sgl5v                1/1     Running   0          1m
cilium-operator-896cdbf88-jlgt7   1/1     Running   0          1m
cilium-operator-896cdbf88-nj6jc   1/1     Running   0          1m
cilium-zrxwn                      1/1     Running   0          1m
```

### Uninstall TKE Components

Clean up all tke-cni-agent and kube-proxy pods via kubectl patch:

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[Description]

1. By adding nodeSelector, the daemonset will not be deployed to any nodes, which is equivalent to uninstalling while leaving a fallback; currently kube-proxy can only be uninstalled this way, if kube-proxy is deleted directly, subsequent cluster upgrades will be blocked.
3. If Pods use VPC-CNI network, tke-cni-agent is not needed, uninstall to avoid CNI configuration file conflicts.
4. As mentioned earlier, it is not recommended to add nodes before installing Cilium. If for some reason general nodes or native nodes are added before installing Cilium, and you don't want to restart existing nodes after installing Cilium, you can add preStop to tke-cni-agent before executing uninstall to clean up CNI configuration on existing nodes:

```bash
kubectl -n kube-system patch daemonset tke-cni-agent --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/lifecycle",
    "value": {
      "preStop": {
        "exec": {
          "command": ["rm", "/host/etc/cni/net.d/00-multus.conf"]
        }
      }
    }
  }
]'
kubectl -n kube-system rollout status daemonset/tke-cni-agent --watch # Wait for tke-cni-agent pods on existing nodes to complete update, ensure preStop is successfully added to all
```

:::

If ip-masq-agent was not unchecked when creating the cluster, you can uninstall it:

```bash
kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

## Create Node Pool

### Node Pool Selection

The following three types of node pools can adapt to Cilium:
- Native Node Pool: Based on native nodes, native nodes have rich features and are the node type recommended by TKE (refer to [Native Node VS Normal Node](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)), OS is fixed to use TencentOS.
- General Node Pool: Based on general nodes (CVM), OS image is flexible.
- Karpenter Node Pool: Similar to native node pool, based on native nodes, OS is fixed to use TencentOS, but node management uses the more powerful [Karpenter](https://karpenter.sh/) instead of [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) (CA) used by regular and native node pools.

Below is a comparison of these node pools, choose the appropriate node pool type based on your situation:

| Node Pool Type   | Node Type       | Available OS Images         | Node Scaling Component |
| ---------------- | --------------- | --------------------------- | ---------------------- |
| Native Node Pool | Native Node     | TencentOS                   | cluster-autoscaler     |
| General Node Pool| General Node (CVM) | Ubuntu/TencentOS/Custom Image | cluster-autoscaler |
| Karpenter Node Pool | Native Node  | TencentOS                   | Karpenter              |


Below are the steps to create various node pools.

### Create Karpenter Node Pool

Before creating a Karpenter node pool, ensure the Karpenter component is enabled, refer to [tke-karpenter documentation](https://cloud.tencent.com/document/product/457/111805).

Prepare `nodepool.yaml` for configuring Karpenter node pool, here's an example:

```yaml title="nodepool.yaml"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
    - nodes: 10%
  template:
    metadata:
      annotations:
        # Native nodes default to TencentOS 3, which is not compatible with latest Cilium version, specify this annotation to install TencentOS 4
        # Note: Currently using this system image requires submitting a ticket
        beta.karpenter.k8s.tke.machine.spec/annotations: node.tke.cloud.tencent.com/beta-image=ts4-public 
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      - key: karpenter.k8s.tke/instance-family
        operator: In
        # Specify expected instance types, you can check in console which instance types are actually sold in cluster region and availability zones
        # Complete list reference: https://cloud.tencent.com/document/product/213/11518#INSTANCETYPE
        values: ["S5", "SA2"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"] # Specify minimum CPU cores when scaling
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default # Reference TKEMachineNodeClass
  limits:
    cpu: 100 # Limit maximum CPU cores for node pool

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms: # VPC subnet for nodes
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # Security group bound to nodes
  - id: sg-nok01xpa
  sshKeySelectorTerms: # SSH key bound to nodes
  - id: skey-3t01mlvf
```

Create Karpenter node pool:

```bash
kubectl apply -f nodepool.yaml
```

### Create Native Node Pool

Below are the steps to create a native node pool through the [TKE Console](https://console.cloud.tencent.com/tke2):
1. In the cluster list, click cluster ID to enter cluster details page.
2. Select **Node Management** from the left menu, click **Node Pool** to enter the node pool list page.
3. Click **Create**.
4. Select **Native Node**.
5. In **Advanced Settings** under Annotations, click **Add**: `node.tke.cloud.tencent.com/beta-image=ts4-public` (native nodes default to TencentOS 3.1, which is not compatible with latest Cilium version, specify via annotation to use TencentOS 4).
6. Select other options according to your needs.
7. Click **Create Node Pool**.

If you want to create a native node pool via Terraform, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations { # Add annotation to specify native node to use TencentOS 4 for Cilium compatibility, currently using this system image requires submitting a ticket
    name  = "node.tke.cloud.tencent.com/beta-image"
    value = "ts4-public"
  }
}
```
### Create General Node Pool

Below are the steps to create a general node pool through the [TKE Console](https://console.cloud.tencent.com/tke2):
1. In the cluster list, click cluster ID to enter cluster details page.
2. Select **Node Management** from the left menu, click **Node Pool** to enter the node pool list page.
3. Click **Create**.
4. Select **General Node**.
5. For **Operating System**, select **TencentOS 4**, **Ubuntu 22.04** or **Ubuntu 24.04**.
6. Select other options according to your needs.
7. Click **Create Node Pool**.

If you want to create a general node pool via Terraform, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "img-gqmik24x" # TencentOS 4 image ID, currently using this system image requires submitting a ticket
}
```

## FAQ

### How to view all Cilium default installation configurations?

Cilium's helm package provides a large number of custom configuration options. The installation steps above only provide the necessary configurations for installing Cilium in TKE environment. You can actually adjust more configurations according to your needs.

Execute the following command to view all installation configuration options:

```bash
helm show values cilium/cilium --version 1.18.3
```

### Why add local-router-ipv4 configuration?

Cilium will create a `cilium_host` virtual interface on each node and needs to configure an IP address for it. Since we want Cilium to coexist with TKE VPC-CNI network plugin, IP allocation needs to be done by TKE VPC-CNI plugin, so Cilium is not responsible for IP allocation. Therefore, we need to manually specify a conflict-free IP address via the `local-router-ipv4` parameter. The IP address `169.254.32.16` will not conflict with other IPs on TKE, so we specify this IP address.

### What if I can't connect to Cilium's helm repo?

When installing Cilium with helm, helm will get chart-related information from Cilium's helm repo and download it. If connection fails, an error will occur.

The solution is to download the chart package in an environment that can connect:

```bash
$ helm pull cilium/cilium --version 1.18.3
$ ls cilium-*.tgz
cilium-1.18.3.tgz
```

Then copy the chart package to the machine executing helm installation, and specify the chart package path during installation:
```bash
helm upgrade --install cilium ./cilium-1.18.3.tgz \
  --namespace kube-system \
  -f values.yaml
```

### How to optimize for large-scale scenarios?

For large clusters, it is recommended to enable the [CiliumEndpointSlice](https://docs.cilium.io/en/stable/network/kubernetes/ciliumendpointslice/) feature, which was introduced in 1.11 and is currently (1.18.3) still in Beta stage (see [CiliumEndpointSlice Graduation to Stable](https://github.com/cilium/cilium/issues/31904)). In large-scale scenarios, this feature can significantly improve Cilium performance and reduce apiserver pressure.

It is not enabled by default. To enable it, add the `--set ciliumEndpointSlice.enabled=true` parameter when installing Cilium with helm.

### Can it be installed on clusters with Global Router network mode?

Test conclusion: No.

Cilium probably doesn't support the bridge CNI plugin (Global Router network plugin is based on bridge CNI plugin), related issues:
- [CFP: eBPF with bridge mode](https://github.com/cilium/cilium/issues/35011)
- [CFP: cilium CNI chaining can support cni-bridge](https://github.com/cilium/cilium/issues/20336)

### Can I check DataPlaneV2?

Conclusion: No.

When selecting VPC-CNI network plugin, there is a DataPlaneV2 option:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

When checked, Cilium components will be deployed to the cluster (replacing kube-proxy component). If you install Cilium yourself, it will cause conflicts. Moreover, the OS used by DataPlaneV2 is not compatible with the latest Cilium version, so this option cannot be checked.

### How can Pods access the public network?

You can create a public NAT gateway, then create routing rules in the routing table of the VPC where the cluster is located to forward public network traffic to the public NAT gateway, and ensure the routing table is associated with the subnets used by the cluster. Refer to [Accessing Public Network via NAT Gateway](https://cloud.tencent.com/document/product/457/48710).

If the nodes themselves have public bandwidth and you want Pods to directly use the node's public network capability to access the public network, you need to make some configuration adjustments when deploying Cilium:

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set ipv4NativeRoutingCIDR="VPC_CIDR" \
  --set bpf.masquerade=true
  # highlight-add-end
```

:::info[Note]

If adjusting configuration of already installed Cilium, existing nodes need to restart Cilium daemonset to take effect:

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

:::

:::tip[Parameter Description]

Below is the `values.yaml` with related parameter explanations:

```yaml title="values.yaml"
# Enable Cilium's IP MASQUERADE functionality
enableIPv4Masquerade: true
# Specify VPC CIDR where cluster is located (replace with actual VPC CIDR), indicating traffic within VPC is not SNAT'd, other traffic needs SNAT.
# This way when Pods access public network, they will be SNAT'd to node IP and can use node's public network capability to access public network.
ipv4NativeRoutingCIDR: 172.22.0.0/16
bpf:
  # Cilium's IP MASQUERADE functionality has bpf and iptables versions, in TKE environment need to use bpf version. Reference https://docs.cilium.io/en/stable/network/concepts/masquerading/
  masquerade: true
```

:::

For more advanced outbound traffic requirements (such as specifying certain Pods to use a specific public IP to access public network), refer to [Egress Gateway Best Practices](egress-gateway.md).

### Image pull failure?

Most images Cilium depends on are in `quay.io`. If you don't use the image address replacement parameter configuration provided in this document during installation, it may cause Cilium-related image pull failures (for example, nodes don't have public network access capability, or the cluster is in mainland China).

In TKE environment, the mirror repository address `quay.tencentcloudcr.com` is provided for downloading images under the `quay.io` domain. Simply replace `quay.io` domain in the original image address with `quay.tencentcloudcr.com`. Pulling goes through internal network, no need for nodes to have public network capability, and no regional restrictions.

If you configured more installation parameters, more image dependencies may be involved. If image address replacement is not configured, it may cause image pull failures. Use the following command to replace all Cilium-dependent images with mirror repository addresses that can be pulled directly via internal network in TKE environment:

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
```

If you manage configuration with yaml, you can save image replacement configuration to `image-values.yaml`:

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

Add `-f image-values.yaml` when updating Cilium to include image replacement configuration:

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[Description]

Using TKE-provided mirror repository addresses to pull external images does not provide SLA guarantees. Sometimes pulling may fail, but usually will eventually succeed automatically after retry.

If you want higher availability for image pulling, you can [Use TCR to Host Cilium Images](tcr.md) to sync Cilium-dependent images to your own [TCR image repository](https://cloud.tencent.com/product/tcr), then refer to the dependency image replacement configuration here to replace corresponding images with your synced image addresses.

:::

### Cannot use TencentOS 4?

TencentOS 4 system image is currently in internal testing and requires [submitting a ticket](https://console.cloud.tencent.com/workorder/category) to apply.

Without application, general nodes cannot select TencentOS 4 system image, and native nodes will fail to initialize successfully if annotation specifies TencentOS 4.

### cilium-operator cannot be ready on serverless nodes?

cilium-operator uses hostNetwork and has readiness probes configured. When using hostNetwork on serverless nodes, probe requests fail, so cilium-operator cannot be ready.

It is not recommended to use serverless nodes in clusters installing Cilium. They can be removed. If you must use them, you can add taints to serverless nodes and add corresponding tolerations to Pods that need to be scheduled to serverless nodes.

## References

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
