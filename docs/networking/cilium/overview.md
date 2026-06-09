# 概述

[Cilium](https://cilium.io/) 是一个基于 eBPF 的开源云原生网络解决方案，可为 Kubernetes 集群提供高性能网络、高级网络安全策略、可观测性等能力。本系列教程介绍如何在 TKE 集群中安装和使用 Cilium。

## 文章地图

### 入门篇

| 文章                    | 内容                                | 适合读者         |
| ----------------------- | ----------------------------------- | ---------------- |
| **安装 Cilium**         | 空集群创建、helm 安装、验证、回滚   | 首次上手         |
| **使用 TCR 托管镜像**   | 生产环境用内网 TCR 替代公网镜像拉取 | 追求集群稳定性   |
| **Cilium 功能测试**     | 功能测试方法与实测数据              | 所有安装后的用户 |
| **Cilium 性能测试**     | 网络基准性能与各方案横向对比        | 关注性能的用户   |

### 网络增强

| 文章                                  | 内容                                  | 前置依赖      |
| ------------------------------------- | ------------------------------------- | ------------- |
| **配置 IP 伪装**                      | 让 Pod 借节点 EIP 出公网（SNAT）      | 已安装 Cilium |
| **Egress Gateway 应用实践**           | 按策略选择固定出口 IP 访问外部        | 已安装 Cilium |
| **启用通信加密**                      | WireGuard / IPsec 加密节点间 Pod 流量 | 已安装 Cilium |
| **使用 Cilium 构建多集群网络**        | Cluster Mesh 打通多集群服务互访       | 已安装 Cilium |

### 安全策略

| 文章                       | 内容                                      |
| -------------------------- | ----------------------------------------- |
| **NetworkPolicy 应用实践** | CiliumNetworkPolicy 入门与常见模式 20+ 例 |

### 可观测性

| 文章                                     | 内容                                           |
| ---------------------------------------- | ---------------------------------------------- |
| **增强可观测性**                         | 启用 Hubble Relay / Hubble UI / 网络流日志审计 |
| **使用 Cilium + CLS 实现网络流日志审计** | 将 Hubble 流日志投递到 CLS 检索分析            |

### 附录（设计原理与运维指南）

| 文章                                     | 内容                                                 |
| ---------------------------------------- | ---------------------------------------------------- |
| **大规模集群 Cilium 调优指南**           | 200+ 节点规模下的参数、资源、BPF map 调优            |
| **已验证的节点操作系统**                 | 8 种 OS 的兼容性验证结果                             |
| **Cilium Host Routing** ◀─┬─▶            | 三部曲之一：Legacy vs BPF 的机制、命中条件、横向对比 |
| **为什么 Native 要加 local-router-ipv4** │ | 三部曲之二：cilium_host IP 配置原理与地址选择        |
| **为什么 Native 禁用 sysctlfix**         │ | 三部曲之三：rp_filter 差异与决策逻辑                 |
| **为什么不提供 GR Native Routing**       | 完整试错记录与 4 类不可用问题                        |
| **Cilium 与 Nodelocal DNSCache 共存**   | 自建 NodeLocal DNS 加速 DNS 解析                    |

> 标有 ◀─┬─▶ 的三篇文章构成 Native Routing 设计原理三部曲，建议按顺序阅读。

### 故障排查

| 文章                                            | 内容                                |
| ----------------------------------------------- | ----------------------------------- |
| **连接 apiserver 报错 operation not permitted** | Cilium bug 排查与根因分析           |
| **Cilium 调试技巧**                             | `cilium status`、monitor 等常用命令 |

## 快速决策树

根据你的需求，从下面快速定位到目标文章：

```text
你想干什么？
├─ 安装 Cilium
│  ├─ 新建集群，首次安装 → 安装 Cilium
│  ├─ 已有集群，想测试是否正常 → 功能测试
│  └─ 关心性能表现 → 性能测试
├─ 配置网络能力
│  ├─ Pod 要出公网
│  │  ├─ 已有 NAT 网关 → 无需额外配置
│  │  ├─ 想复用节点 EIP → 配置 IP 伪装
│  │  └─ 想指定固定出口 IP → Egress Gateway
│  ├─ 加密节点间流量 → 启用通信加密
│  ├─ 让多个集群互通 → 构建多集群网络
│  └─ 加速 DNS 解析 → Nodelocal DNSCache
├─ 写网络策略
│  └─ 限制 Pod 间/出站/入站访问 → NetworkPolicy 应用实践
├─ 做可观测性
│  ├─ 看看集群服务拓扑 → 增强可观测性
│  └─ 做网络流日志审计 → Cilium + CLS 日志审计
├─ 调优与排障
│  ├─ 大规模集群优化 → 大规模集群调优指南
│  ├─ 检查 OS 兼容性 → 已验证的节点操作系统
│  └─ 连接 apiserver 报错 → 对应故障排查文章
└─ 了解设计原理
   ├─ Host Routing 是什么 → Host Routing 附录
   ├─ 为什么配 local-router-ipv4 → 对应附录
   └─ 为什么 GR 不行 → GR Native 不推荐原因
```

## 网络模式

Cilium 路由支持两种模式：

1. **Encapsulation（封装模式）**：在原有网络上再做一层网络封包（如 vxlan）转发。兼容性好、可适配各种网络环境，缺点是性能略低。
2. **Native-Routing（原生路由）**：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。性能好，但依赖底层网络对 Pod IP 路由转发的支持。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，VPC 底层网络都已支持 Pod IP 的路由转发，无需再走一层 overlay，可获得最佳网络性能，所以通常使用 Native-Routing 模式。

但如果你有以下需求，可以选择 Encapsulation（vxlan overlay）模式：

- VPC IP 资源紧张，不希望 Pod IP 占用 underlay IP。
- 需要纳管 IDC 集群，替代 TKE 内置的 CiliumOverlay 网络模式。
- 希望使用最新版本的 Cilium，获得满血功能（不与 kube-proxy 共存，避免 NetworkPolicy 等功能降级）。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。

### 三种推荐部署方案

本系列教程提供以下三种经过完整 e2e 测试的部署方案：

| 方案                         | 集群网络模式 | 路由模式 | Pod IP 来源 | 核心特点                 |
| ---------------------------- | ------------ | -------- | ----------- | ------------------------ |
| **Native Routing (VPC-CNI)** | VPC-CNI      | Native   | VPC 子网 IP | Pod 被 VPC 原生识别      |
| **Overlay (VPC-CNI)**        | VPC-CNI      | VXLAN    | 独立 CIDR   | IP 与 VPC 解耦、满血功能 |
| **Overlay (GR)**             | GR           | VXLAN    | 独立 CIDR   | 仅推荐已有 GR 集群使用   |

> GR + Native Routing 因兼容性问题不再提供，详见 [为什么不提供 GR Native Routing 部署方案？](./appendix/gr-native-not-recommended.md)。

## 前提条件

如果要在 TKE 集群中安装 Cilium，需满足以下前提条件：

- 集群版本：TKE 1.32 及以上，参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)。
- 节点类型：普通节点或原生节点。
- 操作系统：TencentOS 4 或 Ubuntu >= 22.04（完整已验证列表见 [已验证的节点操作系统](./appendix/verified-os.md)）。

