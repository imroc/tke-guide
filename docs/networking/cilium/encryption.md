# 启用通信加密

## 概述

本文介绍如何为 [安装 Cilium](./install.md) 三种部署方案的集群启用节点间 Pod 通信的透明加密（Transparent Encryption）。Cilium 支持以下加密方式：

- **WireGuard**：基于内核 WireGuard 模块的 UDP 隧道，密钥全自动管理（每个节点自动生成密钥对，公钥通过 CiliumNode CRD 的 `network.cilium.io/wg-pub-key` 注解分发），**本教程推荐**。
- **IPsec**：基于 Linux XFRM/ESP 框架，需要手工创建密钥 Secret 并手工轮换，三种部署方案中仅两种 Overlay 方案可用（原因见下文[适用方案矩阵](#适用方案矩阵)）。
- **ztunnel**（Beta）：Istio ambient 模式的节点级 L4 代理，提供 mTLS 加密，仅在集群使用 Istio ambient 模式时才有意义（见[与 Istio ambient 共存](#与-istio-ambientztunnel-共存)）。

两点边界说明（两种加密方式行为一致）：

- **只加密跨节点的 Cilium 管理流量**：同节点上的 Pod 之间流量不加密（明文始终可见于节点，加密无意义）；Pod 访问集群外部地址（公网/VPC 内非 Pod IP）也不加密。
- 加密依据是 Cilium 的身份判断：新节点/新 Pod 的身份信息在集群传播完成前，首批发往它的包可能以明文发出（Cilium 无法提前知道该 IP 属于远端 Pod）。

## 适用方案矩阵

| 部署方案 | WireGuard | IPsec |
| -------- | --------- | ----- |
| Native Routing (VPC-CNI) | ✅ 可用（需补一个 MTU 参数，见[下文](#启用-wireguard-加密)） | ❌ 不可用（CNI chaining 限制） |
| Overlay (VPC-CNI) | ✅ 可用（MTU 自动处理） | ⚠️ 官方支持，教程未实测，不推荐 |
| Overlay (GR) | ✅ 可用（MTU 自动处理） | ⚠️ 官方支持，教程未实测，不推荐 |

**为什么 Native Routing (VPC-CNI) 不能用 IPsec**——因果链如下：

1. 该方案是 CNI chaining 模式：cilium 以 generic-veth 插件链接在 TKE VPC-CNI 之上，Pod IP 是 VPC IP，跨节点路由由 VPC 底层（ENI 策略路由）完成，underlay 连通性归 TKE CNI 掌管。
2. Cilium 的 IPsec 透明加密依赖 Linux XFRM 框架：由 BPF 程序给出向包打加密 mark，内核 XFRM 策略在节点网络栈的 underlay 层按 mark 匹配后做 ESP 隧道封装，对端节点在解密接口上还原——整套机制要求 cilium 对 underlay 转发路径有完整掌控。
3. chaining 模式下这条前提不成立，Cilium 官方明确**不支持在 CNI chaining 之上启用 IPsec 透明加密**（[官方文档 Limitations](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)，追踪 issue [cilium/cilium#15596](https://github.com/cilium/cilium/issues/15596)：底层连通性由其它 CNI 插件负责，cilium 难以在该层正确集成以保证流量被加密）。

因此，"Pod 使用 VPC-CNI 网络就不能用 IPsec"这一说法的准确边界是：**只有 Native Routing (VPC-CNI)（chaining 模式）不可用**；两种 Overlay 方案中 cilium 独占 CNI、自建 VXLAN 隧道，不在该限制范围内。

**为什么 WireGuard 三种方案都可用**：WireGuard 的加密决策与封装都发生在 Cilium 自己的 BPF 程序和 `cilium_wg0` 隧道设备内，对 underlay 只要求"节点 IP 之间 UDP 可达"，不要求接管底层路由，因此在 chaining 模式下依然成立（官方文档对 chaining + WireGuard 场景仅提示 MTU 注意事项，而非可用性限制）。

## 启用 WireGuard 加密

### 前提条件

1. **内核 wireguard 模块**：Linux 5.6+ 内核已内置（`CONFIG_WIREGUARD=m`）。本教程[已验证的节点操作系统](./appendix/verified-os.md)中 8 个 OS 内核版本为 5.10~6.8，全部不低于 5.6，模块开箱可用（详见[下文](#os-内核模块)）。
2. **节点间放行 UDP 51871**：WireGuard 隧道端点监听在每个节点的 UDP 51871 端口，若节点安全组规则做过收紧，需确保集群节点之间互相放行该端口。

### 启用

在已有安装参数基础上追加两个参数即可（三种部署方案通用）：

```bash
helm upgrade cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
```

:::warning[Native Routing (VPC-CNI) 方案必须追加 MTU 参数]

chaining 模式下 Cilium 默认不接管 Pod 的 MTU（详见[MTU 注意事项](#mtu-注意事项)），需追加 `--set cni.enableRouteMTUForCNIChaining=true`，否则启用加密后 Pod 大包会被 WireGuard 封装撑爆网卡 MTU 而分片，造成网络性能下降：

```bash
helm upgrade cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set cni.enableRouteMTUForCNIChaining=true
```

:::

### 验证

1. 查看 Cilium 状态中的 Encryption 行（`Peers` 数量应等于节点数减一）：

   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep Encryption
   # 输出示例：
   # Encryption: Wireguard [cilium_wg0 (Pubkey: <..>, Port: 51871, Peers: 2)]
   ```

2. 查看加密详情（接口名、公钥、peer 数量）：

   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium-dbg encrypt status
   ```

   需要进一步核对每个 peer 的 `allowed-ips`（应包含对端节点上的 Pod IP）与握手时间时，用 `cilium-dbg debuginfo --output json | jq .encryption`。

3. 抓包确认流量确实走 WireGuard 隧道（在任一 cilium Pod 内安装 tcpdump 后）：

   ```bash
   tcpdump -n -i cilium_wg0
   ```

## MTU 注意事项

WireGuard 封装有额外开销（外层 IP + UDP + WireGuard 头，Cilium 按保守值 95 字节预留），启用后 Pod 可用 MTU 会收缩，两种模式的行为不同：

- **Overlay 方案（cilium 独占 CNI）——自动处理，无需任何配置**：Cilium 会自动探测节点网卡的 base MTU，按 `base MTU − VXLAN 开销(50) − WireGuard 开销(95)` 计算路由 MTU 并应用到 Pod netns 的默认路由上。底网 MTU 为 1500 时，跨节点流量的有效 MTU 约 1355。Pod 网卡 MTU 保持不变，同节点本地流量仍可用完整 MTU。
- **Native Routing (VPC-CNI) 方案——必须显式开启 `cni.enableRouteMTUForCNIChaining=true`**：chaining 模式下 Cilium 默认不管理 Pod 的路由 MTU（Pod 路由由 TKE CNI 侧配置），不开启该参数时 1500 字节的 Pod 大包经 WireGuard 封装后超出网卡 MTU，只能分片传输，表现为吞吐下降。开启后新建 Pod 由 CNI 插件在配置网卡时直接写入正确路由 MTU（约 1405），存量 Pod 由 cilium-agent 周期性更新，无需重启业务 Pod。

## OS 内核模块

WireGuard 要求内核提供 wireguard 模块（Linux 5.6+ 已合入主线，`CONFIG_WIREGUARD=m`）。本教程三种部署方案[已实测验证的 8 个节点 OS](./appendix/verified-os.md) 的内核（5.10~6.8：TencentOS Server 4 为 6.6、Ubuntu 22.04 为 5.15 等）全部满足，模块随内核自带、无需单独安装。使用列表外的自定义镜像时，可先在节点上用 `modinfo wireguard` 确认模块存在。

## 为什么教程不推荐 IPsec

除 Native 方案的硬性不可用外，即使在可用 IPsec 的 Overlay 方案中，本教程也统一推荐 WireGuard：

- **密钥管理**：IPsec 需要手工创建 `cilium-ipsec-keys` Secret，轮换密钥也要按官方流程手工执行（有 KEYID 滚动与过渡期约束）；WireGuard 的密钥生成、分发、更新全程自动。
- **性能**：Cilium IPsec 的解密限制在每隧道单 CPU 核心上，高吞吐场景容易成为瓶颈（官方文档 Limitations 明确记载）；WireGuard 内核实现无此限制，社区实测吞吐普遍优于 Cilium IPsec（具备 AES-NI 硬件加速时差距会缩小）。
- **功能覆盖**：加密严格模式的 ingress 侧（丢弃未加密的集群内入向流量）仅支持 WireGuard，不支持 IPsec。
- **运维细节**：Overlay + IPsec 要求节点安全组放行 ESP（IP 协议 50），而 WireGuard 走 UDP 51871，与常规安全组管理习惯更兼容。

## 与 Istio ambient/ztunnel 共存

如果集群使用 Istio ambient 模式，Pod 间 mTLS 加密可由其节点级 ztunnel 代理承担，无需再启用 Cilium 的 WireGuard/IPsec 加密，避免双层加密带来的额外开销与排障复杂度。Cilium 自身也支持 `encryption.type=ztunnel`（Beta）与 ztunnel 集成，本教程不展开。

## 参考资料

- [Cilium Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption/)
- [Cilium WireGuard Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/)
- [Cilium IPsec Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)
- [CNI chaining 限制（IPsec 不支持）issue cilium/cilium#15596](https://github.com/cilium/cilium/issues/15596)
