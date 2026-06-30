# Using Gateway API

[Cilium Gateway API](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/) is Cilium's built-in Gateway API implementation. No additional Ingress Controller deployment is needed—Cilium's eBPF data plane and built-in Envoy proxy handle traffic routing directly.

Compared to standalone Ingress Controllers (such as Envoy Gateway, Nginx Ingress), Cilium Gateway API is deeply integrated with the CNI—after traffic reaches the Gateway Service, eBPF transparently forwards it to the Envoy proxy on the node via the TPROXY mechanism, eliminating an extra hop.

## Prerequisites

- Cilium is installed with `kubeProxyReplacement=true` (enabled by default)
- The installation mode is **Overlay mode** (VPC-CNI or GR). Native Routing (VPC-CNI) mode does not support Gateway API due to the `ipam.mode=delegated-plugin` limitation. See [Installation FAQ](./install.md#does-native-routing-vpc-cni-mode-not-support-gateway-api) for details
- Gateway API CRDs are installed in the cluster (cilium 1.19.5 corresponds to Gateway API v1.5.1)

### Install Gateway API CRDs

If the Gateway API CRDs are not yet installed in the cluster, use the following commands to install them:

```bash
# Standard CRDs (GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, TLSRoute, BackendTLSPolicy)
for crd in gatewayclasses gateways httproutes grpcroutes referencegrants backendtlspolicies tlsroutes; do
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/standard/gateway.networking.k8s.io_${crd}.yaml
done

# Experimental CRDs (TCPRoute, UDPRoute) — for TCP/UDP routing
for crd in tcproutes udproutes; do
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/experimental/gateway.networking.k8s.io_${crd}.yaml
done
```

## Enable Gateway API

On top of an existing Cilium installation, enable Gateway API via helm:

```bash
helm upgrade cilium cilium/cilium --version 1.19.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true

# Restart cilium-operator and cilium-agent to apply the configuration
kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium
```

You can also write the configuration to values.yaml:

```yaml title="gateway-api-values.yaml"
gatewayAPI:
  enabled: true
  # externalTrafficPolicy: Local  # Preserve client source IP (default: Cluster)
```

When updating, append `-f gateway-api-values.yaml`:

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.5 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f gateway-api-values.yaml
```

### Verification

After enabling, cilium-operator will automatically create the `cilium` GatewayClass:

```bash
$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       1m
```

## Quick Start: HTTP Routing

The following example creates an HTTP Gateway that routes traffic for `test.cilium.local` to the nginx service:

```yaml title="gateway-http.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx
  namespace: default
spec:
  parentRefs:
  - name: my-gateway
    sectionName: http
  hostnames:
  - "test.cilium.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: nginx
      port: 80
```

```bash
kubectl apply -f gateway-http.yaml
```

After creation, Cilium will automatically create a LoadBalancer-type Service (`cilium-gateway-<name>`), and TKE's service-controller will automatically create a CLB for it:

```bash
$ kubectl get gateway,httproute,svc
NAME                                        CLASS    ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/my-gateway   cilium   43.141.204.235   True         30s

NAME                                        HOSTNAMES               AGE
httproute.gateway.networking.k8s.io/nginx   ["test.cilium.local"]   30s

NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
cilium-gateway-my-gateway  LoadBalancer   172.28.84.187   43.141.204.235   80:32676/TCP   30s
```

Test access:

```bash
curl -s -H "Host: test.cilium.local" http://43.141.204.235/
```

## HTTPS Routing (TLS Termination)

To use an HTTPS listener for TLS termination, you need to provide a TLS certificate:

```yaml title="gateway-https.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: https-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: my-tls-secret
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-https
  namespace: default
spec:
  parentRefs:
  - name: https-gateway
    sectionName: https
  hostnames:
  - "test.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: nginx
      port: 80
```

Create the TLS Secret beforehand:

```bash
kubectl create secret tls my-tls-secret \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem
```

## Host Network Mode

:::tip[When to use]

Host Network mode is suitable for environments with an external load balancer (such as TKE CLB). Cilium Envoy listens directly on the node network without needing a LoadBalancer Service. Suitable for:

- Reusing an existing CLB (via the `service.kubernetes.io/tke-load-balancer-id` annotation or manually configuring CLB backends)
- Scenarios requiring direct control over CLB backend registration
- Eliminating an extra layer of Service forwarding

:::

Enable Host Network mode:

```yaml
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
    # nodes:  # Optional: expose Gateway listeners only on specific nodes
    #   matchLabels:
    #     role: gateway
```

```bash
helm upgrade cilium cilium/cilium --version 1.19.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true \
  --set gatewayAPI.hostNetwork.enabled=true

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
```

In Host Network mode:

- Envoy binds directly to `0.0.0.0:<listener-port>` (on every node)
- The Service created by Cilium is of type ClusterIP (not LoadBalancer), so no CLB is automatically created
- You need to manually configure an external CLB to forward traffic to node IP:listener-port

:::warning[Port conflicts]

In Host Network mode, Envoy directly occupies node ports. Ensure that the listener ports configured in the Gateway are not used by other processes. If you need to use privileged ports below 1024, additionally configure `envoy.securityContext.capabilities.keepCapNetBindService=true`.

:::

### Configure CLB to Forward to Host Network Listeners

Using TKE CLB as an example, manually configure the CLB to forward traffic to the Envoy listener port on each node:

```bash
# Assume Gateway listener port is 8443, CLB ID is lb-xxxxx

# 1. Create a TCP listener
tccli clb CreateListener \
  --region <region> \
  --LoadBalancerId lb-xxxxx \
  --Ports 8443 \
  --Protocol TCP \
  --ListenerName gateway

# 2. Register backends (each node IP + Gateway listener port)
tccli clb RegisterTargets \
  --region <region> \
  --LoadBalancerId lb-xxxxx \
  --ListenerId lbl-xxxxx \
  --cli-unfold-argument \
  --Targets.0.EniIp <node1-ip> --Targets.0.Port 8443 --Targets.0.Weight 10 \
  --Targets.1.EniIp <node2-ip> --Targets.1.Port 8443 --Targets.1.Weight 10 \
  --Targets.2.EniIp <node3-ip> --Targets.2.Port 8443 --Targets.2.Weight 10
```

:::warning[Security group rules]

TKE node security groups by default only allow internal network segments (10.0.0.0/8, etc.). If the CLB uses `SourceIpType=1` (preserving client real IP), traffic from public IPs will be blocked by the security group, causing the CLB to return 502 Bad Gateway.

Solutions (choose one):

1. **Change the CLB's SourceIpType to 0** (SNAT mode, CLB accesses backends using its own IP):
   ```bash
   tccli clb ModifyListener \
     --region <region> \
     --cli-input-json '{"LoadBalancerId":"lb-xxxxx","ListenerId":"lbl-xxxxx","SourceIpType":0}'
   ```
2. **Allow the Gateway listener port in the security group**:
   ```bash
   tccli vpc CreateSecurityGroupPolicies \
     --region <region> \
     --SecurityGroupId sg-xxxxx \
     --SecurityGroupPolicySet.Ingress.0.Protocol TCP \
     --SecurityGroupPolicySet.Ingress.0.Port <gateway-port> \
     --SecurityGroupPolicySet.Ingress.0.CidrBlock 0.0.0.0/0 \
     --SecurityGroupPolicySet.Ingress.0.Action ACCEPT \
     --cli-unfold-argument
   ```

:::

## TLS Passthrough

Use a TLS protocol Gateway listener + TLSRoute to implement TLS passthrough (Envoy does not terminate TLS; it forwards raw TLS traffic based on SNI):

```yaml title="gateway-tls-passthrough.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tls-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: tls
    port: 8443
    protocol: TLS
    tls:
      mode: Passthrough
    allowedRoutes:
      namespaces:
        from: Same
      kinds:
      - kind: TLSRoute
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: my-tls-route
  namespace: default
spec:
  parentRefs:
  - name: tls-gateway
    sectionName: tls
  # hostnames:  # Optional: match by SNI
  # - "secure.example.com"
  rules:
  - backendRefs:
    - name: my-https-service
      port: 443
```

:::note[TLS Passthrough and source IP]

In TLS Passthrough mode, Envoy uses TCP proxy to forward TLS traffic. The source IP seen by the backend is Envoy's IP (usually the node IP), not the client's real IP. This is because TCP proxy establishes a new TCP connection to the backend.

:::

## Configuration Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `gatewayAPI.enabled` | `false` | Enable Gateway API |
| `gatewayAPI.externalTrafficPolicy` | `Cluster` | External traffic policy for the LoadBalancer Service (`Local` preserves source IP) |
| `gatewayAPI.hostNetwork.enabled` | `false` | Host Network mode, Envoy listens directly on node ports |
| `gatewayAPI.hostNetwork.nodes.matchLabels` | `{}` | Restrict Envoy listeners to run only on specific nodes |
| `gatewayAPI.gatewayClass.create` | `auto` | Whether to create a GatewayClass (`auto` auto-detects CRDs) |
| `gatewayAPI.secretsNamespace.name` | `cilium-secrets` | Target namespace for TLS Secret synchronization |
| `gatewayAPI.secretsNamespace.sync` | `true` | Automatically sync TLS Secrets to `secretsNamespace` |

## Supported Protocols

| Protocol | Gateway Listener | Route Type | Description |
| --- | --- | --- | --- |
| HTTP | `protocol: HTTP` | HTTPRoute | Layer 7 HTTP routing |
| HTTPS | `protocol: HTTPS` + `tls.mode: Terminate` | HTTPRoute | TLS termination + Layer 7 routing |
| TLS | `protocol: TLS` + `tls.mode: Passthrough` | TLSRoute | TLS passthrough (route by SNI) |
| GRPC | `protocol: HTTP` / `HTTPS` | GRPCRoute | gRPC routing |
| TCP | `protocol: TCP` | TCPRoute | Experimental, TCP routing |

:::warning[TCP protocol support]

Cilium 1.19.5 support for TCPRoute is experimental. If you need pure TCP proxying (without Layer 7 routing), you can use TLS Passthrough (TLS protocol + TLSRoute, omitting `hostnames` to match all SNIs), or use a standalone TCP proxy (such as socat, nginx stream).

:::

## Traffic Path

```text
Non-Host Network mode:
  Client → CLB → NodePort → eBPF TPROXY → Envoy → Backend Pod
                                     ↑
                         Cilium automatically creates LoadBalancer Service

Host Network mode:
  Client → CLB → Node:Port → Envoy → Backend Pod
                    ↑
          Envoy listens directly on node port (0.0.0.0:port)
          No LoadBalancer Service needed, manual CLB configuration required
```

## FAQ

### Gateway status stays Pending?

Check the cilium-operator logs:

```bash
kubectl -n kube-system logs deploy/cilium-operator | grep gateway
```

Common causes:

1. **Gateway API CRDs not installed**: Install the CRDs and restart cilium-operator
2. **Insufficient RBAC permissions**: Ensure you didn't manually modify the ClusterRole during helm install. If there are conflicts, delete it and run helm upgrade again
3. **`enable-envoy-config` not taking effect**: Restart cilium-agent to apply the configuration

### Gateway is Programmed but not accessible from outside?

1. **LoadBalancer Service has no External IP allocated**: Check if TKE service-controller is running normally
2. **Security group doesn't allow the port**: Ensure the node security group allows the CLB to access the Gateway listener port
3. **CLB SourceIpType causing 502**: See [Host Network Mode - Configure CLB forwarding](#configure-clb-forwarding-to-host-network-listeners)

### Port conflicts in Host Network mode?

In Host Network mode, Envoy binds directly to node ports. If a port is occupied, the Envoy Pod will keep restarting. Solutions:

1. Use a different port
2. Stop the process occupying the port
3. Use `hostNetwork.nodes.matchLabels` to restrict Envoy to run only on specific nodes

### How to view Envoy configuration?

```bash
# View CiliumEnvoyConfig (CEC)
kubectl get cec -A
kubectl get cec <cec-name> -n <namespace> -o yaml

# View Envoy runtime status
kubectl -n kube-system exec ds/cilium-envoy -- cilium-dbg status
```
