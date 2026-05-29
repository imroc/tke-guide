# 已验证的节点操作系统

本附录汇总本指南中各方案已实测验证过的节点操作系统及其内核版本。其它满足组件最低内核要求的 OS 通常也能正常工作，但未经实测覆盖。

## Cilium 已验证 OS

适用范围：[安装 Cilium](../networking/cilium/install.md) 中的 4 种安装模式（VPC-CNI/GR × Native/Overlay）均已验证。

**测试方法**：每种安装模式均部署 cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache，检查 `cilium-health status` 全节点 reachable、`coredns` 与 `node-local-dns` 健康检查正常。

| OS                   | 内核版本 | iptables 后端 | 备注                                        |
| -------------------- | -------- | ------------- | ------------------------------------------- |
| TencentOS Server 4   | 6.6.117  | legacy        | 推荐：TKE 原生节点/Karpenter 默认 OS        |
| Ubuntu 24.04         | 6.8.0    | nf_tables     | 推荐：内核最新，性能最优                    |
| Ubuntu 22.04         | 5.15.0   | nf_tables     |                                             |
| Debian 12 (bookworm) | 6.1.0    | nf_tables     | 默认仅 nftables，cilium 使用容器内 iptables |
| Debian 11 (bullseye) | 5.10.0   | nf_tables     | 同上                                        |
| OpenCloudOS 9.4      | 6.6.119  | legacy        | TencentOS 4 的社区开源版本                  |
| Rocky Linux 9.3      | 5.14.0   | nf_tables     |                                             |
| RedHat 9.5           | 5.14.0   | nf_tables     |                                             |

最低要求：Linux kernel >= 5.10（参考 [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)）。

不在此列表的 OS 如需使用，建议先单节点验证。
