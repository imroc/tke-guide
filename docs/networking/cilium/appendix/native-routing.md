# VPC-CNI Native Routing 模式详解

在 TKE 集群安装 Cilium 时，选择 **Native Routing (VPC-CNI)** 模式与 Overlay 模式相比，有三个特殊配置：

| 配置项                          | Native                              | Overlay                                  | 原因                                      |
| ------------------------------- | ----------------------------------- | ---------------------------------------- | ----------------------------------------- |
| `extraConfig.local-router-ipv4` | `169.254.32.16`（必须显式）         | 自动分配                                | cilium 不掌握 Pod IP 分配权               |
| `sysctlfix.enabled`             | `false`（必须禁用）                 | `false`（禁用）+ 部署 sysctl override DS | 重启 systemd-sysctl 会重放发行版默认值   |
| BPF Host Routing 是否命中       | ❌ 数据路径绕过                     | ✅ 命中                                  | endpointRoutes 让包不经过 `cilium_host`   |

这三个配置并非独立问题，根源是同一个事实：**Pod IP 是 VPC 合法 IP，cilium 通过 `endpointRoutes` 为每个 Pod 建立独立路由，包不经过 `cilium_host`**。这也是 AWS EKS 等所有把 Pod IP 接到云厂商 VPC 的方案（cilium 原生 ENI/GKE/Azure IPAM 也包含在内）的共同特征。

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

Overlay 模式下，cilium 自己管理 Pod IP 分配（multi-pool IPAM），它知道节点 PodCIDR 的所有信息，会自动为 `cilium_host` 从 PodCIDR 中分配一个不冲突的 IP，无需用户介入。

## 为什么禁用 sysctlfix？

### sysctlfix 做了什么

cilium 默认启用一个名为 `sysctlfix` 的功能（helm `sysctlfix.enabled`，默认 `true`）：通过 init 容器 `apply-sysctl-overwrites` 在节点上做**两件事**：

1. 写入 `/etc/sysctl.d/99-zzz-override_cilium.conf`，把 lxc 接口（cilium 为 Pod 创建的 veth）等接口的 `rp_filter` 设为 0：

   ```text
   -net.ipv4.conf.lxc*.rp_filter = 0
   -net.ipv4.conf.cilium_*.rp_filter = 0
   net.ipv4.conf.all.rp_filter = 0
   ```

2. **重启宿主机的 `systemd-sysctl.service`** 让配置立即生效。

`rp_filter`（Reverse Path Filtering，反向路径过滤）是 Linux 内核安全机制：当一个数据包从某个网卡进入时，内核会反向查路由表，确认"如果要回这个源 IP，是否会从同一个网卡出去"。如果不一致，包就会被丢弃，防止 IP 欺骗。rp_filter 的**有效值 = `max(conf.all, conf.接口名)`**，即接口自身值与 `all` 值取较大者。

写文件本身是有价值的保护（下文详述），**问题出在第二个动作**。

### 问题一：重启 systemd-sysctl 会全量重放发行版默认值

`systemd-sysctl.service` 每次启动都会按文件名顺序应用 `/usr/lib/sysctl.d/`、`/etc/sysctl.d/` 下**所有** `.conf` 文件。cilium 的 init 容器每次随 cilium pod 启动而执行，意味着**每次 cilium pod 重建（节点重启、DS 更新、pod 漂移）都会触发一次全量重放**，把发行版默认值重新盖到运行时的值上。

TencentOS 4 的发行版底噪（`/usr/lib/sysctl.d/`）：

```text
50-default.conf:  net.ipv4.conf.default.rp_filter = 2 / net.ipv4.conf.*.rp_filter = 2
50-tencentos.conf: net.ipv4.conf.default.rp_filter = 1 / net.ipv4.conf.*.rp_filter = 1
```

重放的危害分两类：

- **Native Routing (VPC-CNI)：直接断网**。VPC-CNI 共享网卡多 IP 模式下，`tke-eni-agent` 会把网卡的 `rp_filter` 调成 `2`（loose，配合策略路由放行非对称路由）。sysctlfix 触发的重放把 eth0 打回 `1`（strict），辅助网卡 IP 的非对称流量被严格反向路径校验丢弃，Pod 网络随之中断。这是 Native 模式**必须禁用** sysctlfix 的原因。
- **所有模式：运行时 sysctl 修改丢失**。任何不是通过 sysctl.d 文件落盘的运行时修改（节点池脚本 `sysctl -w`、运维手工调优的 `nf_conntrack_max`、`somaxconn` 等）都会在重放时被打回发行版默认值。cilium 自身接口因 99-zzz 文件（文件名排序在后）胜出不受影响，但**节点上其它组件与运维的 sysctl 修改全部遭殃**——而且这类故障"当时没事、pod 一重建就坏"，非常难排查。

