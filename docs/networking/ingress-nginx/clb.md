# 自定义负载均衡器(CLB)

## 概述

默认安装会自动创建出一个公网 CLB 来接入流量，但你也可以利用 TKE 的 Service 注解对 Nginx Ingress Controller 的 CLB 进行自定义，本文介绍自定义的方法。

## 使用内网 CLB

比如改成内网 CLB，在 `values.yaml` 中这样定义:

```yaml showLineNumbers
controller:
  service:
    annotations:
      service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: 'subnet-xxxxxx' # 内网 CLB 需指定 CLB 实例所在的子网 ID
```

## 使用已有 CLB

你也可以直接在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 根据自身需求创建一个 CLB （比如自定义实例规格、运营商类型、计费模式、带宽上限等），然后在 `values.yaml` 中用注解复用这个 CLB:

```yaml showLineNumbers
controller:
  service:
    annotations:
      service.kubernetes.io/tke-existed-lbid: 'lb-xxxxxxxx' # 指定已有 CLB 的实例 ID
```

> 参考文档 [Service 使用已有 CLB](https://cloud.tencent.com/document/product/457/45491)。

:::info[注意]

在 CLB 控制台创建 CLB 实例时，选择的 VPC 需与集群一致。

:::

## 公网和内网 IP 同时接入

有时需要让 nginx ingress 同时使用公网和内网的 IP 来接入流量，有以下两种方案可以实现。

### 方案一：双 Service

第一种思路是配置 nginx ingress 使用两个 service，默认是创建一个公网 CLB Service， 如果还需要一个内网 CLB 的 Service，可以配置 internal service：

```yaml showLineNumbers
controller:
  service:
    internal:
      # highlight-start
      enabled: true # 创建内网 CLB Service
      annotations:
        service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-xxxxxxxx" # 配置内网 CLB 的子网
      # highlight-end
```

### 方案二：内网 CLB 绑 EIP

另一种思路是 [使用内网 CLB](#使用内网-clb)，然后再跳转到 CLB 控制台，给 CLB 再绑个 EIP（参考 CLB 官方文档：[内网负载均衡实例绑定 EIP](https://cloud.tencent.com/document/product/214/65682)）。

:::tip[注意]

该功能是 CLB 的内测功能，需要提工单申请开通。

:::

## CLB 跨域绑定

如果你想使用其它地域或 VPC 的 CLB 来接入流量，可以利用 CLB 的 [跨地域绑定2.0](https://cloud.tencent.com/document/product/214/48180) 和 TKE 的 [Service 跨域绑定](https://cloud.tencent.com/document/product/457/59094) 能力来实现，需要满足以下前提条件:
1. 账号是带宽上移类型。
2. 两个 VPC 通过云联网打通了。
3. 开通了CLB的跨地域绑定2.0 功能(提工单开通)。

然后将 CLB 的 ID、所在地域和 VPC 信息配在注解里:

```yaml showLineNumbers
controller:
  service:
    # highlight-start
    annotations:
      service.cloud.tencent.com/cross-region-id: "ap-guangzhou"  # 如果CLB在其它地域，指定下CLB所在地域
      service.cloud.tencent.com/cross-vpc-id: "vpc-xxx" # 指定CLB所在VPC
      service.kubernetes.io/tke-existed-lbid: "lb-xxx" # 如果使用已有CLB，指定下CLB ID
    # highlight-end
```
