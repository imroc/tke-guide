# 在 TKE 使用 EnvoyGateway

## 什么是 Envoy Gateway?

[EnvoyGateway](https://gateway.envoyproxy.io/) 是基于 [Envoy](https://www.envoyproxy.io/) 实现 [Gateway API](https://gateway-api.sigs.k8s.io/) 的 Kubernetes 网关，你可以通过定义 `Gateway API` 中定义的 `Gateway`、`HTTPRoute` 等资源来管理 Kubernetes 的南北向流量。

## 为什么要用 Gateway API？

Kubernetes 提供了 `Ingress API` 来接入七层南北向流量，但功能很弱，每种实现都带了不同的 annotation 来增强 Ingress 的能力，灵活性和扩展性也较差，在社区的推进下，推出了 `Gateway API` 作为更好的解决方案，解决 Ingress API 痛点的同时，还统一了四七层南北向流量，同时也支持服务网格的东西向流量（参考 [GAMMA](https://gateway-api.sigs.k8s.io/mesh/gamma/)），各个云厂商以及开源代理软件都在积极适配 `Gateway API`，可参考 [Gateway API 的实现列表](https://gateway-api.sigs.k8s.io/implementations/)，其中 Envoy Gateway 便是其中一个很流行的实现。

## 安装

在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 搜索或在 `网络` 分类中找到 `envoygateway`，点击【创建应用】，命名空间选 `envoy-gateway-system`，若没有则先新建一个，完成其余配置后点击【创建】将 envoygateway 安装到集群中。

## 配置 kubectl 访问集群

EnvoyGateway 使用的是 Gateway API 而不是 Ingress API，在 TKE 控制台无法直接创建，可通过 kubectl 命令进行创建，参考 [连接集群](https://cloud.tencent.com/document/product/457/32191) 这篇文档配置 kubectl。

## 创建 GateawyClass

类似 `Ingress`，Gateway API 中每个 `Gateway` 都需要引用一个 `GatewayClass`，所以先创建一个 `GatewayClass`：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

> `GatewayClass` 是 non-namespaced 资源，无需指定命名空间。

## 创建 Gateway

每个 `Gateway` 对应一个 CLB，在 `Gateway` 上声明端口相当于在 CLB 上创建响应协议的监听器：

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

`Gateway` 创建后，`EnvoyGateway` 会自动为其创建一个 LoadBalancer 类型的 Service，也就是一个 CLB。在 TKE 上，LoadBalancer 类型的 Service 默认是一个公网 CLB，如果要自定义，可通过创建 `EnvoyProxy` 自定义资源来自定义，下面是示例：

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: proxy-config
  namespace: test
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 1
        container:
          resources:
            requests:
              tke.cloud.tencent.com/eni-ip: "1"
            limits:
              tke.cloud.tencent.com/eni-ip: "1"
        pod:
          annotations:
            tke.cloud.tencent.com/networks: tke-route-eni
      envoyService:
        annotations:
          service.kubernetes.io/tke-existed-lbid: lb-5nhlk3nr
          service.cloud.tencent.com/direct-access: "true"
```

以上示例中：

* 显式声明使用 VPC-CNI 网络模式且启用 CLB 直连 Pod。
* 使用已有 CLB。

相应的，`GatewayClass` 中需引用该 `EnvoyProxy` 配置:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: proxy-config
    namespace: test
```

更多 CLB 相关的自定义可参考 [Service Annotation 说明](https://cloud.tencent.com/document/product/457/51258)。

## 创建 HTTPRoute

`HTTPRoute` 用于定义 HTTP 转发规则，也是 Gateway API 中最常用的转发规则，类似 Ingress API 中的 `Ingress` 资源。

在 `HTTPRoute` 中引用 `Gateway`，表示将该规则应用到这个 `Gateway` 中：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx
  namespace: test
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: test-gw
      namespace: test
  hostnames:
    - "test.example.com"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: nginx
          port: 80
```
