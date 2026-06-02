# 为什么不提供 GR Native Routing 部署方案？

本系列教程**不再提供 GR 集群 + Native Routing** 的部署方案。本文整理在该模式上踩过的所有坑、技术原理与替代方案，给希望理解原因或已经部署该方案的读者提供完整参考。

:::warning[结论]

GR 集群安装 cilium 时，请只使用 **Overlay 模式**；如需 **Native Routing**，请使用 **VPC-CNI 集群**。

GR + Native Routing 同时撞上以下 4 类问题，组合后基本无法生产可用：

1. ❌ **跨节点 Pod-to-Pod 流量不通**（最严重，参见下文 "1. 跨节点 Pod-to-Pod 流量不通"）
2. ❌ **L7 / DNS / `toFQDNs` NetworkPolicy 不支持**
3. ⚠️ **节点池必须额外打 `node.cilium.io/agent-not-ready` 污点**（其它三种模式不需要）
4. ⚠️ **GR 与 VPC-CNI 共存能力被破坏**

:::

## 为什么我们做过这个方案

GR 集群在国内 TKE 用户中存量很大；最初我们希望"GR 集群也能用上完整的 Native Routing 高性能能力"，所以一开始把 GR + Native Routing 作为推荐方案之一加入了文档。

实际跑完 [4 种部署方案的 e2e 测试](./e2e-test-report.md) 后才发现：在 cilium 的 [generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/) 模式 + tke-bridge 的 `cbr0` 桥之上，cilium 的 eBPF datapath 与 Linux 桥转发路径互不兼容，导致基础连通性都过不去。本文详细列出每一个失败点。

## 1. 跨节点 Pod-to-Pod 流量不通

这是该方案的**致命问题**。e2e 测试在 setup 阶段就过不去：

```text
⌛ Waiting for pod cilium-test-1/client3 to reach DNS server on cilium-test-1/echo-same-node pod...
timeout reached waiting for lookup ... context deadline exceeded
```

复现：

```bash
# 节点 105 上的 client pod 访问节点 222 上的 pod
$ kubectl -n cilium-test-1 exec deploy/client -- ping -c 2 -W 2 9.230.0.14
2 packets transmitted, 0 received, 100% packet loss

# 但 105 节点本身（host network）访问 222 节点上的 pod 完全正常
$ kubectl run nettest --rm -i --restart=Never --image=... \
    --overrides='{"spec":{"hostNetwork":true,"nodeSelector":{...}}}' \
    -- ping -c 3 -W 2 9.230.0.14
3 packets transmitted, 3 received, 0% packet loss
```

`cilium monitor` 抓到出向包能进 host stack：

```text
-> stack flow 0x0, identity 24059->417, ifindex 0
   9.230.0.208 -> 9.230.0.14 icmp EchoRequest
```

但**没有任何回包记录**——回程包到达对端节点 eth0 后，被 cilium ebpf 程序 (`cil_from_netdev`) 拦截或丢弃，无法到达 cbr0 → veth → pod。

**根因**：

- TKE GR 集群的跨节点 PodCIDR 路由由 GlobalRouter 在母机层维护，节点出包走默认网关后由母机转发到对端节点
- 但 cilium 在 chained CNI 模式下，对 eth0 的 ingress 挂了 `cil_from_netdev` eBPF 程序
- 该 eBPF 程序对来自外部、目的为本节点 PodCIDR 的流量，由于 cilium 不掌握 IPAM、不知道这些 IP 是 cilium 管理的合法 endpoint，处理路径与 cbr0 桥转发不兼容，导致包丢失

同节点 Pod-to-Pod 通信因为不经过 eth0 ingress，所以正常工作。这造成"看起来 cilium 装好了"的假象，但任何跨节点业务都会失败。

## 2. L7 / DNS / `toFQDNs` NetworkPolicy 不支持

cilium 的 L7 能力依赖 DNS 代理与 envoy proxy redirect，链路：

```text
Pod ──DNS query──▶ BPF (打 mark) ──▶ iptables TPROXY ──▶ cilium DNS proxy ──▶ upstream DNS
                                       ▲
                                       │
                                       └─ 依赖 socket dispatch（lookup → process socket）
```

GR Native Routing 下，Pod 流量经过 `cbr0` 桥：

```text
Pod ─▶ veth ─▶ cbr0 (bridge forwarding) ─▶ eth0 ─▶ upstream
                  ▲
                  │
                  └─ 桥转发路径上，包不会进入 IP routing/socket lookup
                     iptables TPROXY 无法做 socket dispatch
```

桥转发路径上的数据包**不会真正进入 IP routing / socket lookup**，因此 iptables TPROXY 的 socket dispatch 不生效，cilium DNS 代理收不到流量。

**症状**：被含 `rules.dns` 或 `toFQDNs` 的 CiliumNetworkPolicy 选中的 Pod，**所有 DNS 查询都会超时**（不是返回 NXDOMAIN/REFUSED，而是无任何响应），即使是集群内服务名（如 `kubernetes.default.svc`）也无法解析；移除该 NetworkPolicy 后立即恢复。

cilium 官方文档已将此明确标注为 generic-veth chaining 的 Limitation：

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- 跟踪 issue: [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)（packet mark 冲突导致 proxy redirect 失败，与 GR 场景同源）

