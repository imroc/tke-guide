# Cilium Host Routing：legacy vs BPF

## 什么是 Host Routing

Host Routing 指数据包进入节点 host network namespace 后，**如何决定下一跳并转发**的路径。Cilium 提供两种实现：

- **Legacy Host Routing**：默认实现，包要走完整的 Linux 网络栈——经过 netfilter (iptables) 钩子、conntrack、内核路由表查询，再转发到目标设备（其它 Pod 的 lxc、节点 eth0、tunnel 等）。功能完整、兼容性最好，但每跳都有 overhead。
- **BPF Host Routing**：cilium 1.9+ 引入，直接用 tc-bpf 程序在 `cilium_host` 设备入口完成查 endpoint、查 service 后端、改 dst MAC、redirect 到目标设备整套动作，**完全跳过 netfilter / 内核 routing**，性能更高（小包延迟与吞吐均有改善）。

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

## BPF Host Routing 的两个独立要求

cilium 启动后是否真正使用 BPF host routing，受**两个独立条件**约束，缺一不可：

### 条件 1：配置层不被强制 fallback

cilium-agent 启动时（`pkg/kpr/initializer/kube_proxy_replacement.go`）会检查：

```go
case option.Config.IptablesMasqueradingEnabled():
    // BPF host routing 要求 BPF masquerade。fallback 到 legacy。
case !r.kprCfg.KubeProxyReplacement:
    // BPF host routing 要求 KPR=true。fallback 到 legacy。
```

也就是说：

- **`enableIPv4Masquerade=true` 但没设 `bpf.masquerade=true`** → 走 iptables masquerade → 强制 fallback 到 legacy
- **`kubeProxyReplacement=false`** → 强制 fallback 到 legacy

要拿到 BPF host routing，必须显式：

```yaml
kubeProxyReplacement: true
enableIPv4Masquerade: true # 或 false
bpf:
  masquerade: true # 关键开关
```

### 条件 2：数据通路上的包真的会经过 `cilium_host`

BPF host routing 的代码（`bpf/bpf_host.c` 的 `ENABLE_HOST_ROUTING` 分支）只在 `cilium_host` 设备的 tc-bpf 程序里生效。如果包根本不经过 `cilium_host`，那段代码就不会被执行——即使配置层全开了，实际也走不到 BPF host routing。

**`endpointRoutes.enabled=true` 模式正是这种情况**：每个 Pod 在节点上有独立的内核路由（`ip route` 直接指向 lxc 设备），包不经过 `cilium_host`。这就是 VPC-CNI Native 模式（必启 endpointRoutes）拿不到 BPF host routing 的根本原因，**与 cilium-agent 启动时的 fallback 检查无关**。

## 各 TKE 部署方案使用的 Host Routing

| 部署方案                      | helm values 关键项                                 | 走哪条 fallback / 限制                | 实际 Host Routing         |
| ----------------------------- | -------------------------------------------------- | ------------------------------------- | ------------------------- |
| GR + Overlay (vxlan)          | `bpf.masquerade=true` + 不开 endpointRoutes        | 无                                    | ✅ BPF                    |
| VPC-CNI + Overlay             | `bpf.masquerade=true` + 不开 endpointRoutes        | 无                                    | ✅ BPF                    |
| VPC-CNI + Native（不开 SNAT） | `enableIPv4Masquerade=false` + endpointRoutes=true | endpointRoutes 让包绕过 `cilium_host` | ❌ Legacy（受限于条件 2） |
| VPC-CNI + Native + ip-masq    | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes 让包绕过 `cilium_host` | ❌ Legacy（受限于条件 2） |
| VPC-CNI + Native + Egress     | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes 让包绕过 `cilium_host` | ❌ Legacy（受限于条件 2） |

一键安装脚本 `cilium.sh` 在 GR Overlay / VPC-CNI Overlay 路径上**默认就显式设了 `bpf.masquerade=true`**，所以 Overlay 安装出来直接是 BPF host routing。

