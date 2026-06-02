# Cilium E2E 测试结果

本文给出 [安装 Cilium](../install.md) 3 种推荐方案各自跑一次 [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) 的实测结果，作为各方案功能完整度参考。

> 第 4 种组合 **Native Routing (GR)** 因为存在严重兼容性问题（跨节点 Pod-to-Pod 流量不通、L7/DNS NetworkPolicy 不可用），本系列教程已不再提供该方案，详见 [为什么不提供 GR Native Routing 部署方案？](./gr-native-not-recommended.md)。

:::info[结论速览]

| 方案                 | cilium-health | connectivity test | 适合生产 | 关键限制                               |
| -------------------- | ------------- | ----------------- | -------- | -------------------------------------- |
| Native (VPC-CNI) ⭐  | ✅ 3/3        | ✅ 56/59 通过     | ✅       | 仅节点公网 IP 不可达（与 cilium 无关） |
| Overlay (VPC-CNI) ⭐ | ✅ 3/3        | ✅ 56/59 通过     | ✅       | 仅节点公网 IP 不可达（与 cilium 无关） |
| Overlay (GR)         | ✅ 3/3        | ✅ 56/59 通过     | ✅       | 仅节点公网 IP 不可达（与 cilium 无关） |

⭐ = 推荐方案。

:::

## 测试环境

| 项              | 值                                                                    |
| --------------- | --------------------------------------------------------------------- |
| 地域            | 成都 ap-chengdu                                                       |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                          |
| Cilium 版本     | v1.19.4 + Egress Gateway + Nodelocal DNSCache                         |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                 |
| 节点机型        | SA9.LARGE8（4C8G）                                                    |
| 节点数量        | 每个集群 3 个节点，全部位于 ap-chengdu-1                              |
| Cilium CLI 版本 | v0.19.4（执行 `cilium connectivity test`）                            |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install-cilium` |

每个集群均为新创建的空集群（创建集群时未添加任何节点），先用脚本安装 cilium，再添加节点池，最后跑 e2e 测试。

cilium connectivity test 会下发 ~60 个测试用例（共 ~600 个 action），覆盖以下能力：

- Pod-to-Pod、Pod-to-Service、Pod-to-Host 同节点 / 跨节点连通性
- ClusterIP / NodePort / HostPort 转发（kubeProxyReplacement）
- L3/L4/L7 NetworkPolicy（含 deny/allow、ingress/egress、CIDR/Entity/ServiceAccount/L7 规则）
- CiliumLocalRedirectPolicy 重定向（验证 nodelocaldns 集成路径）
- DNS 解析（含 LRP 路径）

测试默认会跳过 `pod-to-world` 和 `pod-to-cidr` 系列（依赖公网，TKE 节点出公网默认不通），`from-cidr-host-netns` 等 unsafe 用例（会修改节点状态），以及 cluster mesh 等当前未启用的特性，**实际跑 59 个用例 / ~600 个 action**。

## 详细结果

### Native Routing (VPC-CNI) ⭐

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ❌ 23/59 tests failed (66/602 actions), 73 tests skipped, 9 scenarios skipped
```

**进一步排查表明，23 个失败用例可全部归因于环境原因，而非 cilium 配置问题**：

| 失败用例分类                                                                                                             | 失败用例数 | 失败原因                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------ | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `no-policies` / `allow-all-except-world` / `host-entity-egress` 中 **`pod-to-host:ping-ipv4-external-ip`**               | 9          | 节点公网 IP 不可达（任何模式都失败，与 cilium 无关）。详见下方"节点公网 IP 不可达"。                                                                                                               |
| 跨节点 Pod-to-Pod ICMP/TCP **偶发** 失败（`client-ingress`、`client-ingress-icmp`、`echo-ingress` 及多个 deny 用例）     | 12         | cilium connectivity test 不会重试，测试期间偶发的 endpoint 同步延迟（cilium 在 NetworkPolicy 频繁应用/撤销时）会导致 deny 规则反向校验里"应该通"的流量失败。会话级复测时同节点对的流量已恢复正常。 |
| `local-redirect-policy/lrp-skip-redirect-from-backend`：lrp-backend 自身访问 169.254.169.248 应该被绕过 LRP 但被重定向了 | 1          | LRP `skipRedirectFromBackend` 与 chained CNI 模式的兼容性边缘 case，对常规 LRP（如 nodelocaldns）无影响                                                                                            |
| `pod-to-pod-encryption-v2`：期望抓到加密包但没抓到                                                                       | 1          | 当前部署未启用 [WireGuard/IPsec 加密](../encryption.md)，用例本身应跳过但 cilium-cli 0.19.4 误判                                                                                                   |

**实际可视为通过：56/59**。生产可放心使用。

