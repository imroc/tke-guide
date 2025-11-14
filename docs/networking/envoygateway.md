# 在 TKE 使用 EnvoyGateway 流量网关

## 概述

[EnvoyGateway](https://gateway.envoyproxy.io/) 是基于 [Envoy](https://www.envoyproxy.io/) 实现 [Gateway API](https://gateway-api.sigs.k8s.io/) 的 Kubernetes 网关，你可以通过定义 `Gateway API` 中定义的 `Gateway`、`HTTPRoute` 等资源来管理 Kubernetes 的南北向流量。

本文将介绍如何在 TKE 上安装 EnvoyGateway 并使用 `Gateway API` 来接入和管理流量转发。

:::tip[说明]

Kubernetes 提供了 `Ingress API` 来接入七层南北向流量，但功能很弱，每种实现都带了不同的 annotation 来增强 Ingress 的能力，灵活性和扩展性也较差，在社区的推进下，推出了 `Gateway API` 作为更好的解决方案，解决 Ingress API 痛点的同时，还统一了四七层南北向流量，同时也支持服务网格的东西向流量（参考 [GAMMA](https://gateway-api.sigs.k8s.io/mesh/gamma/)），各个云厂商以及开源代理软件都在积极适配 `Gateway API`，可参考 [Gateway API 的实现列表](https://gateway-api.sigs.k8s.io/implementations/)，其中 Envoy Gateway 便是其中一个很流行的实现。

在 TKE 上使用 EnvoyGateway 相比自带的 CLB Ingress 还有一个明显的优势，就是多个转发规则资源（如`HTTPRoute`）可以复用同一个 CLB，且可以跨命名空间。CLB Ingress 必须将所有转发规则写到同一个 Ingress 资源中，不方便管理，且如果不同后端 Service 跨命名空间了，则无法用同一个 Ingress （CLB）来管理了。

:::

## 前提条件

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 确保 EnvoyGateway 支持当前的集群版本，参考 EnvoyGateway 官方文档 [Compatibility Matrix](https://gateway.envoyproxy.io/news/releases/matrix/)。（当前最新 v1.5 需集群版本 >= 1.30）。

## 安装 EnvoyGateway

建议通过 helm 直接安装，可使用社区最新版（TKE 应用市场的版本通常会及时更新，也不保证最新）。

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.6.0 \
  -n envoy-gateway-system \
  --create-namespace
```

> 参考 EnvoyGateway 官方文档 [Install with Helm](https://gateway.envoyproxy.io/docs/install/)。

## 基础用法
### 创建 GatewayClass

类似 `Ingress` 需要指定 `IngressClass`，Gateway API 中每个 `Gateway` 都需要引用一个 `GatewayClass`，`GatewayClass` 相当于是网关实例除监听器外的配置（如部署方式、网关 Pod 的 template、副本数量、关联的 Service 等），所以先创建一个 `GatewayClass`：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

> `GatewayClass` 是 non-namespaced 资源，无需指定命名空间。

### 创建 Gateway

每个 `Gateway` 对应一个 CLB，在 `Gateway` 上声明端口相当于在 CLB 上创建响应协议的监听器：

:::tip[说明]

Gateway 的所有字段参考 [API Specification: Gateway](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.Gateway)

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

> `Gateway` 可以指定命名空间，可以被 `HTTPRoute` 等路由规则跨命名空间引用。

`Gateway` 创建后，`EnvoyGateway` 会自动为其创建一个 LoadBalancer 类型的 Service，也就是一个 CLB。在 TKE 上，LoadBalancer 类型的 Service 默认是一个公网 CLB，如果要自定义，可参考常见问题中的**如何自定义 CLB**。

:::tip[说明]

Gateway 通过 LoadBalancer 类型的 Service 对外暴露流量，所以 CLB 只会用到四层监听器（TCP/UDP），七层流量也是先进入 CLB 四层监听器，转发给 EnvoyGateway 的 Pod，再由 EnvoyGateway 解析四七层流量并根据配置规则进行转发。

:::

如何获取 `Gateway` 对应的 CLB 地址呢？可以通过 `kubectl get gtw` 查看：

```bash
$ kubectl get gtw test-gw -n test
NAME      CLASS   ADDRESS         PROGRAMMED   AGE
test-gw   eg      139.155.64.52   True         358d
```

其中 `ADDRESS` 就是 CLB 的地址（IP 或域名）。

### 创建 HTTPRoute

`HTTPRoute` 用于定义 HTTP 转发规则（七层流量），也是 Gateway API 中最常用的转发规则，类似 Ingress API 中的 `Ingress` 资源。

下面给出一个示例：

:::tip[说明]

HTTPRoute 的所有字段参考 [API Specification: HTTPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRoute)

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

:::info[注意]

1. `parentRefs` 中指定要引用 `Gateway`(CLB)，表示将该规则应用到这个 `Gateway` 中。
2. `hostnames` 定义转发规则使用的的域名，确保该域名解析到 `Gateway` 对应的 CLB，这样可以通过域名访问集群内的服务。
3. `backendRefs` 定义该条转发规则对应的后端 Service。

:::

### 创建 TCPRoute 和 UDPRoute

`TCPRoute` 和 `UDPRoute` 用于定义 TCP 和 UDP 转发规则（四层流量），类似 `LoadBalancer` 类型的 `Service`。

:::tip[说明]

TCPRoute 和 UDPRoute 的所有字段参考 [API Specification: TCPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#tcproute) 和 [API Specification: UDPRoute](https://gateway-api.sigs.k8s.io/reference/spec/#udproute)。

:::

首先确保 Gateway 上有定义 TCP 和 UDP 的端口：

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

然后 `TCPRoute` 和 `UDPRoute` 可引用该 Gateway，的示例：

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

  ```yaml
  ```

  </TabItem>
</Tabs>

:::info[注意]

1. `parentRefs` 指定要引用的`Gateway`(CLB)，表示将该 TCP 要监听到这个 `Gateway` 中。通常只使用 `Gateway` 中的一个端口，所以指定 `sectionName` 来指定使用哪个监听器暴露。
2. `backendRefs` 定义该条转发规则对应的后端 Service。

:::


## 使用案例

### 自定义 CLB

可通过创建 `EnvoyProxy` 自定义资源来自定义，下面是示例：

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

以上示例中：

* 显式声明使用 VPC-CNI 网络模式且启用 CLB 直连 Pod。
* 使用已有 CLB，指定了 CLB 的 ID。

相应的，`Gateway` 中需引用该 `EnvoyProxy` 配置:

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

更多 CLB 相关的自定义可参考 [Service Annotation 说明](https://cloud.tencent.com/document/product/457/51258)。

举几个常见的自定义例子：
1. 通过 `service.cloud.tencent.com/specify-protocol` 注解来修改监听器协议为 HTTPS 并正确引用 SSL 证书，以便让 CLB 能够接入 [腾讯云 WAF](https://cloud.tencent.com/product/waf)。
2. 通过 `service.kubernetes.io/qcloud-loadbalancer-internal-subnetid` 注解指定 CLB 内网 IP，实现自动创建内网 CLB 来接入流量。
3. 通过 `service.kubernetes.io/service.extensiveParameters` 注解自定义自动创建的 CLB 更多属性，如指定运营商、带宽上限、实例规格、网络计费模式等。

### 多个 HTTPRoute 复用同一个 CLB

通常一个 `Gateway` 对象就对应一个 CLB，只要不同 `HTTPRoute` 的 `parentRefs` 引用的是同一个 `Gateway` 对象，那么它们就会复用同一个 CLB。

:::info[注意]

如果多个 `HTTPRoute` 复用同一个 CLB，确保它们定义的 HTTP 规则不要冲突，否则可能转发行为可能不符预期。

:::

下面给个示例，第一个 `HTTPRoute`，引用 Gateway `test-gw`，使用域名 `test1.example.com`：

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

第二个 `HTTPRoute`，也引用 Gateway `test-gw`，域名则使用 `test2.example.com`：

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

### 四七层共用同一个 CLB

使用 TKE 自带的 `LoadBalancer` 类型的 `Service`，可以实现多个 `Service` 复用同一个 CLB，也就是多个四层端口（TCP/UDP）复用同一个 CLB；使用 TKE 自带的 `Ingress` （CLB Ingress），无法与任何其它 `Ingress` 和 `LoadBalancer` 类型的 `Service` 复用同一个 CLB。所以，如果需要实现四七层共用同一个 CLB，直接使用 TKE 自带的 CLB Service 和 CLB Ingress 无法实现，而如果你安装了 `EnvoyGateway` 的话就可以实现。

下面给个示例， 首先 `Gateway` 的监听器声明四层和七层的端口：

:::tip[注意]

使用 `name` 给每个监听器取个名字，方便后续通过 `sectionName` 引用。

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

`HTTPRoute` 里使用 `Gateway` 里的七层监听器（80 和 443）：

:::tip[注意]

使用 `sectionName` 指定具体要绑定的监听器。

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

`TCPRoute` 和 `UDPRoute` 里使用 `Gateway` 里的四层监听器（TCP/6000 和 UDP/6000）：

:::tip[注意]

与 `HTTPRoute` 一样，使用 `sectionName` 指定具体要绑定的监听器。

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

### 自动重定向

通过配置 `HTTPRoute` 的 `filters` 可实现自动重定向，下面给出示例。

路径前缀 `/api/v1` 替换成 `/apis/v1`：

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

> `http://test.example.com/api/v1/pods` 会被重定向到 `http://test.example.com/apis/v1/pods`

以 `/foo` 开头的统一重定向到 `/bar`：

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

> `https://test.example.com/foo/cayenne` 和 `https://test.example.com/foo/paprika` 都会被重定向到 `https://test.example.com/bar`

HTTP 重定向到 HTTPS：

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

> `http://test.example.com/foo` 会被重定向到 `https://test.example.com/foo`

### 配置 HTTPS 与 TLS

将证书和密钥存储在 Kubernetes 的 Secret 中：

:::tip[说明]

如果不想手动管理证书，希望证书自动签发，可考虑使用 `cert-manager` 来自动签发。参考 [使用 cert-manager 为 dnspod 的域名签发免费证书](https://imroc.cc/kubernetes/certs/sign-free-certs-for-dnspod)。

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

在 `Gateway` 的 listeners 中配置 TLS（HTTPS 或 TLS 协议），`tls` 字段里引用证书 Secret：

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

### 修改 HTTP Header

在 `HTTPRoute` 中使用 `RequestHeaderModifier` 这个 filter 可以修改 HTTP 请求的 Header。

以下是修改请求 Header 的例子：

:::tip[说明]

对路径以 `/foo` 开头的请求修改 Header。

:::

<Tabs>
  <TabItem value="add-header" label="增加Header">
    <FileBlock file="gwapi/add-header.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="set-header" label="修改Header">
    <FileBlock file="gwapi/set-header.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="remove-header" label="删除Header">
    <FileBlock file="gwapi/remove-header.yaml" showLineNumbers />
  </TabItem>
</Tabs>

如果要改响应的 Header 也是类似的，`RequestHeaderModifier` 改成 `ResponseHeaderModifier` 即可：

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

### 暴露 apiserver

参考以下配置：

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
        replicas: 3 # 指定 EnvoyGateway 网关 Pod 的数量
      envoyService:
        annotations:
          service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直连 EnvoyGateway 网关 Pod

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
  listeners: # 指定 CLB 对外的监听端口
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
    sectionName: apiserver # 引用 Gateway
  rules:
  - backendRefs: # 后端指向 default/kubernetes 这个 apiserver 的 service
    - group: ""
      kind: Service
      name: kubernetes
      port: 443
      weight: 1
```

## 探索更多用法

Gateway API 非常强大，可实现很多复杂的功能，如基于权重、header、cookie 等特征的路由、灰度发布、流量镜像、URL重定向与重写、TLS 路由、GRPC 路由等，更详细的用法参考 [Gateway API 官方文档](https://gateway-api.sigs.k8s.io/guides/http-routing/)。

EnvoyGateway 也支持了 Gateway API 之外的一些特有的高级能力，可参考 [EnvoyGateway 官方文档](https://gateway.envoyproxy.io/latest/)。
