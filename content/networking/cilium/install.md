# 安装 Cilium

## 概述

本文介绍如何在 TKE 集群中安装 Cilium。

## 前提条件

- 集群版本：1.22 及以上
- 网络模式：VPC-CNI 或 GlobalRouter
- 节点类型：普通节点或原生节点
- 操作系统：TencentOS 4

## 网络选型：Encapsulation vs Native-Routing

Cilium 路由支持两种模式：
1. Encapsulation（封装模式）：即在原有的网络基础上再做一层网络封包进行转发。优点是兼容性好，可适配各种网络环境，缺点是性能较差。
2. Native-Routing（原生路由）：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。优点是性能好，缺点是依赖底层网络对 Pod IP 的路由转发的支持，不通用。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，底层网络都已支持 Pod IP 的路由转发，如果对网络转发性能有要求，推荐使用 Native-Routing 模式，如果希望安装更简单通用，可使用 Encapsulation 模式。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。
