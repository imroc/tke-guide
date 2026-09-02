# 问题排查：Overlay 模式下 Webhook 连接超时

适用于使用 Overlay 方案（VPC-CNI 或 GR）的 TKE 托管集群：apiserver 调用 ValidatingWebhook / MutatingWebhook 时连接超时。

## 问题现象

在 Overlay 模式的 TKE 托管集群中，apiserver 调用 ValidatingWebhook / MutatingWebhook 时连接超时（如 cert-manager 的 `webhook.cert-manager.io`），报错 `context deadline exceeded` 或 `Client.Timeout exceeded while awaiting headers`。

## 根因

TKE 托管集群的 apiserver 运行在管控面（MetaCluster），管控面上没有 cilium-agent，也就没有 cilium 的 overlay 隧道。apiserver 通过 Service ClusterIP → EndpointSlice 访问 webhook Pod 时，EndpointSlice 中的 Pod IP 是 overlay 网段（如 `10.244.x.x`），管控面到 overlay 网段没有路由，因此连接超时。

```text
apiserver (管控面, 无 cilium-agent)
  → Service ClusterIP
  → EndpointSlice: 10.244.x.x (overlay Pod IP)
  → ❌ 管控面无 overlay 隧道，路由不可达
```

Native Routing 模式没有此问题——Pod IP 是 VPC IP，apiserver 可以直接路由。

## 解决方案

Webhook Pod 使用 `hostNetwork: true`，这样 Pod IP 就是节点 IP（VPC IP），apiserver 可直接路由到达。配合 `podAntiAffinity` 将 webhook Pod 打散到不同节点保证高可用：

```yaml
spec:
  hostNetwork: true  # Pod IP = 节点 IP，apiserver 可直达
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: <webhook-name>
        topologyKey: kubernetes.io/hostname
```

:::tip[常见需要 hostNetwork 的组件]

以下组件在 Overlay 模式下通常需要 `hostNetwork: true` 才能正常工作：

- cert-manager webhook
- 各类自定义 admission webhook（如 Gatekeeper、OPA）
- 任何被 apiserver 主动调用的 webhook 服务

:::
