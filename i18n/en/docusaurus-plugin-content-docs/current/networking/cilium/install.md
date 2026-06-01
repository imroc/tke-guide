# Installing Cilium

This article describes how to install Cilium in a TKE cluster, supporting the following network modes:

- **Native Routing**: Coexists with TKE CNI, Pods use IPs allocated by TKE, Cilium provides enhanced capabilities such as NetworkPolicy, observability, and kube-proxy replacement.
- **Overlay (vxlan tunnel)**: Completely replaces all TKE CNIs, Pod IPs don't consume underlay IPs, suitable for scenarios where IP allocation is difficult, or to replace TKE's built-in CiliumOverlay network mode for full functionality.

:::tip[How to Choose]

| Comparison Item     | Native Routing (VPC-CNI) | Native Routing (GR)      | Overlay (vxlan)                                                   |
| ------------------- | ------------------------ | ------------------------ | ----------------------------------------------------------------- |
| Network Performance | Optimal (no extra encap) | Optimal (no extra encap) | Slight overhead (vxlan encapsulation)                             |
| Pod IP Range        | Uses VPC IPs             | Uses GR PodCIDR IPs      | Independent CIDR, doesn't consume VPC/GR IPs                      |
| External Pod Access | Directly routable        | Routable within VPC      | Not directly routable, requires Service/Ingress                   |
| Node Count Limit    | None                     | Limited by ClusterCIDR   | GR limited, VPC-CNI unlimited                                     |
| Use Cases           | General scenarios        | General scenarios        | IP resource shortage, managing IDC clusters, full-featured cilium |
| Base Cluster        | VPC-CNI network mode     | GlobalRouter mode        | GlobalRouter or VPC-CNI mode                                      |

:::

## Preparation

### Prepare TKE Cluster

:::info[Note]

Installing Cilium is a significant change to the cluster. It is not recommended to install it in a cluster with production workloads running, as the installation process may affect the normal operation of online services. It is recommended to install Cilium in a newly created TKE cluster.

:::

