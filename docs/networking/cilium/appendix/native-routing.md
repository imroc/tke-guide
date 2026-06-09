# VPC-CNI Native Routing 模式详解

在 TKE 集群安装 Cilium 时，选择 **Native Routing (VPC-CNI)** 模式与 Overlay 模式相比，有三个特殊配置：

| 配置项 | Native | Overlay | 原因 |
|---|---|---|---|
| `extraConfig.local-router-ipv4` | `169.254.32.16`（必须显式） | 自动分配 | cilium 不掌握 Pod IP 分配权 |
| `sysctlfix.enabled` | `false`（必须禁用） | `true`（默认启用） | 重启 systemd-sysctl 会重置 eth0 rp_filter |
| Host Routing | Legacy（无法 BPF） | BPF（开 `bpf.masquerade` 即可） | endpointRoutes 让包绕过 `cilium_host` |

这三个配置并非独立问题，根源是同一个事实：**Pod IP 是 VPC 合法 IP，cilium 通过 `endpointRoutes` 为每个 Pod 建立独立路由，包不经过 `cilium_host`**。这也是 AWS EKS 等云原生 Native 路由方案的共同特征。

本文逐一解释这三个配置的原理和决策逻辑。

## 为什么需要 local-router-ipv4？

### cilium_host 网卡的作用

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

### Native 模式下的特殊情况

Native Routing (VPC-CNI) 模式下，**cilium 不负责 Pod IP 分配**：Pod 直接挂在弹性网卡上，IP 由 VPC-CNI 从 VPC 子网中分配，cilium 完全没有 Pod IP 来源信息。

由于 cilium 不掌握 IP 分配权，它无法自动决定 `cilium_host` 用什么 IP，因此必须由用户通过 `local-router-ipv4` 显式指定一个**绝对不会与 Pod IP 冲突**的地址。

### 为什么是 169.254.32.16？

`169.254.0.0/16` 是 IPv4 link-local 地址段（RFC 3927），有以下特点：

1. **不可路由**：永远不会和 VPC IP 或 Service CIDR 冲突。
2. **跨节点统一**：所有节点都可以用同一个值，配置和排障更简单。
3. **TKE 特定预留**：`169.254.32.16` 这个具体地址在 TKE 上不会被其它组件占用，是经过验证的安全值。

:::tip[TKE 上 169.254 段的其它用途]

TKE 在 `169.254.0.0/16` 段还承载了以下能力，配置时要注意不要冲突：

- 元数据服务（IMDS）
- apiserver 的内部 VIP（`kubectl get ep kubernetes` 看到的地址）
- COS / 镜像仓库 / 部分内部服务的 VIP

`169.254.32.16` 是已确认与上述服务不冲突的地址。

:::

### Overlay 模式为什么不需要

Overlay 模式下，cilium 自己管理 Pod IP 分配（cluster-pool IPAM），它知道节点 PodCIDR 的所有信息，会自动为 `cilium_host` 从 PodCIDR 中分配一个不冲突的 IP，无需用户介入。

## 为什么禁用 sysctlfix？

### 背景

cilium 默认会启用一个名为 `sysctlfix` 的功能：通过一个 init container 在节点上写入 `/etc/sysctl.d/99-zzz-override_cilium.conf`，把 lxc 接口（cilium 为 Pod 创建的 veth）的 `rp_filter` 设置为 0，并**重启 `systemd-sysctl.service`** 让配置生效。

`rp_filter`（Reverse Path Filtering，反向路径过滤）是 Linux 内核安全机制：当一个数据包从某个网卡进入时，内核会反向查路由表，确认"如果要回这个源 IP，是否会从同一个网卡出去"。如果不一致，包就会被丢弃，防止 IP 欺骗。

cilium 调整 lxc 接口 `rp_filter` 是为了让 host → 本节点 Pod 的回包能正常通过。但在 TKE 不同的安装模式下，启用 sysctlfix 的影响完全不同。

### Native Routing (VPC-CNI)：必须禁用

- **数据路径**：cilium 与 VPC-CNI 共存，Pod IP 来自 VPC，**回程包从 eth0 进入**。
- **风险**：sysctlfix 会重启 `systemd-sysctl.service`，重启时会重新应用 OS 默认配置。TKE 的 OS 镜像中 `eth0` 的 `rp_filter` 默认是 `1`（strict 模式），严格校验下 Pod IP 在 eth0 上不匹配会被丢弃，导致网络不通。
- **结论**：**必须禁用** sysctlfix：

  ```bash
  --set sysctlfix.enabled=false
  ```

### Overlay：必须启用（默认即启用）

