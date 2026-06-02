# 为什么 Native Routing 模式禁用 sysctlfix，Overlay 模式却启用？

## 背景

cilium 默认会启用一个名为 `sysctlfix` 的功能：通过一个 init container 在节点上写入：

```text
/etc/sysctl.d/99-zzz-override_cilium.conf
```

把 lxc 接口（cilium 为 Pod 创建的 veth）的 `rp_filter` 设置为 0，并 **重启 `systemd-sysctl.service`** 让配置生效。

`rp_filter`（Reverse Path Filtering，反向路径过滤）是 Linux 内核安全机制：当一个数据包从某个网卡进入时，内核会反向查路由表，确认"如果要回这个源 IP，是否会从同一个网卡出去"。如果不一致，包就会被丢弃，防止 IP 欺骗。

cilium 调整 lxc 接口 `rp_filter` 是为了让 host → 本节点 Pod 的回包能正常通过。但在 TKE 不同的安装模式下，启用 sysctlfix 的影响完全不同。

## 两种模式下的行为对比

### Native Routing (VPC-CNI)：必须禁用

- **数据路径**：cilium 与 VPC-CNI 共存，Pod IP 来自 VPC，**回程包从 eth0 进入**。
- **风险**：sysctlfix 会重启 `systemd-sysctl.service`，重启时会重新应用 OS 默认配置。TKE 的 OS 镜像中 `eth0` 的 `rp_filter` 默认是 `1`（strict 模式），严格校验下 Pod IP 在 eth0 上不匹配会被丢弃，导致网络不通。
- **结论**：**必须禁用** sysctlfix：

  ```bash
  --set sysctlfix.enabled=false
  ```

### Overlay：必须启用（默认即启用）

- **数据路径**：Pod IP 来自 cilium 自己的 CIDR，跨节点流量走 vxlan tunnel，eth0 上看不到 Pod IP，eth0 的 `rp_filter=1` 不会引发问题。
- **风险点**：host → 本节点 Pod 的回包会经过 lxc 接口，需要 `lxc*.rp_filter=0` 否则被丢弃。
- **结论**：Overlay 模式**必须启用** sysctlfix（默认即启用，无需显式设置）。

## 决策总结

| 模式                     | sysctlfix 状态 | 关键原因                             |
| ------------------------ | -------------- | ------------------------------------ |
| Native Routing (VPC-CNI) | ❌ 必须禁用    | 重启 systemd-sysctl 会重置 eth0 配置 |
| Overlay (VPC-CNI / GR)   | ✅ 必须启用    | host → Pod 回包需要 lxc rp_filter=0  |

GR 集群仅支持 Overlay 模式，详见 [为什么不提供 GR Native Routing 部署方案？](./gr-native-not-recommended.md)。

## 故障排查

如果 Overlay 模式下 `cilium-health status` 显示 localhost endpoint 0/1（host → Pod 不通），多半是 sysctlfix 没生效：

```bash
# 检查所有 lxc 接口（包括 cilium 健康检测网卡 lxc_health 和 Pod 对应的 lxcXXXX）的 rp_filter 是否全为 0
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# 如果存在不为 0 的项，检查 cilium sysctlfix init container 是否正常运行
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

排查思路：

1. 如果 `lxc*.rp_filter` 全部为 0，但仍然不通 → 问题不在 sysctlfix，需要从其它路径继续排查。
2. 如果存在不为 0 的项 → sysctlfix init container 可能没运行成功，查 init container 日志。
3. 如果 init container 日志正常，但 sysctl 值仍未生效 → 可能是 systemd-sysctl.service 被其它进程或脚本覆盖，需要手动 `sysctl -w` 测试。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/daemon/cmd/sysctlfix.go)
- [Linux 内核 rp_filter 说明](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