Create a TKE cluster in the [Container Service Console](https://console.cloud.tencent.com/tke2/cluster), common options:

- Cluster Type: Standard Cluster
- Kubernetes Version: No lower than 1.32, recommended to choose the latest version (refer to [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)).
- Operating System: Recommended **TencentOS 4** or **Ubuntu 24.04**. Minimum requirement: Linux kernel >= 5.10 (refer to [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)). For verified OS list, see [Verified Node Operating Systems](#verified-node-operating-systems).
- Nodes: Do not add any regular nodes or native nodes to the cluster before installation to avoid residual rules and configurations. Add them after the installation is complete.
- Basic Components: Uncheck ip-masq-agent to avoid conflicts.

The following are the **mode-specific options**:

<Tabs>
<TabItem value="native-vpccni" label="Native Routing (VPC-CNI)" default>

- Container Network Plugin: **VPC-CNI shared NIC multi-IP**.
- Enhanced Components: If you want to use Karpenter node pools, check to install the Karpenter component; otherwise, no need to check (refer to the node pool selection section later).

</TabItem>
<TabItem value="native-gr" label="Native Routing (GR)">

- Container Network Plugin: **GlobalRouter**.

:::info[Note]

GR mode clusters have the limitation of ClusterCIDR constraining the number of nodes (ClusterCIDR IPs are split and assigned to each node as PodCIDR).

:::

</TabItem>
<TabItem value="overlay" label="Overlay">

Overlay mode supports two base cluster types:

- **Option 1: GlobalRouter (GR) Cluster** — Recommended, simplest to operate, but limited by ClusterCIDR for node count.
- **Option 2: VPC-CNI Cluster** — No node count limitation, requires additional steps.

Choose **GlobalRouter** or **VPC-CNI shared NIC multi-IP** as the container network plugin depending on the option.

When using overlay mode with a VPC-CNI cluster, VPC-CNI components (tke-eni-ipamd, etc.) remain running, but you need to additionally disable `add-pod-eni-ip-limit-webhook` (otherwise Pods will be automatically injected with `tke.cloud.tencent.com/eni-ip` resource requests, causing ip-scheduler to block scheduling):

```bash
kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook
```

</TabItem>
</Tabs>

After the cluster is successfully created, you need to enable cluster access to expose the cluster's apiserver so that the helm command can operate the TKE cluster normally when installing Cilium later. Refer to [How to Enable Cluster Access](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4).

Depending on your situation, choose to enable internal network access or public network access, mainly depending on whether the network where the helm command is located can communicate with the VPC where the TKE cluster is located:

1. If it can communicate, enable internal network access.
2. If it cannot communicate, enable public network access. Currently, enabling public network access requires deploying the `kubernetes-proxy` component to the cluster as a relay, which depends on the existence of nodes in the cluster (this dependency may be removed in the future, but currently it is required). If you want to use public network access, it is recommended to add a super node to the cluster first so that the `kubernetes-proxy` pod can be scheduled normally, and then delete this super node after Cilium installation is complete.

If using Terraform to create a cluster, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  # Standard Cluster
  cluster_deploy_type = "MANAGED_CLUSTER"
  # Kubernetes Version >= 1.32
  cluster_version = "1.32.2"
  # Operating System (OsName), see appendix for full verified OS list
  cluster_os = "tlinux4_x86_64_public"
  # Container Network Plugin: VPC-CNI
  network_type = "VPC-CNI"
  # Enable Cluster APIServer Access
  cluster_internet = true
  # Expose APIServer through internal CLB, need to specify the subnet ID where CLB is located
  cluster_intranet_subnet_id = "subnet-xxx"
  # Do not install ip-masq-agent (disable_addons requires tencentcloud provider version 1.82.33+)
  disable_addons = ["ip-masq-agent"]
  # To use the Karpenter node pool, the Karpenter component must be installed. (cluster-autoscaler and karpenter are mutually exclusive,
  # enabling this component will prevent cluster-autoscaler from being installed, thus disabling the scaling functionality of the native
  # node pool and the regular node pool, if you are not using a Karpenter node pool, you can omit the following code. For specific node
  # pool selection, please refer to the section on "Create New Node Pools" below).
  extension_addon {
    name = "karpenter"
    param = jsonencode({
      "kind" : "App", "spec" : { "chart" : { "chartName" : "karpenter" } }
    })
  }
  # Omit other necessary but unrelated configurations
}
```

### Environment Preparation

Installing cilium requires a machine (local computer or bastion host) that can connect to the cluster. Ensure the following tools are installed:

1. **kubectl** — connect to the cluster and run K8s operations (refer to [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)).
2. **helm** — install the cilium chart (refer to [Install Helm](https://helm.sh/docs/intro/install/)).
3. **cilium CLI** (optional) — needed for running connectivity tests (refer to [Install cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)).

Configure a kubeconfig that can connect to the cluster (refer to [Connecting to Cluster](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)), then add cilium's helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

## Install Cilium

### Configure CNI (VPC-CNI Chaining Mode Only)

:::info[Note]

This step only applies to Native Routing (VPC-CNI) mode. GR chaining mode and Overlay mode do not require this step — GR chaining automatically appends Cilium to the existing configuration via `chainingTarget`, and Overlay mode lets Cilium manage the CNI configuration on its own.

:::

Prepare the CNI configuration ConfigMap `cni-config.yaml` for Cilium:

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

Create the CNI ConfigMap:

```bash
kubectl apply -f cni-config.yaml
```

### Install Cilium using Helm

Execute the installation using Helm:

:::info[Note]

`k8sServiceHost` is the apiserver address, obtained dynamically through command.

:::

<Tabs>
<TabItem value="native" label="Native Routing (VPC-CNI)" default>

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

GR mode uses `chainingTarget` to let Cilium automatically watch and append to the CNI configuration generated by tke-bridge-agent, without needing to manually create a CNI ConfigMap.

Pre-install steps required:

1. Patch tke-bridge-agent — two changes:
   - **Change CNI config output directory** (from multus subdirectory to CNI root) so cilium can discover and append to the bridge config via `chainingTarget`.
   - **Disable the portmap plugin** (`--port-mapping=false`): Cilium's `kubeProxyReplacement=true` already provides HostPort forwarding. The portmap plugin depends on the `KUBE-MARK-MASQ` iptables chain created by kube-proxy, which has been disabled. Without this flag, creating Pods with hostPort fails (CNI portmap call errors out).
   ```bash
   # Get current full args
   CURRENT_ARGS=$(kubectl -n kube-system get ds tke-bridge-agent -o jsonpath='{.spec.template.spec.containers[0].args}')
   # 1. Replace CNI config directory path
   PATCHED_ARGS=$(echo "$CURRENT_ARGS" | sed 's|/host/etc/cni/net.d/multus|/host/etc/cni/net.d|g')
   # 2. Append --port-mapping=false to disable portmap (skip if already set)
   if ! echo "$PATCHED_ARGS" | grep -q 'port-mapping=false'; then
     PATCHED_ARGS=$(echo "$PATCHED_ARGS" | sed 's/\]$/,"--port-mapping=false"]/')
   fi
   kubectl -n kube-system patch ds tke-bridge-agent --type='json' \
     -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${PATCHED_ARGS}}]"
   ```
2. Disable tke-cni-agent (multus is no longer needed):
   ```bash
   kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
   ```
3. After tke-bridge-agent finishes rolling restart, delete residual multus configuration (execute on each node, can be done via tke-bridge-agent Pods):
   ```bash
   for pod in $(kubectl -n kube-system get pod -l app=tke-bridge-agent -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || kubectl -n kube-system get pod --no-headers 2>/dev/null | grep tke-bridge-agent | awk '{print $1}'); do
     kubectl -n kube-system exec "$pod" -- rm -f /host/etc/cni/net.d/00-multus.conf
   done
   ```

Then execute helm install:

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
  --set cni.exclusive=false \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

:::tip[Explanation]

Key differences from VPC-CNI chaining mode:

| Parameter                             | Description                                                                                                                |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `cni.chainingTarget=tke-bridge`       | Cilium automatically watches the CNI config named `tke-bridge` and appends itself, adapting to per-node subnet differences |
| `cni.exclusive=false`                 | Does not exclusively own the CNI directory, preserves tke-bridge-agent's config file                                       |
| No `cni.customConf` / `cni.configMap` | No need to manually create CNI ConfigMap                                                                                   |

:::

:::warning[GR clusters do NOT support dynamically enabling VPC-CNI after Cilium installation]

GR clusters natively support enabling VPC-CNI coexistence via the `EnableVpcCniNetworkType` API. However, **after installing Cilium with this guide, this feature no longer works** — Cilium chaining takes over all Pod networking via multus's `defaultDelegates=tke-bridge`. Even Pods annotated with `tke.cloud.tencent.com/networks: tke-route-eni` still get IPs from the GR ClusterCIDR (not the VPC-CNI subnet). If you need VPC-CNI coexistence, use a VPC-CNI cluster directly.

:::

</TabItem>
<TabItem value="overlay" label="Overlay">

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

:::tip[Parameter Description]

Key differences from Native Routing mode:

| Parameter                                  | Description                                                           |
| ------------------------------------------ | --------------------------------------------------------------------- |
| `routingMode=tunnel`                       | Use tunnel mode (instead of native)                                   |
| `tunnelProtocol=vxlan`                     | Use vxlan encapsulation protocol                                      |
| `ipam.mode=cluster-pool`                   | Cilium manages Pod IP allocation itself (instead of delegated-plugin) |
| `ipam.operator.clusterPoolIPv4PodCIDRList` | Pod CIDR range, adjustable as needed                                  |
| `ipam.operator.clusterPoolIPv4MaskSize`    | Subnet mask size per node (24 means max 254 Pods per node)            |
| `enableIPv4Masquerade=true`                | Enable SNAT, overlay IPs need masquerade when leaving the cluster     |

VPC-CNI chaining related parameters are not needed (`cni.chainingMode`, `cni.customConf`, `cni.configMap`, `cni.externalRouting`, `devices`, `endpointRoutes`, `extraConfig.local-router-ipv4`).

:::

</TabItem>
</Tabs>

:::tip[Explanation]

The following is the `values.yaml` with parameter explanations, split into common and mode-specific parts:

<Tabs>
  <TabItem value="common" label="Common Parameters">

Parameters shared by all installation modes:

```yaml showLineNumbers title="common-values.yaml"
# Replace kube-proxy, including ClusterIP/NodePort/HostPort forwarding
kubeProxyReplacement: "true"
# Replace with actual apiserver address
# How to get: kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112
k8sServicePort: 60002
# Enable CiliumLocalRedirectPolicy capability
# Refer to: https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/
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
  # Tolerate TKE's taints to avoid circular dependencies during first installation
  - key: "tke.cloud.tencent.com/uninitialized"
    operator: Exists
