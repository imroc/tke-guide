# Verified Node Operating Systems

## Scope

This page lists node OS images and kernel versions that have been hands-on verified across all **4 installation modes** covered in [Installing Cilium](../install.md) (VPC-CNI/GR × Native Routing/Overlay). Use it as a reference when choosing the OS for your cilium node pools.

When creating a new node pool, prefer something from the table below. If your business requires an OS not listed here, validate on a single-node test cluster first before rolling out broadly.

## Verified OS List

All entries below have passed the full e2e suite (cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache) under all 4 installation modes.

| OS                   | OsName                  | Kernel  |
| -------------------- | ----------------------- | ------- |
| TencentOS Server 4   | `tlinux4_x86_64_public` | 6.6.117 |
| Ubuntu 24.04         | `ubuntu24.04x86_64`     | 6.8.0   |
| Ubuntu 22.04         | `ubuntu22.04x86_64`     | 5.15.0  |
| Debian 12 (bookworm) | `debian12.8x86_64`      | 6.1.0   |
| Debian 11 (bullseye) | `debian11.11x86_64`     | 5.10.0  |
| OpenCloudOS 9.4      | `opencloudos9.0x86_64`  | 6.6.119 |
| Rocky Linux 9.3      | `rockylinux9.3x86_64`   | 5.14.0  |
| RedHat 9.5           | `redhat9.5x86_64`       | 5.14.0  |

**Top picks**: **TencentOS Server 4** or **Ubuntu 24.04** — newer kernels, best compatibility with recent cilium releases.

The `OsName` column matches the `node_os` field of the [tencentcloud_kubernetes_node_pool](https://registry.terraform.io/providers/tencentcloudstack/tencentcloud/latest/docs/resources/kubernetes_node_pool) terraform resource, and corresponds to the image identifier shown in the console's "Operating System" dropdown.

## How These Were Verified

The list above is produced as follows:

1. Use the modules in [terraform-manifests](https://github.com/imroc/terraform-manifests) to create one isolated test cluster per network mode (VPC-CNI / GR), then create one node pool per OS in the list (1 node per pool).
2. Use the [one-click install script](../install.md#one-click-install-script) to install cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache.
3. Run the e2e subcommand:
   ```bash
   ./cilium.sh e2e-test
   ```
4. Verify all of the following pass:
   - `cilium-health status` reports all nodes reachable (covers host↔Pod and Pod↔Pod cross-node connectivity)
   - `coredns` Pods pass health checks
   - `node-local-dns` Pods pass health checks
   - Default `cilium connectivity test` suite (skipping public-internet cases) passes end-to-end

## Validating an Unlisted OS Yourself

If you need an OS not in the list (e.g. a custom image, or another CVM public image), validate it on a single node like this:

1. **Kernel pre-check**: confirm the OS kernel is ≥ 5.10 (see cilium [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)).
2. **Create a test cluster**: use the target OS, with just 1-2 nodes; install cilium.
3. **Run the e2e suite**: `./cilium.sh e2e-test`. Watch for:
   - `cilium-health status` — all nodes reachable
   - DNS resolution (both in-cluster service names and external domains) works
   - `cilium connectivity test` passes
4. **Run business-path checks**: if you rely on extra features (NetworkPolicy, Egress Gateway, Cluster Mesh, etc.), exercise their critical paths once.

After the above checks pass, the OS is safe to use in production node pools.

## Common OS Pitfalls

- **TencentOS 3.x / older Ubuntu 20.04**: kernel may be < 5.10; cilium install errors or some features (e.g. BPF Host Routing) won't work.
- **DataPlaneV2's bundled OS**: when creating a VPC-CNI cluster with the DataPlaneV2 option, the underlying OS is incompatible with the latest cilium — see [Installing Cilium — FAQ: Can DataPlaneV2 be selected when creating a VPC-CNI cluster?](../install.md#can-dataplanev2-be-selected-when-creating-a-vpc-cni-cluster).
- **Custom-trimmed OS images**: if you stripped BPF-related kernel modules (e.g. `bpf`, `bpf_jit`), cilium fails to start.

## Related

- [Installing Cilium](../install.md)
- [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)
- [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
