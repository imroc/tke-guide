# NetworkPolicy 应用实践

## 默认拒绝 egress 流量

集群默认拒绝 egress 流量（dns 解析除外，kube-system 命名空间中的 pod 除外）：

 ```yaml title="default-deny.yaml"
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny
spec:
  description: "Block all the traffic (except DNS) by default"
  egress:
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: '53'
        protocol: UDP
      rules:
        dns:
        - matchPattern: '*'
  endpointSelector:
    matchExpressions:
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system
 ```

## 允许部分 Pod 访问 apiserver

允许 `test` 命名空间下所有 pod 访问 apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-apiserver
  namespace: test
spec:
  endpointSelector: {}
  egress:
  - toEntities:
    - kube-apiserver
```

允许 `test` 命名空间下有 `app=test` 的 pod 请求 apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-debug-to-apiserver
  namespace: test
spec:
  endpointSelector:
    matchLabels:
      app: test
  egress:
  - toEntities:
    - kube-apiserver
```
