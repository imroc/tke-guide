# FAQ

This page collects frequently asked "can-I / how-to / what-if-it-errors" questions about self-hosting Cilium on TKE. For "why is it designed this way" questions, see the other rationale articles in this Cilium appendix.

## How to view all default installation configurations for Cilium?

Cilium's helm chart provides a huge number of customization options. The configurations given in [Install Cilium](../install.md) are only what's required for TKE — you can adjust many more as needed.

Run this to see all options:

```bash
helm show values cilium/cilium --version 1.19.4
```

## What if I can't reach the cilium helm repo?

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

## How to optimize for large-scale scenarios?

For large clusters (hundreds of nodes / tens of thousands of Pods), consider the following:

### 1. Enable CiliumEndpointSlice (recommended)

Aggregates multiple CiliumEndpoint resources into a single CiliumEndpointSlice, significantly reducing watch/list pressure on the apiserver:

```yaml
ciliumEndpointSlice:
  enabled: true
```

This feature was introduced in 1.11 and remains Beta in 1.19 ([tracking Stable progress](https://github.com/cilium/cilium/issues/31904)).

### 2. Tune K8s client rate limits

cilium-agent defaults to QPS=10, Burst=20 — possibly a bottleneck at scale; cilium-operator defaults are QPS=100, Burst=200:

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

### 3. Reduce identity count

cilium assigns a Security Identity to each unique label combination. Too many identities increase memory and policy computation overhead. Exclude irrelevant labels to reduce identity bloat:

```yaml
# Exclude high-cardinality labels to reduce Identity bloat
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

### 4. Configure agent / operator resources

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

### 5. Use API Priority and Fairness (APF)

The install script in [Install Cilium](../install.md) creates cilium-specific APF FlowSchema and PriorityLevelConfiguration by default, preventing cilium's list requests from impacting other components. For manual installs, set this up the same way.

### 6. Dynamic BPF map sizing

By default, BPF map capacity is auto-calculated based on system memory. To adjust the ratio manually:

```yaml
bpf:
  mapDynamicSizeRatio: 0.0025
```

## Can VPC-CNI be dynamically enabled on a GR cluster after installing cilium?

Not recommended. GR clusters natively support enabling VPC-CNI for coexistence, but **with this guide's cilium setup installed, this feature is no longer actually usable**:

- cilium chaining takes over all Pod networking via multus config (`defaultDelegates=tke-bridge`).
- Even when you create Pods with the `tke.cloud.tencent.com/networks: tke-route-eni` annotation, IPs still come from the GR ClusterCIDR (not the VPC-CNI subnet) — the VPC-CNI path is never actually used.
- The `EnableVpcCniNetworkType` API call succeeds and the components deploy, but it has no real effect on Pod networking.

If your business truly needs VPC-CNI, use a **VPC-CNI cluster with Native Routing** directly — don't pick a GR cluster.

## Can DataPlaneV2 be selected when creating a VPC-CNI cluster?

No.

When choosing the VPC-CNI network plugin, there's a DataPlaneV2 option:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

If selected, it deploys cilium components to the cluster (replacing kube-proxy). Installing cilium yourself on top of that causes conflicts. Additionally, the OS used by DataPlaneV2 is not compatible with the latest cilium. So do not check this option.

## How can Pods access the public network?

Create a public-network NAT gateway, then add a route in the cluster's VPC route table forwarding outbound traffic to the NAT gateway, and make sure the route table is associated with the subnets used by the cluster. See [Accessing the Internet via NAT Gateway](https://www.tencentcloud.com/document/product/457/35427).

If your nodes themselves have public bandwidth and you want Pods to use the node's public access, enable cilium's IP Masquerade. See [Configure IP Masquerading](../masquerading.md).

For more advanced egress needs (e.g. routing certain Pods through a specific public IP), see [Egress Gateway Practice](../egress-gateway.md).

## Image pull failure?

Most cilium images live on `quay.io`. If you didn't replace image addresses during install (as shown in [Install Cilium](../install.md)), pulls can fail (e.g. nodes without internet access, or clusters in mainland China).

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

For higher availability, you can [host Cilium images via TCR](../tcr.md) — sync cilium's image dependencies into your own [TCR registry](https://www.tencentcloud.com/products/tcr), then update the image override config to point at your synced addresses.

:::

## cilium-operator cannot become ready on super nodes?

cilium-operator uses hostNetwork and configures a readiness probe. On super nodes, hostNetwork-based probes don't pass, so cilium-operator never reports ready.

Super nodes are not recommended in clusters with cilium installed — remove them. If you must keep them, taint them and add matching tolerations to the Pods you want to schedule there.

## cilium-agent reports `operation not permitted` connecting to apiserver?

If during installation `k8sServiceHost` points to a CLB address (the CLB used for cluster intranet access — either the CLB VIP or a domain resolving to the CLB VIP), cilium-agent's connection to apiserver gets intercepted and forwarded by cilium itself instead of going through the CLB. cilium implements that forwarding via eBPF, which depends on eBPF data (endpoint list) stored in the kernel. Under certain conditions the eBPF data may be flushed — when it is, the endpoint list may be temporarily emptied, making cilium-agent unable to reach apiserver (error `operation not permitted`), so it can't see the real endpoint list to refresh the eBPF data — a circular dependency that only recovers after a node reboot.

So the recommendation is: do **not** configure `k8sServiceHost` with the apiserver's CLB address. Use the cluster's `169.254.x.x` apiserver address instead (`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`) — this is also a VIP, but cilium does not intercept and forward it, and it doesn't change once the cluster is created. For a more readable form, you can resolve a domain to this address and configure that domain in `k8sServiceHost`.

For full root-cause analysis, reproduction steps, and the upstream cilium PR link, see [Troubleshooting: APIServer reports operation not permitted](../troubleshooting/connect-apiserver-operation-not-permitted.md).

## See also

- [Install Cilium](../install.md)
- [Cilium Troubleshooting](../troubleshooting/debug.md)
