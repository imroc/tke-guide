# sysctlfix 与 rp_filter 机制详解

cilium 默认启用的 `sysctlfix` 功能会在 TKE 上引发两类问题，因此**本系列教程的两种安装模式（Native Routing 与 Overlay）都禁用它**（`sysctlfix.enabled=false`）。但两种模式的禁用原因、以及禁用后是否需要补偿措施并不相同：

| 模式                     | 禁用原因                                 | 禁用后需要补偿？                            |
| ------------------------ | ---------------------------------------- | ------------------------------------------- |
| Native Routing (VPC-CNI) | 重启 systemd-sysctl 会把 eth0 打回 strict，直接断网 | 不需要（路由对称，lxc rp_filter 值无影响） |
| Overlay (VPC-CNI / GR)   | 同上（重放覆盖运行时 sysctl 修改）       | **需要**：部署 `cilium-sysctl-override` DaemonSet |

无论哪种模式，只要节点上有**其它组件依赖非默认的 sysctl 值**——典型如 AI 推理 RDMA 场景的 bond 网卡依赖 `rp_filter=0`——sysctlfix 触发的全量重放都会把它打回发行版默认值导致业务不可用（详见下文[受害清单](#问题一重启-systemd-sysctl-会全量重放发行版默认值)）。

本文解释这套结论背后的完整机制。

## sysctlfix 做了什么

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

## 问题一：重启 systemd-sysctl 会全量重放发行版默认值

`systemd-sysctl.service` 每次启动都会按文件名顺序应用 `/usr/lib/sysctl.d/`、`/etc/sysctl.d/` 下**所有** `.conf` 文件。cilium 的 init 容器每次随 cilium pod 启动而执行，意味着**每次 cilium pod 重建（节点重启、DS 更新、pod 漂移）都会触发一次全量重放**，把发行版默认值重新盖到运行时的值上。

TencentOS 4 的发行版底噪（`/usr/lib/sysctl.d/`）：

```text
50-default.conf:  net.ipv4.conf.default.rp_filter = 2 / net.ipv4.conf.*.rp_filter = 2
50-tencentos.conf: net.ipv4.conf.default.rp_filter = 1 / net.ipv4.conf.*.rp_filter = 1
```

重放会打坏什么？**99-zzz 只保护 cilium 自己写的三类 key（lxc*、cilium_*、all），其余全部裸奔**——任何不是通过 sysctl.d 文件落盘的设置都会被打回发行版默认值：

| 受害对象                          | 典型例子                                                                  | 后果                             |
| --------------------------------- | ------------------------------------------------------------------------- | -------------------------------- |
| **其它组件设置的网卡参数**        | Native 模式的 eth0：`tke-eni-agent` 为 VPC-CNI 策略路由设 `rp_filter=2`   | 打回 1（strict），**直接断网**   |
|                                   | AI 推理 RDMA 场景的 bond 网卡：多机训练/推理依赖 `bond.rp_filter=0`        | 打回 1，**RDMA 通信不可用**      |
| **运维/脚本的全局 sysctl 调优**   | 节点池脚本 `sysctl -w` 设置的 `nf_conntrack_max`、`somaxconn`、`tcp_*` 等 | 打回默认值，性能回退且难察觉     |

而 cilium 自己的接口（lxc*、cilium_*、all）因 99-zzz 文件名排序靠后而胜出——**sysctlfix 保护了自己，代价是打坏节点上所有人**。

以上面第一行为例的完整因果链：eth0 被打回 `1`（strict）→ 非对称路由的流量（VPC-CNI 辅助网卡的策略路由、RDMA bond 的多路径流量）反向路径校验不过 → 包被内核丢弃 → 网络中断。这是 Native 模式**必须禁用** sysctlfix 的原因，也是 Overlay + RDMA 场景必须禁用它的原因。

这类故障尤其难排查：触发时机是"cilium pod 重建"（节点重启、DS 更新、pod 漂移），与受害症状之间没有 obvious 的因果关联，往往"当时没事、某次 cilium 更新后突然坏"。

## 问题二：Overlay 模式不能简单关掉了事

既然重启 systemd-sysctl 有害，Overlay 模式直接 `sysctlfix.enabled=false` 行不行？**不行**——实测发现关掉后 host → Pod 会不通，根因是两条机制的叠加：

**机制 A：systemd 发行版的 udev 规则会给每个新接口重放 sysctl。**

TencentOS 4（以及使用 systemd 的主流发行版）自带这条 udev 规则：

```text
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo",
RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/ipv4/conf/$name ..."
```

即**每个新网络接口创建时**，udev 会异步执行 `systemd-sysctl --prefix`，把 sysctl.d 配置中所有匹配该接口的项应用上去——`net.ipv4.conf.*.rp_filter = 1` 的 glob 恰好匹配每个新 lxc 接口。

cilium CNI 插件在创建 Pod veth 时确实会写 `lxc.rp_filter = 0`（源码 `pkg/datapath/connector/veth.go` 的 `DisableRpFilter`），**但 udev 的应用在它之后异步执行，会把 0 覆盖回 1**。没有任何覆盖文件时，新建 Pod 的 lxc 接口 rp_filter 恒为 1。

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

## 最终方案：禁用 sysctlfix + cilium-sysctl-override DaemonSet

结论：**两种模式都禁用 sysctlfix**（消除"cilium 每次启动都全量重放宿主机 sysctl"的扳机），Overlay 模式用 `cilium-sysctl-override` DaemonSet 补上 rp_filter 的保护——而且比 sysctlfix 原版覆盖面更大（[安装文档](../install.md)的前置操作中已内置）：

| 模式                     | sysctlfix        | cilium-sysctl-override DaemonSet       | 说明                                                     |
| ------------------------ | ---------------- | -------------------------------------- | -------------------------------------------------------- |
| Native Routing (VPC-CNI) | ❌ 禁用          | 不需要（可选部署，见下）               | 路由对称，lxc rp_filter=1 无影响                          |
| Overlay (VPC-CNI / GR)   | ❌ 禁用          | ✅ 必须：全节点接口 rp_filter=0        | 不重启 systemd-sysctl，无重放副作用                      |

**DaemonSet 的方案比 sysctlfix 更进一步：不写 cilium 专属的覆盖（lxc*/cilium_*），而是把全节点所有接口的 `rp_filter` 统一固定为 0**（`all`/`default`/`*` 三行）。这样 cilium 接口、VPC-CNI 策略路由的 eth*、AI 推理 RDMA 的 bond 网卡一次性全覆盖，三重保护：

1. **文件落盘**（`/etc/sysctl.d/99-zzz-rp-filter.conf`）：文件名排序在发行版配置（`50-*.conf`）之后，任何时机触发 sysctl 重放（节点重启、OS 升级、管理员手工执行）都是 0 胜出；新接口创建时 udev 的 per-interface 应用（机制 A）同样以本文件收尾，且新接口还从 `default=0` 直接继承初值，双保险。
2. **立即应用**（直写 `/proc/sys`）：文件本身只在未来某次 systemd-sysctl 运行时才生效，对部署时已存在的接口（含 bond、eth*）由 DaemonSet 每轮循环直接写入归零。
3. **周期自愈**（每 60 秒）：值被外部改动、文件被误删都会在下一轮纠正；新节点加入集群自动覆盖。

同时 DaemonSet 会清理旧版 sysctlfix 留下的 `99-zzz-override_cilium.conf`，并顺带删除 cilium 的接口覆盖（内容已包含在全接口版本中）。

在 K8s 节点上全量关闭 rp_filter 是安全惯例（cilium 官方对 kube-proxy-free 模式的建议同样如此）：节点上的多接口路由（veth/vxlan/策略路由/bond）天然非对称，strict rp_filter 只会误伤；源地址校验由 cilium 的 BPF 层和 VPC 安全组承担。

Native 模式因路由对称不依赖此 DaemonSet，但节点上若有 RDMA bond 等依赖 `rp_filter=0` 的组件，部署同一个 DaemonSet 可获得相同的全接口免疫（实测 `tke-eni-agent` 不会周期性回写 eth0，无覆盖竞争）。

:::tip[AI 推理 RDMA 场景（bond 网卡依赖 rp_filter=0）]

Overlay 模式部署的 `cilium-sysctl-override` DaemonSet 已经把**全节点接口**的 rp_filter 固定为 0，bond 网卡天然被覆盖——bond 创建时 udev 应用以 `99-zzz-rp-filter.conf` 收尾（实测新建 bond0 立即为 0），外部重放后也保持 0，bond 的 rp_filter 被 cilium 重放打坏的问题从根源消除。

实测验证过的完整矩阵（TencentOS 4.4 + cilium 1.20.1）：存量接口立即归零、新建 bond/新建 Pod lxc 均为 0、手动重启 systemd-sysctl 后全部保持 0、手动破坏后 60 秒内自愈、节点重启后全部接口 0 且文件持久、host→Pod / 跨节点 / cilium-health 全通。

:::

## 故障排查

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
2. **文件存在但值仍为 1** → DaemonSet 每 60 秒会直写 `/proc/sys` 自愈，持续为 1 说明 DS Pod 没在正常运行：检查 `kubectl -n kube-system get pod -l app=cilium-sysctl-override`（是否 Running、是否配置了 `privileged: true`，否则 `/proc/sys` 只读导致 CrashLoop）。
3. **全部为 0 但仍不通** → 问题不在 rp_filter，从其它路径继续排查（`cilium-health status --verbose`、`hubble observe`）。

## 参考资料

- [安装 Cilium](../install.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/tools/sysctlfix/main.go)
- [Cilium Source - DisableRpFilter](https://github.com/cilium/cilium/blob/main/pkg/datapath/connector/add.go)
- [Linux 内核 rp_filter 说明](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
