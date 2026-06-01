# 为什么 Native Routing (GR) 节点池必须打 cilium agent-not-ready 污点？

## 背景

在 TKE 集群安装 cilium 后创建节点池，如果使用的是 **Native Routing (GR)** 方案，**必须**给节点池添加以下污点：

```text
node.cilium.io/agent-not-ready=true:NoSchedule
```

而其它三种模式（Native Routing VPC-CNI、Overlay VPC-CNI、Overlay GR）则**不需要**这个污点。本文解释这一差异。

## 故障现象

不打这个 taint 时，新加入集群的节点可能会出现：

- 节点上的某些 Pod（特别是早期调度的，如 `csi-cbs-controller`、依赖元数据服务的组件）会因网络问题反复 CrashLoopBackOff
- Pod 缺少 cilium 提供的 masquerade、NetworkPolicy 等能力
- 重启节点后部分恢复，但不稳定

根因是节点加入时存在 **CNI 配置时序竞争**。

## GR 模式 CNI 的特殊性

GR 模式下：

- **每个节点的 PodCIDR 都不同**（GR 给每个节点分一段子网作为该节点的 PodCIDR）
- CNI 配置由 `tke-bridge-agent` 按节点动态生成，**包含该节点专属的子网信息**

```text
节点 A (PodCIDR 10.244.1.0/24)         节点 B (PodCIDR 10.244.2.0/24)
┌─────────────────────────┐            ┌─────────────────────────┐
│ /etc/cni/net.d/         │            │ /etc/cni/net.d/         │
│  10-tke-bridge.conflist │            │  10-tke-bridge.conflist │
│  ┌───────────────────┐  │            │  ┌───────────────────┐  │
│  │ subnet:           │  │            │  │ subnet:           │  │
│  │   10.244.1.0/24   │  │            │  │   10.244.2.0/24   │  │
│  └───────────────────┘  │            │  └───────────────────┘  │
└─────────────────────────┘            └─────────────────────────┘
```

这意味着 cilium **无法像 VPC-CNI 或 Overlay 模式那样用一份统一的 CNI 配置接管所有节点**。它只能通过 `chainingTarget` 监视 tke-bridge 生成的 CNI 配置，并把自己追加到 chain 末尾。

## 时序竞争

节点加入集群时，正常顺序应该是：

1. tke-bridge-agent 写入 CNI 配置（含本节点 PodCIDR 信息）
2. cilium agent 启动，检测到 tke-bridge 配置，append 自己到 chain
3. kubelet 看到完整 CNI chain 就绪，开始调度业务 Pod
4. Pod 经过 tke-bridge + cilium-cni 的增强链路，获得 masquerade、NetworkPolicy 等能力

但实际发生的是：

```text
T0: 节点加入集群
T1: tke-bridge-agent 写好 CNI 配置 ──┐
T2: kubelet 看到 CNI 就绪，立即调度 Pod │ 时序问题：cilium 还没来得及 append！
T3: Pod 使用「裸 tke-bridge CNI」启动 ─┘
T4: cilium agent 启动完成，append 到 chain
T5: 后续新建的 Pod 才能享受 cilium 增强
```

T2 → T3 期间创建的 Pod 处于"残缺态"：

- 它们的网络配置是裸 tke-bridge 给的，没有 cilium-cni 的增强
- 缺少 masquerade，可能无法访问 TKE 元数据服务等
- 缺少 NetworkPolicy 强制
- 即使后来 cilium agent 起来了，这些 Pod 也已经"错过"了 cilium-cni 的初始化，不会自动修复

## 污点的作用

给节点池打上 `node.cilium.io/agent-not-ready=true:NoSchedule` 后：

- 节点加入集群时**默认带这个污点**，业务 Pod 不会被调度上来
- cilium agent 启动完成后，**会自动移除该污点**（这是 cilium 的内置行为）
- 移除污点后，kubelet 才开始调度业务 Pod，此时 CNI chain 已就绪，Pod 进入"完整态"

```text
T0: 节点加入集群（带 agent-not-ready 污点，无业务 Pod 被调度）
T1: tke-bridge-agent 写 CNI 配置
T2: cilium agent 启动 → append 到 chain → 自动移除污点
T3: 业务 Pod 才开始调度，CNI chain 完整 ✓
```

## 其它模式为什么不需要

| 模式                     | 是否需要 taint | 原因                                                                                      |
| ------------------------ | -------------- | ----------------------------------------------------------------------------------------- |
| Native Routing (VPC-CNI) | ❌ 不需要      | `cni.customConf=true`，所有节点共用一份 ConfigMap，无 per-node 动态生成 → 无时序问题      |
| Native Routing (GR)      | ✅ **必须**    | 每节点 PodCIDR 不同，CNI 由 tke-bridge-agent 动态生成 → 时序竞争存在                      |
| Overlay (VPC-CNI / GR)   | ❌ 不需要      | cilium 完全接管 CNI，kubelet 在 cilium CNI 就绪前不会成功创建 Pod sandbox（自然阻塞调度） |

## 如何配置

### 控制台

新建节点池时，在**高级设置**中添加污点：

- Key: `node.cilium.io/agent-not-ready`
- Value: `true`
- Effect: `NoSchedule`

### Terraform

普通节点池：

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  # ...
  taints {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NoSchedule"
  }
}
```

原生节点池 / Karpenter NodePool 类似，按对应资源的字段添加 taint 即可。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium Docs - Taint Effects](https://docs.cilium.io/en/stable/installation/taints/)
