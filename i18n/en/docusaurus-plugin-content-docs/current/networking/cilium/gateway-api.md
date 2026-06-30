# Using Gateway API

[Cilium Gateway API](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/) is Cilium's built-in Gateway API implementation. No additional Ingress Controller deployment is needed—Cilium's eBPF data plane and built-in Envoy proxy handle traffic routing directly.

Compared to standalone Ingress Controllers (such as Envoy Gateway, Nginx Ingress), Cilium Gateway API is deeply integrated with the CNI—after traffic reaches the Service, eBPF transparently forwards it to the Envoy proxy on the node via the TPROXY mechanism, eliminating an extra hop.

:::warning[Important limitations in TKE environments]

When using Cilium Gateway API in a TKE environment, be aware of the following limitations:

1. **Host Network mode is required**: In non-Host Network mode, the Endpoints of the LoadBalancer Service automatically created by Cilium are virtual addresses (`192.192.192.192`). TKE's service-controller cannot register them as CLB backends, resulting in empty CLB backends and external traffic unable to reach the cluster. In Host Network mode, Envoy binds directly to node ports, and the `direct-access` annotation allows the CLB to connect directly to node IPs.
2. **TCP protocol is unavailable**: Cilium Gateway API does not support TCP protocol listeners (error: `model source can't be empty, 0 listeners`). For pure TCP proxying, use the TLS protocol + TLS Passthrough, or use a standalone TCP proxy.
3. **Only Overlay mode is supported**: Native Routing (VPC-CNI) mode does not support Gateway API due to the `ipam.mode=delegated-plugin` limitation.

:::

## Prerequisites

- Cilium is installed with `kubeProxyReplacement=true` (enabled by default)
- The installation mode is **Overlay mode** (VPC-CNI or GR). Native Routing (VPC-CNI) mode does not support Gateway API due to the `ipam.mode=delegated-plugin` limitation. See [Installation FAQ](./install.md#native-routing-vpc-cni-mode-does-not-support-gateway-api) for details
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

On top of an existing Cilium installation, enable Gateway API via helm (**Host Network mode must be enabled**):

```yaml title="gateway-api-values.yaml"
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
```

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.5 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f gateway-api-values.yaml

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
```

### What Host Network Mode Does

:::tip[cilium-envoy Pod always runs in hostNetwork]

Whether or not `gatewayAPI.hostNetwork.enabled` is set, the cilium-envoy Pod always runs in hostNetwork mode. The `hostNetwork.enabled` configuration affects **how Envoy listeners are bound** and **the type of the Gateway Service**.

:::

| Aspect | Non-Host Network Mode | Host Network Mode |
| --- | --- | --- |
| Envoy listener binding | Does not bind to an address; receives traffic via eBPF TPROXY | Binds directly to `0.0.0.0:<port>` |
| Gateway Service type | LoadBalancer (automatically creates CLB) | ClusterIP (does not create CLB) |
| TKE CLB backend registration | ❌ Endpoints are virtual addresses; CLB backends are empty | ✅ Can register via a standalone Service + `direct-access` annotation |
| TKE usability | ❌ Not usable | ✅ Usable |

After enabling Host Network mode, Envoy binds directly to `0.0.0.0:<Gateway listener port>`. External traffic arriving at the node port is received directly by Envoy.

### Verification

After enabling, cilium-operator will automatically create the `cilium` GatewayClass:

```bash
$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       1m
```

## Exposing the Gateway: LoadBalancer Service + direct-access

In Host Network mode, the Gateway Service created by Cilium is of type ClusterIP and does not automatically create a CLB. You need to create a standalone LoadBalancer Service in the TKE environment to expose the Gateway. Key configurations:

1. **`service.kubernetes.io/tke-existed-lbid`**: Reuse an existing CLB (avoids creating a new CLB for each Gateway)
2. **`service.cloud.tencent.com/direct-access: "true"`**: Tells service-controller to register the Pod IP (which is the node IP in hostNetwork mode) + targetPort directly to the CLB, bypassing NodePort

```yaml title="gateway-lb-svc.yaml"
apiVersion: v1
kind: Service
metadata:
  name: <gateway-name>-lb
  namespace: <gateway-namespace>
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx  # Reuse existing CLB (optional)
    service.cloud.tencent.com/direct-access: "true"       # Direct access to Pod IP, bypassing NodePort
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy  # Selects the cilium-envoy DaemonSet
  ports:
  - name: <port-name>
    port: <external-port>     # CLB external port
    targetPort: <gateway-port> # Gateway listener port
    protocol: TCP
```

:::tip[Advantages of direct-access]

The `direct-access` annotation tells service-controller to register Pod IP:targetPort directly as CLB backends (instead of NodePort). Since cilium-envoy runs in hostNetwork mode, the Pod IP is the node IP, and the CLB connects directly to node IP:Gateway port. Traffic reaches Envoy directly without going through eBPF NodePort interception.

When nodes scale up or down, the cilium-envoy DaemonSet is automatically scheduled on new nodes, Service Endpoints are automatically updated, and service-controller automatically registers/deregisters CLB backends—**fully automated management**.

:::

### CLB Security Group Passthrough

TKE CLB uses `SourceIpType=1` (preserves client real IP) by default. The source IP of traffic from CLB to backends is the client's public IP, which may be blocked by node security groups, causing 502 errors. The solution is to enable security group passthrough on the CLB:

```bash
# Set LoadBalancerPassToTarget=true on the CLB (security group passthrough)
# Traffic from CLB to backends is no longer restricted by backend security groups
tccli clb ModifyLoadBalancerAttributes \
  --region <region> \
  --cli-input-json '{"LoadBalancerId":"lb-xxxxxxxx","LoadBalancerPassToTarget":true}'
```

:::warning[pass-to-target annotation conflicts with tke-existed-lbid]

The `service.cloud.tencent.com/pass-to-target` annotation only supports CLBs automatically created by TKE and is mutually exclusive with `tke-existed-lbid` (CLB reuse). When reusing a CLB, you can only set `LoadBalancerPassToTarget=true` manually via the CLB API. This is a one-time configuration that applies to all listeners on the CLB.

:::

## Quick Start: HTTP Routing

The following example creates an HTTP Gateway that routes traffic for `test.cilium.local` to the nginx service.

**1. Create Gateway + HTTPRoute**:

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

**2. Create a LoadBalancer Service to expose the Gateway**:

```yaml title="gateway-http-lb.yaml"
apiVersion: v1
kind: Service
metadata:
  name: my-gateway-lb
  namespace: default
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx  # Reuse existing CLB (optional)
    service.cloud.tencent.com/direct-access: "true"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy
  ports:
  - name: http
    port: 80
    targetPort: 80  # Must match the Gateway listener port
    protocol: TCP
```

```bash
kubectl apply -f gateway-http-lb.yaml
```

**3. Verify**:

```bash
$ kubectl get gateway,httproute,svc
NAME                                          CLASS    ADDRESS   PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/my-gateway  cilium             True         30s

NAME                                        HOSTNAMES               AGE
httproute.gateway.networking.k8s.io/nginx   ["test.cilium.local"]   30s

NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)       AGE
my-gateway-lb    LoadBalancer   172.28.84.187   <clb-vip>     80:32676/TCP  30s

