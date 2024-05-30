# 在 TKE 上自建 Envoy Gateway

## 什么是 Envoy Gateway?

[EnvoyGateway](https://gateway.envoyproxy.io/) 是基于 [Envoy](https://www.envoyproxy.io/) 实现 [Gateway API](https://gateway-api.sigs.k8s.io/) 的 Kubernetes 网关，你可以通过定义 `Gateway API` 中定义的 `Gateway`、`HTTPRoute` 等资源来管理 Kubernetes 的南北向流量。

## 为什么要用 Gateway API？

Kubernetes 提供了 `Ingress API` 来接入七层南北向流量，但功能很弱，每种实现都带了不同的 annotation 来增强 Ingress 的能力，灵活性和扩展性也较差，在社区的推进下，推出了 `Gateway API` 作为更好的解决方案，解决 Ingress API 痛点的同时，还统一了四七层南北向流量，同时也支持服务网格的东西向流量（参考 [GAMMA](https://gateway-api.sigs.k8s.io/mesh/gamma/)），各个云厂商以及开源代理软件都在积极适配 `Gateway API`，可参考 [Gateway API 的实现列表](https://gateway-api.sigs.k8s.io/implementations/)，其中 Envoy Gateway 便是其中一个很流行的实现。

## 安装