- **数据路径**：Pod IP 来自 cilium 自己的 CIDR，跨节点流量走 vxlan tunnel，eth0 上看不到 Pod IP，eth0 的 `rp_filter=1` 不会引发问题。
- **风险点**：host → 本节点 Pod 的回包会经过 lxc 接口，需要 `lxc*.rp_filter=0` 否则被丢弃。
- **结论**：Overlay 模式**必须启用** sysctlfix（默认即启用，无需显式设置）。

### 决策总结

| 模式                     | sysctlfix 状态 | 关键原因                             |
| ------------------------ | -------------- | ------------------------------------ |
| Native Routing (VPC-CNI) | ❌ 必须禁用    | 重启 systemd-sysctl 会重置 eth0 配置 |
| Overlay (VPC-CNI / GR)   | ✅ 必须启用    | host → Pod 回包需要 lxc rp_filter=0  |

### 故障排查

如果 Overlay 模式下 `cilium-health status` 显示 localhost endpoint 0/1（host → Pod 不通），多半是 sysctlfix 没生效：

```bash
# 检查所有 lxc 接口的 rp_filter 是否全为 0
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# 如果存在不为 0 的项，检查 sysctlfix init container 是否正常运行
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

排查思路：

1. 如果 `lxc*.rp_filter` 全部为 0，但仍然不通 → 问题不在 sysctlfix，需要从其它路径继续排查。
2. 如果存在不为 0 的项 → sysctlfix init container 可能没运行成功，查 init container 日志。
3. 如果 init container 日志正常，但 sysctl 值仍未生效 → 可能是 systemd-sysctl.service 被其它进程或脚本覆盖，需要手动 `sysctl -w` 测试。

## Host Routing：只能走 legacy

### 什么是 Host Routing

Host Routing 指数据包进入节点 host network namespace 后，**如何决定下一跳并转发**的路径。Cilium 提供两种实现：

- **Legacy Host Routing**：默认实现，包要走完整的 Linux 网络栈——经过 netfilter (iptables) 钩子、conntrack、内核路由表查询，再转发到目标设备。功能完整、兼容性最好，但每跳都有 overhead。
- **BPF Host Routing**：cilium 1.9+ 引入，直接用 tc-bpf 程序在 `cilium_host` 设备入口完成查 endpoint、查 service 后端、改 dst MAC、redirect 到目标设备整套动作，**完全跳过 netfilter / 内核 routing**，性能更高。

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

### 为什么 Native 只能走 legacy

BPF host routing 的启用需要两个条件：

**条件 1：配置层不被强制 fallback**

cilium-agent 启动时会检查，以下情况会强制 fallback 到 legacy：

- `enableIPv4Masquerade=true` 但没设 `bpf.masquerade=true` → 走 iptables masquerade → fallback
- `kubeProxyReplacement=false` → fallback

要拿到 BPF host routing 必须显式：

```yaml
kubeProxyReplacement: true
bpf:
  masquerade: true  # 关键开关
```

**条件 2：数据通路上的包真的会经过 `cilium_host`**

BPF host routing 的代码（`bpf/bpf_host.c` 的 `ENABLE_HOST_ROUTING` 分支）只在 `cilium_host` 设备的 tc-bpf 程序里生效。如果包根本不经过 `cilium_host`，那段代码就不会被执行——即使配置层全开了，实际也走不到 BPF host routing。

**`endpointRoutes.enabled=true` 模式正是这种情况**：每个 Pod 在节点上有独立的内核路由（`ip route` 直接指向 lxc 设备），包不经过 `cilium_host`。这就是 VPC-CNI Native 模式（必启 endpointRoutes）拿不到 BPF host routing 的根本原因，**与 cilium-agent 启动时的 fallback 检查无关**。

### 各 TKE 部署方案使用的 Host Routing

| 部署方案                      | helm values 关键项                                 | 实际 Host Routing |
| ----------------------------- | -------------------------------------------------- | ----------------- |
| GR + Overlay (vxlan)          | `bpf.masquerade=true` + 不开 endpointRoutes        | ✅ BPF            |
| VPC-CNI + Overlay             | `bpf.masquerade=true` + 不开 endpointRoutes        | ✅ BPF            |
| VPC-CNI + Native（不开 SNAT） | `enableIPv4Masquerade=false` + endpointRoutes=true | ❌ Legacy         |
| VPC-CNI + Native + ip-masq    | `bpf.masquerade=true` + endpointRoutes=true        | ❌ Legacy         |
| VPC-CNI + Native + Egress     | `bpf.masquerade=true` + endpointRoutes=true        | ❌ Legacy         |

一键安装脚本 `cilium.sh` 在 GR Overlay / VPC-CNI Overlay 路径上**默认就显式设了 `bpf.masquerade=true`**，所以 Overlay 安装出来直接是 BPF host routing。

> 历史小坑：cilium 默认的 masquerade 是 iptables 实现。如果 helm values 只写了 `enableIPv4Masquerade=true`、漏掉 `bpf.masquerade=true`，cilium 启动时会打日志 `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.`，然后 `cilium status` 显示 `Host: Legacy`、`Masquerading: IPTables`。

### 验证方法

```bash
# 看 cilium status 的 Routing 与 Masquerading 行
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'Routing:|Masquerading:'
# 期望（BPF 路径）：
#   Routing:                 Network: Tunnel [vxlan]   Host: BPF
#   Masquerading:            BPF
# 退化（legacy 路径）：
#   Routing:                 Network: Tunnel [vxlan]   Host: Legacy
#   Masquerading:            IPTables ...

