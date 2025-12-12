# Egress Gateway Guide

## Overview

This article explains how to use Cilium's Egress Gateway and CiliumEgressGatewayPolicy to flexibly control which egress IP is used for outbound traffic from the cluster.

## Known Issues

Using Cilium's Egress Gateway feature has the following known issues:

1. **Egress policy delay for new Pods**: After a new Pod starts, if it matches an Egress policy, the expectation is that the Pod's outbound traffic should go through the specified egress gateway. However, during the initial period after Pod startup, this policy may not take effect immediately, though this delay is typically very short and doesn't affect most scenarios.
2. **Incompatibility with Cilium's Cluster Mesh and CiliumEndpointSlice features**.

## Enabling Egress Gateway

To enable Egress Gateway, the following conditions must be met:

1. Enable cilium to replace kube-proxy.
2. Enable IP masquerade using BPF implementation instead of the default iptables implementation.

Method to enable Egress Gateway during cilium installation:

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
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
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  # highlight-add-start
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002 \
  --set egressGateway.enabled=true \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set ipMasqAgent.config.masqLinkLocal=true
  # highlight-add-end
```

Then restart cilium components to take effect:

```bash
kubectl rollout restart ds cilium -n kube-system
kubectl rollout restart deploy cilium-operator -n kube-system
```

:::tip[Note]

If you already installed cilium using the **Install cilium using helm** provided in [Installing Cilium](install.md), the command to enable Egress Gateway can be simplified to:

```bash
helm upgrade cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --reuse-values \
  --set egressGateway.enabled=true \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set ipMasqAgent.config.masqLinkLocal=true
```

:::

## Creating Egress Nodes

You can create a node pool as an Egress node pool, which can later be configured to route certain Pods' outbound traffic through these nodes. Refer to the **Creating New Node Pool** section in [Installing Cilium](install.md) for creation methods.

Things to note:

1. Use the node pool to label the scaled-out nodes (e.g., `egress-node=true`) to identify them as Egress Gateway nodes.
2. If internet access is needed, assign public IPs to the nodes.
3. To prevent regular Pods from being scheduled there, add taints.
4. Egress node pools typically don't enable auto-scaling and set a fixed number of nodes.

Below are specific operational considerations for creating node pools:

<Tabs>
  <TabItem value="1" label="Native Node Pool">

If creating through the console, make sure to check **Create Elastic Public IP**:
![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029142955.png)

Add Labels and Taints (optional):
![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F30%2F20251030140442.png)

If creating via terraform, refer to the following code snippet:

```hcl showLineNumbers
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations {
    name  = "node.tke.cloud.tencent.com/beta-image"
    value = "ts4-public"
  }
  # highlight-add-start
  # Label the scaled-out nodes with this label
  labels {
    name = "egress-node"
    value = "true"
  }
  # (Optional) Add taints to nodes to prevent regular Pods from scheduling to Egress nodes
  taints {
    key    = "egress-node"
    effect = "NoSchedule"
    value  = "true"
  }
  # highlight-add-end
  native {
    # highlight-add-start
    # Set egress node replica count
    replicas = 1
    internet_accessible {
      # Pay by traffic
      charge_type       = "TRAFFIC_POSTPAID_BY_HOUR"
      # Maximum outbound bandwidth 100Mbps
      max_bandwidth_out = 100
    }
    # highlight-add-end
    # Omit other necessary but unrelated configurations
  }
```

  </TabItem>
  <TabItem value="2" label="Regular Node Pool">

If creating through the console, make sure to check **Assign Free Public IP**:
![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029142148.png)

Add Labels and Taints (optional):
![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F30%2F20251030140442.png)

If creating via terraform, refer to the following code snippet:

```hcl showLineNumbers
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name              = "cilium"
  cluster_id        = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os           = "img-gqmik24x" # TencentOS 4, currently requires whitelisting for regular node pools
  enable_auto_scale = false # Disable auto-scaling
  desired_capacity  = 3 # Set egress node count

  auto_scaling_config {
    # highlight-add-start
    # Pay by traffic
    internet_charge_type       = "TRAFFIC_POSTPAID_BY_HOUR"
    # Assign free public IP
    internet_max_bandwidth_out = 100
    # Assign free public IP
    public_ip_assigned         = true
    # highlight-add-end
    # Omit other necessary but unrelated configurations
  }

  # highlight-add-start
  labels = {
    # Label the scaled-out nodes with this label
    "egress-node" = "true"
  }
  # highlight-add-end

  # (Optional) Add taints to nodes to prevent regular Pods from scheduling to Egress nodes
  taints {
    key    = "egress-node"
    effect = "NoSchedule"
    value  = "true"
  }