### 问题二：Overlay 模式不能简单关掉了事

既然重启 systemd-sysctl 有害，Overlay 模式直接 `sysctlfix.enabled=false` 行不行？**不行**——实测发现关掉后 host → Pod 会不通，根因是两条机制的叠加：

**机制 A：systemd 发行版的 udev 规则会给每个新接口重放 sysctl。**

TencentOS 4（以及使用 systemd 的主流发行版）自带这条 udev 规则：

```text
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo",
RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/ipv4/conf/$name ..."
```

即**每个新网络接口创建时**，udev 会异步执行 `systemd-sysctl --prefix`，把 sysctl.d 配置中所有匹配该接口的项应用上去——`net.ipv4.conf.*.rp_filter = 1` 的 glob 恰好匹配每个新 lxc 接口。

cilium CNI 插件在创建 Pod veth 时确实会写 `lxc.rp_filter = 0`（源码 `pkg/datapath/connector/veth.go` 的 `DisableRpFilter`），**但 udev 的应用在它之后异步执行，会把 0 覆盖回 1**。没有 99-zzz 文件时，新建 Pod 的 lxc 接口 rp_filter 恒为 1。

补充一个 cilium 内部的差异：cilium-agent **自己**创建的接口（`cilium_host`、`cilium_net`、`cilium_vxlan`、`lxc_health`）走 agent 内部的 reconciler 管理，每 10 分钟会重新应用期望值，被 udev 覆盖后能自愈；而 **Pod 的 veth 由 CNI 插件进程创建，写一次就结束**，被 udev 覆盖后**永不自愈**——重启 cilium pod 也没用，只有重建业务 Pod 才会再次写入。

**机制 B：Overlay 的路由拓扑让 lxc rp_filter=1 必然丢包。**

Overlay 模式（不开 endpointRoutes）下，节点上 Pod IP 的路由是**聚合到 `cilium_host` 的**：

```text
$ ip route get 10.244.1.246
10.244.1.246 dev cilium_host src 10.244.1.217
```

host → Pod 的回包从 lxc 接口进入内核栈时，rp_filter 反查源 IP（Pod IP）的路由，出口是 `cilium_host` 而非入接口 `lxc`——**必然不对称，strict 模式直接丢包**。所以 Overlay 模式下 lxc 的 rp_filter **必须为 0**。

这也解释了为什么 **Native 模式反而没有这个依赖**：Native 必开 `endpointRoutes`，每个 Pod IP 有一条 `dev lxcXXX scope link` 的 per-endpoint 路由，反查路由的出口就是 lxc 本身——**对称，rp_filter=1 也不丢包**（教程对 Native 模式的 connectivity test 实测全量通过也印证了这点）。

| 模式                   | Pod IP 路由                          | lxc rp_filter=1 时 host→Pod | 依赖 lxc rp_filter=0？ |
| ---------------------- | ------------------------------------ | --------------------------- | ---------------------- |
| Overlay (VPC-CNI / GR) | 聚合路由指向 `cilium_host`          | ❌ 回包被丢（不对称）       | **依赖**               |
| Native (VPC-CNI)       | per-endpoint 路由直接指向 `lxcXXX`   | ✅ 通（对称）               | 不依赖                 |

### 最终方案：禁用 sysctlfix + cilium-sysctl-override DaemonSet

结论：**两种模式都禁用 sysctlfix**（消除"cilium 每次启动都全量重放宿主机 sysctl"的扳机），Overlay 模式用 `cilium-sysctl-override` DaemonSet 补回 99-zzz 文件的保护（[安装文档](../install.md)的前置操作中已内置）：

| 模式                     | sysctlfix        | 99-zzz 覆盖文件                        | 说明                                                     |
| ------------------------ | ---------------- | -------------------------------------- | -------------------------------------------------------- |
| Native Routing (VPC-CNI) | ❌ 禁用          | 不需要                                 | 路由对称，lxc rp_filter=1 无影响                          |
| Overlay (VPC-CNI / GR)   | ❌ 禁用          | ✅ 由 cilium-sysctl-override DaemonSet 持续维护 | 文件内容与 sysctlfix 写的完全一致，但不重启 systemd-sysctl |

这个 DaemonSet 方案兼得两头：

