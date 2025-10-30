# 使用 Egress Gateway 控制外访流量

## 已知问题

使用 Cilium 的 Egress Gateway 功能存在以下已知问题：
1. 对新 Pod 执行 Egress 策略有延迟。新 Pod 启动后，如果该 Pod 命中 Egress 策略，期望 Pod 的外访流量走指定出口网关出去，但实际上在 Pod 刚启动的一段时间内，该策略可能并未生效。
2. 与 Cilium 的 Cluster Mesh 和 CiliumEndpointSlice 功能不兼容。

## 启用 Egress Gateway

如果要启用 Egress Gateway，需满足以下条件：
1. 启用 cilium 替代 kube-proxy。
2. 启用 ip masquerade，且使用 bpf 的实现进行 masquerade 而非默认的 iptables 实现。

启用 Egress Gateway 的 cilium 安装方法：

:::info[注意]

`VPC_CIDR` 需替换为 TKE 集群所在 VPC 的实际 ipv4 网段。

:::

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  # highlight-add-start
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002 \
  --set egressGateway.enabled=true \
  --set enableIPv4Masquerade=true \
  --set ipv4NativeRoutingCIDR="VPC_CIDR" \
  --set bpf.masquerade=true
  # highlight-add-end
```

然后重启 cilium 组件生效：

```bash
kubectl rollout restart ds cilium -n kube-system
kubectl rollout restart deploy cilium-operator -n kube-system
```

:::tip[备注]

如果你是使用 [安装cilium](install.md) 中 **使用 helm 安装 cilium** 给的安装方法进行了安装，可通过以下方式开启 Egress Gateway：

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set egressGateway.enabled=true \
  --set enableIPv4Masquerade=true \
  --set ipv4NativeRoutingCIDR="VPC_CIDR" \
  --set bpf.masquerade=true
```

:::

## 创建 Egress 节点

可以创建一个节点池作为 Egress 节点池，后续可以配置让某些 Pod 出集群的流量经过这些节点出去，创建方法参考 [安装cilium](install.md) 中 **新建节点池** 部分。

需要注意的是：
1. 要通过节点池为扩出来的节点打上 label（如 `egress-node=true`）用以标识的用于 Egress Gateway。
2. 如果需要出公网，要为节点分配公网 IP。
3. 如果不希望普通 Pod 调度过去，可以加下污点。

以下是操作创建节点池的具体注意事项参考。

<Tabs>
  <TabItem value="1" label="原生节点池">

  如果通过控制台创建，注意勾选**创建弹性公网IP**:
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029142955.png)

  新增一下 Labels:
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029143056.png)

  如果通过 terraform 创建，参考以下代码片段：
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
    # 给扩出来的 Node 打上这个 label
    labels {
      name = "egress-node"
      value = "true"
    }
    # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
    taints {
      key    = "egress-node"
      effect = "NoSchedule"
      value  = "true"
    }
    # highlight-add-end
    native {
      # highlight-add-start
      internet_accessible {
        # 按流量计费
        charge_type       = "TRAFFIC_POSTPAID_BY_HOUR"
        # 最大出带宽 100Mbps
        max_bandwidth_out = 100
      }
      # highlight-add-end
      # 省略其它必要但不相关配置
    }