```

  </TabItem>
  <TabItem value="3" label="Karpenter Node Pool">
  
  Configure node public network in `TKEMachineNodeClass`, configure node Label in `NodePool`:

```yaml showLineNumbers
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
        beta.karpenter.k8s.tke.machine.spec/annotations: node.tke.cloud.tencent.com/beta-image=ts4-public
      # highlight-add-start
      # Label the scaled-out nodes with this label
      labels:
        egress-node: "true"
      # (Optional) Add taints to nodes to prevent regular Pods from scheduling to Egress nodes
      taints:
      - key: egress-node
        effect: NoSchedule
        value: "true"
      # highlight-add-end
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
        values: ["S5", "SA2", "SA5"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"]
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default
  limits:
    cpu: 100
---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  # highlight-add-start
  internetAccessible:
    chargeType: TrafficPostpaidByHour # Pay by traffic
    maxBandwidthOut: 100 # Maximum outbound bandwidth 100Mbps
  # highlight-add-end
  subnetSelectorTerms:
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms:
  - id: sg-nok01xpa
  sshKeySelectorTerms:
  - id: skey-3t01mlvf
```

  </TabItem>
</Tabs>

After the node pool is created and nodes are initialized, check which nodes are egress nodes and what public IPs are assigned using:

```bash
$ kubectl get nodes -o wide -l egress-node=true
NAME            STATUS   ROLES    AGE     VERSION         INTERNAL-IP     EXTERNAL-IP      OS-IMAGE               KERNEL-VERSION           CONTAINER-RUNTIME
172.22.48.125   Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.125   43.134.181.245   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.48    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.48    43.156.74.191    TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.64    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.64    43.134.178.226   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
```

## Configuring CiliumEgressGatewayPolicy

By configuring `CiliumEgressGatewayPolicy`, you can flexibly define which egress IPs are used for which Pods' traffic leaving the cluster. Refer to the official documentation [Writing egress gateway policies](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/#writing-egress-gateway-policies) for configuration methods.

## Usage Examples

### Outbound Traffic Through Fixed Egress Nodes

If you want outbound traffic to go through fixed Egress nodes (when accessing the internet, the source IP will be fixed to the public IP bound to the Egress node), refer to the following configuration method.

Deploy an `nginx` workload:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

Configure `CiliumEgressGatewayPolicy` to specify that this workload uses a specific egress node for internet access:

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  selectors:
  - podSelector: # Specify which Pods this egress policy applies to
      matchLabels:
        app: nginx # Specify Pods with app=nginx label
        io.kubernetes.pod.namespace: default # Specify default namespace
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway:
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119 # egress node name
    # Important: Testing shows that in TKE environment, the internal IP of the egress node must be specified here,
    # used to determine the source IP when the egress node forwards outbound traffic. Whether forwarding internal
    # or public network traffic, the source IP used when leaving the egress node is the node's internal IP.
    egressIP: 172.22.49.119
```

Check the egress node:

```bash
$ kubectl get nodes -o wide 172.22.49.119
NAME            STATUS   ROLES    AGE   VERSION         INTERNAL-IP     EXTERNAL-IP    OS-IMAGE               KERNEL-VERSION           CONTAINER-RUNTIME
172.22.49.119   Ready    <none>   69m   v1.32.2-tke.6   172.22.49.119   129.226.84.9   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
```

You can see the node's public IP is `129.226.84.9`. Enter the Pod to test the current egress IP:

```bash
$ kubectl -n default exec -it deployment/nginx -- curl ifconfig.me
129.226.84.9
```

The final egress IP is `129.226.84.9`, which meets expectations.

### Outbound Traffic Through a Group of Egress Nodes

If you want outbound traffic to go through a fixed group of Egress nodes (when accessing the internet, the source IP will be fixed to the public IP bound to the Egress node), refer to the following configuration method.

Deploy an `nginx` workload:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
spec:
  replicas: 10
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

Configure `CiliumEgressGatewayPolicy` to specify that this workload uses a group of Egress nodes for outbound traffic:

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  selectors:
  - podSelector: # Specify which Pods this egress policy applies to
      matchLabels:
        app: nginx # Specify Pods with app=nginx label
        io.kubernetes.pod.namespace: default # Specify namespace
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway: # This field is required. If you want to specify multiple egress nodes, you must still specify one here, otherwise it will error: spec.egressGateway: Required value
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.20 # egress node name
    egressIP: 172.22.49.20 # egress node internal IP
  egressGateways: # Add remaining egress nodes to this list
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.147
    egressIP: 172.22.49.147
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119
    egressIP: 172.22.49.119
```

Testing shows that different Pods in the workload may use different egress public IPs:

```bash
$ kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | xargs -I {} sh -c 'kubectl exec -n default -it {} -- curl -s ifconfig.me 2>/dev/null || echo "Failed"; printf ":\t%s\n" "{}"'
129.226.84.9:   nginx-54c98b4f84-5wlpc
43.156.123.70:  nginx-54c98b4f84-6jx8n
43.156.123.70:  nginx-54c98b4f84-82wmq
129.226.84.9:   nginx-54c98b4f84-8ptvh
129.226.84.9:   nginx-54c98b4f84-jfr2x
129.226.84.9:   nginx-54c98b4f84-jlrr7
43.156.123.70:  nginx-54c98b4f84-mpvpz
129.226.84.9:   nginx-54c98b4f84-s7q4s
43.156.123.70:  nginx-54c98b4f84-vsnng
43.156.123.70:  nginx-54c98b4f84-xt8bs
```

But all use the public IPs bound to the currently defined group of egress nodes:

```bash
$ kubectl get nodes -o custom-columns="NAME:.metadata.name,EXTERNAL-IP:.status.addresses[?(@.type=='ExternalIP')].address" -l egress-node=true
NAME            EXTERNAL-IP
172.22.49.119   129.226.84.9
172.22.49.147   43.156.123.70
172.22.49.20    43.163.1.23
```

### All Cluster Outbound Traffic Through Egress Nodes

If you want all Pods' outbound traffic in the cluster to go through Egress nodes, you can use `podSelector: {}` to select all cluster Pods:

```yaml showLineNumbers
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  # highlight-add-start
  selectors:
  - podSelector: {} # Select all cluster Pods
  # highlight-add-end
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway: # This field is required. If you want to specify multiple egress nodes, you must still specify one here, otherwise it will error: spec.egressGateway: Required value
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.20 # egress node name
    egressIP: 172.22.49.20 # egress node internal IP
  egressGateways: # Add remaining egress nodes to this list
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.147
    egressIP: 172.22.49.147
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119
    egressIP: 172.22.49.119
```

### Different Environments or Business Pods Using Different Egress Nodes

If different environments or business Pods are isolated by namespace, you can specify that Pods in a certain namespace use specific Egress nodes for outbound traffic:

```yaml showLineNumbers
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  selectors:
  - podSelector:
      matchLabels:
        # highlight-add-line
        io.kubernetes.pod.namespace: prod # Specify all Pods in prod namespace
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway:
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119
    egressIP: 172.22.49.119
```

If different businesses are distinguished by labels, you can specify that Pods with specific labels across all namespaces use specific Egress nodes for outbound traffic:

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  selectors:
  - podSelector:
      matchLabels:
        # highlight-add-line
        business: mall # Specify all Pods with business=mall label
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway:
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119
    egressIP: 172.22.49.119
```

## FAQ

### Network Connectivity Issues After Policy Configuration

First confirm if the CiliumEgressGatewayPolicy configuration method is correct. In TKE environment, ensure that egressGateway's nodeSelector only selects one node, and egressIP must be configured as that node's internal IP, otherwise connectivity issues may occur.

You can also log into the cilium pod on the egress node and execute `cilium-dbg bpf egress list` to view current egress bpf rules on the node:

```bash
$ kubectl -n kube-systme exec -it cilium-nz5hd -- bash
root@VM-49-119-tencentos:/home/cilium# cilium-dbg bpf egress list
Source IP      Destination CIDR   Egress IP       Gateway IP
172.22.48.4    0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.10   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.14   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.37   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.38   0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.39   0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.41   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.42   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.43   0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.44   0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.45   0.0.0.0/0          172.22.49.119   172.22.49.119
172.22.48.46   0.0.0.0/0          0.0.0.0         172.22.49.147
172.22.48.47   0.0.0.0/0          0.0.0.0         172.22.49.147
```

`Source IP` is the Pod IP, `Egress IP` is the source IP used when traffic goes through the current node, `0.0.0.0` means the current node is not forwarding traffic for the corresponding Pod IP. If all are `0.0.0.0`, it means no egress rules are selecting the current node.

### Unexpected Egress IP

Usually conflicts with NAT gateway. If the VPC routing table is configured to route public traffic through a NAT gateway, traffic may eventually go through the NAT gateway instead of using the public IP bound to the egress node. Check if the VPC routing table has routing rules configured to send traffic to the NAT gateway.

### 如何让外访流量走 VPC 之外的机器出去？

在某些特定场景下，可能希望某些 Pod 外访流量通过 VPC 之外的指定机器出去，而 cilium 使用 CiliumEgressGatewayPolicy 配置策略时必须要求 Egress 机器是当前集群的节点，正常情况下，TKE 集群添加的节点都是 VPC 内的机器，如何实现让外访流量走 VPC 之外的机器出去？

可以将 VPC 之外的机器已注册节点的形式加入到 TKE 集群中，然后在 CiliumEgressGatewayPolicy 中配置 egress gateway 为该节点即可。

具体操作方法是：

1. 在安装 cilium 之前，在 TKE 集群的基本信息页面中启用注册节点，专线连接勾选开启支持（启用后，集群的 apiserver 地址将发生变化，cilium 替代了 kube-proxy，需感知 apiserver 地址，这也是为什么要在安装 cilium 之前启用）。
   ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F12%2F12%2F20251212095535.png)
   ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F12%2F12%2F20251212100137.png)
