# Cilium 网络性能 Benchmark

本文使用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本对 Cilium Native Routing 与 Overlay 模式进行全方位网络性能对比，覆盖吞吐量、HTTP RPS、TCP 延迟、Service 规模等维度。

:::tip[与 cilium connectivity perf 的区别]

[Cilium 性能测试](./performance-test.md) 使用 `cilium connectivity perf`（基于 netperf）测试 TCP_RR 延迟和 TCP_STREAM 吞吐。本文的 `network-benchmark.sh` 脚本额外覆盖：

- **HTTP 层面**：fortio 全速压测 RPS（长连接 / 短连接）
- **Service 路径**：经 ClusterIP Service 的吞吐和 RPS
- **Service 规模影响**：1000 Services 后 eBPF lookup 性能退化
- **Cilium Agent 资源占用**：测试期间 CPU / Memory 采样

两篇文档互补，建议结合阅读。

:::

## 测试方法

### 一键运行

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/network-benchmark.sh)"
```

:::note[前置条件]

- `KUBECONFIG` 指向目标集群（当前 context 可用）
- 本机需安装 `kubectl`、`python3`、`timeout`（macOS 需 `brew install coreutils`）
- 集群至少 2 个 worker 节点

:::

### 自定义参数

```bash
# 多轮测试（大规格实例无 QoS 顾虑时）
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# 指定输出目录和 namespace
bash network-benchmark.sh --dir ./my-results --ns my-bench
```

| 环境变量          | 默认值 | 说明                                   |
| ----------------- | ------ | -------------------------------------- |
| `IPERF_DURATION`  | 30     | iperf3 每轮测试时长（秒）              |
| `FORTIO_DURATION` | 60     | fortio / netperf 每轮测试时长（秒）    |
| `ROUNDS`          | 1      | 每个场景重复轮次                       |
| `ROUND_SLEEP`     | 30     | 轮间等待（秒），用于 burst credit 恢复 |

### 测试指标说明

| 工具    | 测试内容                    | 指标             |
| ------- | --------------------------- | ---------------- |
| iperf3  | 跨节点 TCP 吞吐             | Gbps（8 并发流） |
| fortio  | HTTP RPS（长连接 / 短连接） | req/s、p99 延迟  |
| netperf | TCP_RR / TCP_CRR 延迟       | p50 / p99 微秒   |
| fortio  | 1000 Services 后 RPS 退化   | 退化百分比       |

## 测试环境

| 项              | 值                                                    |
| --------------- | ----------------------------------------------------- |
| Kubernetes 版本 | v1.34.1                                               |
| Cilium 版本     | v1.19.4                                               |
| 节点 OS         | TencentOS Server 4                                    |
| 内核版本        | 6.6.117-45.7.3.tl4.x86_64                             |
| 节点规格        | SA5.LARGE8（4C 8G，基准 1.5 Gbps / 突发 10 Gbps）     |
| 节点数量        | 3                                                     |
| 测试脚本版本    | network-benchmark.sh                                  |
| Native 模式     | VPC-CNI + Cilium Native Routing (Legacy Host Routing) |
| Overlay 模式    | VPC-CNI + Cilium VXLAN Overlay (BPF Host Routing)     |

## 测试结果

### 吞吐量（iperf3, 30s, 8 streams, 跨节点）

| 场景                     | Native     | Overlay    | 差异  |
| ------------------------ | ---------- | ---------- | ----- |
| Node hostNet 8stream     | 10.44 Gbps | 10.82 Gbps | +3.6% |
| Pod-to-Pod single stream | 10.43 Gbps | 10.76 Gbps | +3.2% |
| Pod-to-Pod 8 streams     | 10.43 Gbps | 10.77 Gbps | +3.3% |
| Via Service 8 streams    | 10.43 Gbps | 10.76 Gbps | +3.2% |

:::note

两者都跑满 10+ Gbps 接近 SA5 突发带宽上限（10 Gbps）。±3% 差异来自不同物理节点间的网络路径波动，不是模式差异。Node hostNet 测试不经过任何 CNI 路径，两组数值接近进一步确认底层带宽一致。

:::

### RPS（fortio, 60s, max QPS, 跨节点）

| 场景                     | Native | Overlay | 差异  |
| ------------------------ | ------ | ------- | ----- |
| Pod-to-Pod c64 keepalive | 80,373 | 77,503  | -3.6% |
| Via Svc c64 keepalive    | 80,231 | 77,342  | -3.6% |
| Via Svc c256 keepalive   | 81,815 | 78,502  | -4.0% |
| Via Svc c64 短连接       | 10,721 | —       | —     |

:::note

RPS 差异约 3-4%，在统计波动范围内。小包 HTTP 请求的瓶颈在 CPU（4 核节点上限约 80K req/s keepalive），VXLAN 封装对小包场景的额外开销可忽略。短连接（每请求新建 TCP）QPS 约为长连接的 1/8，主要开销在 TCP 握手。

:::

### 延迟（netperf TCP_RR / TCP_CRR + fortio HTTP, 跨节点）

| 指标               | Native  | Overlay | 差异   |
| ------------------ | ------- | ------- | ------ |
| TCP_RR p50         | 104 µs  | 105 µs  | +1 µs  |
| TCP_RR p99         | 127 µs  | 129 µs  | +2 µs  |
| TCP_CRR p99        | 628 µs  | 596 µs  | -32 µs |
| HTTP p99 @1000 QPS | 0.99 ms | 0.99 ms | 相同   |

:::note

跨节点延迟两者几乎一致。TCP_RR p99 差异仅 2 µs，在 VPC 物理拓扑的噪声范围内。TCP_CRR（每次新建连接）的 ~30 µs 波动同样属于正常抖动。对应用层完全无感知。

:::

### Service Scale（1000 Services 后 RPS 退化）

|                               | Native       | Overlay      |
| ----------------------------- | ------------ | ------------ |
| baseline（Via Svc keepalive） | 80,231 req/s | 77,342 req/s |
| 1000 Services 后              | 80,195 req/s | 76,087 req/s |
| 退化                          | **-0.0%**    | **-1.6%**    |

Cilium 使用 eBPF hash map 做 Service → Backend 查找（O(1) 时间复杂度），1000 个 Services 不会增加每次请求的查找开销。两者退化均 < 2%，在噪声范围内。

### Cilium Agent 资源占用（测试期间）

|            | Native  | Overlay |
| ---------- | ------- | ------- |
| CPU avg    | 106m    | 181m    |
| Memory avg | 194 MiB | 192 MiB |

Overlay 模式 CPU 略高（VXLAN 隧道管理和额外封包路径），内存基本一致。

## 对比分析

### 汇总

| 维度              | 结论        | 量化差异            |
| ----------------- | ----------- | ------------------- |
| **吞吐量**        | 无差异      | 均达 10G+ 线速      |
| **RPS（长连接）** | 无显著差异  | ±4%（CPU 瓶颈）     |
| **RPS（短连接）** | 无显著差异  | ~10K req/s          |
| **延迟 p99**      | 无显著差异  | ±2 µs               |
| **Service Scale** | 均无退化    | ≤ 1.6%（eBPF O(1)） |
| **Agent CPU**     | Native 略低 | 106m vs 181m        |

### 核心结论

**在 SA5 4C8G 节点上，Cilium Native Routing 和 VXLAN Overlay 的跨节点网络性能没有统计学显著差异。** 两者都能跑满 10G 带宽，RPS 差异在 CPU 瓶颈下不可区分，延迟差异仅 2 µs。

选型时性能不是决定因素——应根据网络架构需求（Pod IP 是否需要 VPC 可路由）和运维偏好来决定。详见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)
