# NetworkPolicy 应用实践

## NetworkPolicy vs CiliumNetworkPolicy

Kubernetes 原生的 NetworkPolicy 和 Cilium 的 CiliumNetworkPolicy 都用于定义 Pod 间的网络访问控制策略，但 CiliumNetworkPolicy 在功能上更加强大和灵活。虽然 Cilium 也兼容 NetworkPolicy，但既然安装了 Cilium 就建议使用功能更强大的 CiliumNetworkPolicy。

### 核心功能对比

| 特性             | NetworkPolicy          | CiliumNetworkPolicy                 |
| ---------------- | ---------------------- | ----------------------------------- |
| **作用域**       | 命名空间级别           | 命名空间级别                        |
| **基本流量控制** | ✅ 支持 ingress/egress | ✅ 支持 ingress/egress              |
| **Pod 选择器**   | ✅ 基于 label 选择     | ✅ 支持更复杂的表达式               |
| **L3/L4 规则**   | ✅ IP/端口控制         | ✅ IP/端口控制                      |
| **L7 协议感知**  | ❌ 不支持              | ✅ 支持 HTTP/gRPC/Kafka 等          |
| **FQDN 支持**    | ❌ 不支持              | ✅ 支持域名匹配                     |
| **显式拒绝规则** | ❌ 只能隐式拒绝        | ✅ 支持 `egressDeny`/`ingressDeny`  |
| **实体选择器**   | ❌ 不支持              | ✅ 支持 `toEntities`/`fromEntities` |
| **DNS 感知**     | ❌ 不支持              | ✅ 支持 DNS 规则                    |
| **服务选择器**   | ❌ 不支持              | ✅ 支持 `toServices`                |

### 主要差异说明

**1. L7 协议感知**
- NetworkPolicy 只能控制到 L3/L4 层（IP 地址和端口）。
- CiliumNetworkPolicy 可以深入到 L7 层，控制 HTTP 方法、路径、header，gRPC 方法等。

**2. FQDN 域名支持**
- NetworkPolicy 只能使用 IP 或 CIDR，无法直接控制域名访问。
- CiliumNetworkPolicy 支持 `toFQDNs`，可以直接使用域名和通配符模式。

**3. 显式拒绝规则**
- NetworkPolicy 采用白名单模式，未匹配的流量默认拒绝，但无法显式拒绝特定流量。
- CiliumNetworkPolicy 支持 `egressDeny`/`ingressDeny`，可以在允许大部分流量的同时显式拒绝特定目标。

**4. 实体选择器**
- NetworkPolicy 需要通过 CIDR 或选择器间接指定目标。
- CiliumNetworkPolicy 提供 `toEntities`/`fromEntities`，可以直接选择 `kube-apiserver`、`host`、`remote-node`、`world` 等预定义实体。

**5. 选择器灵活性**
- NetworkPolicy 使用标准的 `podSelector` 和 `namespaceSelector`。
- CiliumNetworkPolicy 的 `endpointSelector` 支持更复杂的表达式。

### 兼容性

- Cilium 完全兼容 Kubernetes 原生 NetworkPolicy。
- 可以在同一集群中混用两种策略类型。

## CiliumNetworkPolicy vs CiliumClusterwideNetworkPolicy

CiliumNetworkPolicy 和 CiliumClusterwideNetworkPolicy 的核心区别在于作用域和管理方式，它们的策略语法完全相同。

### 核心差异

| 特性               | CiliumNetworkPolicy | CiliumClusterwideNetworkPolicy        |
| ------------------ | ------------------- | ------------------------------------- |
| **作用域**         | 命名空间级别        | 集群级别                              |
| **资源类型**       | 命名空间资源        | 集群资源（无命名空间）                |
| **管理权限**       | 命名空间管理员      | 集群管理员                            |
| **选择器默认范围** | 同命名空间 Pod      | 集群所有 Pod                          |
| **跨命名空间选择** | 需要显式指定        | 天然支持                              |
| **策略优先级**     | 普通优先级          | 较高优先级                            |
| **节点防火墙**     | ❌ 不支持           | ✅ 支持（通过 nodeSelector 选中节点） |
| **使用场景**       | 应用级策略          | 集群基线策略                          |

### 主要差异说明

**1. 作用域和资源位置**
- CiliumNetworkPolicy 必须创建在特定命名空间中，通过 `metadata.namespace` 指定。
- CiliumClusterwideNetworkPolicy 是集群级资源，没有命名空间概念。

**2. 选择器行为**
- CiliumNetworkPolicy 的 `endpointSelector` 默认只选择同命名空间的 Pod。
- CiliumClusterwideNetworkPolicy 的 `endpointSelector` 可以选择集群中任意命名空间的 Pod。

**3. 跨命名空间访问控制**
- CiliumNetworkPolicy 控制跨命名空间访问时，需要在 `toEndpoints`/`fromEndpoints` 中显式指定命名空间标签。
- CiliumClusterwideNetworkPolicy 可以直接通过命名空间标签统一管理多个命名空间的策略。

