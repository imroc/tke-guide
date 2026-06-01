# Installing Cilium

This article describes how to install cilium in a TKE cluster, with support for the following network modes:

- **Native Routing**: Coexists with TKE CNI. Pods use IPs allocated by TKE; cilium provides NetworkPolicy, observability, kube-proxy replacement, and other enhancements.
- **Overlay (vxlan tunnel)**: Completely replaces all TKE CNIs. Pod IPs do not consume underlay IPs, suitable for scenarios where IP allocation is difficult, or as a replacement for TKE's built-in CiliumOverlay mode to get full cilium functionality.

Each mode supports both VPC-CNI and GlobalRouter (GR) base clusters, for a total of 4 combinations. **VPC-CNI clusters are recommended** — better network performance and no node count limit.

:::note[How to Choose]

| Comparison Item       | Native Routing (VPC-CNI) ⭐ | Native Routing (GR)                      | Overlay (VPC-CNI) ⭐                          | Overlay (GR)                                       |
| --------------------- | --------------------------- | ---------------------------------------- | --------------------------------------------- | -------------------------------------------------- |
| Network Performance   | Optimal                     | Good (extra bridge hop)                  | Slight overhead (vxlan encap)                 | Slight overhead (vxlan encap)                      |
| Pod IP Range          | VPC IP                      | VPC secondary CIDR IP                    | Independent CIDR, doesn't consume VPC IP      | Independent CIDR, doesn't consume VPC IP           |
| IP Capacity Expansion | Add a VPC-CNI subnet        | Add a GR CIDR (VPC secondary CIDR)       | Append CIDR to `clusterPoolIPv4PodCIDRList`   | Same as left                                       |
| Node Count Limit      | None                        | Limited by ClusterCIDR                   | None                                          | Limited by GR ClusterCIDR (GR cluster's own limit) |
| External Pod Access   | Directly routable           | Routable within VPC                      | Not directly routable, via Service/Ingress    | Not directly routable                              |
| L7/DNS NetworkPolicy  | ✅ Fully supported          | ⚠️ Not supported (cbr0 bridge limit)     | ✅ Fully supported                            | ✅ Fully supported                                 |
| Node Pool Requirement | None                        | ⚠️ Must add cilium agent-not-ready taint | None                                          | None                                               |
| Use Cases             | General (recommended)       | Existing GR cluster                      | IP shortage, IDC, full-featured cilium (rec.) | Same as left, but existing GR cluster              |

See the appendix for details on the two GR limitations:

- ⚠️ Native Routing (GR) does not support L7/DNS NetworkPolicy → [Why GR Native Routing does not support L7/DNS NetworkPolicy](#why-gr-native-routing-does-not-support-l7dns-networkpolicy)
- ⚠️ Native Routing (GR) node pools must add the cilium agent-not-ready taint → [Why Native Routing (GR) node pools must add the cilium agent-not-ready taint](#why-native-routing-gr-node-pools-must-add-the-cilium-agent-not-ready-taint)

:::

## Preparation

### Prepare TKE Cluster

:::info[Note]

Installing cilium is a major change to the cluster. Do not install it in a cluster running production workloads — installation may disrupt online services. It is recommended to install cilium in a newly created TKE cluster.

:::

In the [TKE Console](https://console.cloud.tencent.com/tke2/cluster), create a TKE cluster with the following key options:

- Container network plugin: choose **VPC-CNI Shared ENI Multi-IP** or **GlobalRouter** based on the comparison table above.
- Cluster type: Standard cluster.
- Kubernetes version: 1.32 or later, latest is recommended (see [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)).
- Operating system: recommend **TencentOS 4** or **Ubuntu 24.04**. Minimum: Linux kernel >= 5.10 (see [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)). For verified OS images see [Verified Node Operating Systems](#verified-node-operating-systems).
- Nodes: do not add any regular or native nodes before installation, to avoid leftover rules and configuration. Add them after installation completes.
- Base addons: uncheck the **TKE built-in ip-masq-agent** component to avoid conflict with cilium's built-in ipMasqAgent. Native Routing (GR) mode will enable cilium's built-in ipMasqAgent later (different components — do not confuse them).
- Extension addons: if you plan to use Karpenter node pools, enable the Karpenter addon; otherwise skip (see node pool selection below).

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
  # Container network plugin: VPC-CNI / GR
  network_type = "VPC-CNI"
  # Enable apiserver access
  cluster_internet = true
  # Expose apiserver via intranet CLB — specify the CLB subnet ID
  cluster_intranet_subnet_id = "subnet-xxx"
  # Do not install ip-masq-agent (disable_addons requires tencentcloud provider >= 1.82.33)
  disable_addons = ["ip-masq-agent"]
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

You can use a script that auto-detects the cluster environment and guides the installation. Download first, then run:

```bash
curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh install-cilium
```

If the GitHub URL is not reachable, use the site mirror:

```bash
curl -sfL https://imroc.cc/tke/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh install-cilium
```

The script auto-detects the cluster's network mode, guides you through choosing a mode and version, then performs the installation. During installation you can optionally enable [Egress Gateway](egress-gateway.md) and [Nodelocal DNSCache](with-node-local-dns.md). For manual installation, follow the steps below.

:::tip[Why not `curl ... | bash`?]

The `install-cilium` subcommand is interactive (you have to choose the installation mode). With `curl ... | bash`, bash's stdin is consumed by curl's output, so the script's `read` cannot receive keyboard input and the script exits immediately (the menu prints, then the script ends). That's why this guide always uses "download then execute".

If you really want a one-liner, you can preset parameters via environment variables to skip interaction (no stdin needed — see the non-interactive mode notes in the script comments):

```bash
ROUTING_MODE=native CILIUM_VERSION=1.19.4 \
  curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh | bash -s install-cilium
```

:::

### Uninstall TKE Components

All modes need kube-proxy uninstalled (cilium replaces it):

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

For all modes **except Native Routing (GR)**, also uninstall tke-cni-agent (to avoid CNI config conflicts):

```bash
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[Notes]

1. Using a non-matching nodeSelector to keep the DaemonSet off all nodes is equivalent to uninstalling, and leaves a fallback path. For kube-proxy this is currently the only safe way — directly deleting kube-proxy will block future cluster upgrades.
2. Native Routing (GR) mode must keep tke-cni-agent, because it's responsible for copying the bridge and other CNI binaries to nodes. In this mode cilium's default `cni.exclusive=true` automatically renames the multus config to `.cilium_bak` to disable it, so there is no conflict.
3. As noted above, don't add nodes before installing cilium. If for some reason regular or native nodes were added before installation, restart those existing nodes to clear any leftover rules and configuration.
4. If you forgot to uncheck ip-masq-agent during cluster creation, uninstall it manually:
   ```bash
   kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
   ```

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
<TabItem value="native-gr" label="Native Routing (GR)">

Two changes are required for tke-bridge-agent:

1. **Change the CNI config output directory** — from the multus subdirectory to the CNI root directory, so cilium can discover and append to the bridge config via `chainingTarget`.
2. **Disable the portmap plugin** (`--port-mapping=false`) — cilium's `kubeProxyReplacement=true` already includes HostPort forwarding, while the portmap plugin depends on the `KUBE-MARK-MASQ` iptables chain created by the (now uninstalled) kube-proxy. If you don't disable it, Pods with hostPort will fail to be created (CNI portmap call fails).

```bash
# Get current full args
CURRENT_ARGS=$(kubectl -n kube-system get ds tke-bridge-agent -o jsonpath='{.spec.template.spec.containers[0].args}')
# 1. Replace the CNI config directory path
PATCHED_ARGS=$(echo "$CURRENT_ARGS" | sed 's|/host/etc/cni/net.d/multus|/host/etc/cni/net.d|g')
# 2. Append --port-mapping=false to disable the portmap plugin (skip if already present)
if ! echo "$PATCHED_ARGS" | grep -q 'port-mapping=false'; then
  PATCHED_ARGS=$(echo "$PATCHED_ARGS" | sed 's/\]$/,"--port-mapping=false"]/')
fi
kubectl -n kube-system patch ds tke-bridge-agent --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${PATCHED_ARGS}}]"
```

Wait for the tke-bridge-agent rolling restart to finish:

```bash
kubectl -n kube-system rollout status ds/tke-bridge-agent --timeout=120s
```

:::tip[Note]

After cilium is installed, `cni.exclusive=true` (default) will automatically rename `00-multus.conf` to `00-multus.conf.cilium_bak` — no manual deletion needed.

:::

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
<TabItem value="native-gr" label="Native Routing (GR)">

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
  --set operator.tolerations[1].key="node.kubernetes.io/not-ready",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[2].operator="Exists" \
  --set cni.chainingMode=generic-veth \
  --set cni.chainingTarget=tke-bridge \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set devices=eth+ \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

After installation, also create the `ip-masq-agent` ConfigMap to specify which CIDRs should be excluded from SNAT. You can refer to the auto-generated `ip-masq-agent-config` ConfigMap from TKE (which contains the VPC CIDR plus all secondary CIDRs) for the `NonMasqueradeCIDRs` values:

```bash
# View the NonMasqueradeCIDRs that TKE auto-generates
kubectl -n kube-system get cm ip-masq-agent-config -o jsonpath='{.data.config}'
```

Fill those CIDRs into cilium's `ip-masq-agent` ConfigMap:

```yaml title="ip-masq-agent.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
    - <VPC CIDR>                  # e.g. 10.0.0.0/16 — Pod traffic to VPC keeps source IP
    - <VPC secondary CIDR (GR)>   # e.g. 172.16.0.0/16 — Pod-to-Pod traffic keeps source IP
    - 169.254.0.0/16              # TKE metadata / apiserver VIP / COS / image registry — MUST preserve source IP
    masqLinkLocal: false          # Required so 169.254.0.0/16 hits the nonMasq rule
```

:::tip[About 169.254.0.0/16]

TKE places several critical services on this range: apiserver VIP, instance metadata service (e.g. csi-cbs controller reads instance metadata), COS, image registry, etc. Some of these components use hostAlias and bypass DNS resolution. If Pod traffic to these addresses is SNATed, the source IP is lost — and some services (e.g. a COS bucket with an IP allowlist) may break.

:::

```bash
kubectl apply -f ip-masq-agent.yaml
```

:::tip[Differences vs. VPC-CNI chaining]

| Parameter                                    | Description                                                                                                       |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `cni.chainingTarget=tke-bridge`              | cilium auto-watches the CNI config named `tke-bridge` and appends itself — adapts to per-node PodCIDR differences |
| No `cni.customConf` / `cni.configMap` needed | No manual CNI ConfigMap                                                                                           |
| `enableIPv4Masquerade=true`                  | GR Pod IPs need SNAT to node IP for things like CVM metadata access                                               |
| Do **not** uninstall `tke-cni-agent`         | Required to copy the bridge and other CNI binaries to nodes                                                       |

:::

:::warning[GR clusters can no longer dynamically enable VPC-CNI after installing cilium]

GR clusters natively support dynamically enabling VPC-CNI (GR + VPC-CNI coexistence), but **once you install cilium with this guide's setup, that feature is no longer usable**. cilium chaining takes over all Pod networking via multus's `defaultDelegates=tke-bridge`. Even if you create Pods with the `tke.cloud.tencent.com/networks: tke-route-eni` annotation, the IP still comes from the GR ClusterCIDR — not the VPC-CNI subnet. If you need VPC-CNI coexistence, use a VPC-CNI cluster directly.

:::

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
  # Must be true for native routing — routes Pod traffic directly via veth device
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
  <TabItem value="native-gr" label="Native (GR)">

Native Routing (GR) mode-specific parameters:

```yaml showLineNumbers title="native-gr-values.yaml"
# Use native routing
routingMode: "native"
endpointRoutes:
  enabled: true
ipam:
  # Pod IP allocation handled by tke-bridge-agent
  mode: "delegated-plugin"
# GR Pod IPs need SNAT to node IP for things like CVM metadata access
enableIPv4Masquerade: true
bpf:
  masquerade: true
ipMasqAgent:
  enabled: true
# Attach cilium eBPF programs to all eth* interfaces
devices: eth+
cni:
  # Use generic-veth + chainingTarget to auto-adapt to tke-bridge's CNI config
  chainingMode: generic-veth
  chainingTarget: tke-bridge
  externalRouting: true
extraConfig:
  local-router-ipv4: 169.254.32.16
# Disable sysctlfix. See FAQ.
sysctlfix:
  enabled: false
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

For the **full list of verified OS images**, see the appendix [Verified Node Operating Systems](#verified-node-operating-systems) at the end of this document.

:::

:::warning[Native Routing (GR) node pools MUST add the cilium taint]

When using **Native Routing (GR)**, you **must** add the following taint to nodes when creating node pools (in **Advanced Settings** in the console, or via the terraform snippet below):

```
node.cilium.io/agent-not-ready=true:NoSchedule
```

See the appendix [Why Native Routing (GR) node pools must add the cilium agent-not-ready taint](#why-native-routing-gr-node-pools-must-add-the-cilium-agent-not-ready-taint) for the reason.

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
5. For **Operating System**, choose any image from [Verified Node Operating Systems](#verified-node-operating-systems) (recommend **TencentOS 4** or **Ubuntu 24.04**). You may also use other CVM public images or custom images that meet the kernel requirement (kernel >= 5.10) — single-node validation is recommended first.
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

## Verify Cilium

After installation completes and nodes are added, verify cilium functionality:

### Quick Test

Use the script to run cilium connectivity test (skips public-network tests automatically and uses TKE-reachable images):

```bash
curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh e2e-test
```

If GitHub is unreachable, use the site mirror:

```bash
curl -sfL https://imroc.cc/tke/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh e2e-test
```

### Manual Test

You need [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) installed first, then run:

```bash
cilium connectivity test \
  --test '!/pod-to-world' \
  --test '!/pod-to-cidr' \
  --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
  --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
  --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1
```

:::tip[Notes]

- `--test '!/pod-to-world'` and `--test '!/pod-to-cidr'` skip public-network connectivity tests (nodes may not have internet bandwidth, and default public targets may be blocked in some regions).
- Image addresses are replaced with TKE-reachable mirrors (`quay.io` → `quay.tencentcloudcr.com`, `registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`).

:::

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
./cilium.sh e2e-test
```

:::warning[Upgrade Cautions]

- **Validate on a test cluster before upgrading production**, confirm no business impact.
- **NetworkPolicy behavior may change subtly between versions** — regression-test your core policies after upgrade.
- For major-version upgrades involving ConfigMap / CRD changes, run `cilium upgrade --pre-flight` per the official docs, or migrate manually.

:::

### Rollback to TKE Built-in CNI

Rolling back from cilium to TKE's native CNI (VPC-CNI or GR) inevitably disrupts traffic. Schedule a maintenance window:

1. **Stop new scheduling**: cordon all node pools so no new Pods are placed during the rollback.
2. **Uninstall cilium**:
   ```bash
   helm uninstall cilium -n kube-system
   kubectl -n kube-system delete cm ip-masq-agent  # If GR mode was used
   ```
3. **Clean up node residue**: on each node, manually clear cilium's BPF programs, CNI config, and iptables rules:
   ```bash
   # Run on each node
   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist
   sudo rm -f /etc/cni/net.d/*.cilium_bak  # Restore original CNI config that cilium renamed
   sudo iptables-save | grep -i cilium | wc -l  # Check leftover rules; manually -D if needed
   ```
4. **Re-enable TKE components**: in the console, re-enable `tke-cni-agent`, `kube-proxy`, `ip-masq-agent`, and any other addons you uninstalled.
5. **Reboot or recreate nodes**: the safest approach is to recreate all nodes to ensure a clean datapath.

:::warning

Rollback is a high-risk operation. **Strongly recommend recreating nodes** instead of manually cleaning them. If you must keep nodes (e.g. stateful workloads), rehearse the full procedure on a test cluster first.

:::

## Appendix

The appendix is organized into three categories:

- **[Design Rationale](#design-rationale)**: "Why is it done this way" — understanding these helps with edge cases.
- **[FAQ](#faq)**: "Can I do X / How do I / What if it errors" type questions.
- **[References](#references)**: Reference data such as the verified OS list.

### Design Rationale

#### Why does Native Routing mode need local-router-ipv4?

In Native Routing mode, cilium creates a `cilium_host` virtual interface on every node and requires an IP for it. Since cilium does not allocate Pod IPs in Native Routing mode (TKE CNI does), `local-router-ipv4` must be set manually to an IP that won't conflict. `169.254.32.16` is in the link-local range and doesn't collide with any IP on TKE, so it's the chosen value.

**Both Native Routing (VPC-CNI) and Native Routing (GR) need this configuration**:

- VPC-CNI mode: Pods are attached directly to ENIs and IPs come from VPC-CNI — cilium has no Pod IP source information at all.
- GR mode: Pod IPs are allocated by tke-bridge from the node's PodCIDR, and each node's PodCIDR is different. Although tke-bridge's gateway IP (e.g. `<PodCIDR>.1`) is already in use by the node route, cilium cannot reuse it; using the link-local `169.254.32.16` avoids any PodCIDR collision and keeps configuration consistent across nodes.

Overlay mode does not need this configuration because cilium manages Pod IP allocation itself (cluster-pool IPAM) and automatically assigns an IP to `cilium_host`.

#### Why does Native Routing mode disable sysctlfix while Overlay enables it?

Cilium enables `sysctlfix` by default. It uses an init container to write `/etc/sysctl.d/99-zzz-override_cilium.conf`, setting lxc interface `rp_filter` to 0, and **restarts `systemd-sysctl.service`** to apply.

- **Native Routing (VPC-CNI)**: cilium coexists with VPC-CNI; Pod IPs come from the VPC and return traffic enters via eth0. Restarting `systemd-sysctl.service` re-applies the OS defaults — and TKE's OS images default eth0 `rp_filter` to 1 (strict mode), under which Pod IPs not matching on eth0 are dropped, breaking the network. **Must disable** sysctlfix (`--set sysctlfix.enabled=false`).
- **Native Routing (GR)**: cilium chaining takes over all Pod networking, no lxc interface needs rp_filter adjustment, and enabling sysctlfix in our tests didn't break the network. However, to stay consistent with Native Routing (VPC-CNI) and avoid edge issues from OS sysctl default changes, **we still disable** sysctlfix.
- **Overlay mode**: Pod IPs come from cilium's own CIDR; cross-node traffic goes through vxlan tunnels; Pod IPs are never seen on eth0, so eth0 `rp_filter=1` is fine. But host→same-node-Pod return traffic goes through the lxc interface, which requires `lxc*.rp_filter=0` or it gets dropped — so Overlay mode **must enable** sysctlfix (enabled by default — no explicit setting needed).

**Troubleshooting**: if Overlay mode shows localhost endpoint 0/1 in `cilium-health status` (host→Pod unreachable), sysctlfix likely didn't take effect:

```bash
# Check rp_filter on all lxc interfaces (including cilium's health-check interface lxc_health and Pod interfaces lxcXXXX)
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'
# If any are non-zero, check whether the cilium sysctlfix init container ran successfully
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

#### Why GR Native Routing does not support L7/DNS NetworkPolicy

This is a **known limitation** of cilium in generic-veth chaining mode. The official cilium documentation explicitly lists "Layer 7 Policy" among the Limitations of this mode:

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- Tracking issue: [cilium/cilium#12454 - Proxy redirect issue when running Cilium on top of Calico (CNI-Chaining)](https://github.com/cilium/cilium/issues/12454) (packet mark conflict causing proxy redirect failure — same root cause as our scenario)

Specifically for TKE GR mode: while coexisting with tke-bridge, Pod traffic passes through the Linux bridge `cbr0`. cilium marks DNS traffic via BPF and relies on iptables TPROXY to dispatch packets to the cilium DNS proxy socket — but bridge-forwarded packets don't really enter IP routing / socket lookup, so the DNS proxy never sees the traffic. Pods selected by policies with `toFQDNs` or `rules.dns` experience DNS query timeouts.

VPC-CNI Native Routing does not go through cbr0 (Pods are attached directly to ENIs), so this issue does not occur. If your business needs `toFQDNs` on a GR cluster, choose Overlay mode. See [NetworkPolicy Practice - Mode Compatibility](networkpolicy.md#mode-compatibility).

#### Why Native Routing (GR) node pools must add the cilium agent-not-ready taint

In GR mode, every node has a different PodCIDR, and the CNI config is dynamically generated per-node by tke-bridge-agent (containing that node's specific subnet info). cilium cannot use a unified CNI config to take over all nodes the way VPC-CNI or Overlay modes do — it can only watch tke-bridge's generated config via `chainingTarget` and append itself. This creates a timing problem: when a node joins, tke-bridge-agent writes the CNI config first; kubelet sees CNI as ready and immediately schedules Pods; but at this moment cilium agent has not finished starting, so Pods use the raw tke-bridge CNI without cilium-cni enhancement — missing masquerade, NetworkPolicy, etc.

Adding the `node.cilium.io/agent-not-ready=true:NoSchedule` taint ensures business Pods are only scheduled after cilium agent is ready (cilium agent automatically removes this taint when it starts).

Native Routing (VPC-CNI) and Overlay modes **do not need** this taint:

- Native Routing (VPC-CNI) uses `cni.customConf=true` with a unified CNI config (one ConfigMap shared by all nodes, no per-node dynamic generation), so there's no "other CNI writes first" race.
- Overlay mode has cilium fully own CNI — kubelet won't successfully create Pod sandboxes until cilium CNI is ready.

### FAQ

#### How to view all default installation configurations for Cilium?

Cilium's helm chart provides a huge number of customization options. The steps above show only the configurations required for TKE — there are plenty more you can adjust as needed.

Run this to see all options:

```bash
helm show values cilium/cilium --version 1.19.4
```

#### What if I can't reach the cilium helm repo?

During `helm` installation, helm fetches chart info from the cilium helm repo. If it's unreachable, the command fails.

Workaround: download the chart archive from a reachable environment:

```bash
$ helm pull cilium/cilium --version 1.19.4
$ ls cilium-*.tgz
cilium-1.19.4.tgz
```

Copy the archive to the machine running helm, then install referencing the local path:

```bash
helm upgrade --install cilium ./cilium-1.19.4.tgz \
  --namespace kube-system \
  -f values.yaml
```

#### How to optimize for large-scale scenarios?

For large clusters (hundreds of nodes / tens of thousands of Pods), consider the following:

**1. Enable CiliumEndpointSlice (recommended)**

Aggregates multiple CiliumEndpoint resources into a single CiliumEndpointSlice, significantly reducing watch/list pressure on the apiserver:

```yaml
ciliumEndpointSlice:
  enabled: true
```

This feature was introduced in 1.11 and remains Beta in 1.19 ([tracking Stable progress](https://github.com/cilium/cilium/issues/31904)).

**2. Tune K8s client rate limits**

cilium-agent defaults to QPS=10, Burst=20 — possibly a bottleneck at scale; cilium-operator defaults are QPS=100, Burst=200:

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

**3. Reduce identity count**

cilium assigns a Security Identity to each unique label combination. Too many identities increase memory and policy computation overhead. Exclude irrelevant labels to reduce identity bloat:

```yaml
# Exclude high-cardinality labels to reduce Identity bloat
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

**4. Configure agent / operator resources**

Default resource configs are conservative — for large clusters, set explicit values:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
operator:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

**5. Use API Priority and Fairness (APF)**

The install script in this guide creates cilium-specific APF FlowSchema and PriorityLevelConfiguration by default, preventing cilium's list requests from impacting other components. For manual installs, set this up the same way.

**6. Dynamic BPF map sizing**

By default, BPF map capacity is auto-calculated based on system memory. To adjust the ratio manually:

```yaml
bpf:
  mapDynamicSizeRatio: 0.0025
```

#### Can VPC-CNI be dynamically enabled on a GR cluster after installing cilium?

Not recommended. GR clusters natively support enabling VPC-CNI for coexistence, but **with this guide's cilium setup installed, this feature is no longer actually usable**:

- cilium chaining takes over all Pod networking via multus config (`defaultDelegates=tke-bridge`).
- Even when you create Pods with the `tke.cloud.tencent.com/networks: tke-route-eni` annotation, IPs still come from the GR ClusterCIDR (not the VPC-CNI subnet) — the VPC-CNI path is never actually used.
- The `EnableVpcCniNetworkType` API call succeeds and the components deploy, but it has no real effect on Pod networking.

If your business truly needs VPC-CNI, use a **VPC-CNI cluster with Native Routing** directly — don't pick a GR cluster.

#### Can DataPlaneV2 be selected when creating a VPC-CNI cluster?

No.

When choosing VPC-CNI network plugin, there's a DataPlaneV2 option:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

If selected, it deploys cilium components to the cluster (replacing kube-proxy). Installing cilium yourself on top of that causes conflicts. Additionally, the OS used by DataPlaneV2 is not compatible with the latest cilium. So do not check this option.

#### How can Pods access the public network?

Create a public-network NAT gateway, then add a route in the cluster's VPC route table forwarding outbound traffic to the NAT gateway, and make sure the route table is associated with the subnets used by the cluster. See [Accessing the Internet via NAT Gateway](https://www.tencentcloud.com/document/product/457/35427).

If your nodes themselves have public bandwidth and you want Pods to use the node's public access, enable cilium's IP Masquerade. See [Configure IP Masquerading](./masquerading.md).

For more advanced egress needs (e.g. routing certain Pods through a specific public IP), see [Egress Gateway Practice](egress-gateway.md).

#### Image pull failure?

Most cilium images live on `quay.io`. If you didn't replace image addresses during install, pulls can fail (e.g. nodes without internet access, or clusters in mainland China).

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

For higher availability, you can [host Cilium images via TCR](tcr.md) — sync cilium's image dependencies into your own [TCR registry](https://www.tencentcloud.com/products/tcr), then update the image override config to point at your synced addresses.

:::

#### cilium-operator cannot become ready on super nodes?

cilium-operator uses hostNetwork and configures a readiness probe. On super nodes, hostNetwork-based probes don't pass, so cilium-operator never reports ready.

Super nodes are not recommended in clusters with cilium installed — remove them. If you must keep them, taint them and add matching tolerations to the Pods you want to schedule there.

#### cilium-agent reports `operation not permitted` connecting to apiserver?

If during installation `k8sServiceHost` points to a CLB address (CLB used for cluster intranet access — either the CLB VIP or a domain resolving to the CLB VIP), cilium-agent's connection to apiserver gets intercepted and forwarded by cilium itself instead of going through the CLB. cilium implements that forwarding via eBPF, which depends on eBPF data (endpoint list) stored in the kernel. Under certain conditions, the eBPF data may be flushed — and when it is, the endpoint list may be temporarily emptied, making cilium-agent unable to reach apiserver (error `operation not permitted`), so it can't see the real endpoint list to refresh the eBPF data — a circular dependency that only recovers after a node reboot.

So the recommendation is: do **not** configure `k8sServiceHost` with the apiserver's CLB address. Use the cluster's `169.254.x.x` apiserver address instead (`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`) — this is also a VIP, but cilium does not intercept and forward it, and it doesn't change once the cluster is created. For a more readable form, you can resolve a domain to this address and configure that domain in `k8sServiceHost`.

### References

#### Verified Node Operating Systems

The table below lists OS images and kernels that have been hands-on verified across all 4 installation modes (VPC-CNI/GR × Native/Overlay) covered in this guide.

**Test method**: for each installation mode, cilium 1.19.4 was deployed with Egress Gateway and Nodelocal DNSCache. Verified that `cilium-health status` shows all nodes reachable and that `coredns` / `node-local-dns` pass health checks.

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

For OS not in this list, validate on a single node first.

## External References

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
