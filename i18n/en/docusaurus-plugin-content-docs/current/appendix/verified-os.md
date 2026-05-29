# Verified Node Operating Systems

This appendix lists all node operating systems and kernel versions that have been verified by hands-on testing for the solutions in this guide. Other OS versions that meet the minimum kernel requirements of the components should also work, but are not covered by our tests.

## Cilium Verified OS

Applies to: all 4 installation modes (VPC-CNI/GR × Native/Overlay) in [Install Cilium](../networking/cilium/install.md).

**Test method**: For each installation mode, cilium 1.19.4 was deployed with Egress Gateway and Nodelocal DNSCache enabled. Verified that `cilium-health status` shows all nodes reachable, and `coredns` / `node-local-dns` pass health checks.

| OS                   | Kernel  | iptables backend | Notes                                                       |
| -------------------- | ------- | ---------------- | ----------------------------------------------------------- |
| TencentOS Server 4   | 6.6.117 | legacy           | Recommended: default OS for TKE Native/Karpenter            |
| Ubuntu 24.04         | 6.8.0   | nf_tables        | Recommended: newest kernel, optimal performance             |
| Ubuntu 22.04         | 5.15.0  | nf_tables        |                                                             |
| Debian 12 (bookworm) | 6.1.0   | nf_tables        | Only nftables by default; cilium uses iptables in container |
| Debian 11 (bullseye) | 5.10.0  | nf_tables        | Same as above                                               |
| OpenCloudOS 9.4      | 6.6.119 | legacy           | Community open-source variant of TencentOS 4                |
| Rocky Linux 9.3      | 5.14.0  | nf_tables        |                                                             |
| RedHat 9.5           | 5.14.0  | nf_tables        |                                                             |

Minimum requirement: Linux kernel >= 5.10 (see [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)).

For OS versions not in the list above, we recommend a single-node smoke test first.