**4. 管理权限和职责分离**
- CiliumNetworkPolicy 可以由命名空间管理员（有该命名空间权限的用户）管理。
- CiliumClusterwideNetworkPolicy 需要集群管理员权限，适合平台团队管理。

**5. 策略合并和优先级**
- 当同一个 Pod 同时被两种策略选中时，规则会合并生效。
- 拒绝规则（`egressDeny`/`ingressDeny`）优先于允许规则。
- 通常使用 CiliumClusterwideNetworkPolicy 设置安全基线，用 CiliumNetworkPolicy 添加应用特定规则。

**6. 配置节点防火墙**
- CiliumClusterwideNetworkPolicy 支持将网络策略应用到节点上，用于设置节点维度防火墙。
- 这种策略只能由 CiliumClusterwideNetworkPolicy 来配置，CiliumNetworkPolicy 不支持。

### 典型使用场景

**CiliumNetworkPolicy 适用于：**
- 微服务之间的访问控制。
- 应用特定的网络隔离需求。
- 开发团队自主管理的网络策略。
- 命名空间内的细粒度控制。

**CiliumClusterwideNetworkPolicy 适用于：**
- 集群默认拒绝策略（default deny）。
- 统一管理多个基础设施命名空间的网络策略。
- 全局安全基线和合规要求。
- 跨命名空间的统一访问控制。
- 限制对敏感资源（如 kube-apiserver）的访问。
- 配置节点防火墙。

### 最佳实践

**分层管理策略：**
1. 使用 CiliumClusterwideNetworkPolicy 设置集群安全基线（如默认拒绝、DNS 访问、基础设施互通）。
2. 使用 CiliumNetworkPolicy 实现应用特定的网络策略（如服务间调用、外部 API 访问）。

**权限分离：**
- 平台团队管理 CiliumClusterwideNetworkPolicy，确保集群整体安全。
- 应用团队管理 CiliumNetworkPolicy，满足业务需求。

**命名规范：**
- 集群策略使用描述性前缀，如 `default-deny-all`、`global-infrastructure`。
- 命名空间策略使用应用相关名称，如 `frontend-to-backend`、`allow-external-api`。

## 用法实践
### 安全基线：默认拒绝

集群默认拒绝 egress 流量（dns 解析除外，kube-system 命名空间中的 pod 除外），严格控制集群 Pod 的网络访问权限：

:::tip[备注]

通常 ingress 流量不设置全局的默认拒绝，可针对敏感业务单独设置 ingress 策略（如只允许某些服务访问）。

:::

 ```yaml
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

### 统一管控基础设施的网络策略

集群中可能会部署许多基础设施相关应用，分散在多个命名空间，我们可以用 CiliumClusterwideNetworkPolicy 和命名空间标签来统一设置这些命名空间的网络策略（假设这些命名空间都打上了 `role=infrastructure` 这个 label）：

 ```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-infrastructure
spec:
  endpointSelector: # 选中所有基础设施命名空间中的 Pod
    matchLabels:
      io.cilium.k8s.namespace.labels.role: infrastructure
  egress: # 配置 egress 策略
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

### 配置节点防火墙

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-host-firewall
spec:
  nodeSelector: {} # 选中所有节点
  ingress:
  - fromEntities:
    - cluster # 不限制集群内的流量
  - toPorts:
    - ports: # 允许 ssh 访问
      - port: "22"
        protocol: TCP
  - icmps: # 允许 ping 请求
    - fields:
      - type: EchoRequest
        family: IPv4
```

### 允许部分 Pod 访问 apiserver

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

### 允许 A 访问 B

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

### 限制 B 只能被 A 访问，且只能访问 80/TCP 端口

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
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

### 允许 A 访问同名空间下的所有 Pod 

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

### 允许 A 访问 192.0.2.0/24 网段下的 80/TCP 端口

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-a-to-cidr
spec:
  endpointSelector:
    matchLabels:
      role: a
  egress:
  - toCIDR:
    - 192.0.2.0/24
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

### 显式禁止 A 访问 B

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: a
  egressDeny:
  - toEndpoints: # 显式禁止 A 访问 B
    - matchLabels:
        app: b
  egress:
  - toEntities: # 允许 A 的其它流量
    - all
```

### 允许 A 被集群外部访问

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

### 只允许 A 访问 80-444 的 TCP 端口

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-a-ports
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
    - toPorts:
      - ports: # 只能发送目标端口在 80-444 的 TCP 端口
        - port: "80"
          endPort: 444
          protocol: TCP
```

### 允许 A 访问指定域名的服务

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


### 允许 B 的指定接口被 A 访问

 ```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-a-to-b-api
spec:
  description: "Allow HTTP API from a to b"
  endpointSelector:
    matchLabels:
      role: b
  ingress:
  - fromEndpoints:
    - matchLabels:
        role: a
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET" # 允许 GET /public
          path: "/public"
        - method: "PUT" # 允许 PUT /avatar，但需要携带 X-My-Header: true 的 header
          path: "/avatar$" 
          headers:
          - 'X-My-Header: true'
 ```

## 参考资料

- [Cilium NetworkPolicy Examples](https://docs.cilium.io/en/stable/security/policy/language/)

