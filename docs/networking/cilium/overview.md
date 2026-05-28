# 概述

[cilium](https://cilium.io/) 是一个开源的云原生网络解决方案，可以为 Kubernetes 集群提供更多高级的网络能力。

本系列实践教程将介绍如何在 TKE 集群中根据自身需求来安装和使用 cilium。

## 网络模式

Cilium 路由支持两种模式：

1. `Encapsulation`（封装模式）：即在原有的网络基础上再做一层网络封包进行转发。优点是兼容性好，可适配各种网络环境，缺点是性能较差。
2. `Native-Routing`（原生路由）：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。优点是性能好，缺点是依赖底层网络对 Pod IP 的路由转发的支持，不通用。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，VPC 底层网络都已支持 Pod IP 的路由转发，无需再走一层 overlay，可获得最佳的网络性能，所以通常使用 `Native-Routing` 模式。

但如果你有以下需求，可以选择 `Encapsulation`（vxlan overlay）模式：

- VPC IP 资源紧张，不希望 Pod IP 占用 underlay IP。
- 需要纳管 IDC 集群，替代 TKE 内置的 CiliumOverlay 网络模式。
- 希望使用最新版本的 cilium，获得满血功能（不与 kube-proxy 共存，避免 NetworkPolicy 等功能降级）。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。

## 前提条件

如果要在 TKE 集群中安装 cilium，需满足以下前提条件：

- 集群版本：TKE 1.32 及以上，参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)。
- 节点类型：普通节点或原生节点。
- 操作系统：TencentOS 4 或 Ubuntu>=22.04。