```
  </TabItem>
  <TabItem value="2" label="普通节点池">

  如果通过控制台创建，注意勾选**分配免费公网IP**:
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029142148.png)

  新增一下 Labels:
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F29%2F20251029142311.png)

  如果通过 terraform 创建，参考以下代码片段：

  ```hcl showLineNumbers
  resource "tencentcloud_kubernetes_node_pool" "cilium" {
    name       = "cilium"
    cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
    node_os    = "img-gqmik24x"

    auto_scaling_config {
      # highlight-add-start
      # 按流量计费
      internet_charge_type       = "TRAFFIC_POSTPAID_BY_HOUR"
      # 分配免费公网IP
      internet_max_bandwidth_out = 100
      # 分配免费公网IP
      public_ip_assigned         = true 
      # highlight-add-end
      # 省略其它必要但不相关配置
    }

    # highlight-add-start
    labels = {
      # 给扩出来的 Node 打上这个 label
      "egress-node" = "true"
    }
    # highlight-add-end

    # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
    taints {
      key    = "egress-node"
      effect = "NoSchedule"
      value  = "true"
    }
  ```

  </TabItem>
  <TabItem value="3" label="Karpenter 节点池">
  
  在 `TKEMachineNodeClass` 配置节点公网，在 `NodePool` 配置节点 Label：

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
        # 给扩出来的 Node 打上这个 label
        labels:
          egress-node: "true"
        # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
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
      chargeType: TrafficPostpaidByHour # 按流量计费
      maxBandwidthOut: 100 # 最大出带宽 100Mbps
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

节点池创建并初始化节点后，通过如下方式查看哪些节点是 Egress Gateway 使用的节点，以及分配的公网 IP 是什么：

```bash
$ kubectl get nodes -o wide -l egress-node=true
NAME            STATUS   ROLES    AGE     VERSION         INTERNAL-IP     EXTERNAL-IP      OS-IMAGE               KERNEL-VERSION           CONTAINER-RUNTIME
172.22.48.125   Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.125   43.134.181.245   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.48    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.48    43.156.74.191    TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.64    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.64    43.134.178.226   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
```

## 配置 CiliumEgressGatewayPolicy

通过配置 `CiliumEgressGatewayPolicy` 可以灵活的定义哪些 Pod 的流量走哪些网关的出口 IP 出集群，配置方法参考官方文档 [Writing egress gateway policies](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/#writing-egress-gateway-policies)。

## 使用案例
### 外访流量走固定的 Egress 节点出去

如果希望让外访流量通过固定的 Egress 节点出去（出公网时，出口源 IP 将固定是 Egress 节点绑定的公网 IP），可参考下面的方法配置。

部署一个 `nginx` 工作负载：

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

通过配置 `CiliumEgressGatewayPolicy` 来指定该工作负载使用指定 Egress Gateway 节点访问公网：

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
        io.kubernetes.pod.namespace: default # 指定 default 命名空间
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway:
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119 # egress 节点名称
    # 重要：经测试在 TKE 环境这里必须指定使用 egress 节点的内网 IP，
    # 用于决定 egress 节点转发外访流量时使用什么源 IP，不管是转发内网
    # 还是公网流量，出 egress 节点时使用的源 IP 都是使用节点的内网 IP。
    egressIP: 172.22.49.119
```

查看 Egress Gateway 节点：

```bash
$ kubectl get nodes -o wide 172.22.49.119
NAME            STATUS   ROLES    AGE   VERSION         INTERNAL-IP     EXTERNAL-IP    OS-IMAGE               KERNEL-VERSION           CONTAINER-RUNTIME
172.22.49.119   Ready    <none>   69m   v1.32.2-tke.6   172.22.49.119   129.226.84.9   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
```

可以看到该节点的公网 IP 为 `129.226.84.9`，进入 Pod 测试当前出口 IP：

```bash
$ kubectl -n default exec -it deployment/nginx -- curl ifconfig.me
129.226.84.9
```

可以看到最终的出口 IP 就是 `129.226.84.9`，符合预期。

### 外访流量走一组 Egress 节点出去

如果希望让外访流量通过固定的一组 Egress 节点出去（出公网时，出口源 IP 将固定是 Egress 节点绑定的公网 IP），可参考下面的方法配置。

部署一个 `nginx` 工作负载：

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

通过配置 `CiliumEgressGatewayPolicy` 来指定该工作负载通过一组 Egress 节点进行流量外访：

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-test
spec:
  selectors:
  - podSelector: # 指定该 egress 针对哪些 Pod 生效
      matchLabels:
        app: nginx # 指定带 app=nginx 标签的 Pod
        io.kubernetes.pod.namespace: default # 指定命名空间
  destinationCIDRs:
  - "0.0.0.0/0"
  - "::/0"
  egressGateway: # 该字段是必填的，如果要指定多个 egress 节点，这里还是必须要指定一个，不然会报错： spec.egressGateway: Required value
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.20 # egress 节点名称
    egressIP: 172.22.49.20 # egress 节点内网 IP
  egressGateways: # 其余的 egress 节点追加到这个列表
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.147
    egressIP: 172.22.49.147
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: 172.22.49.119
    egressIP: 172.22.49.119
```

测试可以看到工作负载中各个 Pod 使用的出口公网 IP 可能不同：

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

但都使用的当前定义的这组 egress 节点所绑定的公网 IP：

```bash
$ kubectl get nodes -o custom-columns="NAME:.metadata.name,EXTERNAL-IP:.status.addresses[?(@.type=='ExternalIP')].address" -l cilium.io/egress-gateway=true
NAME            EXTERNAL-IP
172.22.49.119   129.226.84.9
172.22.49.147   43.156.123.70
172.22.49.20    43.163.1.23
```

## 常见问题

### 配置 CiliumEgressGatewayPolicy 后网络不通

首先确认 CiliumEgressGatewayPolicy 配置方法是否正确，在 TKE 环境下，确保 egressGateway 的 nodeSelector 只选中一个 node，egressIP 必须配置该 node 的内网 IP，否则可能就会出现不通的问题。

另外还可以登录 egress 节点所在的 cilium pod，执行 `cilium-dbg bpf egress list` 查看当前节点上的 egress bpf 规则：

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

`Source IP` 是 Pod IP，`Egress IP` 是走当前节点出去使用的源 IP， `0.0.0.0` 表示当前节点没有转发对应 Pod IP 的流量，如果全都为 `0.0.0.0` 表示没有 egress 规则选中当前节点。

### 出口 IP 不符预期

通常是跟 NAT 网关冲突，如果 VPC 路由表配置了公网走 NAT 网关，最终就可能走 NAT 网关出公网而不是用 egress 节点绑定的公网 IP  出去。

## 参考资料

- [Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)