```

  </TabItem>
  <TabItem value="native-vpccni" label="Native (VPC-CNI)">

Native Routing (VPC-CNI) mode-specific parameters:

```yaml showLineNumbers title="native-vpccni-values.yaml"
# Use native routing, Pods directly use VPC IP routing without overlay
routingMode: "native"
endpointRoutes:
  # Must be true for native routing, routes Pod traffic directly to veth device
  enabled: true
ipam:
  # Pod IP allocation handled by tke-eni-ipamd, cilium doesn't manage it
  mode: "delegated-plugin"
# VPC-CNI Pods use VPC IPs, no masquerade needed
enableIPv4Masquerade: false
# All eth-prefixed NICs may carry traffic (auxiliary NICs eth1/eth2...)
# Mount cilium eBPF programs on all of them for proper conntrack/reverse NAT
devices: eth+
cni:
  # Use generic-veth for CNI Chaining with VPC-CNI
  chainingMode: generic-veth
  # Fully custom CNI config from the ConfigMap created earlier
  customConf: true
  configMap: cni-configuration
  # VPC-CNI handles Pod routing, cilium doesn't need to
  externalRouting: true
extraConfig:
  # cilium doesn't allocate Pod IPs, manually specify cilium_host IP
  local-router-ipv4: 169.254.32.16