- **新接口保护**：文件落盘后，udev 的 per-interface 应用（机制 A）会按文件名顺序先应用 `50-*.conf`（=1）再应用 `99-zzz`（=0），每个新建 lxc 的最终值是 0。
- **重放保护**：任何时机触发 `systemd-sysctl`（节点重启、OS 升级、管理员手工 `sysctl --system`），`99-zzz` 都因文件名排序靠后而胜出，存量接口的值也保持 0。
- **无副作用**：全程不重启 `systemd-sysctl.service`，不触发全量重放，运行时 sysctl 修改不受影响。
- **自愈与扩容**：DaemonSet 每 60 秒重写文件（防误删），新节点加入集群自动写上。

唯一需要人工介入的场景是**从旧的 sysctlfix=true 配置切换过来**的存量集群：节点上已有的 lxc 接口可能停留在被重放后的 1（agent 不管存量 Pod veth 的 rp_filter），处理方式是滚动重启业务 Pod 或在节点上执行一次 `sudo systemctl restart systemd-sysctl`（有 99-zzz 文件在，重放后 cilium 值胜出）。

### 故障排查

**症状：`cilium-health status` 中 localhost endpoint 显示 0/1（host → 本节点 Pod 不通）**，或 kubelet 探针（HTTP/TCP probe）大面积失败、节点上进程访问 Pod IP 超时。

Overlay 模式下这个症状几乎总是 lxc 接口 `rp_filter` 不为 0（Pod ↔ Pod、ClusterIP、跨节点流量不受影响——它们走 BPF host routing，在 tc 层直接转发，绕过了内核 rp_filter 检查）：

```bash
# 1. 检查所有 lxc 接口的 rp_filter 是否全为 0（在节点上或通过 hostNetwork Pod 执行）
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# 2. 不为 0 时，检查 99-zzz 文件是否存在
ls -l /etc/sysctl.d/ | grep 99-zzz

# 3. 检查 cilium-sysctl-override DaemonSet 是否正常运行
kubectl -n kube-system get pod -l app=cilium-sysctl-override -o wide
```

排查思路：

1. **99-zzz 文件不存在** → cilium-sysctl-override DaemonSet 未部署或未就绪，参考 [安装文档](../install.md) 部署后等待 60 秒。
2. **文件存在但值仍为 1** → 存量接口停留在被重放后的值（常见于从 sysctlfix=true 切换的集群），在节点执行 `sudo systemctl restart systemd-sysctl` 让 99-zzz 重放胜出，或滚动重启业务 Pod。
3. **全部为 0 但仍不通** → 问题不在 rp_filter，从其它路径继续排查（`cilium-health status --verbose`、`hubble observe`）。

## BPF Host Routing 在 Native 模式下不命中

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

### 为什么 Native 模式 BPF host routing 不命中

BPF host routing 真正在数据路径上生效，需要同时满足两个条件：

**条件 1：cilium-agent 配置层不被强制 fallback**

cilium-agent 启动时会检查，以下情况会强制设 `EnableHostLegacyRouting=true`，让编译时 `ENABLE_HOST_ROUTING` 宏定义不进 BPF 程序（源码：`pkg/kpr/initializer/kube_proxy_replacement.go:46-64`）：

- `kubeProxyReplacement=false` → fallback
- `enableIPv4Masquerade=true` 但没设 `bpf.masquerade=true`（即用 iptables masquerade） → fallback

要拿到 BPF host routing 必须显式：

```yaml
kubeProxyReplacement: true
bpf:
  masquerade: true  # 关键开关
```

满足这两个开关，`cilium status` 就会显示 `Host Routing: BPF`。

**条件 2：数据通路上的包真的会经过 `cilium_host`**

BPF host routing 的代码挂在 `cilium_host` 设备的 tc-bpf 程序上（源码：`bpf/bpf_host.c` 的 `ENABLE_HOST_ROUTING` 宏分支）。如果包根本不经过 `cilium_host`，这段代码就不会被执行——即使配置层全开、`cilium status` 报 `BPF`，**数据路径上 BPF host routing 也不会命中**。

**`endpointRoutes.enabled=true` 模式正是这种情况**：每个 Pod 在节点上有独立的内核路由（`ip route` 直接指向 lxc 设备），包不经过 `cilium_host`。源码 `pkg/endpoint/endpoint.go:1036-1056` 的 `NewDatapathConfiguration()` 注释直接说明这一点：

> _"Since routing occurs via endpoint interface directly, BPF program on cilium_host interface is bypassed"_

