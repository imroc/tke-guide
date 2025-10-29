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

## 为 Egress Gateway 新建节点池

创建一个节点池作为 Egress Gateway 使用的节点池，后续可以配置让某些 Pod 出集群的流量经过这些节点出去，创建方法参考 [安装cilium](install.md) 中 **新建节点池** 部分。

需要注意的是：
1. 要通过节点池为扩出来的节点打上 label（如 `cilium.io/egress-gateway=true`）用以标识的用于 Egress Gateway。
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
      name = "cilium.io/egress-gateway"
      value = "true"
    }
    # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
    taints {
      key    = "cilium.io/egress-gateway"
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
      "cilium.io/egress-gateway" = "true"
    }
    # highlight-add-end

    # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
    taints {
      key    = "cilium.io/egress-gateway"
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
          cilium.io/egress-gateway: "true"
        # （可选）给节点加污点，避免普通 Pod 调度到 Egress Gateway 节点
        taints:
        - key: cilium.io/egress-gateway
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
$ kubectl get nodes -o wide -l cilium.io/egress-gateway=true
NAME            STATUS   ROLES    AGE     VERSION         INTERNAL-IP     EXTERNAL-IP      OS-IMAGE               KERNEL-VERSION           CONTAINER-RUNTIME
172.22.48.125   Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.125   43.134.181.245   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.48    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.48    43.156.74.191    TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
172.22.48.64    Ready    <none>   3h17m   v1.32.2-tke.6   172.22.48.64    43.134.178.226   TencentOS Server 4.4   6.6.98-40.2.tl4.x86_64   containerd://1.6.9-tke.8
```

## 配置 CiliumEgressGatewayPolicy

通过配置 `CiliumEgressGatewayPolicy` 可以灵活的定义哪些 Pod 的流量走哪些网关的出口 IP 出集群，配置方法参考官方文档 [Writing egress gateway policies](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/#writing-egress-gateway-policies)。

## 使用案例
### 指定工作负载出口 IP

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
    # 选中 Egress Gateway 节点
    nodeSelector:
      matchLabels:
        cilium.io/egress-gateway: "true"
    # 指定使用 Egress Gateway 节点的内网 IP 出去
    # （即使是出公网，也是指定节点内网 IP，不能直接使用公网 IP）
    egressIP: "172.22.49.119"
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

## 参考资料

- [Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)
