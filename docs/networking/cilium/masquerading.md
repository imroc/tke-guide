# 配置 IP 伪装

## IP 伪装简介

简单来说，IP 伪装就是将 Pod 出集群的流量的源 IP 伪装成节点 IP（SNAT），通常用在 Pod IP 无法直接在集群外路由但又希望流量能够外访的场景。

## VPC-CNI 大部分场景不需要 IP 伪装

TKE VPC-CNI 网络模式，Pod IP 使用的 VPC IP，与节点 IP 一样，可直接在 VPC 内路由，与其他 VPC 或其它云（如 AWS）通过云联网打通后，Pod IP 也可以直接路由。另外，它还支持 NAT 网关，Pod 通过 NAT 网关访问公网也是可以的。

所以，大部分场景，我们不需要开启 IP 伪装，[安装 Cilium](./install.md) 中给出的默认安装方式也是禁用了 Cilium 的 IP 伪装功能（`--set enableIPv4Masquerade=false`）。

## 什么场景需要 IP 伪装？

如果有以下需求场景，可启用 Cilium 的 IP 伪装功能：
1. 希望 Pod 利用节点的公网带宽访问公网。
2. Pod 需要调用某些基于节点 IP 鉴权的腾讯云接口，如 [CVM metadata 接口](https://cloud.tencent.com/document/product/213/4934)。
3. 跨 VPC 或跨云互通时，网段有重叠，但 Node IP 可以互通。

## Cilium 的 IP 伪装功能介绍

Cilium 默认启用了 IP 伪装功能，关闭需显式配置 `--set enableIPv4Masquerade=false`。

默认行为是只要目的 IP 不在本机，就会 SNAT 成节点 IP，通常 Pod IP 在集群内可路由，如果所有 Pod IP 都在一个固定的网段内，可通过设置 `ipv4NativeRoutingCIDR` 实现只针对该网段之外的 IP 通信进行伪装。

## eBPF vs iptables
Cilium 支持 ebpf 和 iptables 两种 IP 伪装的实现，在 TKE 环境需使用 ebpf 实现的版本。

ebpf 的实现也有两种使用方式：
1. 通过 `ipv4NativeRoutingCIDR` 配置针对单个 CIDR 不做 SNAT。
2. 启用 eBPF 版的 ipMasqAgent 实现，可配置针对多个 CIDR 不做 SNAT。

腾讯云 VPC 支持添加辅助 CIDR 来扩展 VPC 的 CIDR，相同集群中的 Pod IP 也就可能属于不同的大内网网段（比如 Pod A 的 IP 是 172.x.x.x，而 Pod B 的 IP 是 10.x.x.x），而且将来如果与其它云上的 Kubernetes 集群互通（如 AWS EKS 集群），两边集群所使用的 Pod IP 也可能属于不同的大内网网段。

所以，如果需要启用 IP 伪装，推荐使用 Cilium 内置的 eBPF 版的 ipMasqAgent。

## 如何启用 IP 伪装？

可通过以下命令启用：

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.0 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set ipMasqAgent.config.masqLinkLocal=true
  # highlight-add-end
```

:::info[注意]

如果是调整已安装的 cilium 配置，存量节点需重启 cilium-agent 才能生效：

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

:::

:::tip[参数说明]

以下是是包含相关参数解释的 `values.yaml`:

```yaml title="values.yaml"
# 启用 cilium 的 IP MASQUERADE 功能
enableIPv4Masquerade: true
bpf:
  # cilium 的 IP MASQUERADE 功能有 bpf 和 iptables 两个版本，在 TKE 环境需使用 bpf 版本。参考 https://docs.cilium.io/en/stable/network/concepts/masquerading/
  masquerade: true
ipMasqAgent:
  # 使用 cilium 基于 ebpf 实现的 ipMasqAgent 来控制 IP MASQUERADE，这样可以支持配置多个 CIDR 网段不做 SNAT。
  # 说明：ipv4NativeRoutingCIDR 方式仅支持单个 CIDR，而腾讯云 VPC 支持添加辅助 CIDR 来扩展 VPC 的 CIDR，所以
  # 相同集群中的 Pod IP 可能属于不同的大内网网段（比如 Pod A 的 IP 是 172.x.x.x，而 Pod B 的 IP 是 10.x.x.x）。
  enabled: true
  config:
    # masqLinkLocal 用于控制 link local 网段（169.254.0.0/16）是否做 SNAT，该网段在腾讯云上用于公共服务使用，
    # 比如 cvm 的 metadata 服务（查询当前 cvm 的元信息），或者其它一些需要使用节点 IP 鉴权的接口，在  Pod 中
    # 调用这些接口都需要确保 SNAT 节点 IP，所以将 masqLinkLocal 置为 true，确保发送给 169.254.0.0/16 网段的流
    # 量都 SNAT 成节点 IP，避免这类接口调用失败。
    masqLinkLocal: true
```

:::

## 配置 nonMasqueradeCIDRs

前面的 IP 伪装启用方法会针对所有内网网段（169.255.0.0/16 除外）不做 SNAT，如需更精细化的控制，可显式配置具体哪些 CIDR 不做 SNAT，具体方法如下。

1. 准备 ip-masq-agent ConfigMap 到文件 `ip-masq-agent-config.yaml`：

:::tip[说明]

将不需要 SNAT 的 CIDR 都 nonMasqueradeCIDRs 中，通常是 TKE 集群中的 Pod 使用到的 VPC CIDR（包括 VPC 辅助 CIDR）。

:::

```yaml title="ip-masq-agent-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
    - 10.0.0.0/16
    - 172.18.0.0/16
    - 192.168.0.0/17
    masqLinkLocal: true
```

2. 创建 ConfigMap：

```bash
kubectl apply -f ip-masq-agent-config.yaml
```

3. 更新 cilium 配置：

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.0 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true
  # highlight-add-end
```

4. 重启 cilium-agent:

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

## 参考资料

- [Masquerading](https://docs.cilium.io/en/stable/network/concepts/masquerading/)
