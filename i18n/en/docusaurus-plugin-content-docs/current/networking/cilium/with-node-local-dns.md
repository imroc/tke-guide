# Cilium with NodeLocal DNSCache Coexistence

## Overview

[NodeLocal DNS Cache](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns/nodelocaldns) is used for DNS caching and acceleration, which can reduce the pressure on CoreDNS and improve DNS query performance.

This article describes how to achieve coexistence between Cilium and NodeLocal DNSCache in TKE clusters where Cilium is installed.

## Incompatibility with TKE's NodeLocalDNSCache Addon

When Cilium is installed and replaces kube-proxy, requests accessing CoreDNS are intercepted and forwarded by Cilium's eBPF program, making them unable to be intercepted by the `node-local-dns` Pod on the node. This prevents the direct implementation of DNS caching capabilities, rendering the addon's functionality ineffective.

Cilium officially provides a method to achieve coexistence with NodeLocal DNSCache by configuring CiliumLocalRedirectPolicy. However, if you are using TKE's [NodeLocalDNSCache](https://cloud.tencent.com/document/product/457/40613) addon, even configuring CiliumLocalRedirectPolicy cannot achieve coexistence. This is because the addon uses HostNetwork and does not listen on node/Pod IP addresses (it listens on `169.254.20.10` and CoreDNS's Cluster IP), preventing DNS traffic from being redirected by CiliumLocalRedirectPolicy to the local `node-local-dns` Pod.

Therefore, if you want to use NodeLocal DNSCache in a cluster with Cilium installed, it is recommended to build your own NodeLocal DNSCache. The specific method is described below.

## Self-built NodeLocal DNSCache

1. Save the following content to a file `node-local-dns.yaml`:

:::tip[Note]

The following content is based on the **Manual Configuration** method from Cilium's official documentation [Node-local DNS cache](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache), modified from the official NodeLocal DNS deployment YAML file [nodelocaldns.yaml](https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml). Additionally, the image address has been replaced with a mirror image on Docker Hub for convenient internal network pulls in TKE environments, and HINFO requests have been disabled to avoid continuous log errors (VPC's DNS service does not support HINFO requests).

:::

<FileBlock file="cilium/node-local-dns.yaml" title="node-local-dns.yaml" />

2. Install:
    ```bash
    kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml
    kubectl apply -f node-local-dns.yaml
    ```

3. Save the following content to a file `localdns-redirect-policy.yaml`:
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

4. Create CiliumLocalRedirectPolicy (redirects DNS requests to the local node-local-dns pod):
    ```bash
    kubectl apply -f localdns-redirect-policy.yaml
    ```

## Common Issues

### sed Error: extra characters at the end of n command

When installing NodeLocal DNSCache on macOS, sed may report an error:

```bash
$ kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml

sed: 1: "node-local-dns.yaml
": extra characters at the end of n command
```

This occurs because macOS's built-in sed command is not standard (GNU) and has different syntax. Install GNU version of sed:

```bash
brew install gnu-sed
```

And set the PATH:

```bash
PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
```

Then open a new terminal and re-execute the installation command.

### Unable to Create CiliumLocalRedirectPolicy

The CiliumLocalRedirectPolicy capability is not enabled by default. It needs to be enabled during installation by adding the parameter `--set localRedirectPolicies.enabled=true`.

If Cilium is already installed, update the Cilium configuration to enable it:

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
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
- [Using NodeLocal DNSCache in Kubernetes Clusters](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/nodelocaldns/)
- [TKE DNS Best Practices](https://cloud.tencent.com/document/product/457/78005)
