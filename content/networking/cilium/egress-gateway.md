# 使用 Egress Gateway 控制集群外部访问

## 启用 Egress Gateway

如果要启用 Egress Gateway，需要使用 cilium 替代 kube-proxy 方式部署，另外还需要启用 bpf masquerade 功能，如果使用 [安装cilium](install.md) 中的默认安装参数，可通过以下方式启用 Egress Gateway:

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
   --namespace kube-system \
   --reuse-values \
   --set egressGateway.enabled=true \
   --set bpf.masquerade=true 
```

然后重启 cilium 组件生效：

```bash
kubectl rollout restart ds cilium -n kube-system
kubectl rollout restart deploy cilium-operator -n kube-system
```

## 新建 Egress Gateway 节点池

创建一个节点池作为 Egress Gateway 使用的节点池，可以让出集群的流量经过这些节点出去，创建方法参考 [安装cilium](install.md) 中 **新建节点池** 部分。

需要注意的是，要为节点分配公网 IP 并打上用以标识的 label（如 `cilium.io/egress-gateway=true`）。

以下是操作创建节点池的具体注意事项参考：

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
    labels {
      # 给扩出来的 Node 打上这个 label
      name = "cilium.io/egress-gateway"
      value = "true"
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
        labels:
          # highlight-add-line
          cilium.io/egress-gateway: "true" # 给扩出来的 Node 打上这个 label
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
    # highlight-end-start
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

## 参考资料

- [Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)