# Test access
curl -s -H "Host: test.cilium.local" http://<clb-vip>/
```

:::note[Empty Gateway ADDRESS is normal]

In Host Network mode, the Gateway ADDRESS is empty (because the Gateway Service is of type ClusterIP and has no external IP). `Programmed=True` indicates that Envoy has been configured. The external IP is provided by the standalone LoadBalancer Service you created.

:::

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

You also need to create a LoadBalancer Service to expose port 443 (see [HTTP Routing example](#quick-start-http-routing)).

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

## Practice: Exposing the APIServer

Using TLS Passthrough, you can expose the cluster apiserver through Gateway API without enabling TKE cluster public/private network access.

```yaml title="apiserver-gateway.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: apiserver
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: apiserver
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
  name: apiserver
  namespace: default
spec:
  parentRefs:
  - name: apiserver
    sectionName: apiserver
  rules:
  - backendRefs:
    - name: kubernetes
      port: 443
---
apiVersion: v1
kind: Service
metadata:
  name: apiserver-gw
  namespace: kube-system
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx
    service.cloud.tencent.com/direct-access: "true"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy
  ports:
  - name: tls
    port: 8443
    targetPort: 8443
    protocol: TCP
```

Traffic path:

```text
Client → CLB:8443 → cilium-envoy (hostNetwork:8443)
       → eBPF TPROXY → Envoy TLS Passthrough
       → kubernetes Service → apiserver (169.254.x.x:60002)
```

Get the kubeconfig (use tccli to fetch it, then replace the server address with the CLB address):

```bash
tccli tke DescribeClusterKubeconfig --region <region> --ClusterId <cluster-id> | \
  python3 -c "
