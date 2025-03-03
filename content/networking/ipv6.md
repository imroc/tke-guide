# 在 TKE 上使用 IPv6

## 为 Pod 分配 IPv6 地址

下面介绍在 TKE 中如何为 Pod 分配 IPv6 地址。

### 前提条件

1. 集群所在 VPC 启用 IPv6，并且使用的子网需获取 IPv6 CIDR。
2. 如果 Pod 需调度到普通节点或原生节点，在创建集群时，集群 IP 类型选 `IPv4/IPv6双栈`。


### VPC 和子网启用 IPv6 的方法

在[私有网络](https://console.cloud.tencent.com/vpc/vpc)页面，选中集群所使用的 VPC，点击**更多**-**编辑IPv6 CIDR**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164608.png)

然后点**获取**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164416.png)

然后在[子网](https://console.cloud.tencent.com/vpc/subnet)页面，选中 VPC，然后对需要使用 IPv6 的子网点击**更多**-**获取 IPv6 CIDR**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164815.png)

### 超级节点使用 IPv6

如果你能让需要 IPv6 的 Pod 调度到超级节点上，那么对集群网络就没有要求，只需在创建超级节点时选分配了 IPv6 网段的子网，然后在工作负载里为 Pod 指定下注解就能让 Pod 支持 IPv6:

```yaml showLineNumbers
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      annotations:
        # highlight-start
        tke.cloud.tencent.com/ipv6-attributes: '{"InternetMaxBandwidthOut": 100}'
        tke.cloud.tencent.com/need-ipv6-addr: "true"
        # tke.cloud.tencent.com/ipv6-attributes: '{"BandwidthPackageId":"bwp-xxx","InternetChargeType":"BANDWIDTH_PACKAGE","InternetMaxBandwidthOut":1}' # 如需带宽包，参考这个配置
        # highlight-end
      labels:
        app: nginx
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: eklet # 调度到超级节点
      containers:
        - image: nginx:latest
          name: nginx
```

### 普通节点或原生节点使用 IPv6

如果你的 Pod 调度到普通节点或原生节点，需要在创建 `标准集群` 的时候选支持 `IPv4/IPv6双栈` 的操作系统，且集群 IP 类型选择**IPv4/IPv6双栈**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709165012.png)

后续在集群中创建的任何 Pod 就都会带有 IPv6 了。
