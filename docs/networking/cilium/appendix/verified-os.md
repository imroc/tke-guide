# 已验证的节点操作系统

## 适用范围

本文列出 [安装 Cilium](../install.md) 涉及的 **4 种安装模式**（VPC-CNI/GR × Native Routing/Overlay）均已实测通过的节点 OS 镜像及内核版本，作为节点池 OS 选型的参考。

如果你正在新建节点池，可优先从下表中挑选；如果业务必须使用未在本表中的 OS，建议先在测试集群单节点验证后再上量。

## 实测通过的 OS 列表

下表中所有 OS 均已在 4 种安装模式下完整跑通 e2e 验证（cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache）。

| OS                   | OsName                  | 内核版本 |
| -------------------- | ----------------------- | -------- |
| TencentOS Server 4   | `tlinux4_x86_64_public` | 6.6.117  |
| Ubuntu 24.04         | `ubuntu24.04x86_64`     | 6.8.0    |
| Ubuntu 22.04         | `ubuntu22.04x86_64`     | 5.15.0   |
| Debian 12 (bookworm) | `debian12.8x86_64`      | 6.1.0    |
| Debian 11 (bullseye) | `debian11.11x86_64`     | 5.10.0   |
| OpenCloudOS 9.4      | `opencloudos9.0x86_64`  | 6.6.119  |
| Rocky Linux 9.3      | `rockylinux9.3x86_64`   | 5.14.0   |
| RedHat 9.5           | `redhat9.5x86_64`       | 5.14.0   |

**首选推荐**：**TencentOS Server 4** 或 **Ubuntu 24.04**，内核版本高、与 cilium 最新版兼容性最好。

`OsName` 列对应 [tencentcloud_kubernetes_node_pool](https://registry.terraform.io/providers/tencentcloudstack/tencentcloud/latest/docs/resources/kubernetes_node_pool) 资源中 `node_os` 字段的取值，也是控制台「操作系统」下拉框对应的镜像标识。

## 验证方法

本文 OS 列表的产生过程：

1. 用 [terraform-manifests](https://github.com/imroc/terraform-manifests) 中的模块为每种网络模式（VPC-CNI / GR）创建独立测试集群，每个集群按 OS 清单创建多个节点池（一个 OS 一个节点池，每个节点池 1 个节点）。
2. 用 [安装脚本](../install.md#一键安装脚本) 在集群上安装 cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache。
3. 执行脚本的 e2e 测试子命令：
   ```bash
   ./cilium.sh e2e-test
   ```
4. 验证以下指标全部通过：
   - `cilium-health status` 所有节点 reachable（覆盖 host↔Pod、Pod↔Pod 跨节点连通性）
   - `coredns` Pod 健康检查正常
   - `node-local-dns` Pod 健康检查正常
   - `cilium connectivity test` 默认用例（跳过公网用例）全部 pass

## 自行验证未列出的 OS

如果你需要使用本表外的 OS（如自定义镜像、其他 CVM 公共镜像），按以下步骤单节点验证：

1. **内核版本预检查**：确认 OS 内核 ≥ 5.10（参考 cilium [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)）。
2. **创建测试集群**：使用目标 OS 创建只有 1-2 个节点的测试集群，安装 cilium。
3. **运行 e2e 测试**：执行 `./cilium.sh e2e-test`，关注：
   - `cilium-health status` 是否所有节点 reachable
   - DNS 解析（含集群内 svc 名和外部域名）是否正常
   - `cilium connectivity test` 是否全部通过
4. **跑业务功能验证**：如使用 NetworkPolicy、Egress Gateway、Cluster Mesh 等额外特性，对应跑一遍业务的关键路径。

通过以上验证后即可在生产节点池放心使用。

## 常见 OS 选择陷阱

- **TencentOS 3.x / 早期 Ubuntu 20.04 等老 OS**：内核版本可能 < 5.10，cilium 安装报错或部分特性（如 BPF Host Routing）不可用。
- **DataPlaneV2 自带的 OS**：TKE 创建 VPC-CNI 集群勾选 DataPlaneV2 时使用的 OS 与最新 cilium 不兼容（详见 [安装 Cilium - 常见问题: VPC-CNI 集群创建时能否勾选 DataPlaneV2？](../install.md#vpc-cni-集群创建时能否勾选-dataplanev2)）。
- **自定义裁剪过的 OS 镜像**：如果裁剪了 BPF 相关内核模块（如 `bpf`、`bpf_jit`），cilium 启动失败。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