# Disable sysctlfix to prevent eth0 rp_filter reset, see FAQ for details
sysctlfix:
  enabled: false
operator:
  tolerations:
  # VPC-CNI mode additionally needs this toleration
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
# GR Pod IPs need SNAT to node IP for accessing CVM metadata etc.
enableIPv4Masquerade: true
bpf:
  masquerade: true
ipMasqAgent:
  enabled: true
# All eth-prefixed NICs mount cilium eBPF programs
devices: eth+
cni:
  # Use generic-veth + chainingTarget to auto-adapt tke-bridge CNI config
  chainingMode: generic-veth
  chainingTarget: tke-bridge
  externalRouting: true
extraConfig:
  local-router-ipv4: 169.254.32.16
# Disable sysctlfix, see FAQ for details
sysctlfix:
  enabled: false
```

  </TabItem>
  <TabItem value="overlay" label="Overlay (VPC-CNI/GR)">

Overlay (vxlan) mode-specific parameters, common for both VPC-CNI and GR clusters:

```yaml showLineNumbers title="overlay-values.yaml"
# Use vxlan tunnel for cross-node traffic
routingMode: "tunnel"
tunnelProtocol: "vxlan"
ipam:
  mode: "cluster-pool"
  operator:
    # Pod CIDR; adjust for cluster size; must not conflict with VPC/Service CIDRs
    clusterPoolIPv4PodCIDRList:
    - "10.244.0.0/16"
    # Per-node subnet mask; /24 = 254 Pod IPs per node
    clusterPoolIPv4MaskSize: "24"
# Overlay needs masquerade; Pod IPs need SNAT to node IP for external access
enableIPv4Masquerade: true
# Do NOT set sysctlfix (keep default true) to ensure lxc interface rp_filter=0
```

VPC-CNI clusters additionally need this operator toleration:

```yaml
operator:
  tolerations:
  - key: "tke.cloud.tencent.com/eni-ip-unavailable"
    operator: Exists
```

  </TabItem>
  <TabItem value="images" label="Image Related">

Replace all cilium dependent images with mirror images that can be directly pulled from internal network in TKE environment, avoiding image pull failures due to network issues:

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

For production environment deployment, it's recommended to save parameters to YAML files, then execute commands similar to the following during installation or update (if upgrading version, just replace `--version`):

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml
```

If you have many custom configurations, it's recommended to split them into multiple yaml files for maintenance, for example, put configurations for enabling Egress Gateway in `egress-values.yaml`, put container request and limit configurations in `resources-values.yaml`, and merge multiple yaml files by adding multiple `-f` parameters when updating configurations:

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f egress-values.yaml \
  -f resources-values.yaml
