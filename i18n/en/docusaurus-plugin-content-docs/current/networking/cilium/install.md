# Installing Cilium

This article describes how to install cilium in a TKE cluster, with support for the following network modes:

- **Native Routing**: Coexists with TKE CNI. Pods use IPs allocated by TKE; cilium provides NetworkPolicy, observability, kube-proxy replacement, and other enhancements.
- **Overlay (vxlan tunnel)**: Completely replaces all TKE CNIs. Pod IPs do not consume underlay IPs, suitable for scenarios where IP allocation is difficult, or as a replacement for TKE's built-in CiliumOverlay mode to get full cilium functionality.

VPC-CNI clusters support both modes; GR clusters only support Overlay mode. **VPC-CNI clusters are recommended** — better network performance, no node count limit, and they don't waste a VPC secondary CIDR like GR does (see FAQ [Why aren't GR clusters recommended?](#why-arent-gr-clusters-recommended)).

:::note[How to Choose]

| Comparison Item           | Native Routing (VPC-CNI) ⭐ | Overlay (VPC-CNI) ⭐                          | Overlay (GR)                                                                                                                                                                                                                                                                                      |
| ------------------------- | --------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network Performance       | ✅ Optimal                  | Slight overhead (vxlan encap)                 | Slight overhead (vxlan encap)                                                                                                                                                                                                                                                                     |
| Pod IP Range              | VPC IP                      | Independent CIDR, doesn't consume VPC IP      | Independent CIDR, doesn't consume VPC IP                                                                                                                                                                                                                                                          |
| VPC Secondary CIDR Burned | ✅ None                     | ✅ None                                       | ⚠️ A GR cluster **mandates a VPC secondary CIDR be carved out as its ClusterCIDR** at creation. Even when Overlay assigns Pod IPs from an independent CIDR and that ClusterCIDR is never used by any Pod, the secondary CIDR remains permanently held by the GR cluster (a GR cluster limitation) |
| IP Capacity Expansion     | ✅ Supported (add a VPC-CNI subnet)        | ✅ Supported (append CIDR to `clusterPoolIPv4PodCIDRList`)   | ✅ Supported (append CIDR to `clusterPoolIPv4PodCIDRList`)                                                                                                                                                                                                                                        |
| Node Count Limit          | ✅ None                     | ✅ None                                       | ⚠️ Limited by GR ClusterCIDR (GR cluster's own limit)                                                                                                                                                                                                                                             |
| External Pod Access       | ✅ Directly routable        | Not directly routable, via Service/Ingress    | Not directly routable (Same as left)                                                                                                                                                                                                                                                              |
| CLB Direct-to-Pod         | ✅ Supported                | ❌ Not supported (CLB can't route Overlay IP) | ❌ Not supported (Same as left)                                                                                                                                                                                                                                                                   |
| L7/DNS NetworkPolicy      | ✅ Fully supported          | ✅ Fully supported                            | ✅ Fully supported                                                                                                                                                                                                                                                                                |
| Use Cases                 | General (recommended)       | IP shortage, IDC, full-featured cilium (rec.) | Only recommended if you already have a GR cluster — do NOT create a new GR cluster just to install cilium                                                                                                                                                                                         |

:::

:::warning[GR clusters: Overlay only, and don't create a new GR cluster just for cilium]

GR clusters have two hard limitations that don't pair well with cilium:

1. **GR + Native Routing on cilium chained CNI is not production-viable**: cross-node Pod-to-Pod traffic is broken, and L7/DNS NetworkPolicy is unsupported. This guide no longer offers that combination. Full write-up: [Why this guide does not offer GR Native Routing](./appendix/gr-native-not-recommended.md).
2. **GR clusters mandate a ClusterCIDR at creation** — that CIDR is carved out of the VPC's secondary CIDR list and pinned to the cluster. Even after installing cilium Overlay, when Pod IPs come entirely from an independent CIDR and not a single IP in ClusterCIDR is ever used, that CIDR is still held by the GR cluster and cannot be reused by any other resource in the same VPC. See FAQ [Why aren't GR clusters recommended?](#why-arent-gr-clusters-recommended) below.

If you already have a GR cluster, follow the **Overlay (GR)** path in this guide. For new clusters, choose **VPC-CNI** instead.

:::

## Preparation

### Prepare TKE Cluster

:::info[Note]

Installing cilium is a major change to the cluster. Do not install it in a cluster running production workloads — installation may disrupt online services. It is recommended to install cilium in a newly created TKE cluster.

:::

In the [TKE Console](https://console.cloud.tencent.com/tke2/cluster), create a TKE cluster with the following key options:

- Container network plugin: choose **VPC-CNI Shared ENI Multi-IP**. GR clusters have several constraints (forced ClusterCIDR consuming a VPC secondary CIDR, node count capped by ClusterCIDR), so they are **not recommended** for new cilium deployments (see [Why aren't GR clusters recommended?](#why-arent-gr-clusters-recommended)). Existing GR clusters can still follow the Overlay (GR) install path, but the rest of this section uses VPC-CNI as the baseline.
- Cluster type: Standard cluster.
- Kubernetes version: 1.32 or later, latest is recommended (see [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)).
- Operating system: recommend **TencentOS 4** or **Ubuntu 24.04**. Minimum: Linux kernel >= 5.10 (see [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)). For the full verified OS list, see [Verified Node Operating Systems](./appendix/verified-os.md).
- Nodes: **the cluster MUST have no regular or native nodes before cilium is installed** — super nodes (eklet) are fine. See the warning block below.
- Base addons: **keep ip-masq-agent checked** (the default). The cilium install script will disable TKE's built-in ip-masq-agent (to avoid conflict with cilium's built-in ipMasqAgent), but it will **reuse** the `ip-masq-agent-config` ConfigMap that TKE auto-populates with the VPC's primary + all secondary CIDRs. The [one-click install script](#one-click-install-script) reads this cm and uses it as cilium ipMasqAgent's `nonMasqueradeCIDRs`, so you don't have to manually look up VPC CIDRs in the console.
- Extension addons: if you plan to use Karpenter node pools, enable the Karpenter addon; otherwise skip (see node pool selection below).

:::warning[Do NOT add regular or native nodes to the cluster before installing cilium]

Cilium must be installed on an **empty cluster** (no nodes / super nodes only). If regular or native nodes already exist:

- Their leftover kube-proxy iptables rules and tke-cni-agent CNI configs will conflict with cilium, **causing post-install Pod network failures, broken NetworkPolicy**, and other hard-to-debug issues
- Even if you disable the TKE addons before installing cilium, kernel-level state on those nodes is NOT cleaned up

The right order:

1. **Create the cluster empty** (no nodes from console / terraform)
2. **Install cilium → add nodes**: the one-click script pauses after install and prompts you to add nodes; once they're Ready, it continues

If you accidentally added nodes before installing cilium, **reboot or recreate those nodes** so cilium can take over cleanly.

:::

After the cluster is created, enable cluster access so helm can talk to the apiserver during installation. See [Enabling Cluster Access](https://www.tencentcloud.com/document/product/457/30638).

Choose intranet or internet access depending on whether the network where you run helm is reachable to the cluster's VPC:

1. If reachable → enable intranet access.
2. If not reachable → enable internet access. The current internet-access path requires deploying a `kubernetes-proxy` component as a relay, which depends on at least one node existing in the cluster (this dependency may go away in the future, but it exists today). If you must use internet access, add a super node to the cluster first so the `kubernetes-proxy` pod can be scheduled, then remove the super node after cilium installation.

If you use terraform to create the cluster, the snippet below is a reference:

```hcl
resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  # Standard cluster
  cluster_deploy_type = "MANAGED_CLUSTER"
  # Kubernetes version >= 1.32
  cluster_version = "1.34.1"
  # Default node OS (OsName) — see appendix for the full verified list
  # Note: the actual OS of a node is determined by the node pool's own OS attribute, not cluster_os.
  cluster_os = "tlinux4_x86_64_public"
  # Container network plugin: prefer VPC-CNI (GR has ClusterCIDR / VPC secondary
  # CIDR limitations and is not recommended for new cilium deployments)
  network_type = "VPC-CNI"
  # Enable apiserver access
  cluster_internet = true
  # Expose apiserver via intranet CLB — specify the CLB subnet ID
  cluster_intranet_subnet_id = "subnet-xxx"
  # Keep ip-masq-agent installed (terraform provider installs it by default).
  # The cilium install script will disable it but reuse its ip-masq-agent-config
  # ConfigMap (containing VPC primary + secondary CIDRs) as cilium ipMasqAgent's
  # nonMasqueradeCIDRs.
  # If you plan to use Karpenter node pools, install the Karpenter addon.
  # (cluster-autoscaler and karpenter are mutually exclusive — enabling this disables
  # cluster-autoscaler, which also disables scaling for regular and native node pools.
  # If you don't need Karpenter, omit this block. See "Create Node Pools" below.)
  extension_addon {
    name = "karpenter"
    param = jsonencode({
      "kind" : "App", "spec" : { "chart" : { "chartName" : "karpenter" } }
    })
  }
  # Other required-but-unrelated config omitted
}
```

### Tool & Environment Setup

You need a workstation (local laptop or jump host) that can reach the cluster, with the following tools installed:

1. **kubectl** — for cluster operations (see [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)).
2. **helm** — for installing the cilium chart (see [Install helm](https://helm.sh/docs/intro/install/)).
3. **cilium CLI** — required for the one-click install/test scripts, or for running `cilium connectivity test` manually (see [Install cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)).

Configure kubeconfig to reach the cluster (see [Connect to Cluster](https://www.tencentcloud.com/document/product/457/30637)), then add the cilium helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

## Install Cilium

### One-Click Install Script

You can use a script that auto-detects the cluster environment and guides the installation. One-liner that works in any shell — no separate download needed:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- install
```

If the GitHub URL is not reachable, use the site mirror:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- install
```

The script auto-detects the cluster's network mode, guides you through choosing a mode and version, then performs the installation. During installation you can optionally enable [Egress Gateway](egress-gateway.md) and [Nodelocal DNSCache](with-node-local-dns.md). For manual installation, follow the steps below.

:::tip[Why `bash -c "$(curl ...)"` and not `curl ... | bash`?]

The `install` subcommand is interactive (it calls `read` to ask for choices). With `curl ... | bash`, bash's stdin is consumed by curl's pipe output, so `read` returns EOF immediately and the script exits.

With `bash -c "$(curl ...)"`, bash receives the script as a string argument and stdin remains attached to the terminal — `read` works normally. This pattern works for both interactive and non-interactive subcommands.

If you want a fully non-interactive one-liner, set the parameters via environment variables (`bash -c` inherits them from the parent shell):

```bash
ROUTING_MODE=native CILIUM_VERSION=1.19.4 \
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- install
```

:::

### Uninstall TKE Components

All modes need kube-proxy disabled (cilium replaces it), tke-cni-agent disabled (to avoid CNI config conflicts), and ip-masq-agent disabled (to avoid conflict with cilium's built-in ipMasqAgent):

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
```

:::tip[Notes]

1. Using a non-matching nodeSelector to keep the DaemonSet off all nodes is equivalent to uninstalling, and leaves a fallback path. For kube-proxy this is currently the only safe way — directly deleting kube-proxy will block future cluster upgrades.
2. As emphasized above: **cilium must be installed on an empty cluster**. If regular or native nodes were added by mistake before installation, reboot or recreate them so cilium can take over cleanly.
3. **Do NOT delete the `ip-masq-agent-config` ConfigMap** — TKE's ip-masq-agent populates it at cluster creation with the VPC primary + all secondary CIDRs. Cilium's built-in ipMasqAgent reads this cm for its `nonMasqueradeCIDRs`, saving you from manually looking up VPC CIDRs. The one-click install script reuses it automatically; for manual installs, inspect with `kubectl -n kube-system get cm ip-masq-agent-config -o yaml`.

:::

### Mode-Specific Pre-Install Steps

Run the steps corresponding to your chosen mode:

<Tabs>
<TabItem value="native-vpccni" label="Native Routing (VPC-CNI)" default>

Create a CNI config ConfigMap defining the chaining relationship between VPC-CNI and cilium:

```yaml title="cni-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-config
  namespace: kube-system
data:
  cni-config: |-
    {
      "cniVersion": "0.3.1",
      "name": "generic-veth",
      "plugins": [
        {
          "type": "tke-route-eni",
          "routeTable": 1,
          "disableIPv6": true,
          "mtu": 1500,
          "ipam": {
            "type": "tke-eni-ipamc",
            "backend": "127.0.0.1:61677"
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
```

```bash
kubectl apply -f cni-config.yaml
```

</TabItem>
<TabItem value="overlay-gr" label="Overlay (GR)">

No extra pre-install steps.

</TabItem>
<TabItem value="overlay-vpccni" label="Overlay (VPC-CNI)">

Disable `add-pod-eni-ip-limit-webhook` (otherwise Pods get auto-injected with the `tke.cloud.tencent.com/eni-ip` resource request, which causes ip-scheduler to block scheduling):

```bash
kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook
```

</TabItem>
</Tabs>

### Install Cilium via Helm

:::info[Note]

`k8sServiceHost` is the apiserver address, fetched dynamically via the command shown.

:::

<Tabs>
<TabItem value="native-vpccni" label="Native Routing (VPC-CNI)" default>

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
<TabItem value="overlay-gr" label="Overlay (GR)">

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set localRedirectPolicies.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
<TabItem value="overlay-vpccni" label="Overlay (VPC-CNI)">

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set localRedirectPolicies.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
</Tabs>

#### Configuration Parameters (values.yaml)

The `--set` flags above are convenient for quick tests. **For production use, switch to a `values.yaml` file**: clearer parameter semantics, version-controllable in Git, easier to review and roll back. Below are annotated examples organized as: common parameters + mode-specific parameters + optional (images / Egress / resources).

<Tabs>
  <TabItem value="common" label="Common">

Parameters common to all modes:

```yaml showLineNumbers title="common-values.yaml"
# Replace kube-proxy — handles ClusterIP/NodePort/HostPort forwarding
kubeProxyReplacement: "true"
# Replace with your actual apiserver address.
# Get it via: kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112
k8sServicePort: 60002
# Enable CiliumLocalRedirectPolicy
# See: https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/
localRedirectPolicies:
  enabled: true
operator:
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: Exists
  - key: "node-role.kubernetes.io/master"
    operator: Exists
  - key: "node.kubernetes.io/not-ready"
    operator: Exists
  - key: "node.cloudprovider.kubernetes.io/uninitialized"
    operator: Exists
  # Tolerate TKE taints — avoid bootstrap circular dependency at first install
  - key: "tke.cloud.tencent.com/uninitialized"
    operator: Exists
```

  </TabItem>
  <TabItem value="native-vpccni" label="Native (VPC-CNI)">

Native Routing (VPC-CNI) mode-specific parameters:

```yaml showLineNumbers title="native-vpccni-values.yaml"
# Use native routing — Pods use VPC IPs directly, no overlay
routingMode: "native"
endpointRoutes:
  # Must be true for native routing — routes Pod traffic directly via veth device.
  # Note: this also forces cilium onto legacy host routing rather than BPF host routing.
  # See appendix "Cilium Host Routing: Legacy vs BPF" for details.
  enabled: true
ipam:
  # Pod IP allocation handled by tke-eni-ipamd, not by cilium
  mode: "delegated-plugin"
# In VPC-CNI Pods already have VPC IPs — no IP masquerade needed
enableIPv4Masquerade: false
# All eth-prefixed interfaces on TKE nodes can carry traffic (auxiliary ENIs eth1/eth2/...)
# This flag attaches cilium eBPF programs to all eth* interfaces
devices: eth+
cni:
  # Use generic-veth chaining with VPC-CNI
  chainingMode: generic-veth
  # Fully custom CNI config — use the ConfigMap we created earlier
  customConf: true
  configMap: cni-configuration
  # VPC-CNI already configures Pod routes — cilium doesn't need to
  externalRouting: true
extraConfig:
  # cilium doesn't allocate Pod IPs here — manually specify the cilium_host IP
  local-router-ipv4: 169.254.32.16
# Disable sysctlfix — prevents restarting systemd-sysctl from resetting eth0 rp_filter. See FAQ.
sysctlfix:
  enabled: false
operator:
  tolerations:
  # VPC-CNI mode additionally needs to tolerate this taint
  - key: "tke.cloud.tencent.com/eni-ip-unavailable"
    operator: Exists
```

  </TabItem>
  <TabItem value="overlay" label="Overlay (VPC-CNI/GR)">

Overlay (vxlan) mode-specific parameters — applies to both VPC-CNI and GR base clusters:

```yaml showLineNumbers title="overlay-values.yaml"
# Encapsulate cross-node traffic in vxlan tunnel
routingMode: "tunnel"
tunnelProtocol: "vxlan"
ipam:
  mode: "cluster-pool"
  operator:
    # Pod CIDR — adjust to cluster scale. Just don't conflict with VPC CIDR or Service CIDR.
    clusterPoolIPv4PodCIDRList:
    - "10.244.0.0/16"
    # Per-node subnet mask — /24 = up to 254 Pod IPs per node
    clusterPoolIPv4MaskSize: "24"
# Overlay mode needs IP masquerade so Pod IPs are SNATed to node IP when leaving the cluster
enableIPv4Masquerade: true
bpf:
  # Must enable BPF masquerade. Without it cilium falls back to iptables masquerade,
  # which forces host routing back to legacy (BPF host routing won't be active).
  # See appendix "Cilium Host Routing: Legacy vs BPF" for details.
  masquerade: true
# Don't set sysctlfix (leave the default true) — ensures lxc interface rp_filter=0
```

VPC-CNI base cluster additionally needs this operator toleration:

```yaml
operator:
  tolerations:
  - key: "tke.cloud.tencent.com/eni-ip-unavailable"
    operator: Exists
```

  </TabItem>
  <TabItem value="images" label="Images">

Replace all cilium-related images with mirrors reachable from TKE intranet, to avoid pull failures:

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

  </TabItem>
</Tabs>

For production, save the parameters to YAML files and run the same command for both install and update (just swap `--version` for upgrades):

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml
```

If you have lots of custom config, split it into multiple files (e.g. Egress Gateway config in `egress-values.yaml`, container resource requests/limits in `resources-values.yaml`) and merge them via multiple `-f` flags:

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f egress-values.yaml \
  -f resources-values.yaml
```

#### Verify Installation

Verify that cilium-related Pods are running:

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/part-of=cilium
NAME                              READY   STATUS    RESTARTS   AGE
cilium-5rfrk                      1/1     Running   0          1m
cilium-9mntb                      1/1     Running   0          1m
cilium-envoy-4r4x9                1/1     Running   0          1m
cilium-envoy-kl5cz                1/1     Running   0          1m
cilium-envoy-sgl5v                1/1     Running   0          1m
cilium-operator-896cdbf88-jlgt7   1/1     Running   0          1m
cilium-operator-896cdbf88-nj6jc   1/1     Running   0          1m
cilium-zrxwn                      1/1     Running   0          1m
```

### Configure API Priority and Fairness (APF)

A cilium-agent Pod runs on every node. In large clusters this can put significant pressure on the apiserver — in extreme cases triggering a cascading failure that takes the whole cluster down. Configure APF to rate-limit cilium components.

Save the following to `cilium-apf.yaml`:

:::tip[Note]

Adjust `nominalConcurrencyShares` based on cluster size. See the comments in the file.

:::

<FileBlock file="cilium/cilium-apf.yaml" showLineNumbers showFileName />

Apply the APF rules:

```bash
kubectl apply -f cilium-apf.yaml
```

## Create Node Pools

:::tip[OS Compatibility]

Cilium requires Linux kernel >= 5.10. **Recommended OS**: Ubuntu 24.04 or the latest TencentOS 4.

For the **full list of verified OS images**, see [Verified Node Operating Systems](./appendix/verified-os.md).

:::

### Node Pool Selection

Three node pool types are compatible with cilium:

- **Native node pool**: based on native nodes. Native nodes are feature-rich and the recommended type by TKE (see [Native Nodes vs Regular Nodes](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)). OS is fixed to TencentOS.
- **Regular node pool**: based on regular nodes (CVM). OS image is flexible.
- **Karpenter node pool**: similar to native node pools (also based on native nodes, OS fixed to TencentOS), but uses the more powerful [Karpenter](https://karpenter.sh/) for node management instead of [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) (CA) used by regular and native node pools.

Comparison — pick whichever fits:

| Node Pool Type      | Node Type          | Available OS Images                                          | Scaling Component  |
| ------------------- | ------------------ | ------------------------------------------------------------ | ------------------ |
| Native node pool    | Native node        | TencentOS                                                    | cluster-autoscaler |
| Regular node pool   | Regular node (CVM) | All CVM public images (Ubuntu/TencentOS/...) + custom images | cluster-autoscaler |
| Karpenter node pool | Native node        | TencentOS                                                    | Karpenter          |

Steps for creating each type follow.

### Create Karpenter Node Pool

Before creating a Karpenter node pool, make sure the Karpenter addon is enabled — see [tke-karpenter docs](https://cloud.tencent.com/document/product/457/111805).

Prepare a `nodepool.yaml`, example:

```yaml title="nodepool.yaml"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
    - nodes: 10%
  template:
    metadata:
      annotations:
        # Native nodes default to TencentOS 3, which is incompatible with the latest cilium.
        # Use this annotation to install TencentOS 4 instead.
        # Note: using this OS image currently requires opening a support ticket.
        beta.karpenter.k8s.tke.machine.spec/annotations: node.tke.cloud.tencent.com/image-label=ts4-public
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      - key: karpenter.k8s.tke/instance-family
        operator: In
        # Pick the instance families you want. Check the console for what's actually available in
        # your region/AZ. Full list: https://cloud.tencent.com/document/product/213/11518#INSTANCETYPE
        values: ["S5", "SA2"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"] # Minimum CPU cores when scaling out
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default # Reference TKEMachineNodeClass
  limits:
    cpu: 100 # Max CPU cores for this node pool

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms: # VPC subnets for nodes
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # Security groups for nodes
  - id: sg-nok01xpa
  sshKeySelectorTerms: # SSH key for nodes
  - id: skey-3t01mlvf
```

Create the Karpenter node pool:

```bash
kubectl apply -f nodepool.yaml
```

### Create Native Node Pool

Steps to create a native node pool via the [TKE Console](https://console.cloud.tencent.com/tke2):

1. In the cluster list, click the cluster ID to enter the cluster details page.
2. In the left menu, click **Node Management**, then click **Node Pools**.
3. Click **New**.
4. Select **Native Node**.
5. In **Advanced Settings**, click **Add** under Annotations: `node.tke.cloud.tencent.com/image-label=ts4-public` (native nodes default to TencentOS 3.1, which is incompatible with the latest cilium — this annotation installs TencentOS 4 instead).
6. Configure other options as needed.
7. Click **Create Node Pool**.

If you prefer terraform:

```hcl
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations { # Use this annotation to make native nodes run TencentOS 4 (compatible with cilium). Currently requires opening a support ticket.
    name  = "node.tke.cloud.tencent.com/image-label"
    value = "ts4-public"
  }
}
```

### Create Regular Node Pool

Steps to create a regular node pool via the [TKE Console](https://console.cloud.tencent.com/tke2):

1. In the cluster list, click the cluster ID to enter the cluster details page.
2. In the left menu, click **Node Management**, then click **Node Pools**.
3. Click **New**.
4. Select **Regular Node**.
5. For **Operating System**, choose any image from [Verified Node Operating Systems](./appendix/verified-os.md) (recommend **TencentOS 4** or **Ubuntu 24.04**). You may also use other CVM public images or custom images that meet the kernel requirement (kernel >= 5.10) — single-node validation is recommended first.
6. Configure other options as needed.
7. Click **Create Node Pool**.

If you prefer terraform:

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "tlinux4_x86_64_public" # OsName — see appendix for full verified OS list

  # Ensure business Pods are only scheduled after cilium agent is ready
  taints {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NoSchedule"
  }
}
```

## Upgrade and Rollback

### Upgrade Cilium Version

Cilium minor-version upgrades (e.g. 1.19.4 → 1.19.5) are usually backward-compatible — upgrade directly with helm. **For major-version upgrades (e.g. 1.18 → 1.19), you MUST consult the corresponding version section of the official [Upgrade Guide](https://docs.cilium.io/en/stable/operations/upgrade/)** to confirm breaking changes and required parameter adjustments.

Upgrade steps:

```bash
# 1. Back up current values
helm get values cilium -n kube-system > cilium-values-backup.yaml

# 2. Update helm repo
helm repo update cilium

# 3. Upgrade (keep existing values)
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --version <new-version> \
  --reuse-values

# 4. Rolling restart so the datapath uses the new version (cilium-agent uses RollingUpdate by default — no interruption)
kubectl -n kube-system rollout status ds/cilium

# 5. Verify
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
```

:::warning[Upgrade Cautions]

- **Validate on a test cluster before upgrading production**, confirm no business impact.
- **NetworkPolicy behavior may change subtly between versions** — regression-test your core policies after upgrade.
- For major-version upgrades involving ConfigMap / CRD changes, run `cilium upgrade --pre-flight` per the official docs, or migrate manually.

:::

### Rollback to TKE Built-in CNI

Rolling back from cilium to TKE's native CNI (VPC-CNI or GR) inevitably disrupts traffic. Schedule a maintenance window.

**One-click uninstall script** (recommended — automates the first 4 steps):

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- uninstall
```

The script uninstalls the cilium helm release, deletes cni-config / APF rules, restores TKE network DaemonSet scheduling, and prints the remaining manual steps. To do it manually:

1. **Stop new scheduling**: cordon all node pools so no new Pods are placed during the rollback.
2. **Uninstall cilium**:
   ```bash
   helm uninstall cilium -n kube-system
   ```
3. **Clean up node residue**: on each node, manually clear cilium's BPF programs, CNI config, and iptables rules:
   ```bash
   # Run on each node
   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist
   sudo rm -f /etc/cni/net.d/*.cilium_bak  # Restore original CNI config that cilium renamed
   sudo iptables-save | grep -i cilium | wc -l  # Check leftover rules; manually -D if needed
   ```
4. **Re-enable TKE components**: in the console, re-enable `tke-cni-agent`, `kube-proxy`, `ip-masq-agent`, and any other addons you uninstalled.
5. **Reboot or recreate nodes**: the safest approach is to recreate all nodes to ensure a clean datapath (**this step still requires manual action regardless of whether you used the one-click script**).

:::warning

Rollback is a high-risk operation. **Strongly recommend recreating nodes** instead of manually cleaning them. If you must keep nodes (e.g. stateful workloads), rehearse the full procedure on a test cluster first.

:::

## FAQ

### How do I verify the cilium installation works?

Cilium provides two verification suites:

- **Connectivity tests** (~35 minutes, covers NetworkPolicy / Hubble / KPR / DNS / FQDN, 130+ scenarios):

  ```bash
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
  ```

- **Performance tests** (~3 minutes, runs TCP_RR / TCP_STREAM via netperf):

  ```bash
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
  ```

Full methodology, environment prerequisites, and per-mode benchmark results: [Cilium Connectivity Test](./appendix/connectivity-test.md) and [Cilium Performance Test](./appendix/performance-test.md).

### How to view all default installation configurations for Cilium?

Cilium's helm chart provides a huge number of customization options. The configurations given in this guide are only what's required for TKE — you can adjust many more as needed.

Run this to see all options:

```bash
helm show values cilium/cilium --version 1.19.4
```

### What if I can't reach the cilium helm repo?

During `helm` installation, helm fetches chart info from the cilium helm repo. If unreachable, the command fails.

Workaround: download the chart archive from a reachable environment:

```bash
$ helm pull cilium/cilium --version 1.19.4
$ ls cilium-*.tgz
cilium-1.19.4.tgz
```

Copy the archive to the machine running helm, then install using the local path:

```bash
helm upgrade --install cilium ./cilium-1.19.4.tgz \
  --namespace kube-system \
  -f values.yaml
```

### How to optimize for large-scale scenarios?

For large clusters (hundreds of nodes / tens of thousands of Pods), cilium defaults may show apiserver pressure, cilium-agent OOMs, and slow policy compilation. Tuning options include enabling CiliumEndpointSlice, APF rate limiting, raising client QPS, and trimming Security Identities — see [Cilium Tuning for Large-Scale Clusters](./appendix/large-scale-tuning.md) for the full guide.

### Why aren't GR clusters recommended?

GR (GlobalRouter) clusters carry a few constraints that don't pair well with cilium. **If you already have a GR cluster, going with the Overlay (GR) install is fine**, but **don't create a new GR cluster just to install cilium**:

1. **GR clusters mandate a ClusterCIDR at creation, and that CIDR is carved out of a VPC secondary CIDR**

   Every GR cluster requires a ClusterCIDR at creation time. That range is taken from the VPC's secondary CIDR list and pinned to the cluster.
   - If you choose Overlay (GR), Pod IPs come entirely from cilium's independent pool (e.g. `10.244.0.0/16`); **not a single IP from that ClusterCIDR is ever used by a Pod**
   - But the ClusterCIDR is still held by the GR cluster — **no other resource in the same VPC (CVMs, other clusters, CLBs, etc.) can use that range**. It's a permanently-burned secondary CIDR

2. **Node count is capped by ClusterCIDR**

   Every GR node carves a per-node subnet (default /24, 254 IPs) from the ClusterCIDR. Maximum nodes = `ClusterCIDR total IPs / per-node subnet size`, and ClusterCIDR is hard to expand later. VPC-CNI clusters have no such cap (node count tracks the VPC subnet capacity and you can attach more subnets).

3. **GR + Native Routing has severe compatibility issues with cilium chained CNI**

   Cross-node Pod-to-Pod broken, no L7 / DNS / toFQDNs NetworkPolicy support. Not offered in this guide. Details: [Why this guide does not offer GR Native Routing](./appendix/gr-native-not-recommended.md).

The takeaway: **for new cilium deployments, always pick a VPC-CNI cluster**:

- Want Pod IP == VPC IP (recognized natively by VPC routing / CLB / security groups / CCN)? → VPC-CNI + Native Routing
- Want to save VPC IPs, integrate IDC, or get full-featured cilium? → VPC-CNI + Overlay (also avoids GR's wasted ClusterCIDR)

### Can DataPlaneV2 be selected when creating a VPC-CNI cluster?

No.

When choosing the VPC-CNI network plugin, there's a DataPlaneV2 option:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

If selected, it deploys cilium components to the cluster (replacing kube-proxy). Installing cilium yourself on top of that causes conflicts. Additionally, the OS used by DataPlaneV2 is not compatible with the latest cilium. So do not check this option.

### How can Pods access the public network?

Pod public-internet egress behaves differently per network mode — case-by-case below.

**GR and VPC-CNI Overlay modes**: cilium enables IP masquerading by default (`enableIPv4Masquerade=true`), so Pod traffic leaving the node has already been SNAT'd to the node IP. As long as the node has public-internet capability (NAT gateway / node EIP / Egress Gateway), Pods can reach the public internet.

**VPC-CNI Native mode**: cilium **disables** IP masquerading by default (`enableIPv4Masquerade=false`), since Pod IPs are valid VPC IPs and east-west traffic just needs to be routed. But this means when a Pod tries to reach the public internet, the source IP is the Pod IP (allocated from the node's secondary ENI IP pool), and the secondary ENI has no EIP — so **even if the node has an EIP bound (an EIP only sits on the primary ENI), Pods cannot reach the public internet**. One of the following must be true:

1. **Configure a NAT gateway in the VPC** (cleanest, applies to all node subnets): add a route in the cluster's VPC route table forwarding outbound traffic to the NAT gateway, and make sure the route table is associated with the subnets used by the cluster. See [Accessing the Internet via NAT Gateway](https://www.tencentcloud.com/document/product/457/35427).
2. **Enable cilium's ip-masq-agent**: SNAT Pod traffic destined outside the VPC to the node IP so it egresses via the primary ENI + node EIP (a self-managed equivalent of TKE's built-in ip-masq-agent). Suitable when "the node already has an EIP and we want Pods to share its public bandwidth". See [Configure IP Masquerading](./masquerading.md).
3. **Enable Cilium Egress Gateway**: suitable for advanced cases like "route specific Pods through a specific public IP". See [Egress Gateway Practice](./egress-gateway.md).

### Image pull failure?

Most cilium images live on `quay.io`. If you didn't replace image addresses during install (as shown earlier in this guide), pulls can fail (e.g. nodes without internet access, or clusters in mainland China).

TKE provides the mirror registry `quay.tencentcloudcr.com` for `quay.io` images — just replace the `quay.io` domain with `quay.tencentcloudcr.com`. The pull goes over the intranet, requires no internet access, and has no regional restrictions.

If you've configured many additional install parameters, more image dependencies may be involved — without address replacement these may fail to pull. The following command replaces all cilium dependencies with TKE-intranet-reachable mirrors in one shot:

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
```

If you manage configuration in YAML, save the image override config as `image-values.yaml`:

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

When updating cilium, append `-f image-values.yaml` to include the image overrides:

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[Note]

The TKE mirror registry doesn't come with an SLA — occasionally pulls may fail, though retries usually succeed eventually.

For higher availability, you can [host Cilium images via TCR](./tcr.md) — sync cilium's image dependencies into your own [TCR registry](https://www.tencentcloud.com/products/tcr), then update the image override config to point at your synced addresses.

:::

### cilium-operator cannot become ready on super nodes?

cilium-operator uses hostNetwork and configures a readiness probe. On super nodes, hostNetwork-based probes don't pass, so cilium-operator never reports ready.

Super nodes are not recommended in clusters with cilium installed — remove them. If you must keep them, taint them and add matching tolerations to the Pods you want to schedule there.

### cilium-agent reports `operation not permitted` connecting to apiserver?

If during installation `k8sServiceHost` points to a CLB address (the CLB used for cluster intranet access — either the CLB VIP or a domain resolving to the CLB VIP), cilium-agent's connection to apiserver gets intercepted and forwarded by cilium itself instead of going through the CLB. cilium implements that forwarding via eBPF, which depends on eBPF data (endpoint list) stored in the kernel. Under certain conditions the eBPF data may be flushed — when it is, the endpoint list may be temporarily emptied, making cilium-agent unable to reach apiserver (error `operation not permitted`), so it can't see the real endpoint list to refresh the eBPF data — a circular dependency that only recovers after a node reboot.

So the recommendation is: do **not** configure `k8sServiceHost` with the apiserver's CLB address. Use the cluster's `169.254.x.x` apiserver address instead (`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`) — this is also a VIP, but cilium does not intercept and forward it, and it doesn't change once the cluster is created. For a more readable form, you can resolve a domain to this address and configure that domain in `k8sServiceHost`.

For full root-cause analysis, reproduction steps, and the upstream cilium PR link, see [Troubleshooting: APIServer reports operation not permitted](./troubleshooting/connect-apiserver-operation-not-permitted.md).

## Further Reading

Design rationale and operational guides have been split into standalone articles under the [Cilium Appendix](./appendix) directory:

- [Cilium Tuning for Large-Scale Clusters](./appendix/large-scale-tuning.md)
- [Verified Node Operating Systems](./appendix/verified-os.md)
- [Cilium Connectivity Test](./appendix/connectivity-test.md)
- [Cilium Performance Test](./appendix/performance-test.md)
- [Why Native Routing mode needs local-router-ipv4](./appendix/local-router-ipv4.md)
- [Why Native Routing disables sysctlfix while Overlay enables it](./appendix/sysctlfix.md)
- [Cilium Host Routing: Legacy vs BPF](./appendix/host-routing.md)
- [Why this guide does not offer GR Native Routing](./appendix/gr-native-not-recommended.md)

## External References

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