> 历史小坑：cilium 默认的 masquerade 是 iptables 实现。如果 helm values 只写了 `enableIPv4Masquerade=true`、漏掉 `bpf.masquerade=true`，cilium 启动时会打日志 `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.`，然后 `cilium status` 显示 `Host: Legacy`、`Masquerading: IPTables`。这种情况下"Overlay 默认 BPF"的直觉是错的。

## 验证方法

```bash
# 看 cilium status 的 Routing 与 Masquerading 行
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'Routing:|Masquerading:'
# 期望（BPF 路径）：
#   Routing:                 Network: Tunnel [vxlan]   Host: BPF
#   Masquerading:            BPF
# 退化（legacy 路径）：
#   Routing:                 Network: Tunnel [vxlan]   Host: Legacy
#   Masquerading:            IPTables ...

# 看 cilium-agent 启动日志确认 fallback 原因（如果是 Legacy）
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'
# 比如：
#   BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.
```

## 性能影响

Legacy host routing 比 BPF host routing 多走的开销：

- 每个包额外经过 5 个 netfilter 钩子（PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING）
- conntrack 表 lookup 与 update（即使不写规则也会走 connection tracking 状态机）
- 内核 routing table 查询（FIB lookup）

实测（4C8G S5、TencentOS 4、kernel 6.6）小包 RR 场景下，Native 模式（Legacy）的 TCP_RR 比 Overlay 模式（BPF，前提是显式开了 `bpf.masquerade=true`）低约 10-15%；单流 TCP_STREAM 吞吐差异不明显（被网卡带宽限制）。完整数据参考 [Cilium 性能测试](./performance-test.md)。

## 是否需要切换 BPF host routing？

**不建议为了切到 BPF host routing 而放弃 VPC-CNI Native 模式**：

- Native 模式的核心价值是 Pod IP 与 VPC IP 一致——可被 VPC 路由、安全组、CLB、云联网原生识别
- 切换到 Overlay 拿到 BPF host routing，但同时失去：Pod IP 直接路由到外部、四层 LB 直通 Pod、IPAM 由 VPC 统一管理
- 大多数业务对每包 ~5μs 级别的 host stack overhead 不敏感

**只有以下场景值得为 BPF host routing 切到 Overlay**：

- 高频小包业务（RPC、KV 数据库、MQ broker）追求极致 RTT
- 节点 PPS 压力大、netfilter / conntrack 是瓶颈（可通过 `nf_conntrack_count` 接近 `nf_conntrack_max` 判定）

## 横向对比：AWS EKS 用 cilium ENI IPAM 也是同样的限制

cilium 官方 helm chart 在 `eni.enabled=true`（cilium 自管 AWS ENI IPAM）时**自动写入** `enable-endpoint-routes: "true"`：

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

原因和 TKE Native 完全一致：AWS ENI IP 也是合法 VPC IP（"directly routable in the AWS VPC"），cilium 不需要也不应该把流量集中到 `cilium_host` 上做 redirect，所以走 endpointRoutes 给每个 Pod 独立路由——但这同时也意味着 BPF host routing 在该模式下同样不会被命中（条件 2 不成立）。

| 方案                                    | IPAM          | endpointRoutes      | Host Routing |
| --------------------------------------- | ------------- | ------------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)      | tke-eni-ipamd | 必须 true（手动设） | Legacy       |
| AWS EKS 用 cilium ENI IPAM (非 chained) | cilium eni    | 自动 true（chart）  | Legacy       |
| AWS EKS chained aws-cni                 | aws-vpc-cni   | 必须 true（手动设） | Legacy       |

可以看到：**只要 Pod IP 是 VPC 合法 IP，cilium 都走 endpointRoutes，都拿不到 BPF host routing**——这是云原生 Native 路由方案的共同代价。

## 不影响的能力

虽然 host routing 走 legacy，下列 cilium 核心能力在所有部署方案下**全部正常**：

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
