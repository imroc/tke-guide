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
  - toEndpoints: # 允许集群所有 Pod 通过 coredns 解析域名
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"
  endpointSelector:
    matchExpressions: # 不限制 kube-system 命名空间中 Pod 的 egress 流量
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system
 ```

## 统一管理 infrastructure 命名空间网络策略

集群中可能会部署许多基础设施应用，分散在多个命名空间，我们可以用 CiliumClusterwideNetworkPolicy + namespace label 来统一设置这些命名空间的网络策略（假设这些命名空间都打上了 `role=infrastructure` 这个 label）：

 ```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-infrastructure
spec:
  endpointSelector: # 选中所有基础设施命名空间中的 Pod
    matchLabels:
      io.cilium.k8s.namespace.labels.role: infrastructure
  egress:
  - toEndpoints: # 允许访问所有基础设施命名空间中的 Pod
    - matchLabels:
        io.cilium.k8s.namespace.labels.role: infrastructure
  - toFQDNs: # 允许调用腾讯云相关 API
    - matchPattern: '*.tencent.com'
    - matchPattern: '*.*.tencent.com'
    - matchPattern: '*.*.*.tencent.com'
    - matchPattern: '*.*.*.*.tencent.com'
    - matchPattern: '*.*.*.*.*.tencent.com'
    - matchPattern: '*.tencentcloudapi.com'
    - matchPattern: '*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.*.*.tencentcloudapi.com'
    - matchPattern: '*.tencentyun.com'
    - matchPattern: '*.*.tencentyun.com'
    - matchPattern: '*.*.*.tencentyun.com'
    - matchPattern: '*.*.*.*.tencentyun.com'
    - matchPattern: '*.*.*.*.*.tencentyun.com'
  - toCIDR: # 169.254 是腾讯云上的保留网段，一些内部服务会使用这个 IP，如 TKE 集群 apiserver 的 VIP、COS 存储、镜像仓库等。
    - 169.254.0.0/16
  - toEntities: # 允许访问 apiserver
    - kube-apiserver
  - toEntities: # 允许访问集群中所有节点的 10250 端口，可用于监控指标采集
    - host
    - remote-node
    toPorts:
    - ports:
      - port: "10250"
        protocol: TCP
 ```

## 允许部分 Pod 访问 apiserver

允许 `test` 命名空间下所有 pod 访问 apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-allow-apiserver
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
  name: from-a-to-apiserver
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

```yaml
apiVersion: cilium.io/v2
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

## 允许 A 被集群外部访问


```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-world-to-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  ingress:
  - fromEntities:
    - world
```

## 允许 A 访问指定域名的服务

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-a-to-domains
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toFQDNs:
    - matchName: 'imroc.cc'
    - matchPattern: '*.imroc.cc'
    - matchPattern: '*.*.*.myqcloud.com'
    - matchPattern: '*.tencent.com'
    - matchPattern: '*.*.tencent.com'
    - matchPattern: '*.*.*.tencent.com'
    - matchPattern: '*.*.*.*.tencent.com'
    - matchPattern: '*.*.*.*.*.tencent.com'
    - matchPattern: '*.tencentcloudapi.com'
    - matchPattern: '*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.*.tencentcloudapi.com'
    - matchPattern: '*.*.*.*.*.tencentcloudapi.com'
    - matchPattern: '*.tencentyun.com'
    - matchPattern: '*.*.tencentyun.com'
    - matchPattern: '*.*.*.tencentyun.com'
    - matchPattern: '*.*.*.*.tencentyun.com'
    - matchPattern: '*.*.*.*.*.tencentyun.com'
```

## 参考资料

- [Cilium NetworkPolicy Examples](https://docs.cilium.io/en/stable/security/policy/language/)

