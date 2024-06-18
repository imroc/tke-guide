# 从 TCM 迁移到自建 istio

## 概述

腾讯云服务网格（Tencent Cloud Mesh, TCM）是基于 TKE 的 istio 托管服务，未来将会下线，本文介绍如何从 TCM 迁移到自建 istio。

## 迁移思路

istio 架构分为控制面和数据面，控制面是 istiod，数据面是网关 (istio-ingressgateway/istio-egressgateway) 或 sidecar，数据面的本质上都是使用 Envoy 作为代理程序，控制面会将计算出的流量规则通过 `xDS` 下发给数据面：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618150336.png)

TCM 主要托管的是 isitod，迁移的关键点就是使用自建的 istiod 替换 TCM 的 isitod。
