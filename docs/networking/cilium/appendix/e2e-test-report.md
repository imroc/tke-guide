# Cilium E2E 测试结果

本文给出 [安装 Cilium](../install.md) 3 种推荐方案各自跑一次 [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) 的实测结果，作为各方案功能完整度参考。

> 第 4 种组合 **Native Routing (GR)** 因为存在严重兼容性问题（跨节点 Pod-to-Pod 流量不通、L7/DNS NetworkPolicy 不可用），本系列教程已不再提供该方案，详见 [为什么不提供 GR Native Routing 部署方案？](./gr-native-not-recommended.md)。

:::info[结论速览]

| 方案                 | cilium-health | connectivity test | 适合生产 |
| -------------------- | ------------- | ----------------- | -------- |
| Native (VPC-CNI) ⭐  | ✅ 3/3        | ✅ 全部通过       | ✅       |
| Overlay (VPC-CNI) ⭐ | ✅ 3/3        | ✅ 全部通过       | ✅       |
| Overlay (GR)         | ✅ 3/3        | ✅ 全部通过       | ✅       |

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

cilium connectivity test 默认会下发 132 个测试用例 / ~600 个 action，覆盖 Pod-to-Pod、Pod-to-Service、Pod-to-Host 同/跨节点连通性、ClusterIP/NodePort/HostPort 转发（kubeProxyReplacement）、L3/L4/L7 NetworkPolicy（含 deny/allow、ingress/egress、CIDR/Entity/ServiceAccount/L7 规则）、CiliumLocalRedirectPolicy 重定向、DNS 解析等。

`cilium.sh e2e-test` 在跑测前会过滤掉以下用例（详见后文 "[跳过的测试用例](#跳过的测试用例)"）：

- `pod-to-world` / `pod-to-cidr`：依赖公网，TKE 节点出公网默认不通
- `pod-to-host`：默认会用节点的 ExternalIP（EIP）做 ping 目标，TKE 节点安全组默认禁止公网 ICMP 入向，必失败且与 cilium 无关
- 其它 `unsafe`、未启用特性等用例：cilium-cli 自身条件性跳过

最终实际跑 **58 个用例 / 521 个 action**。

## 详细结果

### Native Routing (VPC-CNI) ⭐

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

全部通过。生产可放心使用。

### Overlay (VPC-CNI) ⭐

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

全部通过。生产可放心使用。

### Overlay (GR)

```text
[1/2] cilium-health 验证通过: 3/3 节点健康
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

全部通过。生产可放心使用。

## 跳过的测试用例

`cilium.sh e2e-test` 会通过 `--test '!...'` 过滤器跳过下列在 TKE 节点环境下无法跑通、且与 cilium 本身能力无关的用例：

| 跳过的 scenario | 跳过原因                                                                                                                                                                                                                     |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pod-to-world`  | 默认目标是 `one.one.one.one`，国内节点出公网受限/被防火墙拦截                                                                                                                                                                |
| `pod-to-cidr`   | 同上，依赖公网 CIDR                                                                                                                                                                                                          |
| `pod-to-host`   | 该 scenario 中 `ping-ipv4-external-ip` action 用节点的 ExternalIP（即 EIP/公网 IP）作为目标。TKE 节点 EIP 默认安全组**不允许公网 ICMP 入向**——任何 TKE 部署都必失败，且包根本到不了 cilium datapath，过不过都不能验证 cilium |

> Pod 与节点（Internal IP）的连通性已被 `pod-to-pod`、`pod-to-service` 等其他 scenario 覆盖，跳过 `pod-to-host` 不会减少实际覆盖。

除上述 3 类外，cilium-cli 还会按自身条件**自动跳过** 74 个用例：

| 跳过原因                                              | 用例示例                                                                                                                  | 是否需要关注                                         |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`、`all-ingress-deny-from-outside`、`echo-ingress-from-outside`、`from-cidr-host-netns` 等       | 否——这些会修改节点 iptables/路由，不适合在生产集群跑 |
| `skipped by condition`                                | `cluster-entity-multi-cluster`（依赖 cluster mesh）、依赖 ENI/IPv6/Multicast/`node-without-cilium` 等当前未启用特性的用例 | 否——按需启用对应特性后这些用例才会运行               |
| `skipped by user`                                     | TLS / `egress-gateway-excluded-cidrs` 等带 client cert 或外部 host 的子用例                                               | 否——这些用例需要预先准备外部资源，不适合默认跑       |

## 测试方法

每个集群独立跑一次脚本：

```bash
./cilium.sh e2e-test
```

脚本会自动：

1. **Phase 1: cilium-health 验证**——检查每个节点的 cilium-agent 报告 `cilium-health status` 中 `localhost` 行 `node=1/1 endpoint=1/1`
2. **Phase 2: cilium connectivity test**——执行 cilium 官方 e2e 套件，使用 TKE 内网可拉取的 mirror 镜像，通过 `--test '!...'` 跳过上文列出的 3 类用例

完整实现：[cilium.sh](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh) 的 `cmd_e2e_test` 函数。

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
