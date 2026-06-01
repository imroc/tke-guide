# 为什么 Native Routing 模式要加 local-router-ipv4 配置？

## 背景

在 TKE 集群安装 cilium 时，如果选择 **Native Routing**（无论是 VPC-CNI 还是 GR 基础集群），都必须显式给 cilium 配置一个 `local-router-ipv4` 参数：

```bash
--set extraConfig.local-router-ipv4=169.254.32.16
```

而 **Overlay 模式**则不需要这个配置。本文解释这个差异背后的原因，以及为什么我们选择 `169.254.32.16` 这个具体地址。

## cilium_host 网卡的作用

cilium 在每台节点上都会创建一对虚拟网卡：

- `cilium_host`：节点上的"网关"接口，作为本节点上所有 Pod 的下一跳。
- `cilium_net`：与 `cilium_host` 配对的 veth peer。

`cilium_host` 必须有一个 IP 地址，否则节点内的路由会缺一个"出口"。

```text
                ┌──────────────────────────────────────┐
                │                Node                  │
                │                                      │
                │   ┌──────────┐      ┌────────────┐   │
                │   │   Pod    │─────▶│ cilium_host│──▶│  外发
                │   │ (lxcXX)  │      │  (gateway) │   │
                │   └──────────┘      └────────────┘   │
                └──────────────────────────────────────┘
```

## Native Routing 模式的特殊情况

Native Routing 模式下，**cilium 不负责 Pod IP 分配**，IP 由底层 TKE CNI 分配：

- **Native Routing (VPC-CNI)**：Pod 直接挂在弹性网卡上，IP 由 VPC-CNI 从 VPC 子网中分配。cilium 完全没有 Pod IP 来源信息。
- **Native Routing (GR)**：Pod IP 由 tke-bridge 从节点的 PodCIDR 中分配，每节点 PodCIDR 不同。虽然 tke-bridge 的网关 IP（如 `<PodCIDR>.1`）已被节点路由占用，cilium 也无法直接复用它（每节点都要单独算一次，且会和原网关冲突）。

由于 cilium 不掌握 IP 分配权，它无法自动决定 `cilium_host` 用什么 IP，因此必须由用户通过 `local-router-ipv4` 显式指定一个"绝对不会与 Pod IP 冲突"的地址。

## 为什么是 169.254.32.16？

`169.254.0.0/16` 是 IPv4 link-local 地址段（RFC 3927），有以下特点：

1. **不可路由**：永远不会和 VPC IP、GR 网段或 Service CIDR 冲突。
2. **跨节点统一**：所有节点都可以用同一个值，配置和排障更简单。
3. **TKE 特定预留**：`169.254.32.16` 这个具体地址在 TKE 上不会被其它组件占用，是经过验证的安全值。

:::tip[TKE 上 169.254 段的其它用途]

TKE 在 `169.254.0.0/16` 段还承载了以下能力，配置时要注意不要冲突：

- 元数据服务（IMDS）
- apiserver 的内部 VIP（`kubectl get ep kubernetes` 看到的地址）
- COS / 镜像仓库 / 部分内部服务的 VIP

`169.254.32.16` 是已确认与上述服务不冲突的地址。

:::

## Overlay 模式为什么不需要

Overlay 模式下，cilium 自己管理 Pod IP 分配（cluster-pool IPAM），它知道节点 PodCIDR 的所有信息，会自动为 `cilium_host` 从 PodCIDR 中分配一个不冲突的 IP，无需用户介入。

## 总结

| 模式                     | local-router-ipv4 | 原因                                        |
| ------------------------ | ----------------- | ------------------------------------------- |
| Native Routing (VPC-CNI) | ✅ 必须显式配置   | cilium 不掌握 Pod IP 分配权                 |
| Native Routing (GR)      | ✅ 必须显式配置   | 同上；且每节点 PodCIDR 不同，无统一网关可用 |
| Overlay (VPC-CNI / GR)   | ❌ 自动分配       | cilium 自己管理 IPAM                        |

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium Docs - local-router-ipv4](https://docs.cilium.io/en/stable/network/concepts/routing/)
