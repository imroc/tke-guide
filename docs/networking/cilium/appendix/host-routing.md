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

| 部署方案             | Host Routing          | 是否可切到 BPF                                                                 |
| -------------------- | --------------------- | ------------------------------------------------------------------------------ |
| GR + Overlay (vxlan) | ✅ BPF（默认）        | 已是 BPF                                                                       |
| VPC-CNI + Overlay    | ✅ BPF（默认）        | 已是 BPF                                                                       |
| VPC-CNI + Native     | ❌ Legacy（**强制**） | **不能**——`endpointRoutes.enabled=true` 模式下 BPF host routing 路径不会被命中 |

VPC-CNI Native 模式即使在 helm values 里显式设 `bpf.hostRouting=true` 也无效——这是 endpointRoutes 模式下数据通路决定的，并非 cilium 主动 fallback。

## 为什么 VPC-CNI Native 模式无法使用 BPF Host Routing

因果链路：

1. **TKE Native 模式中 Pod IP 必须是合法 VPC IP，且每个 Pod 在节点上单独有路由表项**
   - Pod IP 由 `tke-eni-ipamd` 从节点辅助 ENI 的 IP 池分配，cilium 不接管 IPAM
   - 跨节点连通性靠 VPC 路由表（同子网 ARP，跨子网 VPC 路由），cilium 不接管 routing
   - 这种数据通路要求 helm values 必须设 `endpointRoutes.enabled=true`——给每个本地 Pod 单独建一条到 lxc 设备的路由

2. **`endpointRoutes` 模式的本质：host 收包绕过 `cilium_host`，直接走内核 routing 到 lxc**
   - 默认（非 endpointRoutes）模式下，所有进入 host netns 的包先到 `cilium_host` 设备，由其 tc-bpf 程序统一分发——这正是 BPF Host Routing 工作的入口
   - endpointRoutes 模式下，每个 Pod 有独立的内核路由（`ip route` 直接指向 lxc），包根本**不经过** `cilium_host` 设备
   - cilium BPF 源码里 `bpf_host.c` 的 `ENABLE_HOST_ROUTING` 分支只在 `cilium_host` 路径上生效；endpointRoutes 模式下这段代码不会被执行

3. **结果：endpointRoutes 模式下，包必须走完整内核网络栈（netfilter / conntrack / FIB）**
   - cilium 仍然在 lxc 设备的 ingress/egress 上挂 BPF 程序做 NetworkPolicy / Service / Hubble 观测
   - 但**主机内的转发**只能依赖内核——这就是 legacy host routing 的本质

所以 Native 模式（Pod IP = VPC IP）→ 必须 `endpointRoutes.enabled=true` → host 收包不进 `cilium_host` → BPF host routing 不会被触发。

## 横向对比：AWS EKS 用 cilium ENI IPAM 也是同样的限制

cilium 官方 helm chart 在 `eni.enabled=true`（cilium 自管 AWS ENI IPAM）时**自动写入** `enable-endpoint-routes: "true"`：

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

原因和 TKE Native 完全一致：AWS ENI IP 也是合法 VPC IP（"directly routable in the AWS VPC"），cilium 不需要也不应该把流量集中到 `cilium_host` 上做 redirect，所以走 endpointRoutes 给每个 Pod 独立路由——但这同时也意味着 BPF host routing 在该模式下同样不会被命中。

| 方案                                    | IPAM          | endpointRoutes      | Host Routing |
| --------------------------------------- | ------------- | ------------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)      | tke-eni-ipamd | 必须 true（手动设） | Legacy       |
| AWS EKS 用 cilium ENI IPAM (非 chained) | cilium eni    | 自动 true（chart）  | Legacy       |
| AWS EKS chained aws-cni                 | aws-vpc-cni   | 必须 true（手动设） | Legacy       |

可以看到：**只要 Pod IP 是 VPC 合法 IP，cilium 都走 endpointRoutes，都拿不到 BPF host routing**。这是云原生 Native 路由方案的共同代价，不是 TKE 特有的实现选择。

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
