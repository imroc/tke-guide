# 在 TKE 上使用 IPv6

## VPC 和子网要求

集群所在 VPC 需启用 IPv6，启用方法是在【[私有网络](https://console.cloud.tencent.com/vpc/vpc)】页面，选中集群所使用的 VPC，点击【更多】-【编辑IPv6 CIDR】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164608.png)

然后点【获取】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164416.png)

然后在【[子网](https://console.cloud.tencent.com/vpc/subnet)】页面，选中 VPC，然后对需要使用 IPv6 的子网点击【更多】-【获取 IPv6 CIDR】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164815.png)

## 集群要求

创建集群时选【标准集群】，操作系统需要选择支持 `IPv4/IPv6双栈` 的操作系统，然后网络选择【IPv4/IPv6双栈】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709165012.png)

## 创建节点池

创建节点池时，子网需选择分配了 IPv6 网段的子网。

## Workload 指定 IPv6

如果使用超级节点，通过注解指定 Pod 使用 IPv6:

```yaml
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
