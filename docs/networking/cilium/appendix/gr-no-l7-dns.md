# 为什么 GR Native Routing 不支持 L7/DNS NetworkPolicy？

## 背景

在 TKE 集群安装 cilium 后，配置 NetworkPolicy 时，你可能希望使用 **L7/DNS 能力**：

- `toFQDNs`：按域名做出向访问控制
- `toPorts.rules.dns`：按域名模式做 DNS 查询过滤

这两类规则在 **Native Routing (GR)** 模式下**不支持**。被这类策略选中的 Pod 会出现 DNS 查询超时，**所有 DNS 解析都不通**（不是 NXDOMAIN/REFUSED，而是无任何响应），即使是集群内服务名（如 `kubernetes.default.svc`）也无法解析。

本文解释该限制的由来与解决方案。

## 这是 cilium 的已知限制

cilium 官方文档已明确将 "Layer 7 Policy" 列为 generic-veth chaining 模式的 Limitations 之一：

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- 跟踪 issue: [cilium/cilium#12454 - Proxy redirect issue when running Cilium on top of Calico (CNI-Chaining)](https://github.com/cilium/cilium/issues/12454)（涉及 packet mark 冲突导致 proxy redirect 失败，与本文 GR 场景同源）

## 技术原理

cilium 的 L7 DNS 策略实现链路：

1. cilium 通过 BPF 程序识别被策略选中的 Pod 发出的 DNS 流量，给数据包打 mark。
2. iptables TPROXY 规则根据 mark 把 DNS 包重定向到 cilium-agent 内置的 DNS 代理 socket。
3. DNS 代理解析、记录响应，并把响应中的 IP 加入到 toFQDNs 的允许列表。

```text
Pod ──DNS query──▶ BPF (打 mark) ──▶ iptables TPROXY ──▶ cilium DNS proxy ──▶ upstream DNS
                                       ▲
                                       │
                                       └─ 依赖 socket dispatch（lookup → process socket）
```

### GR 模式的失败点

GR 模式使用 [generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/) 与 tke-bridge 共存，Pod 流量经过 Linux bridge `cbr0`：

```text
Pod ─▶ veth ─▶ cbr0 (bridge forwarding) ─▶ eth0 ─▶ upstream
                  ▲
                  │
                  └─ 桥转发路径上，包不会进入 IP routing/socket lookup
                     iptables TPROXY 无法做 socket dispatch
```

桥转发路径上的数据包**不会真正进入 IP routing / socket lookup**，因此 iptables TPROXY 的 socket dispatch 不生效，cilium DNS 代理收不到流量。

### VPC-CNI 和 Overlay 为什么没有这个问题

- **VPC-CNI Native Routing**：Pod 直接挂在弹性网卡上，不经过 `cbr0`，DNS 重定向链路完整。
- **Overlay (VPC-CNI / GR)**：cilium 完全接管 Pod datapath，所有流量都走 cilium 的 BPF，DNS 重定向链路完整。

## 症状与识别

在 GR Native Routing 模式下，**被含 `rules.dns` 或 `toFQDNs` 的 CiliumNetworkPolicy 选中的 Pod**：

- 所有 DNS 查询都会超时
- 不会返回 NXDOMAIN 或 REFUSED，而是**无任何响应**（DNS 客户端看到的是超时）
- 即使是集群内服务名（如 `kubernetes.default.svc.cluster.local`）也无法解析
- 一旦移除该 NetworkPolicy，Pod 立即恢复正常解析

## 替代方案

如果你在 GR Native Routing 模式下，需要做出向访问控制：

| 替代方案                            | 适用场景                         | 局限                          |
| ----------------------------------- | -------------------------------- | ----------------------------- |
| `toCIDR` / `toCIDRSet` 列出目标网段 | 目标 IP 段稳定，如腾讯云内部服务 | IP 变更需要更新 NetworkPolicy |
| `toEntities: [world]` 允许所有公网  | 仅需要"允许出公网"的粗粒度场景   | 完全无访问控制                |
| `toEndpoints` 配合命名空间/Pod 标签 | 集群内 Pod-to-Pod 访问控制       | 仅适用于集群内目标            |
| 切到 Overlay 模式                   | 业务必须按域名控制出向           | 需要切换网络模式              |

## 总结

| 模式                     | toFQDNs / dns L7 | 原因                            |
| ------------------------ | ---------------- | ------------------------------- |
| Native Routing (VPC-CNI) | ✅ 完整支持      | 不走 cbr0，DNS 重定向链路完整   |
| Native Routing (GR)      | ❌ 不支持        | cbr0 桥转发绕过 socket dispatch |
| Overlay (VPC-CNI / GR)   | ✅ 完整支持      | cilium 完全接管 datapath        |

## 相关链接

- [安装 Cilium](../install.md)
- [NetworkPolicy 应用实践 - 模式兼容性](../networkpolicy.md#模式兼容性)
- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)
