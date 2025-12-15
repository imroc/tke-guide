---
sidebar_position: 2
---

# Using EnvoyGateway Traffic Gateway on TKE

## Overview

[EnvoyGateway](https://gateway.envoyproxy.io/) is a Kubernetes gateway based on [Envoy](https://www.envoyproxy.io/) that implements the [Gateway API](https://gateway-api.sigs.k8s.io/). You can manage Kubernetes north-south traffic by defining resources like `Gateway`, `HTTPRoute` from the Gateway API specification.

This article describes how to install EnvoyGateway on TKE and use the `Gateway API` to manage traffic forwarding.

:::tip[Note]

Kubernetes provides the `Ingress API` to handle layer 7 north-south traffic, but its functionality is limited. Each implementation adds different annotations to enhance Ingress capabilities, resulting in poor flexibility and extensibility. Driven by community efforts, the `Gateway API` was introduced as a better solution that addresses Ingress API pain points while unifying layer 4/7 north-south traffic, and also supports service mesh east-west traffic (refer to [GAMMA](https://gateway-api.sigs.k8s.io/mesh/gamma/)). Various cloud providers and open-source proxy software are actively adapting to the `Gateway API`. Refer to the [Gateway API Implementations List](https://gateway-api.sigs.k8s.io/implementations/), where Envoy Gateway is one of the popular implementations.

Using EnvoyGateway on TKE has a clear advantage over the built-in CLB Ingress: multiple forwarding rule resources (like `HTTPRoute`) can reuse the same CLB and can cross namespaces. CLB Ingress requires all forwarding rules to be written in the same Ingress resource, which is inconvenient to manage, and if different backend Services are in different namespaces, they cannot be managed with the same Ingress (CLB).

:::

## Prerequisites

1. Ensure [helm](https://helm.sh/zh/docs/intro/install/) and [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) are installed, and kubeconfig is configured to connect to the cluster (refer to [Connecting to Cluster](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)).
2. Ensure EnvoyGateway supports your current cluster version. Refer to EnvoyGateway official documentation [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/) (current latest v1.5 requires cluster version >= 1.30).

## Installing EnvoyGateway

It is recommended to install directly via Helm, and you can use the latest version from the community (the version from the TKE application market is usually updated in a timely manner, but it is not guaranteed to be the latest).

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.6.1 \
  -n envoy-gateway-system \
  --create-namespace
```

> Refer to the EnvoyGateway official documentation [Install with Helm](https://gateway.envoyproxy.io/docs/install/install-helm/)。

## Basic Usage

### Create GatewayClass

Similar to how `Ingress` needs to specify `IngressClass`, each `Gateway` in Gateway API needs to reference a `GatewayClass`. `GatewayClass` essentially represents the gateway instance configuration excluding listeners (such as deployment method, gateway Pod template, replica count, associated Service, etc.). So first create a `GatewayClass`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

> `GatewayClass` is a non-namespaced resource, no need to specify namespace.

### Create Gateway

Each `Gateway` corresponds to a CLB. Declaring ports on a `Gateway` is equivalent to creating corresponding protocol listeners on the CLB:

:::tip[Note]

All Gateway fields refer to [API Specification: Gateway](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.Gateway)

:::

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: test-gw
  namespace: test
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
    allowedRoutes:
      namespaces:
        from: All
```

> `Gateway` can specify namespace and can be referenced cross-namespace by routing rules like `HTTPRoute`.

After `Gateway` creation, `EnvoyGateway` automatically creates a LoadBalancer-type Service for it, which is a CLB. On TKE, LoadBalancer-type Services default to public CLBs. To customize, refer to the FAQ section on **How to Customize CLB**.

:::tip[Note]

Gateway exposes traffic externally through LoadBalancer-type Services, so CLB only uses layer 4 listeners (TCP/UDP). Layer 7 traffic first enters CLB layer 4 listeners, gets forwarded to EnvoyGateway Pods, then EnvoyGateway parses layer 4/7 traffic and forwards according to configuration rules.

:::

How to get the CLB address corresponding to `Gateway`? Use `kubectl get gtw`:

```bash
$ kubectl get gtw test-gw -n test
NAME      CLASS   ADDRESS         PROGRAMMED   AGE
test-gw   eg      139.155.64.52   True         358d
```

Where `ADDRESS` is the CLB address (IP or domain).

### Create HTTPRoute

`HTTPRoute` is used to define HTTP forwarding rules (layer 7 traffic) and is the most commonly used forwarding rule in Gateway API, similar to the `Ingress` resource in Ingress API.

Example below:

:::tip[Note]

All HTTPRoute fields refer to [API Specification: HTTPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRoute)

:::

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx
  namespace: test
spec:
  parentRefs:
  - name: test-gw
    namespace: test
  hostnames:
  - "test.example.com"
  rules:
  - backendRefs:
    - name: nginx
      port: 80
```

:::info[Note]

1. `parentRefs` specifies the `Gateway` (CLB) to reference, applying this rule to that `Gateway`.
2. `hostnames` defines the domains used by the forwarding rules. Ensure these domains resolve to the `Gateway`'s corresponding CLB so you can access cluster services via domain names.
3. `backendRefs` defines the backend Service corresponding to this forwarding rule.

:::

### Create TCPRoute and UDPRoute

`TCPRoute` and `UDPRoute` are used to define TCP and UDP forwarding rules (layer 4 traffic), similar to `LoadBalancer`-type `Service`.

:::tip[Note]

All TCPRoute and UDPRoute fields refer to [API Specification: TCPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#tcproute) and [API Specification: UDPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#udproute).

:::

First ensure Gateway has defined TCP and UDP ports:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: test-gw
  namespace: test
spec:
  gatewayClassName: eg
  listeners:
  - name: foo
    protocol: TCP
    port: 6000
    allowedRoutes:
      namespaces:
        from: All
  - name: bar
    protocol: UDP
    port: 6000
    allowedRoutes:
      namespaces:
        from: All
```

Then `TCPRoute` and `UDPRoute` can reference this Gateway:

<Tabs>
  <TabItem value="1" label="TCPRoute">

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: foo
spec:
  parentRefs:
  - namespace: test
    name: test-gw
    sectionName: foo
  rules:
  - backendRefs:
    - name: foo
      port: 6000
```

  </TabItem>
  <TabItem value="2" label="UDPRoute">

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: bar
spec:
  parentRefs:
  - namespace: test
    name: test-gw
    sectionName: bar
  rules:
  - backendRefs:
    - name: bar
      port: 6000
```

  </TabItem>
</Tabs>

:::info[Note]

1. `parentRefs` specifies the `Gateway` (CLB) to reference, indicating this TCP should listen on this `Gateway`. Usually only one port from the `Gateway` is used, so specify `sectionName` to indicate which listener to expose through.
2. `backendRefs` defines the backend Service corresponding to this forwarding rule.

:::

## Usage Examples

### Customize CLB

You can customize by creating `EnvoyProxy` custom resources. Example below:

```yaml showLineNumbers
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 1
        container:
          # highlight-add-start
          resources:
            requests:
              tke.cloud.tencent.com/eni-ip: "1"
            limits:
              tke.cloud.tencent.com/eni-ip: "1"
          # highlight-add-end
        pod:
          annotations:
            # highlight-add-line
            tke.cloud.tencent.com/networks: tke-route-eni
      envoyService:
        annotations:
          # highlight-add-start
          service.kubernetes.io/tke-existed-lbid: lb-5nhlk3nr
          service.cloud.tencent.com/direct-access: "true"
          # highlight-add-end
```

In the above example:

- Explicitly declare using VPC-CNI network mode and enable CLB direct-to-pod.
- Use existing CLB, specifying CLB ID.

Correspondingly, `Gateway` needs to reference this `EnvoyProxy` configuration:

```yaml showLineNumbers
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  # highlight-add-start
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: proxy-config
  # highlight-add-end
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      certificateRefs:
      - kind: Secret
        group: ""
        name: website-crt-secret
    allowedRoutes:
      namespaces:
        from: All
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
```

For more CLB-related customization, refer to [Service Annotation Description](https://cloud.tencent.com/document/product/457/51258).

Some common customization examples:

1. Use `service.cloud.tencent.com/specify-protocol` annotation to modify listener protocol to HTTPS and correctly reference SSL certificates to enable CLB integration with [Tencent Cloud WAF](https://cloud.tencent.com/product/waf).
2. Use `service.kubernetes.io/qcloud-loadbalancer-internal-subnetid` annotation to specify CLB private IP, enabling automatic creation of private CLB for traffic access.
3. Use `service.kubernetes.io/service.extensiveParameters` annotation to customize more properties of automatically created CLBs, such as specifying carriers, bandwidth limits, instance specifications, network billing modes, etc.

### Multiple HTTPRoutes Reusing Same CLB

Usually one `Gateway` object corresponds to one CLB. As long as different `HTTPRoute`s reference the same `Gateway` object in their `parentRefs`, they will reuse the same CLB.

:::info[Note]

If multiple `HTTPRoute`s reuse the same CLB, ensure their defined HTTP rules don't conflict, otherwise forwarding behavior may not match expectations.

:::

Example below. First `HTTPRoute`, referencing Gateway `test-gw`, using domain `test1.example.com`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test1
  namespace: test
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: test-gw
      namespace: test
  hostnames:
    - "test1.example.com"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: test1
          port: 80
```

Second `HTTPRoute`, also referencing Gateway `test-gw`, using domain `test2.example.com`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test2
  namespace: test
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: test-gw
      namespace: test
  hostnames:
    - "test2.example.com"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: test2
          port: 80
```

### Layer 4 and Layer 7 Sharing Same CLB

Using TKE's built-in `LoadBalancer`-type `Service`, you can achieve multiple `Service`s reusing the same CLB, meaning multiple layer 4 ports (TCP/UDP) reuse the same CLB. Using TKE's built-in `Ingress` (CLB Ingress), you cannot reuse the same CLB with any other `Ingress` or `LoadBalancer`-type `Service`. So if you need to achieve layer 4 and layer 7 sharing the same CLB, it's impossible with TKE's built-in CLB Service and CLB Ingress, but if you install `EnvoyGateway`, you can achieve it.

Example below. First `Gateway` listener declares layer 4 and layer 7 ports:

:::tip[Note]

Use `name` to give each listener a name for easy reference via `sectionName` later.

:::

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: test-gw
  namespace: test
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        group: ""
        name: https-cert
  - name: tcp-6000
    protocol: TCP
    port: 6000
    allowedRoutes:
      namespaces:
        from: All
  - name: udp-6000
    protocol: UDP
    port: 6000
    allowedRoutes:
      namespaces:
        from: All
```

`HTTPRoute` uses layer 7 listeners (80 and 443) from `Gateway`:

:::tip[Note]

Use `sectionName` to specify the exact listener to bind to.

:::

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test
  namespace: test
spec:
  parentRefs:
  - name: test-gw
    namespace: test
    sectionName: http
  - name: test-gw
    namespace: test
    sectionName: https
  hostnames:
  - "test.example.com"
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: nginx
      port: 80
```

`TCPRoute` and `UDPRoute` use layer 4 listeners (TCP/6000 and UDP/6000) from `Gateway`:

:::tip[Note]

Same as `HTTPRoute`, use `sectionName` to specify the exact listener to bind to.

:::

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: foo
spec:
  parentRefs:
  - namespace: test
    name: test-gw
    sectionName: tcp-6000
  rules:
  - backendRefs:
    - name: foo
      port: 6000
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: foo
spec:
  parentRefs:
  - namespace: test
    name: test-gw
    sectionName: udp-6000
  rules:
  - backendRefs:
    - name: foo
      port: 6000
```

### Automatic Redirect

Configure `HTTPRoute`'s `filters` to achieve automatic redirects. Examples below.

Replace path prefix `/api/v1` with `/apis/v1`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-api-v1
  namespace: test
spec:
  hostnames:
  - test.example.com
  parentRefs:
  - name: test-gw
    namespace: test
    sectionName: https
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /apis/v1
        statusCode: 301
```

> `http://test.example.com/api/v1/pods` will be redirected to `http://test.example.com/apis/v1/pods`

Redirect all paths starting with `/foo` to `/bar`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-api-v1
  namespace: test
spec:
  hostnames:
  - test.example.com
  parentRefs:
  - name: test-gw
    namespace: test
    sectionName: https
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /foo
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplaceFullPath
          replaceFullPath: /bar
        statusCode: 301
```

> `https://test.example.com/foo/cayenne` and `https://test.example.com/foo/paprika` will both be redirected to `https://test.example.com/bar`

HTTP to HTTPS redirect:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-https
  namespace: test
spec:
  hostnames:
  - test.example.com
  parentRefs:
  - name: test-gw
    namespace: test
    sectionName: http
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
        port: 443
```

> `http://test.example.com/foo` will be redirected to `https://test.example.com/foo`

### Configure HTTPS and TLS

Store certificates and keys in Kubernetes Secrets:

:::tip[Note]

If you don't want to manually manage certificates and prefer automatic issuance, consider using `cert-manager` for automatic certificate issuance. Refer to [Using cert-manager to Issue Free Certificates for dnspod Domains](https://imroc.cc/kubernetes/certs/sign-free-certs-for-dnspod).

:::

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-cert
  namespace: test
type: kubernetes.io/tls
data:
  tls.crt: ***
  tls.key: ***
```

Configure TLS in `Gateway` listeners (HTTPS or TLS protocol), reference certificate Secret in `tls` field:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: test-gw
  namespace: test
spec:
  gatewayClassName: eg
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        group: ""
        name: test-cert
  - name: tls
    protocol: TLS
    port: 9443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        group: ""
        name: test-cert
```

### Modify HTTP Headers

Use the `RequestHeaderModifier` filter in `HTTPRoute` to modify HTTP request headers.

Examples of modifying request headers:

:::tip[Note]

Modify headers for requests with paths starting with `/foo`.

:::

<Tabs>
  <TabItem value="add-header" label="Add Header">
    <FileBlock file="gwapi/add-header.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="set-header" label="Set Header">
    <FileBlock file="gwapi/set-header.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="remove-header" label="Remove Header">
    <FileBlock file="gwapi/remove-header.yaml" showLineNumbers />
  </TabItem>
</Tabs>

Modifying response headers is similar, just change `RequestHeaderModifier` to `ResponseHeaderModifier`:

```yaml
    filters:
    - type: ResponseHeaderModifier
      responseHeaderModifier:
        add:
        - name: X-Header-Add-1
          value: header-add-1
        - name: X-Header-Add-2
          value: header-add-2
        - name: X-Header-Add-3
          value: header-add-3
```

### Expose API Server

Refer to the following configuration:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller

---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 3 # Specify the number of EnvoyGateway gateway Pods
      envoyService:
        annotations:
          service.cloud.tencent.com/direct-access: "true" # Enable CLB direct-to-EnvoyGateway gateway Pod

---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: eg
  listeners: # Specify CLB external listening ports
  - name: apiserver
    protocol: TCP
    port: 443
    allowedRoutes:
      namespaces:
        from: All

---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: apiserver
  namespace: default
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: eg
    namespace: envoy-gateway-system
    sectionName: apiserver # Reference Gateway
  rules:
  - backendRefs: # Backend points to default/kubernetes apiserver service
    - group: ""
      kind: Service
      name: kubernetes
      port: 443
      weight: 1
```

## Explore More Usage

Gateway API is very powerful and can implement many complex functions, such as routing based on weights, headers, cookies; canary releases; traffic mirroring; URL redirects and rewrites; TLS routing; GRPC routing, etc. For more detailed usage, refer to [Gateway API Official Documentation](https://gateway-api.sigs.k8s.io/guides/http-routing/).

EnvoyGateway also supports some advanced capabilities beyond Gateway API. Refer to [EnvoyGateway Official Documentation](https://gateway.envoyproxy.io/latest/).
