# 使用 CLB 为 Pod 分配公网地址映射

## 概述

房间类的游戏一般都要求每个每个房间都需要有独立的公网地址，TKE 集群默认只支持 EIP 方案，但 EIP 资源有限，有申请的数量限制和每日申请的次数限制（参考 [EIP 配额限制](https://cloud.tencent.com/document/product/1199/41648#eip-.E9.85.8D.E9.A2.9D.E9.99.90.E5.88.B6)），稍微上点规模，或频繁扩缩容更换EIP，可能很容易触达限制导致 EIP 分配失败；而如果保留 EIP，在 EIP 没被绑定前，又会收取额外的闲置费。

> TKE Pod 绑定 EIP 参考 [Pod 绑 EIP](https://imroc.cc/tke/networking/pod-eip)。
>
> 关于 EIP 与 CLB 映射两种方案的详细对比参考 [TKE 游戏方案：房间类游戏网络接入](https://imroc.cc/tke/game/room-networking)。

除了 EIP 方案，您还可以使用 `tke-extend-network-controller` 插件的方案，本文将介绍如何使用 `tke-extend-network-controller` 插件来实现为每个 Pod 的指定端口都分配一个独立的公网地址映射(公网 `IP:Port` 到内网 Pod `IP:Port` 的映射)。

> `tke-extend-network-controller` 的代码是开源的，源码托管在 GitHub: https://github.com/tkestack/tke-extend-network-controller

## 安装 tke-extend-network-controller

参考 [安装 tke-extend-network-controller](../networking/tke-extend-network-controller)。

## 确保 Pod 调度到原生节点或超级节点

要使用 CLB 为 Pod 分配公网地址映射的能力，需要保证承载游戏房间的 Pod 调度到原生节点或超级节点上，如果 Pod 在普通节点（CVM），将不会为该 Pod 分配 CLB 公网地址映射。

## 使用 CLB 端口池为 Pod 映射公网地址

参考 [使用 CLB 端口池为 Pod 映射公网地址](https://github.com/tkestack/tke-extend-network-controller/blob/main/docs/clb-port-pool.md)。
