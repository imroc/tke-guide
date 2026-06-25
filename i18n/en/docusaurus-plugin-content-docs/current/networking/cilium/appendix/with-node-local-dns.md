# Cilium with Nodelocal DNSCache

## Overview

[Nodelocal DNS Cache](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns/nodelocaldns) is used for DNS caching and acceleration, reducing coredns pressure and improving DNS query performance.

This article describes how to make Nodelocal DNSCache coexist with Cilium in TKE clusters.

## Incompatibility with TKE's NodeLocalDNSCache Addon

When Cilium is installed and replaces kube-proxy, requests to coredns are intercepted and forwarded by Cilium's eBPF programs, and cannot be intercepted by the `node-local-dns` Pod on the node. Therefore, DNS caching capability cannot be achieved directly, and the addon's functionality becomes ineffective.

Cilium provides an official method to coexist with Nodelocal DNSCache by configuring `CiliumLocalRedirectPolicy`. However, if you are using TKE's [NodeLocalDNSCache](https://cloud.tencent.com/document/product/457/40613) addon, coexistence with Cilium cannot be achieved even with `CiliumLocalRedirectPolicy`, because this addon uses HostNetwork and does not listen on node/Pod IPs (it listens on `169.254.20.10` and the `kube-dns` Cluster IP), making it impossible for `CiliumLocalRedirectPolicy` to redirect DNS traffic to the local `node-local-dns` Pod.

Therefore, if you want to use Nodelocal DNSCache in a cluster with Cilium installed, it is recommended to self-build Nodelocal DNSCache. Refer to the section below for details.

## Self-Build Nodelocal DNSCache

### One-Click Installation

You can use a script to automatically install and configure coexistence with Cilium:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- install-localdns
```

If your network environment cannot reach GitHub, use the site address:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- install-localdns
```

### Manual Installation

For manual installation, follow these steps:

1. Save the following content to `node-local-dns.yaml`:

:::tip[Note]

The content below is adapted from the **Manual Configuration** approach in Cilium's official documentation [Node-local DNS cache](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache), modified from the official node-local-dns deployment YAML [nodelocaldns.yaml](https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml). The image addresses have been replaced with Docker Hub mirror images for easy internal network pulling in TKE environments, and HINFO requests are disabled to prevent continuous log errors (VPC's DNS service does not support HINFO requests).

:::

<FileBlock file="cilium/node-local-dns.yaml" title="node-local-dns.yaml" />

2. Install:

   ```bash
   kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml
   kubectl apply -f node-local-dns.yaml
   ```

3. Save the following content to `localdns-redirect-policy.yaml`:

   ```yaml title="localdns-redirect-policy.yaml"
   apiVersion: cilium.io/v2
   kind: CiliumLocalRedirectPolicy
   metadata:
     name: nodelocaldns
     namespace: kube-system
   spec:
     redirectFrontend:
       serviceMatcher:
         serviceName: kube-dns
         namespace: kube-system
     redirectBackend:
       localEndpointSelector:
         matchLabels:
           k8s-app: node-local-dns
       toPorts:
       - port: "53"
         name: dns
         protocol: UDP
       - port: "53"
         name: dns-tcp
         protocol: TCP
   ```

4. Create the CiliumLocalRedirectPolicy (redirect DNS requests to the local node-local-dns pod):
   ```bash
   kubectl apply -f localdns-redirect-policy.yaml
   ```

## FAQ

### sed Error: extra characters at the end of n command

When installing Nodelocal DNSCache on macOS, sed reports an error:

```bash
$ kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml

sed: 1: "node-local-dns.yaml
": extra characters at the end of n command
```

This is because the built-in sed on macOS is not standard (GNU) and has slightly different syntax. Install the GNU version of sed:

```bash
brew install gnu-sed
```

And set the PATH:

```bash
PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
```

Then open a new terminal and re-run the installation command.

### Cannot Create CiliumLocalRedirectPolicy

The CiliumLocalRedirectPolicy feature is not enabled by default. You need to add `--set localRedirectPolicies.enabled=true` during installation to enable it.

If Cilium is already installed, update the Cilium configuration to enable it:

```bash
helm upgrade cilium cilium/cilium --version 1.19.5 \
  --namespace kube-system \
  --reuse-values \
  --set localRedirectPolicies.enabled=true
```

Then restart the operator and agent for the changes to take effect:

```bash
kubectl rollout restart deploy cilium-operator -n kube-system
kubectl rollout restart ds cilium -n kube-system
```

## References

- [Local Redirect Policy Use Cases: Node-local DNS cache](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache)
- [Using NodeLocal DNSCache in Kubernetes Clusters](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/)
- [TKE DNS Best Practices](https://cloud.tencent.com/document/product/457/78005)
