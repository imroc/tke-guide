# Verified Node Operating Systems

## Scope

This document lists the node OS images and kernel versions that have been verified for all **3 installation modes** (Native Routing (VPC-CNI), Overlay (VPC-CNI), Overlay (GR)) covered in [Installing Cilium](../install.md). Use it as a reference for node pool OS selection.

If you are creating a new node pool, you can prioritize from the table below. If your workloads require an OS not listed here, we recommend testing on a single node in a test cluster before scaling up.

## Verified OS List

All OS entries in the table below have passed complete e2e verification across all 3 installation modes (cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache).

| OS                   | OsName                  | Kernel Version |
| -------------------- | ----------------------- | -------------- |
| TencentOS Server 4   | `tlinux4_x86_64_public` | 6.6.117        |
| Ubuntu 24.04         | `ubuntu24.04x86_64`     | 6.8.0          |
| Ubuntu 22.04         | `ubuntu22.04x86_64`     | 5.15.0         |
| Debian 12 (bookworm) | `debian12.8x86_64`      | 6.1.0          |
| Debian 11 (bullseye) | `debian11.11x86_64`     | 5.10.0         |
| OpenCloudOS 9.4      | `opencloudos9.0x86_64`  | 6.6.119        |
| Rocky Linux 9.3      | `rockylinux9.3x86_64`   | 5.14.0         |
| RedHat 9.5           | `redhat9.5x86_64`       | 5.14.0         |

**Top recommendations**: **TencentOS Server 4** or **Ubuntu 24.04** — newer kernel versions with the best compatibility with the latest cilium.

The `OsName` column corresponds to the `node_os` field value in the [tencentcloud_kubernetes_node_pool](https://registry.terraform.io/providers/tencentcloudstack/tencentcloud/latest/docs/resources/kubernetes_node_pool) resource, and also the image identifier shown in the "Operating System" dropdown in the console.

## Verification Method

The OS list in this document was produced as follows:

1. Prepare a test cluster for each network mode (VPC-CNI / GR), create multiple node pools from the OS list (one OS per node pool, 1 node per pool).
2. Install cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache using the [install script](../install.md#one-click-install-script).
3. From an environment connected to the cluster (with kubeconfig configured), run the script's e2e test subcommand:
   ```bash
   bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
   ```
4. Verify all the following pass:
   - `cilium-health status`: all nodes reachable (covers host↔Pod, Pod↔Pod cross-node connectivity)
   - `coredns` Pod health check normal
   - `node-local-dns` Pod health check normal
   - `cilium connectivity test`: all default test cases pass (skipping public network cases)

## Testing Unlisted OS Yourself

If you need to use an OS not in the table (e.g., custom images, other CVM public images), follow these steps for single-node verification:

1. **Kernel version pre-check**: Ensure the OS kernel is ≥ 5.10 (see cilium [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)).
2. **Create a test cluster**: Create a test cluster with 1-2 nodes using the target OS, then install cilium.
3. **Run e2e tests**: Execute `cilium.sh test` (see the one-click command above), focusing on:
   - Whether all nodes are reachable in `cilium-health status`
   - Whether DNS resolution (both in-cluster svc names and external domain names) is working
   - Whether `cilium connectivity test` passes all cases
4. **Run business feature verification**: If using additional features like NetworkPolicy, Egress Gateway, Cluster Mesh, etc., test each feature's key path.

Once all verifications pass, you can safely use the OS in production node pools.

## Common OS Selection Pitfalls

- **Older OS versions (TencentOS 3.x / early Ubuntu 20.04)**: Kernel versions may be < 5.10, causing cilium installation errors or some features (e.g., BPF Host Routing) being unavailable.
- **DataPlaneV2's bundled OS**: The OS used when creating a VPC-CNI cluster with DataPlaneV2 is incompatible with the latest cilium (see [Installing Cilium - FAQ: Can I select DataPlaneV2 when creating a VPC-CNI cluster?](../install.md#vpc-cni-集群创建时能否勾选-dataplanev2)).
- **Custom stripped OS images**: If BPF-related kernel modules (e.g., `bpf`, `bpf_jit`) have been stripped, cilium will fail to start.

## Related Links

- [Installing Cilium](../install.md)
- [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
