# Overview

[Cilium](https://cilium.io/) is an open-source cloud-native networking solution based on eBPF that provides high-performance networking, advanced network security policies, observability, and more for Kubernetes clusters. This series of tutorials explains how to install and use Cilium on TKE clusters.

## Article Map

### Getting Started

| Article                      | Content                                                      | Audience                  |
| ---------------------------- | ------------------------------------------------------------ | ------------------------- |
| **Install Cilium**           | Empty cluster creation, helm install, verification, rollback | First-time users          |
| **Cilium Connectivity Test** | Functional testing methodology and real-world results        | All users                 |
| **Cilium Performance Test**  | Network benchmark across all deployment schemes              | Performance-focused users |

### Networking Enhancements

| Article                                  | Content                                                | Prerequisites    |
| ---------------------------------------- | ------------------------------------------------------ | ---------------- |
| **Configuring IP Masquerade**            | Let Pods use node EIP for outbound Internet (SNAT)     | Cilium installed |
| **Egress Gateway**                       | Select fixed egress IPs per policy for external access | Cilium installed |
| **Enabling Encryption**                  | WireGuard / IPsec encrypt inter-node Pod traffic       | Cilium installed |
| **Cilium with Nodelocal DNSCache**       | Self-deployed NodeLocal DNS for faster DNS resolution  | Cilium installed |
| **Multi-Cluster Networking with Cilium** | Cluster Mesh for multi-cluster service connectivity    | Cilium installed |

### Security Policies

| Article           | Content                                           |
| ----------------- | ------------------------------------------------- |
| **NetworkPolicy** | CiliumNetworkPolicy intro and 20+ common patterns |

### Observability

| Article                         | Content                                              |
| ------------------------------- | ---------------------------------------------------- |
| **Enhance Observability**       | Enable Hubble Relay / Hubble UI / flow log audit     |
| **Cilium + CLS Flow Log Audit** | Send Hubble flow logs to CLS for search and analysis |

### Appendices (Design Principles & Operations)

| Article                                      | Content                                                        |
| -------------------------------------------- | -------------------------------------------------------------- |
| **Large-Scale Cilium Tuning**                | Parameter, resource, and BPF map tuning for 200+ node clusters |
| **Verified Node OS**                         | Compatibility verification for 7 operating systems             |
| **Cilium Host Routing**                      | Legacy vs BPF: mechanism, conditions, comparison               |
| **Why Native Needs local-router-ipv4**       | Principle and address selection                                |
| **Why Native Disables sysctlfix**            | rp_filter differences and decision logic                       |
| **Why GR Native Routing Is Not Recommended** | Complete trial record with 4 categories of issues              |

### Troubleshooting

| Article                                                       | Content                                          |
| ------------------------------------------------------------- | ------------------------------------------------ |
| **Connect to apiserver fails with `operation not permitted`** | Cilium bug investigation and root cause analysis |
| **Cilium Debugging Tips**                                     | Common commands: `cilium status`, monitor, etc.  |

## Quick Decision Tree

Based on your needs, jump to the relevant article:

```text
What do you want to do?
├─ Install Cilium
│  ├─ New cluster, first install → Install Cilium
│  ├─ Existing cluster, verify it works → E2E Test
│  └─ Care about performance → Performance Test
├─ Configure networking
│  ├─ Pod needs outbound Internet access
│  │  ├─ Already has NAT Gateway → No extra config needed
│  │  ├─ Want to reuse node EIP → Configuring IP Masquerade
│  │  └─ Want fixed egress IP → Egress Gateway
│  ├─ Encrypt inter-node traffic → Enabling Encryption
│  ├─ Connect multiple clusters → Multi-Cluster Networking
│  └─ Speed up DNS resolution → Nodelocal DNSCache
├─ Write network policies
│  └─ Restrict inter-Pod/egress/ingress access → NetworkPolicy
├─ Do observability
│  ├─ See cluster service topology → Enhance Observability
│  └─ Audit network flows → Cilium + CLS Flow Log Audit
├─ Tune & troubleshoot
│  ├─ Large-scale optimization → Large-Scale Tuning Guide
│  ├─ Check OS compatibility → Verified Node OS
│  └── Connect to apiserver errors → Troubleshooting articles
└─ Understand design principles
   ├─ What is Host Routing → Host Routing appendix
   ├─ Why configure local-router-ipv4 → Corresponding appendix
   └─ Why GR doesn't work → GR Native not recommended
```

## Network Modes

Cilium supports two routing modes:

1. **Encapsulation Mode**: Adds an additional network packet layer (e.g., VXLAN) on top of the existing network for forwarding. It offers good compatibility and adaptability to various network environments, albeit with slightly lower performance.
2. **Native-Routing**: Pod IPs are directly routed on the underlying network; Cilium doesn't interfere. Performance is excellent, but it depends on the underlying network's support for Pod IP routing.

In cloud-hosted Kubernetes clusters including TKE, the VPC underlying network already supports Pod IP routing, eliminating the need for an overlay layer for optimal performance. Therefore, Native-Routing mode is typically used.

Consider Encapsulation (VXLAN overlay) mode if:

- VPC IP resources are scarce and you prefer Pod IPs not to consume underlay IPs.
- You need to manage IDC clusters, replacing TKE's built-in CiliumOverlay network mode.
- You want the latest Cilium with full features (no kube-proxy coexistence, avoiding NetworkPolicy feature degradation).

> For more details, see the official Cilium documentation: [Routing](https://docs.cilium.io/en/stable/network/concepts/routing/).

### Three Recommended Deployment Schemes

This series provides the following three deployment schemes that have passed comprehensive e2e testing:

| Scheme                       | Cluster Type | Routing | Pod IP Source    | Key Feature                               |
| ---------------------------- | ------------ | ------- | ---------------- | ----------------------------------------- |
| **Native Routing (VPC-CNI)** | VPC-CNI      | Native  | VPC subnet IP    | Pod natively recognized by VPC            |
| **Overlay (VPC-CNI)**        | VPC-CNI      | VXLAN   | Independent CIDR | IP decoupled from VPC, full features      |
| **Overlay (GR)**             | GR           | VXLAN   | Independent CIDR | Only recommended for existing GR clusters |

> GR + Native Routing is no longer provided due to compatibility issues. See [Why GR Native Routing Is Not Recommended](./appendix/gr-native-not-recommended.md).

## Prerequisites

To install Cilium on a TKE cluster, the following prerequisites must be met:

- Cluster version: TKE 1.32+, see [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/).
- Node type: Regular nodes or native nodes.
- Operating system: TencentOS 4 or Ubuntu >= 22.04 (full list in [Verified Node OS](./appendix/verified-os.md)).

## Companion Script

This series comes with a [one-click installation script](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh), `cilium.sh`, which wraps common operations:

| Subcommand                        | Function                                                         |
| --------------------------------- | ---------------------------------------------------------------- |
| `cilium.sh install`               | Auto-detect cluster environment, interactive guided installation |
| `cilium.sh uninstall`             | Uninstall Cilium and restore TKE components                      |
| `cilium.sh test`                  | Run 130+ functional test cases (with China region adaptation)    |
| `cilium.sh perf`                  | Run network performance benchmarks (TCP_RR / TCP_STREAM)         |
| `cilium.sh enable-hubble`         | One-click enable Hubble Relay + UI                               |
| `cilium.sh enable-egress-gateway` | One-click enable Egress Gateway                                  |
| `cilium.sh install-localdns`      | One-click install NodeLocal DNSCache (Cilium-compatible)         |

## Key Capabilities

Installing Cilium on TKE can replace or enhance the following native TKE networking components:

| Capability         | TKE Native           | Cilium Replacement / Enhancement                  |
| ------------------ | -------------------- | ------------------------------------------------- |
| **kube-proxy**     | Installed by default | kubeProxyReplacement (full replacement)           |
| **NetworkPolicy**  | No L7/DNS support    | CiliumNetworkPolicy (supports L7 / FQDN)          |
| **Observability**  | None                 | Hubble (service topology + network flow logs)     |
| **Egress control** | Requires extra setup | Egress Gateway (per-policy egress IP selection)   |
| **Encryption**     | None                 | WireGuard / IPsec transparent encryption          |
| **IP masquerade**  | ip-masq-agent        | Built-in BPF ip-masq-agent (better performance)   |
| **Multi-cluster**  | None                 | Cluster Mesh (cross-cluster Service connectivity) |