2. 安装 cilium 并启用 Egress Gateway。
3. 准备 VPC 之外的 Egress 机器，主要要求网络与 TKE 集群所在 VPC 打通，并且 Linux 内核版本 >= 5.10。
4. 新建一个注册节点池，建议 Labels 和 Taints 都打上（Taints 示例 `egress-node=true:NoSchedule`，可避免普通 Pod 被调度到该节点上，因为注册节点无法使用 VPC-CNI 网络插件，无法分配到 Pod IP，只能使用 HostNetwork）。
5. 进入新建的注册节点池，点击新建节点，按照提示复制注册脚本并在 VPC 之外的 Egress 机器上执行，让该机器作为节点加入到 TKE 集群中。
6. 按需配置 CiliumEgressGatewayPolicy，让指定的外访流量走该 VPC 之外的机器出去，示例：
   ```yaml
   apiVersion: cilium.io/v2
   kind: CiliumEgressGatewayPolicy
   metadata:
     name: egress-test
   spec:
     selectors:
     - podSelector: # 指定该 egress 策略针对哪些 Pod 生效
         matchLabels:
           app: nginx # 指定带 app=nginx 标签的 Pod
           io.kubernetes.pod.namespace: test # 指定 default 命名空间
     destinationCIDRs:
     - "0.0.0.0/0"
     - "::/0"
     egressGateway:
       nodeSelector:
         matchLabels:
           kubernetes.io/hostname: node-10.111.128.148 # egress 注册节点名称
       # 重要：经测试在 TKE 环境这里必须指定使用 egress 节点的内网 IP，
       # 用于决定 egress 节点转发外访流量时使用什么源 IP，不管是转发内网
       # 还是公网流量，出 egress 节点时使用的源 IP 都是使用节点的内网 IP。
       egressIP: 10.111.128.148
   ```

## Reference Materials

- [Cilium Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)
