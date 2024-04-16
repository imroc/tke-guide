# 自定义负载均衡器(CLB)

## 概述

默认安装会自动创建出一个公网 CLB 来接入流量，但你也可以利用 TKE 的 Service 注解对 Nginx Ingress Controller 的 CLB 进行自定义，本文介绍自定义的方法。

## 使用内网 CLB

比如改成内网 CLB，在 `values.yaml` 中这样定义:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: 'subnet-xxxxxx' # 内网 CLB 需指定 CLB 实例所在的子网 ID
```

## 使用已有 CLB

你也可以直接在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 根据自身需求创建一个 CLB （比如自定义实例规格、运营商类型、计费模式、带宽上限等），然后在 `values.yaml` 中用注解复用这个 CLB:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/tke-existed-lbid: 'lb-xxxxxxxx' # 指定已有 CLB 的实例 ID
```

> 参考文档 [Service 使用已有 CLB](https://cloud.tencent.com/document/product/457/45491)。

:::info[注意]

在 CLB 控制台创建 CLB 实例时，选择的 VPC 需与集群一致。

:::

## 使用内外网双 CLB

有时需要让 nginx ingress 同时使用公网和内网 CLB 接入流量，此时可以配置 nginx ingress 使用两个 service，默认是创建一个公网 CLB Service， 如果还需要一个内网 CLB 的 Service，可以配置 internal service：

```yaml
controller:
  service:
    internal:
      # highlight-start
      enabled: true # 创建内网 CLB Service
      annotations:
        service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-xxxxxxxx" # 配置内网 CLB 的子网
      # highlight-end
```
