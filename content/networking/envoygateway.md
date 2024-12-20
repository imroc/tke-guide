# 在 TKE 使用 EnvoyGateway 流量网关

## 什么是 Envoy Gateway ?

[EnvoyGateway](https://gateway.envoyproxy.io/) 是基于 [Envoy](https://www.envoyproxy.io/) 实现 [Gateway API](https://gateway-api.sigs.k8s.io/) 的 Kubernetes 网关，你可以通过定义 `Gateway API` 中定义的 `Gateway`、`HTTPRoute` 等资源来管理 Kubernetes 的南北向流量。

## 为什么要用 Gateway API ？

Kubernetes 提供了 `Ingress API` 来接入七层南北向流量，但功能很弱，每种实现都带了不同的 annotation 来增强 Ingress 的能力，灵活性和扩展性也较差，在社区的推进下，推出了 `Gateway API` 作为更好的解决方案，解决 Ingress API 痛点的同时，还统一了四七层南北向流量，同时也支持服务网格的东西向流量（参考 [GAMMA](https://gateway-api.sigs.k8s.io/mesh/gamma/)），各个云厂商以及开源代理软件都在积极适配 `Gateway API`，可参考 [Gateway API 的实现列表](https://gateway-api.sigs.k8s.io/implementations/)，其中 Envoy Gateway 便是其中一个很流行的实现。

## 安装 EnvoyGateway

### 方法一：通过应用市场安装

在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 搜索或在 `网络` 分类中找到 `envoygateway`，点击【创建应用】，命名空间选 `envoy-gateway-system`，若没有则先新建一个，完成其余配置后点击【创建】即可将 envoygateway 安装到集群中。

### 方法二：通过 Helm 安装

首先确保本机安装了 helm 并能操作 TKE 集群，参考 [本地 Helm 客户端连接集群](https://cloud.tencent.com/document/product/457/32731)。

然后再参考 EnvoyGateway 官方文档 [使用 Helm 安装](https://gateway.envoyproxy.io/zh/latest/install/install-helm/) 进行安装。

## 配置 kubectl 访问集群

EnvoyGateway 使用的是 Gateway API 而不是 Ingress API，在 TKE 控制台无法直接创建，可通过 kubectl 命令进行创建，参考 [连接集群](https://cloud.tencent.com/document/product/457/32191) 这篇文档配置 kubectl。

## 创建 GatewayClass

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

举几个常见的自定义例子：
1. 通过 `service.cloud.tencent.com/specify-protocol` 注解来修改监听器协议为 HTTPS 并正确引用 SSL 证书，以便让 CLB 能够接入 [腾讯云 WAF](https://cloud.tencent.com/product/waf)。
2. 通过 `service.kubernetes.io/qcloud-loadbalancer-internal-subnetid` 注解指定 CLB 内网 IP，实现自动创建内网 CLB 来接入流量。
3. 通过 `service.kubernetes.io/service.extensiveParameters` 注解自定义自动创建的 CLB 更多属性，如指定运营商、带宽上限、实例规格、网络计费模式等。

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

确保在 `hostnames` 里定义的域名解析到 `Gateway` 对应的 CLB，然后就可以通过域名访问集群内的服务了。

## 探索更多用法

Gateway API 非常强大，可实现很多复杂的功能，如基于权重、header、cookie 等特征的路由、灰度发布、流量镜像、URL重定向与重写、TLS 路由、GRPC 路由等，更详细的用法参考 [Gateway API 官方文档](https://gateway-api.sigs.k8s.io/guides/http-routing/)。

EnvoyGateway 也支持了 Gateway API 之外的一些特有的高级能力，可参考 [EnvoyGateway 官方文档](https://gateway.envoyproxy.io/latest/)。
