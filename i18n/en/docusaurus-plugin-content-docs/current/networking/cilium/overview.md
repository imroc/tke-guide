# Overview

[Cilium](https://cilium.io/) is an eBPF-based open-source cloud-native networking solution that provides high-performance networking, advanced network security policies, and observability for Kubernetes clusters. This series of tutorials covers how to install and use Cilium in TKE clusters.

## Article Map

### Getting Started

| Article                    | Content                                                    | Audience                  |
| -------------------------- | ---------------------------------------------------------- | ------------------------- |
| **Installing Cilium**      | Empty cluster creation, helm installation, verification, rollback | First-time users   |

| **Cilium Functional Test** | Functional testing methods and measured data               | All post-install users    |
| **Cilium Performance Test**| Baseline network performance and cross-scheme comparison   | Performance-focused users |

### Network Enhancement

| Article                                           | Content                                                  | Prerequisites     |
| ------------------------------------------------ | -------------------------------------------------------- | ----------------- |

| **Egress Gateway in Practice**                   | Select fixed egress IP per policy for external access    | Cilium installed  |
| **Enabling Communication Encryption**            | WireGuard / IPsec encryption for inter-node Pod traffic  | Cilium installed  |
| **Building Multi-Cluster Networks with Cilium**  | Cluster Mesh to connect services across clusters         | Cilium installed  |

### Security Policies

| Article                                | Content                                                        |
| -------------------------------------- | -------------------------------------------------------------- |
| **NetworkPolicy in Practice**          | CiliumNetworkPolicy introduction with 20+ common patterns      |

### Observability

| Article                                                    | Content                                                    |
| ---------------------------------------------------------- | ---------------------------------------------------------- |
| **Enhanced Observability**                                 | Enable Hubble Relay / Hubble UI / network flow log audit   |
| **Cilium + CLS for Network Flow Log Audit**                | Ship Hubble flow logs to CLS for search and analysis       |

### Appendix (Design Principles & Operations Guide)

| Article                                                    | Content                                                            |
| ---------------------------------------------------------- | ------------------------------------------------------------------ |
| **Cilium Tuning for Large Clusters**                       | Parameter, resource, and BPF map tuning for 200+ node clusters     |
| **Verified Node Operating Systems**                        | Compatibility verification results for 8 OS types                  |
| **Cilium Host Routing** ◀─┬─▶                              | Trilogy 1: Legacy vs BPF mechanisms, hit conditions, comparison    |
| **Why Native Mode Needs local-router-ipv4**                │ | Trilogy 2: cilium_host IP config principles and address selection  |
| **Why Native Mode Disables sysctlfix**                     │ | Trilogy 3: rp_filter differences and decision logic                |
| **Why GR Native Routing Is Not Available**                 | Complete trial-and-error record and 4 types of issues              |
| **Cilium with NodeLocal DNSCache**               | Self-built NodeLocal DNS cache for DNS acceleration      |
| **Configure IP Masquerading**                    | Let Pods egress via node EIP without NAT gateway         |
| **Host Cilium Images via TCR**                   | Use internal TCR instead of pulling from Docker Hub      |

> Articles marked ◀─┬─▶ form the Native Routing design principles trilogy. Recommended reading order: Host Routing → local-router-ipv4 → sysctlfix.

### Troubleshooting

| Article                                                    | Content                                                    |
| ---------------------------------------------------------- | ---------------------------------------------------------- |
| **Apiserver Connection Error: operation not permitted**    | Cilium bug investigation and root cause analysis           |
| **Cilium Debugging Tips**                                  | `cilium status`, monitor, and other common commands        |

## Quick Decision Tree

Find the target article based on your needs:

```text
What do you want to do?
├─ Install Cilium
│  ├─ New cluster, first-time install → Installing Cilium
│  ├─ Existing cluster, want to test → Functional Test
│  └─ Care about performance → Performance Test
├─ Configure network capabilities
│  ├─ Pods need outbound internet
│  │  ├─ Already have NAT Gateway → No additional config needed
│  │  ├─ Want to reuse node EIP → Configure IP Masquerade
│  │  └─ Want fixed egress IP → Egress Gateway
│  ├─ Encrypt inter-node traffic → Enable Communication Encryption
│  ├─ Connect multiple clusters → Building Multi-Cluster Networks
│  └─ Accelerate DNS resolution → Nodelocal DNSCache
├─ Write network policies
│  └─ Restrict Pod-to-Pod/egress/ingress access → NetworkPolicy in Practice
├─ Observability
│  ├─ View cluster service topology → Enhanced Observability
│  └─ Audit network flow logs → Cilium + CLS Log Audit
├─ Tuning & Troubleshooting
│  ├─ Large cluster optimization → Large Cluster Tuning Guide
│  ├─ Check OS compatibility → Verified Node Operating Systems
│  └─ Apiserver connection error → Corresponding troubleshooting article
└─ Understand design principles
   ├─ What is Host Routing → Host Routing Appendix
   ├─ Why configure local-router-ipv4 → Corresponding appendix
   └─ Why GR doesn't work → GR Native Not Recommended
```

## Network Modes

Cilium supports two routing modes:

1. **Encapsulation**: Wraps network packets in another layer (e.g., vxlan) for forwarding. Good compatibility across various network environments, slightly lower performance.
2. **Native-Routing**: Pod IPs are routed directly on the underlying network without Cilium intervention. Better performance, but relies on the underlying network's support for Pod IP routing.

In cloud-managed Kubernetes clusters, including TKE, the VPC underlay network already supports Pod IP routing, eliminating the need for an overlay layer to achieve optimal network performance. Therefore, Native-Routing mode is typically used.

However, if you have the following requirements, you may choose Encapsulation (vxlan overlay) mode:

- VPC IP resources are scarce and you don't want Pod IPs to consume underlay IPs.
- Need to manage IDC clusters, replacing TKE's built-in CiliumOverlay network mode.
- Want to use the latest Cilium version with full feature set (without coexisting with kube-proxy, avoiding degradation of NetworkPolicy and other features).

> For more details, refer to the Cilium official documentation: [Routing](https://docs.cilium.io/en/stable/network/concepts/routing/).

### Three Recommended Deployment Schemes

This series provides three deployment schemes that have been fully e2e tested:

| Scheme                        | Cluster Network Mode | Routing Mode | Pod IP Source   | Key Features                              |
| ----------------------------- | -------------------- | ------------ | --------------- | ----------------------------------------- |
| **Native Routing (VPC-CNI)**  | VPC-CNI              | Native       | VPC subnet IP   | Pods natively recognized by VPC           |
| **Overlay (VPC-CNI)**         | VPC-CNI              | VXLAN        | Independent CIDR| IP decoupled from VPC, full feature set   |
| **Overlay (GR)**              | GR                   | VXLAN        | Independent CIDR| Only recommended for existing GR clusters |

> GR + Native Routing is no longer provided due to compatibility issues. See [Why GR Native Routing Deployment Is Not Recommended](./appendix/gr-native-not-recommended.md).

## Prerequisites

To install Cilium in a TKE cluster, the following prerequisites must be met:

- Cluster version: TKE 1.32 and above, see [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/).
- Node type: Regular nodes or native nodes.
- Operating system: TencentOS 4 or Ubuntu >= 22.04 (full verified list at [Verified Node Operating Systems](./appendix/verified-os.md)).

## Companion Tools

This series comes with a [one-click installation script](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh) `cilium.sh` that wraps common operations such as installation, testing, and uninstallation:

| Subcommand                           | Function                                                     |
| ------------------------------------ | ------------------------------------------------------------ |
| `cilium.sh install`                  | Auto-detect cluster environment, interactive guided installation |
| `cilium.sh uninstall`                | Uninstall Cilium, restore TKE components                     |
| `cilium.sh test`                     | Run 130+ functional test cases (with China region adaptation)|
| `cilium.sh perf`                     | Execute network performance benchmarks (TCP_RR / TCP_STREAM) |
| `cilium.sh enable-hubble`            | One-click enable Hubble Relay + UI                           |
| `cilium.sh enable-egress-gateway`    | One-click enable Egress Gateway                              |
| `cilium.sh install-localdns`         | One-click install NodeLocal DNSCache (coexists with Cilium)  |

## Key Capabilities

After installing Cilium in TKE, it can replace or enhance the following TKE native network components:

| Capability            | TKE Native       | Cilium Replacement/Enhancement                   |
| --------------------- | ---------------- | ------------------------------------------------ |
| **kube-proxy**        | Installed by default | kubeProxyReplacement (complete replacement)   |
| **NetworkPolicy**     | L7/DNS not supported | CiliumNetworkPolicy (supports L7 / FQDN)      |
| **Observability**     | None             | Hubble (service topology + network flow logs)    |
| **Egress Control**    | Requires additional config | Egress Gateway (per-policy egress IP selection)  |
| **Encryption**        | None             | WireGuard / IPsec transparent encryption         |
| **IP Masquerade**     | ip-masq-agent    | Built-in BPF ip-masq-agent (better performance)   |
| **Multi-Cluster Network** | None         | Cluster Mesh (cross-cluster Service access)      |
