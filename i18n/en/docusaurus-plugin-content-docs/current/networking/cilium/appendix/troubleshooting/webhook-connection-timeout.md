# Troubleshooting: Webhook Connection Timeout in Overlay Mode

Applies to TKE managed clusters using an Overlay plan (VPC-CNI or GR): apiserver calls to ValidatingWebhook / MutatingWebhook time out.

## Symptom

In a TKE managed cluster with Overlay mode, apiserver calls to ValidatingWebhook / MutatingWebhook time out (e.g. cert-manager's `webhook.cert-manager.io`), reporting `context deadline exceeded` or `Client.Timeout exceeded while awaiting headers`.

## Root Cause

In TKE managed clusters, the apiserver runs on the control plane (MetaCluster), where there is no cilium-agent and therefore no overlay tunnel. When apiserver accesses a webhook Pod via Service ClusterIP → EndpointSlice, the Pod IP in the EndpointSlice is in the overlay subnet (e.g. `10.244.x.x`), which is not routable from the control plane — hence the timeout.

```text
apiserver (control plane, no cilium-agent)
  → Service ClusterIP
  → EndpointSlice: 10.244.x.x (overlay Pod IP)
  → ❌ No overlay tunnel on control plane, route unreachable
```

Native Routing mode does not have this issue — Pod IPs are VPC IPs, directly routable from apiserver.

## Solution

Set `hostNetwork: true` on the webhook Pod, so the Pod IP becomes the node IP (a VPC IP) that apiserver can route to directly. Use `podAntiAffinity` to spread webhook Pods across different nodes for high availability:

```yaml
spec:
  hostNetwork: true  # Pod IP = node IP, apiserver can reach directly
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: <webhook-name>
        topologyKey: kubernetes.io/hostname
```

:::tip[Common components that need hostNetwork]

The following components typically require `hostNetwork: true` in Overlay mode:

- cert-manager webhook
- Custom admission webhooks (e.g. Gatekeeper, OPA)
- Any webhook service that apiserver actively calls

:::
