---
sidebar_position: 1
---

# Using Traefik Traffic Gateway on TKE

## Overview

[Traefik](https://doc.traefik.io/traefik/) is a modern cloud-native reverse proxy tool that offers significant advantages over Nginx:

- Supports three traffic management configuration methods simultaneously: Kubernetes Ingress API, Traefik CRD, and Gateway API.
- Provides a feature-rich Dashboard management interface supporting visual route configuration and monitoring.
- Deeply integrates with Prometheus to provide complete Metrics data for monitoring and alerting.
- Supports rich traffic governance features including: multi-version canary releases, traffic mirroring, automatic Let's Encrypt HTTPS certificate issuance, flexible middleware mechanisms, etc.

This article describes how to deploy Traefik in TKE clusters and manage traffic through various configuration methods.

## Installing Traefik

1. Search for `traefik` in the [TKE Application Market](https://console.cloud.tencent.com/tke2/helm/market).
2. Click `traefik` to enter the application details page.
3. Click **Create Application**.
4. Suggested application name: `traefik`, select the target cluster where Traefik should be installed.
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F03%2F20250303153635.png)
5. Refer to the **Traefik Parameter Configuration** section below, configure parameters according to requirements, then click **Create** to install Traefik into the cluster.
6. After installation, find the Traefik application in [Application Management](https://console.cloud.tencent.com/tke2/helm), click the application name to enter the details page, and check the CLB address information in the **Service** section. Configure DNS resolution for the domains you need to use, ensuring domains resolve to Traefik's CLB address.
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F03%2F20250303171704.png)

If you need to modify configurations later, find the Traefik application in [Application Management](https://console.cloud.tencent.com/tke2/helm), click **Update Application** and edit parameters.

## Traefik Parameter Configuration

Here are some parameter configuration recommendations for installing Traefik, which can be modified according to requirements.

:::tip[Note]

This article uses the TKE Application Market to install Traefik. Applications installed via the TKE Application Market are Helm charts, where the Traefik application is sourced from the open-source community's [traefik-helm-chart](https://github.com/traefik/traefik-helm-chart). Parameter configuration (`values.yaml`) is completely consistent with the community (except for image addresses). If you install via Helm, you can also refer to the parameter configuration suggestions here.

:::

### Enable CLB Direct-to-Pod

It's recommended to enable CLB direct-to-pod, so CLB can forward traffic directly to Pods without going through NodePort, reducing latency. Traefik itself can perceive the real source IP, and backend business Pods can obtain the real source IP through headers.

:::tip[Note]

For more details, refer to [Using LoadBalancer Direct-to-Pod Mode Service](https://cloud.tencent.com/document/product/457/41897).

:::

Configuration method:

```yaml
service:
  annotations:
    service.cloud.tencent.com/direct-access: "true"
```

### Use Existing CLB

If you already have a CLB created, you can specify the CLB instance ID:

:::tip[Note]

For more details, refer to [Service Using Existing CLB](https://cloud.tencent.com/document/product/457/45491).

:::

:::info[Note]

Replace `lb-xxx` with your existing CLB instance ID.

:::

```yaml
service:
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxx
```

### Public and Private Network Simultaneous Access

By default, a public CLB is created. You can achieve simultaneous access via both private and public CLBs with similar configuration:

:::info[Note]

Automatic creation of private CLB requires specifying subnet ID, replace `subnet-xxxxxxxx`.

:::

<Tabs>
  <TabItem value="1" label="Auto Create">
    <FileBlock file="traefik/dubble-clb-autocreate-values.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="2" label="Use Existing CLB">

  :::info[Note]
  
  You need to create the private CLB yourself, obtain the instance ID and replace `lb-xxx` in the configuration.
  
  :::

  <FileBlock file="traefik/dubble-clb-use-exsisted-values.yaml" showLineNumbers />

  </TabItem>
</Tabs>

### IPv4 and IPv6 Simultaneous Access

By default, an IPv4 CLB is created. You can achieve simultaneous access via both IPv6 and IPv4 CLBs with similar configuration:

:::tip[Note]

For more details, refer to [Using IPv6 on TKE](ipv6).

:::

<Tabs>
  <TabItem value="1" label="Auto Create">
    <FileBlock file="traefik/dualstack-clb-autocreate-values.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="2" label="Use Existing CLB">

  :::info[Note]
  
  You need to create the IPv6 CLB yourself, obtain the instance ID and replace `lb-xxx` in the configuration.
  
  :::

  <FileBlock file="traefik/dualstack-clb-use-exsisted-values.yaml" showLineNumbers />

  </TabItem>
</Tabs>

### Enable Gateway API

Gateway API support is not enabled by default. Enable it with the following configuration:

```yaml
providers:
  kubernetesGateway:
    enabled: true
gateway:
  enabled: false # Disable automatic creation of Gateway objects in the same namespace as Traefik, recommend creating manually as needed (one or more, can cross namespaces).
```

If you want to simultaneously disable Ingress and Traefik's own CRD support, use the following configuration:

```yaml
providers:
  kubernetesGateway:
    enabled: true
  kubernetesIngress:
    enabled: false
  kubernetesCRD:
    enabled: false
```

## Using Ingress to Manage Traffic

Traefik supports using Kubernetes Ingress resources as dynamic configuration. You can directly create Ingress resources in the cluster for external exposure, adding the specified IngressClass (customizable during Traefik installation, default is traefik). Example:

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata: 
  name: test-ingress
spec:
  # highlight-add-line
  ingressClassName: traefik
  rules:
  - host: traefik.demo.com
    http:
      paths:
      - path: /test
        backend:
          serviceName: nginx
          servicePort: 80
```

:::info[Note]

TKE has not yet productized Traefik, so you cannot directly create Ingress visually in the TKE console. You need to create using YAML.

:::

## Using Traefik CRD to Manage Traffic

Traefik not only supports standard Kubernetes Ingress resources but also Traefik-specific CRD resources like IngressRoute, which can support more advanced features that Ingress lacks. IngressRoute usage example:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata: 
  name: test-ingressroute
spec: 
  entryPoints: 
    - web
  routes: 
    - match: Host(`traefik.demo.com`) && PathPrefix(`/test`)
      kind: Rule
      services: 
        - name: nginx
          port: 80
```

:::tip[Note]

For more Traefik usage, refer to [Traefik Official Documentation](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/).

:::

## Using Gateway API to Manage Traffic

Traefik also supports [Gateway API](https://gateway-api.sigs.k8s.io/). If you enable Gateway API support, you can use the Gateway API approach to manage traffic. Examples below.

First create a Gateway object (defined ports automatically map to corresponding LoadBalancer Services, exposed through CLB listeners):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gw
  namespace: prod
spec:
  gatewayClassName: traefik # Specify the automatically created GatewayClass name
  listeners:
  - name: http
    protocol: HTTP
    port: 8000
    allowedRoutes:
      namespaces:
        from: All
```

Then define forwarding rules (like `HTTPRoute`) and reference the Gateway object:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: foo
  namespace: prod
spec:
  parentRefs: # Reference Gateway object
  - name: prod-gw
    namespace: prod
  hostnames:
  - "foo.example.com"
  rules:
  - backendRefs:
    - name: foo
      port: 8000
```