## 3. 节点池必须额外打 `node.cilium.io/agent-not-ready` 污点

GR 模式下：

- **每个节点的 PodCIDR 都不同**（GR 给每个节点分一段子网作为该节点的 PodCIDR）
- CNI 配置由 `tke-bridge-agent` 按节点动态生成，**包含该节点专属的子网信息**

这意味着 cilium **无法像 VPC-CNI 或 Overlay 那样用一份统一的 CNI 配置接管所有节点**——它只能通过 `chainingTarget` 监视 tke-bridge 生成的 CNI 配置，再把自己追加到 chain 末尾。

时序竞争：

```text
T0: 节点加入集群
T1: tke-bridge-agent 写好 CNI 配置 ──┐
T2: kubelet 看到 CNI 就绪，立即调度 Pod │ 时序问题：cilium 还没来得及 append！
T3: Pod 使用「裸 tke-bridge CNI」启动 ─┘
T4: cilium agent 启动完成，append 到 chain
T5: 后续新建的 Pod 才能享受 cilium 增强
```

T2 → T3 期间创建的 Pod 处于"残缺态"——它们的网络配置是裸 tke-bridge 给的，没有 cilium-cni 的增强：

- 缺少 masquerade，可能无法访问 TKE 元数据服务等
- 缺少 NetworkPolicy 强制
- 即使后来 cilium agent 起来了，这些 Pod 也已经"错过"了 cilium-cni 的初始化，不会自动修复

**变通**：节点池打上 `node.cilium.io/agent-not-ready=true:NoSchedule` 污点。cilium agent 启动完成后会自动移除该污点，调度才开始。

但这是该模式特有的额外配置负担，其它三种模式都不需要，且漏配后症状隐蔽（Pod 看似 Running，业务才发现部分 Pod 网络异常）。

## 4. GR 与 VPC-CNI 共存能力被破坏

GR 集群本身支持通过 [启用 VPC-CNI 网络能力](https://cloud.tencent.com/document/product/457/50354) 实现 GR 与 VPC-CNI 共存（默认走 GR，带特殊 annotation 的 Pod 走 VPC-CNI）。

但**安装本系列教程方案的 cilium 后此功能将不再实际可用**：

- cilium chaining 通过 multus 配置（`defaultDelegates=tke-bridge`）接管所有 Pod 网络
- 创建带 `tke.cloud.tencent.com/networks: tke-route-eni` annotation 的 Pod 后，IP 仍然来自 GR 的 ClusterCIDR 段（而不是 VPC-CNI 子网），实际并未走 VPC-CNI 路径
- 操作上 `EnableVpcCniNetworkType` 接口可以调用成功，组件也会部署，但对 Pod 网络没有实际影响

如果业务有这种共存需求，必须使用 VPC-CNI 集群。

## 替代方案

按你的实际需求，从下表挑选：

| 需求场景                                         | 推荐方案                                              |
| ------------------------------------------------ | ----------------------------------------------------- |
| 已有 GR 集群、希望用 cilium                      | **Overlay (GR)** —— 完整功能，与 VPC-CNI 集群体验一致 |
| 新建集群、性能优先、Pod 直接路由                 | **Native Routing (VPC-CNI)** —— 推荐                  |
| 新建集群、IP 资源紧张或希望 Pod CIDR 与 VPC 解耦 | **Overlay (VPC-CNI)** —— 推荐                         |

三个推荐方案均已通过 [完整 e2e 测试](./e2e-test-report.md)（56/59 用例通过，余下 3 个为节点公网 IP 不可达，与 cilium 无关）。

如果你已经在生产用 GR 集群但**还没装 cilium**，建议改用 Overlay 模式装 cilium，对业务的影响仅限于 Pod IP 不再来自 GR 网段（独立 CIDR），其他能力完整。

如果你已经按本教程**早期版本**部署了 GR Native Routing 方案：

- 同节点业务可能没有问题，但**任何跨节点 Pod-to-Pod 通信、跨节点 Service 访问都不可靠**
- 建议尽快迁移到 GR Overlay 或 VPC-CNI 集群
- 迁移路径：通常需要 [回滚到 TKE 内置 CNI](../install.md#回滚到-tke-内置-cni)，再按 Overlay 模式重新安装；建议在维护窗口操作

## 历史方案残留 cleanup

如果你希望从 GR Native Routing 状态彻底清理，把集群恢复到可装 Overlay 的状态：

```bash
# 1. 卸载 cilium（含创建的 ip-masq-agent ConfigMap）
helm uninstall cilium -n kube-system
kubectl -n kube-system delete cm ip-masq-agent

# 2. 还原 tke-bridge-agent 配置
#    （安装 GR Native 时改了 --cni-conf-dir 与 --port-mapping=false）
kubectl -n kube-system edit ds tke-bridge-agent
# 把 args 中的 --cni-conf-dir 路径改回 /host/etc/cni/net.d/multus
# 移除 --port-mapping=false
kubectl -n kube-system rollout status ds/tke-bridge-agent

# 3. 节点池移除 node.cilium.io/agent-not-ready taint（如果有）

# 4. 重启或重建节点（推荐重建，避免残留 ebpf 程序与 iptables）
```

之后按 Overlay 流程重新装即可。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium E2E 测试结果](./e2e-test-report.md)
- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)
