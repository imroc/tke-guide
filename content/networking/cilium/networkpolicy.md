# NetworkPolicy 应用实践

## 默认拒绝 egress 流量

集群默认拒绝 egress 流量（dns 解析除外，kube-system 命名空间中的 pod 除外），严格控制集群 Pod 的网络访问权限：

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

允许 `test` 命名空间下的 A 服务访问 apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-debug-to-apiserver
  namespace: test
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEntities:
    - kube-apiserver
```

## 允许 A 访问 B

允许 A 服务访问 B 服务：

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: egress-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEndpoints:
    - matchLabels:
        app: b
```

## 限制 B 只能被 A 访问

限制 B 服务只能被 A 服务访问：

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: ingress-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: b
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: a
```

## 允许 A 访问同名空间下的所有 Pod 

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-all-from-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEndpoints:
    - {}
```


## 禁止 A 访问 B


禁止 A 服务访问 B 服务：

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEntities:
    - all
  egressDeny:
  - toEndpoints:
    - matchLabels:
        app: b
```