VPC-CNI Native 必启 endpointRoutes（因 Pod IP 是 VPC 合法 IP，cilium 不掌握 IP 分配权），所以 cilium status 与 datapath 状态分离：**status 报 BPF，datapath 实际不命中**。这与 cilium-agent fallback 检查无关。

### 各 TKE 部署方案 BPF Host Routing 命中情况

| 部署方案                      | helm values 关键项                                 | cilium status | 数据路径实际命中      |
| ----------------------------- | -------------------------------------------------- | ------------- | --------------------- |
| GR + Overlay (vxlan)          | `bpf.masquerade=true` + 不开 endpointRoutes        | BPF           | ✅ 命中               |
| VPC-CNI + Overlay             | `bpf.masquerade=true` + 不开 endpointRoutes        | BPF           | ✅ 命中               |
| VPC-CNI + Native（不开 SNAT） | `enableIPv4Masquerade=false` + endpointRoutes=true | BPF           | ❌ 包绕过 cilium_host |
| VPC-CNI + Native + ip-masq    | `bpf.masquerade=true` + endpointRoutes=true        | BPF           | ❌ 包绕过 cilium_host |
| VPC-CNI + Native + Egress     | `bpf.masquerade=true` + endpointRoutes=true        | BPF           | ❌ 包绕过 cilium_host |

一键安装脚本 `cilium.sh` 在所有路径上都显式设了 `bpf.masquerade=true` + `kubeProxyReplacement=true`，所以 cilium status 一律显示 `Host Routing: BPF`。Native 模式下 `Host Routing: BPF` 是 status 视角的状态，**不代表数据路径上 BPF host routing 真的被命中**——能否命中取决于包是否经过 cilium_host。

> 历史小坑：如果 helm values 只写了 `enableIPv4Masquerade=true`、漏掉 `bpf.masquerade=true`，cilium 启动时会打日志 `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.`，然后 `cilium status` 直接显示 `Host: Legacy`、`Masquerading: IPTables`。这是配置层 fallback，跟 endpointRoutes 绕过 cilium_host 是两个独立的层面。

### 验证方法

`cilium status` 的 `Host Routing` 字段只反映 cilium-agent 配置层面的状态（满足 `kubeProxyReplacement=true` + `bpf.masquerade=true` 就报 `BPF`），**它不会告诉你数据路径上是否真的命中**。VPC-CNI Native 集群在 cilium status 上同样会显示 `Host: BPF`，但因 endpointRoutes 让包绕过 `cilium_host`，那段 BPF 代码实际上不会被执行。

要准确判断当前集群"BPF host routing 是否被命中"，分两步看：

```bash
# 第一步：看 cilium-agent 配置是否满足
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'KubeProxyReplacement:|Host Routing:|Masquerading:'
# 配置满足：
#   KubeProxyReplacement:    True
#   Host Routing:            BPF
#   Masquerading:            BPF (...)
# 配置不满足（fallback 到 legacy）：
#   Host Routing:            Legacy
# fallback 通常是 KPR=False 或 enableIPv4Masquerade 走了 iptables，看 cilium-agent 日志：
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'

# 第二步：看 endpointRoutes 是否启用——启用则 cilium_host 上的 BPF 程序被绕过
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-endpoint-routes}'
# 输出 "true"：Pod 流量走 per-endpoint veth 路由，BPF host routing 不命中
# 输出 ""/不存在：Pod 流量经 cilium_host，BPF host routing 实际生效
```

> 源码依据：`pkg/endpoint/endpoint.go`（v1.20.1） `NewDatapathConfiguration` 注释明确写 _"Since routing occurs via endpoint interface directly, BPF program on cilium_host interface is bypassed"_。

## 性能影响

cilium_host 被绕过、Pod 流量走 per-endpoint veth 时，每个包多出的开销：

- 每个包额外经过 netfilter 钩子（PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING）
- conntrack 表 lookup 与 update（即使不写规则也会走 connection tracking 状态机）
- 内核 routing table 查询（FIB lookup）

实测（SA5.LARGE8 4C8G、TencentOS 4、kernel 6.6）：

- 跨节点单流吞吐均达 10 Gbps 突发上限，**吞吐无差异**
- 跨节点 keepalive RPS：Native 与 Overlay 几乎持平（差异 < 1%），均比 iptables 集群低 ~18%（Native 是 cni-chaining + per-endpoint 路由的代价，Overlay 是 VXLAN encap/decap 的代价，量级相当）
- 跨节点短连接 RPS：Native 与 Overlay 也几乎持平
- TCP_RR p99：Native 136 µs vs Overlay 130 µs vs iptables 112 µs（Cilium 比 iptables 高 ~20 µs，Native 与 Overlay 差异 < 10 µs）
- HTTP p99 @1000 QPS：三种集群均为 0.99 ms，**真实业务负载下三者完全等价**