```

:::

Ensure cilium related pods are running normally:

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

### Uninstall TKE Components

Use kubectl patch to uninstall kube-proxy and tke-cni-agent:

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[Explanation]

1. By adding nodeSelector to make daemonset not deploy to any nodes, equivalent to uninstalling, while also providing a fallback option; currently kube-proxy can only be uninstalled this way, if directly deleting kube-proxy, subsequent cluster upgrades will be blocked.
2. Using a VPC-CNI network with a fully customized CNI configuration, tke-cni-agent can be dispensed with and uninstalled to avoid CNI profile conflicts. The same applies to Overlay mode, where Cilium writes its own CNI configuration.
3. As mentioned earlier, it's not recommended to add nodes before installing cilium. If regular nodes or native nodes were added before cilium installation for some reason, the existing nodes need to be restarted to avoid leaving any related rules and configurations.
4. If you forgot to uncheck ip-masq-agent when creating the cluster, you can uninstall it manually:
   ```bash
   kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
   ```

:::

### Configuring APF Rate Limiting

Cilium-agent runs on each node. When the cluster scale is large, it may put significant pressure on the APIServer. In extreme scenarios, this could cause a cascade failure, making the entire cluster unavailable. Therefore, it's necessary to configure APF to rate limit Cilium's components.

Save the following content to the file `cilium-apf.yaml`:

:::tip[Note]

You can modify the value of `nominalConcurrencyShares` according to the cluster specifications, refer to the comments.

:::

<FileBlock file="cilium/cilium-apf.yaml" showLineNumbers  showFileName />

Create APF rate limiting rules:

```bash
kubectl apply -f cilium-apf.yaml
```

## Create New Node Pools

:::tip[OS Compatibility Notes]

Cilium requires Linux kernel >= 5.10. **Recommended OS**: Ubuntu 24.04 or TencentOS 4 latest.

For the **full list of verified OS versions**, see the [Verified Node Operating Systems](#verified-node-operating-systems) appendix at the end of this document.

:::

:::warning[Native Routing (GR) node pools must have cilium taint]

When using the **Native Routing (GR)** option, you **must** add the following taint to nodes when creating node pools:

```
node.cilium.io/agent-not-ready=true:NoSchedule
```

**Reason**: In GR mode, each node has a different PodCIDR, and the CNI config is dynamically generated per-node by tke-bridge-agent (containing that node's specific subnet info). Cilium cannot use a single unified CNI config to take over all nodes (unlike VPC-CNI or Overlay modes) — it can only watch tke-bridge's config via `chainingTarget` and append itself. This creates a timing issue: when a node joins, tke-bridge-agent writes the CNI config first, kubelet considers CNI ready and schedules Pods immediately, but cilium agent hasn't finished starting yet. Pods end up using the raw tke-bridge CNI without cilium-cni enhancement, missing masquerade, NetworkPolicy, and other features. This taint ensures business Pods are only scheduled after the cilium agent is ready (cilium agent automatically removes the taint once started).

Native Routing (VPC-CNI) and Overlay modes **do NOT need** this taint:

- Native Routing (VPC-CNI) uses `cni.customConf=true` with a unified CNI config (same ConfigMap shared by all nodes, not per-node generated) — no other CNI writes first.
- Overlay mode has cilium fully manage the CNI — kubelet won't successfully create Pod sandboxes until cilium CNI is ready.

Add this taint in the **Advanced Settings** when creating node pools via the console. For terraform, see the code snippet below.

:::

### Node Pool Selection

The following three types of node pools can adapt to cilium:

- Native Node Pool: Based on native nodes, native nodes have rich features and are also the recommended node type for TKE (refer to [Native Nodes vs Regular Nodes](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)), OS fixed to use TencentOS.
- Regular Node Pool: Based on regular nodes (CVM), OS images are more flexible.
- Karpenter Node Pool: Similar to native node pool, based on native nodes, OS fixed to use TencentOS, but uses the more powerful [Karpenter](https://karpenter.sh/) for node management instead of [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) (CA) used by regular node pools and native node pools.

The following is a comparison of these node pool types, choose the appropriate node pool type based on your situation:

| Node Pool Type      | Node Type           | Available OS Images                                           | Node Scaling Component |
| ------------------- | ------------------- | ------------------------------------------------------------- | ---------------------- |
| Native Node Pool    | Native Nodes        | TencentOS                                                     | cluster-autoscaler     |
| Regular Node Pool   | Regular Nodes (CVM) | All CVM public images (Ubuntu/TencentOS/etc.) + custom images | cluster-autoscaler     |
| Karpenter Node Pool | Native Nodes        | TencentOS                                                     | Karpenter              |

Below are the steps to create various node pools.

### Create Karpenter Node Pool

Before creating a Karpenter node pool, ensure the Karpenter component is enabled, refer to [tke-karpenter instructions](https://cloud.tencent.com/document/product/457/111805).

Prepare `nodepool.yaml` for configuring Karpenter node pool, here's an example:

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
        # Native nodes default to installing TencentOS 3, which is incompatible with the latest cilium version, specify this annotation to install TencentOS 4
        # Note: Currently using this system image still requires submitting a ticket to apply
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
        # Specify the expected instance type list, you can first confirm which instance types are actually available in the cluster's region and related availability zones in the console
        # Complete list reference: https://cloud.tencent.com/document/product/213/11518#INSTANCETYPE
        values: ["S5", "SA2"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"] # Specify the minimum CPU cores when scaling up
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default # Reference TKEMachineNodeClass
  limits:
    cpu: 100 # Limit the maximum CPU cores for the node pool

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms: # VPC subnet where nodes belong
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # Security groups bound to nodes
  - id: sg-nok01xpa
  sshKeySelectorTerms: # SSH keys bound to nodes
  - id: skey-3t01mlvf
```