# 看 cilium-agent 启动日志确认 fallback 原因
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'
```

## 性能影响

Legacy host routing 比 BPF host routing 多走的开销：

- 每个包额外经过 5 个 netfilter 钩子（PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING）
- conntrack 表 lookup 与 update（即使不写规则也会走 connection tracking 状态机）
- 内核 routing table 查询（FIB lookup）

实测（4C8G S5、TencentOS 4、kernel 6.6）小包 RR 场景下，Native 模式（Legacy）的 TCP_RR 比 Overlay 模式（BPF）低约 10-15%；单流 TCP_STREAM 吞吐差异不明显（被网卡带宽限制）。完整数据参考 [Cilium 性能测试](./performance-test.md)。

**不建议为了切到 BPF host routing 而放弃 VPC-CNI Native 模式**：

- Native 模式的核心价值是 Pod IP 与 VPC IP 一致——可被 VPC 路由、安全组、CLB、云联网原生识别
- 切换到 Overlay 拿到 BPF host routing，但同时失去：Pod IP 直接路由到外部、四层 LB 直通 Pod、IPAM 由 VPC 统一管理
- 大多数业务对每包 ~5μs 级别的 host stack overhead 不敏感

**只有以下场景值得为 BPF host routing 切到 Overlay**：

- 高频小包业务（RPC、KV 数据库、MQ broker）追求极致 RTT
- 节点 PPS 压力大、netfilter / conntrack 是瓶颈（可通过 `nf_conntrack_count` 接近 `nf_conntrack_max` 判定）

## 不受影响的能力

虽然 host routing 走 legacy，下列 cilium 核心能力在所有部署方案下**全部正常**：

- **L3/L4/L7 NetworkPolicy**：BPF 程序挂在 lxc 设备的 ingress/egress hook 上（与 host routing 解耦）
- **Hubble Observability**：同上，flow 采集走 lxc BPF 程序
- **kubeProxyReplacement**：完全替代 kube-proxy（ClusterIP / NodePort / HostPort 转发）
- **CiliumLocalRedirectPolicy**：node-local DNS cache 等场景可用
- **Egress Gateway**：可用，详见 [Egress Gateway 应用实践](../egress-gateway.md)

## 横向对比：AWS EKS 也是同样的限制

cilium 官方 helm chart 在 `eni.enabled=true`（cilium 自管 AWS ENI IPAM）时**自动写入** `enable-endpoint-routes: "true"`：

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

原因和 TKE Native 完全一致：AWS ENI IP 也是合法 VPC IP，cilium 不需要也不应该把流量集中到 `cilium_host` 上做 redirect，所以走 endpointRoutes 给每个 Pod 独立路由——但这同时也意味着 BPF host routing 在该模式下同样不会被命中。

| 方案                                    | IPAM          | endpointRoutes      | Host Routing |
| --------------------------------------- | ------------- | ------------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)      | tke-eni-ipamd | 必须 true（手动设） | Legacy       |
| AWS EKS 用 cilium ENI IPAM (非 chained) | cilium eni    | 自动 true（chart）  | Legacy       |
| AWS EKS chained aws-cni                 | aws-vpc-cni   | 必须 true（手动设） | Legacy       |

可以看到：**只要 Pod IP 是 VPC 合法 IP，cilium 都走 endpointRoutes，都拿不到 BPF host routing**——这是云原生 Native 路由方案的共同代价。

## 参考资料

- [安装 Cilium](../install.md)
- [Cilium 性能测试](./performance-test.md)
- [Cilium 官方文档：eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135：generic-veth chaining 不兼容 BPF host routing](https://github.com/cilium/cilium/issues/20135)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/daemon/cmd/sysctlfix.go)
- [Linux 内核 rp_filter 说明](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)