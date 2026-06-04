# Cilium 性能测试

本文介绍如何对在 TKE 集群上安装的 cilium 做网络性能测试，并给出各推荐安装方案的实测结果。

cilium 官方提供了 [`cilium connectivity perf`](https://docs.cilium.io/en/stable/operations/performance/benchmark/) 性能测试工具，基于 netperf 在集群中实际下发 Pod 跑 TCP_RR（请求-响应延迟）/ TCP_STREAM（吞吐）等测试，覆盖 **同节点 / 跨节点** × **Pod 网络 / Host 网络** 共四种网络组合。

## 测试方法

### 一键脚本

[一键安装脚本](../install.md#一键安装脚本) `cilium.sh` 提供了 `perf` 子命令，会用 TKE 内网可拉取的镜像跑 `cilium connectivity perf`：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- perf
```

性能测试默认跑约 1 分钟，每个测试持续 10 秒（可通过 `--duration` 调整），最后输出汇总表格。

### 手动测试

需先安装 [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)：

```bash
cilium connectivity perf \
  --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90
```

`cilium connectivity perf` 默认行为：

- `--duration 10s`：每个 RR/STREAM 测试持续 10 秒
- `--samples 1`：每个测试跑 1 次（可调大跑多次取平均）
- `--rr / --throughput / --throughput-multi`：默认开启 TCP_RR、TCP_STREAM、TCP_STREAM_MULTI 测试
- `--pod-net / --host-net / --other-node / --same-node`：默认全开（覆盖 Pod 网络 + Host 网络 + 同/跨节点 4 种组合）
- 可加 `--udp` 测 UDP，`--crr` 测 TCP_CRR（每次连接都重建），`--bandwidth` 测带宽限速能力

更多参数详见 `cilium connectivity perf --help`。

## 测试环境

| 项              | 值                                                             |
| --------------- | -------------------------------------------------------------- |
| 地域            | 成都 ap-chengdu                                                |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                   |
| Cilium 版本     | v1.19.4                                                        |
| Cilium CLI 版本 | v0.19.4                                                        |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)          |
| 节点机型        | S5.MEDIUM4（2C4G）                                             |
| 节点数量        | 每个集群 3 个节点，全部位于 ap-chengdu-1                       |
| 节点公网        | 节点绑 EIP（性能测试不依赖公网）                               |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install` |

:::tip[结果解读]

性能数据**强依赖节点机型 / VPC 带宽 / 内核版本 / 同时运行的其它负载**。本文给出的是空载新建集群的实测值，仅作为不同 cilium 安装方案之间的横向对比参考，不能作为生产环境性能基线。

S5.MEDIUM4 是入门机型（2C4G），跨节点带宽受限较明显（典型 1-2 Gbps）。生产建议根据实际业务流量选择带宽更大的机型。

:::

## 测试结果

### Native Routing (VPC-CNI) ⭐

```text
🔥 Network Performance Test Summary [cilium-test-1]:
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
📋 Scenario        | Node       | Test            | Duration        | Min             | Mean            | Max             | P50             | P90             | P99             | Transaction rate OP/s
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
📋 pod-to-pod      | same-node  | TCP_RR          | 10s             | 19µs            | 44.35µs         | 2.118ms         | 47µs            | 51µs            | 64µs            | 22434.15
📋 host-to-host    | same-node  | TCP_RR          | 10s             | 16µs            | 38.38µs         | 2.587ms         | 41µs            | 44µs            | 57µs            | 25914.18
📋 pod-to-pod      | other-node | TCP_RR          | 10s             | 106µs           | 146.96µs        | 2.28ms          | 145µs           | 159µs           | 183µs           | 6793.74
📋 host-to-host    | other-node | TCP_RR          | 10s             | 96µs            | 134.16µs        | 2.384ms         | 133µs           | 148µs           | 167µs           | 7443.15
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
📋 Scenario        | Node       | Test               | Duration        | Throughput Mb/s
----------------------------------------------------------------------------------------
📋 pod-to-pod      | same-node  | TCP_STREAM         | 10s             | 20936.00
📋 pod-to-pod      | same-node  | TCP_STREAM_MULTI   | 10s             | 19689.36
📋 host-to-host    | same-node  | TCP_STREAM         | 10s             | 22662.57
📋 host-to-host    | same-node  | TCP_STREAM_MULTI   | 10s             | 20695.98
📋 pod-to-pod      | other-node | TCP_STREAM         | 10s             | 1660.79
📋 pod-to-pod      | other-node | TCP_STREAM_MULTI   | 10s             | 1634.60
📋 host-to-host    | other-node | TCP_STREAM         | 10s             | 1589.32
📋 host-to-host    | other-node | TCP_STREAM_MULTI   | 10s             | 1673.35
----------------------------------------------------------------------------------------

✅ All 1 tests (12 actions) successful, 0 tests skipped, 0 scenarios skipped.
```

观察要点：

- **同节点 pod-to-pod ≈ 同节点 host-to-host**（吞吐 ~21 Gbps，TCP_RR 延迟 44µs vs 38µs）——cilium ebpf 直连 veth 几乎没有 Pod 抽象层开销
- **跨节点 pod-to-pod ≈ 跨节点 host-to-host**（吞吐 ~1.66 Gbps，TCP_RR 延迟 147µs vs 134µs）——Native Routing 走 VPC underlay，Pod 与 Host 走同样路径
- **跨节点带宽 ~1.66 Gbps** 是 S5.MEDIUM4 机型本身的网卡限速，不是 cilium 瓶颈

#### 全量测试维度明细

`cilium connectivity perf` 默认在 4 种网络组合 × 多种测试模式下采样。本次实测的完整数据：

##### 测试模式说明

| Test 类型          | 含义                                            | 测什么                                      |
| ------------------ | ----------------------------------------------- | ------------------------------------------- |
| `TCP_RR`           | TCP Request-Response，反复发小请求等响应        | **延迟**（µs，越低越好）；OP/s 是每秒事务数 |
| `TCP_STREAM`       | TCP 单流持续发送                                | **单流吞吐**（Mb/s，越高越好）              |
| `TCP_STREAM_MULTI` | TCP 多流并发发送（默认 4 流，`--streams` 调整） | **多流并发吞吐**（Mb/s）                    |

##### 网络组合说明

| Scenario       | Node       | 含义                                                 | 数据路径                                                                             |
| -------------- | ---------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `pod-to-pod`   | same-node  | client Pod → 同节点 server Pod                       | client veth → cilium ebpf → server veth                                              |
| `pod-to-pod`   | other-node | client Pod → 跨节点 server Pod                       | client veth → cilium ebpf → 网卡出 → underlay → 对端网卡 → cilium ebpf → server veth |
| `host-to-host` | same-node  | client（hostNetwork） → 同节点 server（hostNetwork） | host stack → host stack（不经过 cilium veth 路径）                                   |
| `host-to-host` | other-node | client（hostNetwork） → 跨节点 server（hostNetwork） | host stack → 网卡 → underlay → 对端网卡 → host stack                                 |

##### TCP_RR（请求-响应延迟）

测试 duration 10s，下表单位 µs：

| #   | Scenario       | Node       | Min | Mean   | Max  | P50 | P90 | P99 | Transactions/s |
| --- | -------------- | ---------- | --- | ------ | ---- | --- | --- | --- | -------------- |
| 1   | `pod-to-pod`   | same-node  | 19  | 44.35  | 2118 | 47  | 51  | 64  | **22434**      |
| 2   | `host-to-host` | same-node  | 16  | 38.38  | 2587 | 41  | 44  | 57  | **25914**      |
| 3   | `pod-to-pod`   | other-node | 106 | 146.96 | 2280 | 145 | 159 | 183 | **6794**       |
| 4   | `host-to-host` | other-node | 96  | 134.16 | 2384 | 133 | 148 | 167 | **7443**       |

##### TCP_STREAM / TCP_STREAM_MULTI（吞吐）

测试 duration 10s，单位 Mb/s：

| #   | Scenario       | Node       | TCP_STREAM (单流) | TCP_STREAM_MULTI (4 流并发) |
| --- | -------------- | ---------- | ----------------- | --------------------------- |
| 5   | `pod-to-pod`   | same-node  | **20936.00**      | **19689.36**                |
| 6   | `host-to-host` | same-node  | **22662.57**      | **20695.98**                |
| 7   | `pod-to-pod`   | other-node | **1660.79**       | **1634.60**                 |
| 8   | `host-to-host` | other-node | **1589.32**       | **1673.35**                 |

##### 解读

- **同节点 vs 跨节点**：吞吐差 ~13 倍（21 Gbps vs 1.66 Gbps），延迟差 ~3 倍（44µs vs 147µs）——跨节点流量经过物理网卡 + VPC underlay，是 S5.MEDIUM4 机型本身网卡带宽（约 1.5 Gbps）的限速结果，不是 cilium 开销
- **Pod 网络 vs Host 网络**：差距很小（同节点 21 vs 22.6 Gbps，~7%），跨节点几乎无差距——Native Routing 模式下 Pod IP 就是 VPC IP，cilium ebpf 不做 SNAT/封装，Pod 流量直接走 host 同样的路径
- **单流 vs 多流**：本测试场景下单流已能跑满网卡带宽，4 流并发反而因竞争略降——这与机型规格（小机型，1-2 个 ENI 队列）有关，大机型多流加速会更明显
- **P99 vs Mean 延迟差距大**（同节点 64µs vs 44µs，跨节点 183µs vs 147µs）——长尾来自调度延迟和 NAPI 软中断，正常现象

### Overlay (VPC-CNI) ⭐

> 待补充：在 Overlay (VPC-CNI) 集群上跑 `cilium.sh perf`，把输出结果填充到此处。
>
> 预期相比 Native：跨节点 pod-to-pod 因 vxlan 封装会有少量开销（吞吐略降、延迟略增）。

### Overlay (GR)

> 待补充：在 Overlay (GR) 集群上跑 `cilium.sh perf`，把输出结果填充到此处。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 功能测试](./connectivity-test.md)
- [Cilium Performance Documentation](https://docs.cilium.io/en/stable/operations/performance/)
