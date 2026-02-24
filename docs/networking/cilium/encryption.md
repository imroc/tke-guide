# 启用通信加密

## 概述

本文介绍如何使用 Cilium 给流量进行加密。

## 可以使用哪些加密方式？

Cilium 支持以下加密方式：

- ipsec（默认）
- wireguard （需确保内核安装了 wireguard 内核模块）
- ztunnel（与 isito ambient 模式共存时可使用）

如果 Pod 使用 VPC-CNI 网络，不能使用 ipsec 方式加密，推荐使用 wireguard 方式加密。

## 启用 wireguard 加密

使用 wireguard 方式加密的前提条件是内核安装了 wireguard 内核模块（已知 TencentOS 4 是有的）。

启用 wireguard 加密的方法：

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
```

## 参考资料

- [Cilium Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption/)
