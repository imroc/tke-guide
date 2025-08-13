# 安装 Cilium

## 概述

本文介绍如何在 TKE 集群中安装 Cilium。

## 前提条件

- 集群版本：1.22 及以上
- 网络模式：VPC-CNI 或 GlobalRouter
- 节点类型：普通节点或原生节点
- 操作系统：TencentOS 4

## 网络选型：Encapsulation vs Native-Routing

参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。