完整数据参考 [Cilium 网络性能 Benchmark](./network-benchmark.md) 与 [Cilium 性能测试](./performance-test.md)。

**不建议为了"想拿 BPF host routing"而放弃 VPC-CNI Native**：

- Native 模式的核心价值是 Pod IP 与 VPC IP 一致——可被 VPC 路由、安全组、CLB、云联网原生识别
- 切到 Overlay 后 cilium_host 上的 BPF 程序确实命中了，但同时失去：Pod IP 直接路由到外部、四层 LB 直通 Pod、VPC 统一 IP 管理
- 实测 Native 与 Overlay 的端到端 RPS/延迟差异都在 < 1% 量级，**BPF host routing 命中与否在跨节点路径上的实测收益极小**

**真正适合切到 Overlay 的场景是**：

- Pod IP 数量超出弹性网卡上限或跨 VPC 复用 CIDR 的需求（这是架构层面的真原因）
- 节点 PPS 压力大、`nf_conntrack_count` 接近 `nf_conntrack_max`（仍取决于业务流量模式而非 host routing 实现）

## 不受影响的能力

虽然 cilium_host 上的 BPF 程序被绕过，下列 cilium 核心能力在所有部署方案下**全部正常**：

- **L3/L4/L7 NetworkPolicy**：BPF 程序挂在 lxc 设备的 ingress/egress hook 上（与 host routing 解耦）
- **Hubble Observability**：同上，flow 采集走 lxc BPF 程序
- **kubeProxyReplacement**：完全替代 kube-proxy（ClusterIP / NodePort / HostPort 转发）
- **CiliumLocalRedirectPolicy**：node-local DNS cache 等场景可用
- **Egress Gateway**：可用，详见 [Egress Gateway 应用实践](../egress-gateway.md)

## 横向对比：所有云厂商 Native IPAM 都是同样情况

cilium 官方 helm chart 在 `eni.enabled=true`（cilium 自管 AWS ENI IPAM）时**自动写入** `enable-endpoint-routes: "true"`：

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.20.1)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

GKE 配置（`gke.enabled=true`）也自动启用 endpoint-routes（源码 `Documentation/network/concepts/routing.rst`）。

原因和 TKE Native 完全一致：**只要 Pod IP 是云厂商 VPC 合法 IP**（不管用 cni-chaining 还是 cilium 原生 IPAM），cilium 都不掌握 IP 来源、也不应该把所有流量都集中到 `cilium_host` 上做 redirect，所以一律走 endpointRoutes 给每个 Pod 独立路由——这同时也让 cilium_host 上的 BPF 程序失去用武之地。

| 方案                                   | IPAM           | endpointRoutes      | Pod IP 类型      | BPF host routing 命中 |
| -------------------------------------- | -------------- | ------------------- | ---------------- | --------------------- |
| TKE VPC-CNI + Native (cni-chaining)    | tke-eni-ipamd  | 必须 true（手动设） | VPC IP           | ❌                    |
| AWS EKS + cilium ENI IPAM (非 chained) | cilium eni     | 自动 true（chart）  | VPC IP           | ❌                    |
| AWS EKS + chained aws-cni              | aws-vpc-cni    | 必须 true（手动设） | VPC IP           | ❌                    |
| GKE + cilium GKE 模式                  | k8s host-scope | 自动 true（chart）  | Alias IP（VPC）  | ❌                    |
| 自建 Cilium Native + Cluster Pool IPAM | cluster-pool   | 默认 false          | cilium 自管 CIDR | ✅                    |
| TKE Cilium Overlay                     | multi-pool     | 默认 false          | cilium 自管 CIDR | ✅                    |

最后两行是反例——**cilium 完全自管 Pod CIDR 时**（不管 Native 还是 Overlay），endpointRoutes 不强制启用，cilium_host 上的 BPF 程序就能在数据路径上命中。**所以"BPF host routing 命中与否"的根本判据不是路由模式（Native/Tunnel），也不是 cni-chaining 与否，而是 Pod IP 是否来自云厂商 VPC**。

## 参考资料

- [安装 Cilium](../install.md)
- [Cilium 性能测试](./performance-test.md)
- [Cilium 官方文档：eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135：generic-veth chaining 不兼容 BPF host routing](https://github.com/cilium/cilium/issues/20135)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/tools/sysctlfix/main.go)
- [Linux 内核 rp_filter 说明](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