Create Karpenter node pool:

```bash
kubectl apply -f nodepool.yaml
```

### Create Native Node Pool

The following are the steps to create a native node pool through the [Container Service Console](https://console.cloud.tencent.com/tke2):

1. In the cluster list, click the cluster ID to enter the cluster details page.
2. Select **Node Management** from the left menu bar, click **Node Pools** to enter the node pool list page.
3. Click **Create New**.
4. Select **Native Nodes**.
5. In **Advanced Settings** under Annotations, click **Add**: `node.tke.cloud.tencent.com/image-label=ts4-public` (native nodes default to using TencentOS 3.1, which is incompatible with the latest cilium version, specify this annotation to make native nodes use TencentOS 4).
6. Choose other options according to your needs.
7. Click **Create Node Pool**.

If you want to create a native node pool through terraform, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations { # Add annotation to specify native nodes use TencentOS 4 to be compatible with cilium, currently using this system image still requires submitting a ticket to apply
    name  = "node.tke.cloud.tencent.com/image-label"
    value = "ts4-public"
  }
}
```

### Create Regular Node Pool

The following are the steps to create a regular node pool through the [Container Service Console](https://console.cloud.tencent.com/tke2):

1. In the cluster list, click the cluster ID to enter the cluster details page.
2. Select **Node Management** from the left menu bar, click **Node Pools** to enter the node pool list page.
3. Click **Create New**.
4. Select **Regular Nodes**.
5. **Operating System**: choose any image from the [Verified Node Operating Systems](#verified-node-operating-systems) appendix (recommended **TencentOS 4** or **Ubuntu 24.04**). You may also use other CVM public images or custom images that meet the minimum kernel requirement (kernel >= 5.10) — a single-node smoke test is recommended first.
6. Choose other options according to your needs.
7. Click **Create Node Pool**.

If you want to create a regular node pool through terraform, refer to the following code snippet:

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "tlinux4_x86_64_public" # OsName, see appendix for full verified OS list

  # Ensure cilium agent is ready before scheduling business Pods
  taints {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NoSchedule"
  }
}
```

## FAQ

### How to view all default installation configurations for Cilium?

Cilium's helm installation package provides a large number of custom configuration items. The above installation steps only provide the necessary configurations for installing Cilium in TKE environment. In practice, you can adjust more configurations according to your needs.

Execute the following command to view all installation configuration items:

```bash
helm show values cilium/cilium --version 1.19.4
```

### Why does Native Routing mode need local-router-ipv4?

In Native Routing mode, Cilium creates a `cilium_host` virtual interface on each node that requires an IP address. Since Cilium doesn't manage Pod IP allocation in this mode (IP allocation is handled by TKE CNI), the `local-router-ipv4` parameter must be manually specified with a non-conflicting IP. `169.254.32.16` is a link-local address that won't conflict with any other IP on TKE.

Overlay mode doesn't need this configuration because Cilium manages Pod IP allocation itself (cluster-pool IPAM) and automatically assigns an IP to `cilium_host`.

### What to do if unable to connect to Cilium's helm repo?

When using helm to install Cilium, helm will get chart related information from Cilium's helm repo and download it. If unable to connect, it will report an error.

The solution is to download the chart compressed package in an environment that can connect:

```bash
$ helm pull cilium/cilium --version 1.19.4
$ ls cilium-*.tgz
cilium-1.19.4.tgz
```

Then copy the chart compressed package to the machine where helm installation is executed, and specify the path of the chart compressed package during installation:

```bash
helm upgrade --install cilium ./cilium-1.19.4.tgz \
  --namespace kube-system \
  -f values.yaml
```

### How to optimize for large-scale scenarios?

For large clusters (hundreds of nodes / 10K+ Pods), consider the following optimizations:

**1. Enable CiliumEndpointSlice (Recommended)**

Aggregates multiple CiliumEndpoint resources into a single CiliumEndpointSlice, significantly reducing apiserver watch/list pressure:

```yaml
ciliumEndpointSlice:
  enabled: true
```

Introduced in 1.11, still Beta in 1.19 ([tracking Stable graduation](https://github.com/cilium/cilium/issues/31904)).

**2. Increase K8s Client Rate Limits**

cilium-agent defaults: QPS=10, Burst=20; cilium-operator defaults: QPS=100, Burst=200. These may bottleneck at scale:

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

**3. Reduce Identity Count**

Cilium assigns a Security Identity per unique label set. Too many identities increase memory and policy computation overhead. Exclude high-cardinality labels:

```yaml
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

**4. Configure Agent / Operator Resources**

Default resource settings are conservative. For large clusters:

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

The installation script in this guide already creates dedicated APF FlowSchema and PriorityLevelConfiguration for Cilium to prevent its list requests from impacting other components. If installing manually, replicate this configuration.

**6. BPF Map Dynamic Sizing**

BPF map capacity is auto-calculated based on system memory by default. To manually adjust the ratio:

```yaml
bpf:
  mapDynamicSizeRatio: 0.0025
```

### Can VPC-CNI be dynamically enabled on a GR cluster after installing Cilium?

Not recommended. GR clusters natively support enabling VPC-CNI coexistence via enable VPC-CNI network capability, but **after installing Cilium with this guide, this feature no longer works in practice**:

- Cilium chaining takes over all Pod networking via the multus configuration (`defaultDelegates=tke-bridge`).
- Pods annotated with `tke.cloud.tencent.com/networks: tke-route-eni` still receive IPs from the GR ClusterCIDR (not the VPC-CNI subnet) — they don't actually use the VPC-CNI datapath.
- The `EnableVpcCniNetworkType` API call succeeds and the components are deployed, but it has no effect on Pod networking.

If you genuinely need VPC-CNI coexistence (some Pods using VPC IPs), use the **VPC-CNI cluster + Native Routing** option directly, not a GR cluster.

### Can DataPlaneV2 be selected when creating a VPC-CNI cluster?

No.

When selecting VPC-CNI network plugin, there's a DataPlaneV2 option:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

After checking, Cilium components will be deployed to the cluster (replacing kube-proxy components). If you install Cilium yourself again, it will cause conflicts. Moreover, the OS used by DataPlaneV2 is incompatible with the latest version of Cilium, so this option cannot be checked.

### How can Pods access the public network?

You can create a public NAT gateway, then create new routing rules in the routing table of the VPC where the cluster is located, redirecting traffic accessing the external network to the public NAT gateway, and ensure the routing table is associated with the subnets used by the cluster. Refer to [Accessing External Network through NAT Gateway](https://cloud.tencent.com/document/product/457/48710).

If the node itself has public network bandwidth and you want Pods to directly utilize the node's public network capability to access the public network, you need to enable Cilium's IP Masquerade capability. For specific methods, refer to [Configuring IP Masquerading](./masquerading.md).

If you have more advanced traffic egress requirements (such as specifying certain Pods to use a specific public IP to access the public network), you can refer to [Egress Gateway Application Practice](egress-gateway.md).

### Image pull failure?

Most of the images that Cilium depends on are on `quay.io`. If you don't use the parameter configuration for replacing image addresses provided in this article during installation, it may cause Cilium related image pull failures (for example, if nodes don't have public network access capability, or the cluster is in mainland China).

In TKE environment, the mirror repository address `quay.tencentcloudcr.com` is provided for downloading images under the `quay.io` domain. Simply replace the `quay.io` domain in the original image address with `quay.tencentcloudcr.com`. Pulling goes through internal network, nodes don't need public network capability, and there are no regional restrictions.

If you configure more installation parameters, it may involve more image dependencies. If you don't configure image address replacement, it may cause image pull failures. Use the following command to replace all Cilium dependent images with mirror repository addresses that can be directly pulled from internal network in TKE environment:

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

If you use yaml to manage configurations, you can save the image replacement configuration to `image-values.yaml`:

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

When updating Cilium, add a `-f image-values.yaml` to include the image replacement configuration:

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[Explanation]

Using the mirror repository address provided by TKE to pull external images itself doesn't provide SLA guarantee. Sometimes it may also fail to pull, but usually it will automatically retry and succeed eventually.

If you want image pulling to have higher availability, you can [use TCR to host Cilium images](tcr.md) to synchronize Cilium dependent images to your own [TCR image repository](https://cloud.tencent.com/product/tcr), then refer to the dependent image replacement configuration here, and replace the corresponding images with your own synchronized image addresses.

:::

### cilium-operator cannot become ready on super nodes?

cilium-operator uses hostNetwork and configures readiness probes. When using hostNetwork on super nodes, probe requests cannot connect, so cilium-operator cannot become ready.

It's not recommended to use super nodes in clusters where Cilium is installed. They can be removed. If you must use them, you can add taints to super nodes, and then add corresponding tolerations to Pods that need to be scheduled to super nodes.

### cilium-agent connecting to apiserver reports `operation not permitted` error?

If when installing Cilium, `k8sServiceHost` points to a CLB address (the CLB used when enabling cluster internal network access), which is either a CLB VIP or a domain name that ultimately resolves to a CLB VIP, then the connection path from cilium-agent to apiserver will be intercepted and forwarded by Cilium itself, not actually going through CLB forwarding. Cilium's forwarding of this address is ultimately implemented by eBPF programs, and the eBPF program forwarding of this address is based on eBPF data (endpoint list) stored in the kernel. Under certain triggering conditions, the eBPF data may be refreshed, and the refresh may cause the endpoint list to be temporarily cleared. Once cleared, cilium-agent can no longer connect to apiserver (reporting `operation not permitted` error), and thus cannot perceive the current real endpoint list to update the eBPF data, forming a circular dependency. Normal operation is only restored after restarting the node.

Therefore, the recommendation is not to configure `k8sServiceHost` with the apiserver's CLB address, but to use the cluster's `169.254.x.x` apiserver address (`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`). This address is also a VIP, but it will not be intercepted and forwarded by Cilium, and it will never change after the cluster is created, so it can be safely used as the `k8sServiceHost` configuration. If you want to use a more recognizable domain name configuration, you can also resolve the domain name to this address and then configure it to `k8sServiceHost`.

### Why does Native Routing mode disable sysctlfix while Overlay mode enables it?

Cilium's `sysctlfix` is enabled by default. It runs an init container that writes `/etc/sysctl.d/99-zzz-override_cilium.conf` to set `rp_filter=0` on lxc interfaces, and then **restarts `systemd-sysctl.service`** to apply the change.

- **Native Routing (VPC-CNI) mode**: Cilium coexists with VPC-CNI. Pod IPs come from VPC, and reply packets enter via eth0. Restarting `systemd-sysctl.service` re-applies OS defaults; TKE OS images default eth0's `rp_filter` to 1 (strict), under which Pod IPs on eth0 fail the source-route check and get dropped, breaking networking. **Must disable** sysctlfix (`--set sysctlfix.enabled=false`).
- **Native Routing (GR) mode**: Cilium chaining takes over all Pod networking, no lxc interfaces need rp_filter fix, and tests show enabling sysctlfix doesn't break networking. We **uniformly disable** it to keep configuration consistent with Native Routing (VPC-CNI) and avoid edge cases caused by changes in OS default sysctl values.
- **Overlay mode**: Pod IPs come from cilium's own CIDR; cross-node traffic goes through vxlan tunnel and eth0 never sees Pod IPs, so eth0 `rp_filter=1` is fine. But host→local Pod reply packets pass through lxc interfaces and require `lxc*.rp_filter=0`, otherwise they get dropped. **Must enable** sysctlfix (default; no explicit setting needed).

**Troubleshooting**: If in Overlay mode `cilium-health status` shows localhost endpoint 0/1 (host→Pod broken), sysctlfix likely didn't take effect:

```bash
# Check if lxc interface rp_filter is 0
sysctl net.ipv4.conf.lxc_health.rp_filter
# If not 0, check if cilium sysctlfix init container ran successfully
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

## References

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

## Appendix

### Verified Node Operating Systems

The table below lists OS versions and kernels that have been hands-on verified across all 4 installation modes (VPC-CNI/GR × Native/Overlay) in this guide.

**Test method**: For each installation mode, cilium 1.19.4 was deployed with Egress Gateway and Nodelocal DNSCache enabled. Verified that `cilium-health status` shows all nodes reachable, and `coredns` / `node-local-dns` pass health checks.

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

For OS versions not in the list above, a single-node smoke test is recommended first.
