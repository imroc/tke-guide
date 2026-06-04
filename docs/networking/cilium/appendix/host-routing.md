# Cilium Host Routing：legacy vs BPF

## 什么是 Host Routing

Host Routing 指数据包进入节点 host network namespace 后，**如何决定下一跳并转发**的路径。Cilium 提供两种实现：

- **Legacy Host Routing**：默认实现，包要走完整的 Linux 网络栈——经过 netfilter (iptables) 钩子、conntrack、内核路由表查询，再转发到目标设备（其它 Pod 的 lxc、节点 eth0、tunnel 等）。功能完整、兼容性最好，但每跳都有 overhead。
- **BPF Host Routing**：cilium 1.9+ 引入，直接用 tc-bpf 程序在网卡入口完成查 endpoint、查 service 后端、改 dst MAC、redirect 到目标设备整套动作，**完全跳过 netfilter / 内核 routing**，性能更高（小包延迟与吞吐均有改善）。

```
              ┌──────────────────────────────────────────────────────┐
              │          数据包进入节点后的转发路径对比              │
              ├──────────────────────────────────────────────────────┤
Legacy        │ ingress → tc-bpf (policy) → host stack               │
              │       → netfilter / conntrack → routing table        │
              │       → veth/eth → out                               │
              ├──────────────────────────────────────────────────────┤
BPF host      │ ingress → tc-bpf (policy + lookup + redirect)        │
routing       │       → veth/eth → out  （跳过 netfilter / routing） │
              └──────────────────────────────────────────────────────┘
```

## 各 TKE 部署方案使用的 Host Routing

| 部署方案             | Host Routing          | 是否可切到 BPF                 |
| -------------------- | --------------------- | ------------------------------ |
| GR + Overlay (vxlan) | ✅ BPF（默认）        | 已是 BPF                       |
| VPC-CNI + Overlay    | ✅ BPF（默认）        | 已是 BPF                       |
| VPC-CNI + Native     | ❌ Legacy（**强制**） | **不能**，cilium 自动 fallback |

VPC-CNI Native 模式即使在 helm values 里显式设 `bpf.hostRouting=true` 也无效，cilium 会在启动时自动判定并 fallback 到 legacy。

## 为什么 VPC-CNI Native 模式无法使用 BPF Host Routing

因果链路：

1. **TKE Native 模式要求 cilium 用 chained CNI 模式与 `tke-route-eni` 共存**
   - Pod IP 必须由 `tke-eni-ipamd` 从节点辅助 ENI 的 IP 池里分配，cilium 不接管 IPAM
   - 跨节点连通性靠 VPC 路由表（同子网 ARP、跨子网走 VPC 路由），cilium 不接管 routing
   - cilium 只挂 BPF 程序做 NetworkPolicy / Service / Observability
   - 这要求 helm values 必须设 `cni.chainingMode=generic-veth` 与 `endpointRoutes.enabled=true`

2. **chained CNI 模式下 cilium 不掌控数据路径**
   - BPF Host Routing 的前提是 cilium 能在节点上**完整接管包的转发决策**——查 endpoint 表、查 service 后端、redirect 到正确设备
   - chained 模式下底层连通性归属另一个 CNI（这里是 `tke-route-eni`），cilium 没法越过它直接 redirect

3. **cilium 源码对此做了硬约束**
   - 启动时检测到 chained CNI 配置，会把 `EnableHostLegacyRouting` 强制置为 true（即关闭 BPF host routing），无法通过 helm values 覆盖
   - 上游讨论详见 [GitHub Issue #20135](https://github.com/cilium/cilium/issues/20135)

所以 chained CNI 模式 → 必须 endpointRoutes.enabled=true → cilium 走 legacy host routing，是一条无法绕过的链路。

## 性能影响

Legacy host routing 比 BPF host routing 多走的开销：

- 每个包额外经过 5 个 netfilter 钩子（PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING）
- conntrack 表 lookup 与 update（即使不写规则也会走 connection tracking 状态机）
- 内核 routing table 查询（FIB lookup）

实测（4C8G S5、TencentOS 4、kernel 6.6）小包 RR 场景下，Native 模式的 TCP_RR 比 Overlay 模式低 ~10-15%（Overlay 走 BPF host routing），单流 TCP_STREAM 吞吐差异不明显（被网卡带宽限制）。完整数据参考 [Cilium 性能测试](./performance-test.md)。

## 是否需要切换 BPF host routing？

**不建议为了切到 BPF host routing 而放弃 VPC-CNI Native 模式**：

- Native 模式的核心价值是 Pod IP 与 VPC IP 一致——可被 VPC 路由、安全组、CLB、云联网原生识别
- 切换到 Overlay 拿到 BPF host routing，但同时失去：Pod IP 直接路由到外部、四层 LB 直通 Pod、IPAM 由 VPC 统一管理
- 大多数业务对每包 ~5μs 级别的 host stack overhead 不敏感

**只有以下场景值得为 BPF host routing 切到 Overlay**：

- 高频小包业务（RPC、KV 数据库、MQ broker）追求极致 RTT
- 节点 PPS 压力大、netfilter / conntrack 是瓶颈（可通过 `nf_conntrack_count` 接近 `nf_conntrack_max` 判定）

## 不影响的能力

虽然 host routing 走 legacy，下列 cilium 核心能力在 VPC-CNI Native 模式下**全部正常**：

- **L3/L4/L7 NetworkPolicy**：BPF 程序挂在 lxc 设备的 ingress/egress hook 上（与 host routing 解耦）
- **Hubble Observability**：同上，flow 采集走 lxc BPF 程序
- **kubeProxyReplacement**：完全替代 kube-proxy（ClusterIP / NodePort / HostPort 转发）
- **CiliumLocalRedirectPolicy**：node-local DNS cache 等场景可用
- **Egress Gateway**：可用，详见 [Egress Gateway 应用实践](../egress-gateway.md)

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 性能测试](./performance-test.md)
- [Cilium 官方文档：eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135：generic-veth chaining 不兼容 BPF host routing](https://github.com/cilium/cilium/issues/20135)