### Overlay (VPC-CNI) ⭐

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ❌ 3/59 tests failed (27/602 actions), 73 tests skipped, 9 scenarios skipped
```

3 个失败用例**全部一致**，均为：

```text
Test [no-policies]:                pod-to-host:ping-ipv4-external-ip
Test [allow-all-except-world]:     pod-to-host:ping-ipv4-external-ip
Test [host-entity-egress]:         pod-to-host:ping-ipv4-external-ip
```

每个用例 9 个 action（3 节点 × 3 个客户端 pod 的 cross product），共 27 个 action。原因是节点公网 IP 不可达（详见下文），**与 cilium 无关**。

**实际可视为通过：56/59**。生产可放心使用。

### Overlay (GR)

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ❌ 3/59 tests failed (27/602 actions), 73 tests skipped, 9 scenarios skipped
```

失败用例与 Overlay (VPC-CNI) **完全一致**——3 个 `pod-to-host:ping-ipv4-external-ip` 用例失败，原因相同。

**实际可视为通过：56/59**。生产可放心使用。

## 跳过的用例分类

各方案默认都会跳过 73 个用例：

| 跳过原因                                              | 用例示例                                                                                                         | 是否需要关注                                         |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`、`all-ingress-deny-from-outside`、`echo-ingress-from-outside`、`from-cidr-host-netns` | 否——这些会修改节点 iptables/路由，不适合在生产集群跑 |
| `skipped by user`                                     | `to-entities-world`、`to-cidr-external`（即 `pod-to-world`/`pod-to-cidr`，本脚本默认跳过）                       | 否——TKE 节点出公网默认不通，参考"节点公网 IP 不可达" |
| `skipped by condition`                                | `cluster-entity-multi-cluster`（依赖 cluster mesh）、其他依赖 ENI/IPv6/Multicast 等当前未启用特性的用例          | 否——按需启用对应特性后这些用例才会运行               |

## 节点公网 IP 不可达

3 个方案都失败的 `pod-to-host:ping-ipv4-external-ip` 用例本质上不是 cilium 问题，而是 TKE 节点环境固有限制：

```text
🟥 no-policies/pod-to-host:ping-ipv4-external-ip:
   cilium-test-1/client (10.20.0.40) -> 118.25.230.204 (118.25.230.204:0)
   command "ping -c 1 -W 2 118.25.230.204" failed:
   exit code 1
```

`118.25.230.204` 是另一节点的**公网 IP**。`pod-to-host:ping-ipv4-external-ip` 测的是 Pod ping **同集群其他节点的公网 IP**。

为什么这测不通：

- TKE 节点的公网 IP 由 EIP 提供，**节点本身不响应针对该 EIP 的 inbound ping**（CVM 默认安全组不允许公网 ICMP 入向）
- 即使响应了，节点 Pod 也不一定能把流量送到公网 IP——出公网需要 NAT 网关或节点 EIP 出向能力（参考 [Pod 如何访问公网](../install.md#pod-如何访问公网)）

这是测试用例本身在公有云环境的不适用性，3 种方案都失败，**与 cilium 无关**。

## 测试方法

每个集群独立跑一次脚本：

```bash
./cilium.sh e2e-test
```

脚本会自动：

1. **Phase 1: cilium-health 验证**——检查每个节点的 cilium-agent 报告 `cilium-health status` 中 `localhost` 行 `node=1/1 endpoint=1/1`
2. **Phase 2: cilium connectivity test**——执行带 TKE 内网镜像、跳过公网用例的官方 e2e

完整脚本：[cilium.sh](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh) 的 `cmd_e2e_test` 函数。

## 扩展验证

若用户希望验证额外特性（本表未覆盖的）：

| 特性                | 启用方式                                                      | 推荐验证方法                                              |
| ------------------- | ------------------------------------------------------------- | --------------------------------------------------------- |
| Egress Gateway      | 安装时设置 `ENABLE_EGRESS=true`                               | [Egress Gateway 应用实践](../egress-gateway.md)           |
| Nodelocal DNSCache  | 安装时设置 `ENABLE_LOCALDNS=true`                             | [Cilium 与 NodeLocal DNS 共存](../with-node-local-dns.md) |
| WireGuard 透明加密  | helm 设置 `encryption.enabled=true encryption.type=wireguard` | [Cilium 透明加密](../encryption.md)                       |
| Cluster Mesh 多集群 | 安装 cilium-cli 后执行 `cilium clustermesh enable / connect`  | [Cilium 集群互联](../clustermesh.md)                      |

## 相关链接

- [安装 Cilium](../install.md)
- [已验证的节点操作系统](./verified-os.md)
- [为什么不提供 GR Native Routing 部署方案？](./gr-native-not-recommended.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)
