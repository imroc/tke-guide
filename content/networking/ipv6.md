# 在 TKE 上使用 IPv6

## VPC 和子网要求

集群所在 VPC 需启用 IPv6，启用方法是在【[私有网络](https://console.cloud.tencent.com/vpc/vpc)】页面，选中集群所使用的 VPC，点击【更多】-【编辑IPv6 CIDR】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164608.png)

然后点【获取】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164416.png)

然后在【[子网](https://console.cloud.tencent.com/vpc/subnet)】页面，选中 VPC，然后对需要使用 IPv6 的子网点击【更多】-【获取 IPv6 CIDR】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164815.png)

## 超级节点使用 IPv6

如果你能让需要 IPv6 的 Pod 调度到超级节点上，那么对集群网络就没有要求，只需在创建超级节点时选分配了 IPv6 网段的子网，然后在工作负载里为 Pod 指定下注解就能让 Pod 支持 IPv6:

<FileBlock file="nginx-ipv6-eks.yaml" showLineNumbers />

## 其它节点使用 IPv6

如果你不能保证让需要 IPv6 的 Pod 调度到超级节点（比如调度到CVM节点、原生节点），可以在创建 `标准集群` 的时候选支持 `IPv4/IPv6双栈` 的操作系统，然后网络就选择【IPv4/IPv6双栈】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709165012.png)

后续在集群中创建的任何 Pod 就都会带有 IPv6 了。