## 配套工具

本系列配套了一个[一键安装脚本](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh) `cilium.sh`，封装了安装、测试、卸载等常见操作：

| 子命令                            | 功能                                          |
| --------------------------------- | --------------------------------------------- |
| `cilium.sh install`               | 自动检测集群环境，交互式引导安装              |
| `cilium.sh uninstall`             | 卸载 Cilium，恢复 TKE 组件                    |
| `cilium.sh test`                  | 跑通 130+ 功能测试用例（含国内地域适配）      |
| `cilium.sh perf`                  | 执行网络性能基准测试（TCP_RR / TCP_STREAM）   |
| `cilium.sh enable-hubble`         | 一键启用 Hubble Relay + UI                    |
| `cilium.sh enable-egress-gateway` | 一键启用 Egress Gateway                       |
| `cilium.sh install-localdns`      | 一键安装 NodeLocal DNSCache（与 Cilium 共存） |

## 关键能力

在 TKE 中安装 Cilium 后，可以替代或增强以下 TKE 原生网络组件：

| 能力              | TKE 原生      | Cilium 替代/增强                      |
| ----------------- | ------------- | ------------------------------------- |
| **kube-proxy**    | 默认安装      | kubeProxyReplacement（完全替代）      |
| **NetworkPolicy** | 不支持 L7/DNS | CiliumNetworkPolicy（支持 L7 / FQDN） |
| **可观测性**      | 无            | Hubble（服务拓扑 + 网络流日志）       |
| **Egress 控制**   | 需额外配置    | Egress Gateway（按策略选择出口 IP）   |
| **加密**          | 无            | WireGuard / IPsec 透明加密            |
| **IP 伪装**       | ip-masq-agent | 内置 BPF 版 ip-masq-agent（性能更好） |
| **多集群网络**    | 无            | Cluster Mesh（跨集群 Service 互访）   |
