# sysctlfix 与 rp_filter 机制详解

cilium 默认启用的 `sysctlfix` 功能会在 TKE 上引发两类问题，因此**本系列教程的两种安装模式（Native Routing 与 Overlay）都禁用它**（`sysctlfix.enabled=false`）。但两种模式的禁用原因、以及禁用后是否需要补偿措施并不相同：

| 模式                     | 禁用原因                                 | 禁用后需要补偿？                            |
| ------------------------ | ---------------------------------------- | ------------------------------------------- |
| Native Routing (VPC-CNI) | 重启 systemd-sysctl 会把 eth0 打回 strict，直接断网 | 不需要（路由对称，lxc rp_filter 值无影响） |
| Overlay (VPC-CNI / GR)   | 同上（重放覆盖运行时 sysctl 修改）       | **需要**：部署 `cilium-sysctl-override` DaemonSet |

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

重放的危害分两类：

- **Native Routing (VPC-CNI)：直接断网**。VPC-CNI 共享网卡多 IP 模式下，`tke-eni-agent` 会把网卡的 `rp_filter` 调成 `2`（loose，配合策略路由放行非对称路由）。sysctlfix 触发的重放把 eth0 打回 `1`（strict），辅助网卡 IP 的非对称流量被严格反向路径校验丢弃，Pod 网络随之中断。这是 Native 模式**必须禁用** sysctlfix 的原因。
- **所有模式：运行时 sysctl 修改丢失**。任何不是通过 sysctl.d 文件落盘的运行时修改（节点池脚本 `sysctl -w`、运维手工调优的 `nf_conntrack_max`、`somaxconn` 等）都会在重放时被打回发行版默认值。cilium 自身接口因 99-zzz 文件（文件名排序在后）胜出不受影响，但**节点上其它组件与运维的 sysctl 修改全部遭殃**——而且这类故障"当时没事、pod 一重建就坏"，非常难排查。

## 问题二：Overlay 模式不能简单关掉了事

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

## 最终方案：禁用 sysctlfix + cilium-sysctl-override DaemonSet

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
2. **文件存在但值仍为 1** → 存量接口停留在被重放后的值（常见于从 sysctlfix=true 切换的集群），在节点执行 `sudo systemctl restart systemd-sysctl` 让 99-zzz 重放胜出，或滚动重启业务 Pod。
3. **全部为 0 但仍不通** → 问题不在 rp_filter，从其它路径继续排查（`cilium-health status --verbose`、`hubble observe`）。

## 参考资料

- [安装 Cilium](../install.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/tools/sysctlfix/main.go)
- [Cilium Source - DisableRpFilter](https://github.com/cilium/cilium/blob/main/pkg/datapath/connector/add.go)
- [Linux 内核 rp_filter 说明](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