import sys, json, yaml
data = json.load(sys.stdin)
kc = yaml.safe_load(data['Kubeconfig'])
kc['clusters'][0]['cluster']['server'] = 'https://<clb-vip>:8443'
kc['clusters'][0]['cluster']['insecure-skip-tls-verify'] = True
kc['clusters'][0]['cluster'].pop('certificate-authority-data', None)
print(yaml.dump(kc, default_flow_style=False, sort_keys=False))
" > ~/.kube/configs/roc.yaml
```

## Configuration Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `gatewayAPI.enabled` | `false` | Enable Gateway API |
| `gatewayAPI.hostNetwork.enabled` | `false` | Host Network mode, Envoy binds directly to node ports (**must be enabled in TKE environments**) |
| `gatewayAPI.hostNetwork.nodes.matchLabels` | `{}` | Restrict Envoy listeners to run only on specific nodes |
| `gatewayAPI.externalTrafficPolicy` | `Cluster` | External traffic policy for the LoadBalancer Service in non-Host Network mode (ignored in Host Network mode) |
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
| TCP | `protocol: TCP` | TCPRoute | ❌ Unavailable (Cilium error `model source can't be empty`) |

:::warning[TCP protocol unavailable]

Although Cilium 1.19.5 supports TCPRoute in the experimental CRD, creating a TCP protocol Gateway listener actually fails with the error `model source can't be empty, 0 listeners`. For pure TCP proxying, use TLS Passthrough (TLS protocol + TLSRoute, omitting `hostnames` to match all SNIs), or use a standalone TCP proxy.

:::

## Traffic Path

```text
Host Network mode (recommended for TKE):
  Client → CLB → cilium-envoy (hostNetwork, 0.0.0.0:port)
         → eBPF TPROXY → Envoy processing (HTTP routing / TLS termination / TLS passthrough)
         → Backend Pod

  CLB backends are automatically managed by the LoadBalancer Service + direct-access:
  service-controller registers cilium-envoy Pod IP (= node IP) :targetPort to the CLB
  Automatically updated when nodes scale up or down
```

## FAQ

### Gateway status stays Pending?

Check the cilium-operator logs:

```bash
kubectl -n kube-system logs deploy/cilium-operator | grep gateway
```

Common causes:

1. **Gateway API CRDs not installed**: Install the CRDs and restart cilium-operator
2. **Insufficient RBAC permissions**: If you manually patched the ClusterRole causing helm apply conflicts, delete the ClusterRole and run helm upgrade again
3. **`enable-envoy-config` not taking effect**: Restart cilium-agent to apply the configuration

### Gateway is Programmed but not accessible from outside?

1. **No LoadBalancer Service created**: In Host Network mode, you need to manually create a LoadBalancer Service to expose the Gateway (see [Quick Start](#quick-start-http-routing))
2. **CLB backends are empty**: Ensure the Service uses the `direct-access: "true"` annotation and the selector correctly matches cilium-envoy Pods
3. **CLB returns 502**: Security groups are blocking traffic from CLB to backends. Set `LoadBalancerPassToTarget=true` on the CLB (see [CLB Security Group Passthrough](#clb-security-group-passthrough))

### Gateway ADDRESS is empty?

In Host Network mode, an empty Gateway ADDRESS is normal. The Gateway Service is of type ClusterIP (no external IP), and the external IP is provided by the standalone LoadBalancer Service you created. `Programmed=True` indicates that Envoy has been configured.

### Port conflicts in Host Network mode?

In Host Network mode, Envoy binds directly to node ports. If a port is occupied, the cilium-envoy Pod will keep restarting. Solutions:

1. Use a different port
2. Stop the process occupying the port
3. Use `hostNetwork.nodes.matchLabels` to restrict Envoy to run only on specific nodes

If you need to use privileged ports below 1024, additionally configure `envoy.securityContext.capabilities.keepCapNetBindService=true`.

### How to view Envoy configuration?

```bash
# View CiliumEnvoyConfig (CEC)
kubectl get cec -A
kubectl get cec <cec-name> -n <namespace> -o yaml

# View Envoy runtime status
kubectl -n kube-system exec ds/cilium-envoy -- cilium-dbg status
```

### CLB backends are empty in non-Host Network mode?

This is a known limitation in TKE environments. In non-Host Network mode, the Endpoints of the Gateway Service created by Cilium are virtual addresses (`192.192.192.192:9999`), which TKE's service-controller cannot register as CLB backends. **You must use Host Network mode in TKE environments** and expose the Gateway through a standalone LoadBalancer Service + the `direct-access` annotation.
