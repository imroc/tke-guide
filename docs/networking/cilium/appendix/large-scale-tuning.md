# 大规模集群 Cilium 调优指南

## 适用场景

当 TKE 集群规模达到以下任一量级时，cilium 的默认配置可能出现 apiserver 压力大、cilium-agent OOM、策略计算慢、BPF map 容量不足等问题，建议参考本文进行调优：

| 维度             | 触发阈值（参考） |
| ---------------- | ---------------- |
| 节点数           | ≥ 200            |
| Pod 数           | ≥ 10,000         |
| Service 数       | ≥ 1,000          |
| Identity 数      | ≥ 1,000          |
| NetworkPolicy 数 | ≥ 500            |

阈值仅供参考，实际是否需要调优应结合 cilium-agent / cilium-operator / apiserver 的资源使用情况和延迟指标综合判断。

## 调优清单

下表汇总了所有调优项，按"建议优先级 + 是否需评估"分类，便于快速决策：

| 优先级      | 调优项                                                      | 风险/代价                      | 何时启用                                   |
| ----------- | ----------------------------------------------------------- | ------------------------------ | ------------------------------------------ |
| ⭐ 强烈推荐 | [1. 启用 CiliumEndpointSlice](#1-启用-ciliumendpointslice)  | 1.19 仍为 Beta，需关注 GA 状态 | 节点数 ≥ 200 即可启用                      |
| ⭐ 强烈推荐 | [2. 启用 APF 限速](#2-启用-apf-限速)                        | 几乎无                         | 任何规模都应启用（安装脚本默认已配）       |
| 推荐        | [3. 调整 K8s Client QPS/Burst](#3-调整-k8s-client-qpsburst) | 配置过高反而压垮 apiserver     | 观察到 cilium-agent 同步延迟高时启用       |
| 推荐        | [4. 精简 Security Identity](#4-精简-security-identity)      | label 排除策略需结合业务设计   | Identity 数 ≥ 1000 或观察到 Identity 膨胀  |
| 推荐        | [5. 调大 Agent/Operator 资源](#5-调大-agentoperator-资源)   | 占用更多节点资源               | 默认 limit 不够用、出现 OOM 或 throttle 时 |
| 按需        | [6. 调整 BPF Map 大小](#6-调整-bpf-map-大小)                | map 过大占用更多内核内存       | BPF map 写入失败或满载告警时               |

## 1. 启用 CiliumEndpointSlice

**作用**：将多个 CiliumEndpoint 聚合为一个 CiliumEndpointSlice 资源，显著减少 apiserver 的 watch/list 压力。

**背景**：默认情况下每个 Pod 对应一个 CiliumEndpoint 对象，万级 Pod 集群意味着万级对象需要被 cilium-agent watch、apiserver 维护。CiliumEndpointSlice 借鉴 EndpointSlice 的思路把多个 CEP 聚合成一个 slice 对象，对象总量降到原来的 1/100 左右。

**配置**：

```yaml
ciliumEndpointSlice:
  enabled: true
```

:::warning[Beta 特性]

该特性于 cilium 1.11 引入，1.19 仍为 **Beta**，建议在测试集群充分验证后再上生产。Stable 进展跟踪：[cilium/cilium#31904](https://github.com/cilium/cilium/issues/31904)。

启用后无法平滑回滚（CEPSlice 与 CEP 不会双写），需评估回滚预案。

:::

## 2. 启用 APF 限速

**作用**：通过 Kubernetes [API Priority and Fairness](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) 给 cilium 配置专属的 FlowSchema 与 PriorityLevelConfiguration，防止 cilium-agent 的大量 list 请求挤占其他控制面组件的 apiserver 配额。

**配置**：[安装 Cilium](../install.md) 中给的一键安装脚本已默认创建 cilium 专属的 APF 配置（见 install.md「配置 APF 限速」章节）。如果是手动 helm 安装，建议参照脚本中的 yaml 单独 apply。

**收益**：

- cilium-agent 重启或 cilium 升级时不会拖慢 kube-controller-manager、kube-scheduler 等核心组件
- 避免 apiserver 出现 "Too many requests" / 429 错误导致 cilium 同步停滞

## 3. 调整 K8s Client QPS/Burst

**作用**：cilium-agent / cilium-operator 内部使用 client-go 与 apiserver 通信，默认 QPS/Burst 偏低，大规模下可能成为同步瓶颈。

**默认值**：

| 组件            | QPS | Burst |
| --------------- | --- | ----- |
| cilium-agent    | 10  | 20    |
| cilium-operator | 100 | 200   |

**调优配置**（按集群规模酌情调整）：

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

:::tip[判断是否需要调整]

执行下面命令查看 cilium-agent 的 client 限速指标（如果存在大量 throttling 说明被限速了）：

```bash
kubectl -n kube-system exec ds/cilium -- cilium metrics list | grep client_rate_limiter
```

如果 throttle 计数持续增长，说明需要提高 QPS/Burst。

:::

## 4. 精简 Security Identity

**作用**：cilium 为每组唯一的 label 组合分配一个 Security Identity，过多 Identity 会增加 cilium-agent 内存占用与策略计算开销，并增加 apiserver 上 CiliumIdentity 资源的存储压力。

**Identity 膨胀的典型来源**：

| 高基数 label                         | 来源                       |
| ------------------------------------ | -------------------------- |
| `pod-template-hash`                  | Deployment 每次更新都会变  |
| `controller-revision-hash`           | StatefulSet/DaemonSet 滚动 |
| `job-name`                           | Job 实例名                 |
| `batch.kubernetes.io/controller-uid` | Job controller UID         |

**配置**：通过 `extraConfig.labels` 排除这些 label，避免它们参与 Identity 计算：

```yaml
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

`!` 表示排除（取反），仅排除指定 label，其余 label 仍参与 Identity 计算。

**验证效果**：

```bash
# 查看当前 Identity 总数
kubectl get ciliumidentities | wc -l
```

调整后观察一段时间，Identity 总数应明显下降。

## 5. 调大 Agent/Operator 资源

**作用**：cilium-agent 与 cilium-operator 默认资源 request/limit 偏保守，大规模集群下可能出现 OOM 或 CPU throttle，导致策略同步延迟、Pod 网络配置不及时。

**推荐配置**（具体值需结合实际观测调整）：

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
operator:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

:::tip[如何确定合适的 limit]

观察 cilium-agent 和 cilium-operator 实际资源占用：

```bash
kubectl -n kube-system top pod -l app.kubernetes.io/part-of=cilium
```

让 limit ≥ 实际峰值的 2 倍即可（避免业务突增时被 OOMKill）。

:::

## 6. 调整 BPF Map 大小

**作用**：cilium 的 service、endpoint、policy 等数据存放在 BPF map 中。默认 map 容量基于节点内存自动计算（`mapDynamicSizeRatio=0.0025`，即按总内存的 0.25% 估算），单 Pod / 单 Service 占满后会写入失败。

**何时调整**：

- cilium-agent 日志出现 `Unable to update element for cilium_lb4_services_v2` 或类似 BPF map 满载错误
- Hubble 告警 BPF map 使用率接近 100%

**调优配置**：

```yaml
bpf:
  mapDynamicSizeRatio: 0.005  # 按节点内存的 0.5% 计算（默认 0.0025）
```

或者直接指定具体 map 大小（不建议，除非有特殊需求）：

```yaml
bpf:
  lbMapMax: 131072      # LoadBalancer service map（默认 65536）
  policyMapMax: 32768   # NetworkPolicy map（默认 16384）
```

:::warning[内存开销]

调大 BPF map 会增加内核内存占用（不计入容器 memory limit，直接占节点内存）。建议先观察后调整，避免节点内存被吃光。

:::

## 上线后观测

完成调优后，建议观测以下指标确认效果：

| 指标                                           | 健康基线                        |
| ---------------------------------------------- | ------------------------------- |
| cilium-agent CPU/内存使用率                    | 远低于 limit（建议留 50% 余量） |
| `cilium_endpoint_regeneration_time_seconds`    | p99 < 5s                        |
| `cilium_policy_l7_total` / 策略计算耗时        | 无明显积压                      |
| apiserver `apiserver_request_duration_seconds` | cilium 相关请求不影响其他组件   |
| CiliumIdentity 总数                            | 调优后下降趋势明显              |

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 官方 Scaling Performance Tuning Guide](https://docs.cilium.io/en/stable/operations/performance/scalability/)
- [Cilium API Priority and Fairness 说明](https://docs.cilium.io/en/stable/operations/scalability/apf/)
- [CiliumEndpointSlice Stable 进展](https://github.com/cilium/cilium/issues/31904)
