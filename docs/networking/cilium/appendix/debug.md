# Cilium 调试速查

本页收集本系列教程中实际使用过的 cilium 排障命令，每条给出一句话用途说明与可直接复制的命令，供排障时快速定位。命令统一按 cilium 1.20（本系列教程当前验证版本）整理，子命令均在该版本源码中核对过。

:::note[cilium 1.20 中 CLI 名为 cilium-dbg]

cilium 1.16 起，原来的 `cilium` CLI 二进制更名为 `cilium-dbg`；cilium 1.20 的容器镜像内仍保留 `cilium` 软链指向 `cilium-dbg`，两者等价。本文统一使用 `cilium-dbg`，在 cilium Pod 内通过 `kubectl -n kube-system exec ds/cilium -- cilium-dbg <子命令>` 执行。

:::

## 查看功能状态

查看当前部署的 cilium 的各项功能实际状态：

<Tabs>
  <TabItem value="basic" label="简洁">

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status
```

  </TabItem>
  <TabItem value="verbose" label="详细">

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

  </TabItem>
</Tabs>

排障时最值得关注的三行字段：

| 字段                   | 含义               | 排障关注点                                                                                          |
| ---------------------- | ------------------ | --------------------------------------------------------------------------------------------------- |
| `KubeProxyReplacement` | kube-proxy 替换    | 应为 `True`；为 `False` 时 Service 转发退回 kube-proxy                                               |
| `Host Routing`         | 主机路由模式       | `BPF` 或 `Legacy`；显示 `Legacy` 说明配置层发生了 fallback（如漏设 `bpf.masquerade=true`）           |
| `Masquerading`         | IP 伪装模式        | `BPF`、`IPTables` 或 `Disabled`；与 `Host Routing` 联动变化                                         |

:::warning[status 显示 BPF 不代表数据面命中]

`cilium status` 的 `Host Routing` 字段只反映 cilium-agent 配置层状态：VPC-CNI Native 模式因启用 endpointRoutes，Pod 流量绕过 `cilium_host` 设备，status 显示 `BPF` 但数据路径上实际不命中。完整分析见 [VPC-CNI Native Routing 模式详解](./native-routing.md)。

:::

## 监控指定节点的 cilium 网络

<Tabs>
  <TabItem value="bash" label="bash">

```bash
NODE=172.22.48.23
POD=$(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium-dbg monitor
```

  </TabItem>

  <TabItem value="fish" label="fish">

```bash
set NODE 172.22.48.23
set POD $(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium-dbg monitor
```

  </TabItem>
</Tabs>

:::note[注意]

替换 `NODE` 的值为实际需要监控的节点名称。

:::

## 实时观测 Pod 间流量

cilium-agent 内置 Hubble Server，Pod 镜像内也自带 `hubble` CLI（默认连接本节点的 unix domain socket），无需部署 Hubble Relay 即可实时观测本节点流量：

```bash
# 实时观测指定 Pod 的流量（匹配源或目的 Pod，Ctrl+C 退出）
kubectl -n kube-system exec ds/cilium -- hubble observe --pod default/my-app -f

# 实时观测被丢弃的流量（NetworkPolicy 拒绝、黑洞丢包等），快速定位策略误伤
kubectl -n kube-system exec ds/cilium -- hubble observe --verdict DROPPED -f

# 观测从 Pod a 到 Pod b 的流量（--from-pod/--to-pod 精确指定方向）
kubectl -n kube-system exec ds/cilium -- hubble observe --from-pod default/a --to-pod default/b
```

:::note[回看历史流量]

不加 `-f` 时 `hubble observe` 只输出缓冲区中最近的 20 条 flow 后退出，可用 `--last N` 调整回看数量。

:::

如需在集群范围观测（Hubble Relay 聚合多节点）或使用 Hubble UI，见 [使用 Cilium 增强可观测性](../observability.md)。

## 查看 BPF map 与 agent 内部数据

### 查看负载均衡映射

kubeProxyReplacement 下 Service 的前端与后端由 cilium 写入 BPF map，排查 Service 不通、后端为空类问题时先看内核态数据：

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf lb list
```

再对照 cilium-agent 进程内存中的服务数据，判断是 agent 没收到后端（watch 异常）还是收到了但没写入 BPF map（同步异常）：

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show frontends
```

实际排障案例见 [连接 apiserver 报错 operation not permitted](./troubleshooting/connect-apiserver-operation-not-permitted.md)（Service 后端为空的定位过程）。

### 查看 Egress Gateway 规则

Egress Gateway 配置策略后网络不通时，查看节点上实际生效的 egress BPF 规则（`Source IP` 为 Pod IP，`Egress IP` 全为 `0.0.0.0` 表示没有规则选中当前节点）：

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf egress list
```

详见 [Egress Gateway 应用实践](../egress-gateway.md) 的「常见问题」章节。

### 查看 Endpoint 与 Identity

排查 Pod 没被 cilium 接管、NetworkPolicy 按身份匹配不生效类问题时，查看节点上的 endpoint 与 security identity 数据：

```bash
# 本节点 BPF map 中所有 endpoint（Pod）条目
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf endpoint list

# 安全身份与 label 的对应关系
kubectl -n kube-system exec ds/cilium -- cilium-dbg identity list

# IP（含节点 IP/EIP）与 identity 的映射
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list
```

大规模集群先通过 `kubectl get ciliumidentities | wc -l` 观察身份总量是否膨胀，再结合上述命令定位，见 [大规模集群 Cilium 调优指南](./large-scale-tuning.md)。
