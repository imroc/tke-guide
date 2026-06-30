# 使用 Gateway API

[Cilium Gateway API](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/) 是 Cilium 内置的 Gateway API 实现，无需额外部署 Ingress Controller，由 Cilium 的 eBPF 数据平面和内置 Envoy 代理直接处理流量路由。

与独立的 Ingress Controller（如 Envoy Gateway、Nginx Ingress）相比，Cilium Gateway API 与 CNI 深度集成——流量到达 Service 后，eBPF 通过 TPROXY 机制透明转发给节点上的 Envoy 代理，无需额外的一跳。

:::warning[TKE 环境下的重要限制]

在 TKE 环境中使用 Cilium Gateway API 需要注意以下限制：

1. **必须使用 Host Network 模式**：非 Host Network 模式下，Cilium 自动创建的 LoadBalancer Service 的 Endpoints 是虚拟地址（`192.192.192.192`），TKE 的 service-controller 无法将其注册为 CLB 后端，导致 CLB 后端为空、外部流量无法到达。Host Network 模式下 Envoy 直接绑定节点端口，可以通过 `direct-access` 注解让 CLB 直连节点 IP。
2. **TCP 协议不可用**：Cilium Gateway API 不支持 TCP 协议的 listener（报错 `model source can't be empty, 0 listeners`）。如需纯 TCP 代理，请使用 TLS 协议 + TLS Passthrough（TLS 透传），或使用独立的 TCP 代理。
3. **仅 Overlay 模式支持**：Native Routing (VPC-CNI) 模式因 `ipam.mode=delegated-plugin` 限制不支持 Gateway API。

:::

## 前提条件

- Cilium 已安装且 `kubeProxyReplacement=true`（默认已启用）
- 安装方案为 **Overlay 模式**（VPC-CNI 或 GR）。Native Routing (VPC-CNI) 模式因 `ipam.mode=delegated-plugin` 限制不支持 Gateway API，详见 [安装文档 FAQ](./install.md#native-routing-vpc-cni-模式不支持-gateway-api)
- 集群中已安装 Gateway API CRD（cilium 1.19.5 对应 Gateway API v1.5.1）

### 安装 Gateway API CRD

如果集群中尚未安装 Gateway API CRD，使用以下命令安装：

```bash
# 标准 CRD（GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, TLSRoute, BackendTLSPolicy）
for crd in gatewayclasses gateways httproutes grpcroutes referencegrants backendtlspolicies tlsroutes; do
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/standard/gateway.networking.k8s.io_${crd}.yaml
done

# 实验 CRD（TCPRoute, UDPRoute）——如需 TCP/UDP 路由
for crd in tcproutes udproutes; do
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/experimental/gateway.networking.k8s.io_${crd}.yaml
done
```

## 启用 Gateway API

在已有的 Cilium 安装基础上，通过 helm 启用 Gateway API（**必须启用 Host Network 模式**）：

```yaml title="gateway-api-values.yaml"
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
```

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.5 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f gateway-api-values.yaml

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
```

### Host Network 模式的作用

:::tip[cilium-envoy Pod 本身始终是 hostNetwork 部署的]

无论是否启用 `gatewayAPI.hostNetwork.enabled`，cilium-envoy Pod 都以 hostNetwork 方式运行。`hostNetwork.enabled` 配置影响的是 **Envoy listener 的绑定方式**和 **Gateway Service 的类型**。

:::

| 对比项 | 非 Host Network 模式 | Host Network 模式 |
| --- | --- | --- |
| Envoy listener 绑定 | 不绑定地址，通过 eBPF TPROXY 接收流量 | 直接绑定 `0.0.0.0:<port>` |
| Gateway Service 类型 | LoadBalancer（自动创建 CLB） | ClusterIP（不创建 CLB） |
| TKE CLB 后端注册 | ❌ Endpoints 是虚拟地址，CLB 后端为空 | ✅ 可通过独立 Service + `direct-access` 注解注册 |
| TKE 可用性 | ❌ 不可用 | ✅ 可用 |

启用 Host Network 模式后，Envoy 会直接绑定到 `0.0.0.0:<Gateway listener port>`，外部流量到达节点端口后直接被 Envoy 接收。

### 验证

启用后，cilium-operator 会自动创建 `cilium` GatewayClass：

```bash
$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       1m
```

## 暴露 Gateway：LoadBalancer Service + direct-access

Host Network 模式下 Cilium 创建的 Gateway Service 是 ClusterIP 类型，不会自动创建 CLB。需要在 TKE 环境中创建一个独立的 LoadBalancer Service 来暴露 Gateway，关键配置：

1. **`service.kubernetes.io/tke-existed-lbid`**：复用已有 CLB（避免每个 Gateway 创建新 CLB）
2. **`service.cloud.tencent.com/direct-access: "true"`**：让 service-controller 直接将 Pod IP（hostNetwork 下即节点 IP）+ targetPort 注册到 CLB，绕过 NodePort

```yaml title="gateway-lb-svc.yaml"
apiVersion: v1
kind: Service
metadata:
  name: <gateway-name>-lb
  namespace: <gateway-namespace>
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx  # 复用已有 CLB（可选）
    service.cloud.tencent.com/direct-access: "true"       # 直连 Pod IP，绕过 NodePort
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy  # 选择 cilium-envoy DaemonSet
  ports:
  - name: <port-name>
    port: <external-port>     # CLB 对外端口
    targetPort: <gateway-port> # Gateway listener 端口
    protocol: TCP
```

:::tip[direct-access 的优势]

`direct-access` 注解让 service-controller 将 Pod IP:targetPort 直接注册为 CLB 后端（而非 NodePort）。由于 cilium-envoy 以 hostNetwork 运行，Pod IP 就是节点 IP，CLB 直连节点 IP:Gateway 端口，流量直达 Envoy，不经过 eBPF NodePort 拦截。

节点扩缩容时，cilium-envoy DaemonSet 自动在新节点调度，Service Endpoints 自动更新，service-controller 自动注册/注销 CLB 后端，**全程自动管理**。

:::

### CLB 安全组放通

TKE CLB 默认使用 `SourceIpType=1`（保留客户端真实 IP），CLB 到后端的流量源 IP 是客户端公网 IP，可能被节点安全组拦截导致 502。解决方案是在 CLB 上开启安全组放通：

```bash
# 在 CLB 上设置 LoadBalancerPassToTarget=true（安全组放通）
# CLB 到后端的流量不再受后端安全组限制
tccli clb ModifyLoadBalancerAttributes \
  --region <region> \
  --cli-input-json '{"LoadBalancerId":"lb-xxxxxxxx","LoadBalancerPassToTarget":true}'
```

:::warning[pass-to-target 注解与 tke-existed-lbid 冲突]

`service.cloud.tencent.com/pass-to-target` 注解只支持 TKE 自动创建的 CLB，与 `tke-existed-lbid`（复用 CLB）互斥。复用 CLB 时只能通过 CLB API 手动设置 `LoadBalancerPassToTarget=true`，这是一次性配置，对 CLB 所有监听器生效。

:::

## 快速入门：HTTP 路由

以下示例创建一个 HTTP Gateway，将 `test.cilium.local` 的流量路由到 nginx 服务。

**1. 创建 Gateway + HTTPRoute**：

```yaml title="gateway-http.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx
  namespace: default
spec:
  parentRefs:
  - name: my-gateway
    sectionName: http
  hostnames:
  - "test.cilium.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: nginx
      port: 80
```

```bash
kubectl apply -f gateway-http.yaml
```

**2. 创建 LoadBalancer Service 暴露 Gateway**：

```yaml title="gateway-http-lb.yaml"
apiVersion: v1
kind: Service
metadata:
  name: my-gateway-lb
  namespace: default
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx  # 复用已有 CLB（可选）
    service.cloud.tencent.com/direct-access: "true"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy
  ports:
  - name: http
    port: 80
    targetPort: 80  # 与 Gateway listener port 一致
    protocol: TCP
```

```bash
kubectl apply -f gateway-http-lb.yaml
```

**3. 验证**：

```bash
$ kubectl get gateway,httproute,svc
NAME                                          CLASS    ADDRESS   PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/my-gateway  cilium             True         30s

NAME                                        HOSTNAMES               AGE
httproute.gateway.networking.k8s.io/nginx   ["test.cilium.local"]   30s

NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)       AGE
my-gateway-lb    LoadBalancer   172.28.84.187   <clb-vip>     80:32676/TCP  30s

# 测试访问
curl -s -H "Host: test.cilium.local" http://<clb-vip>/
```

:::note[Gateway ADDRESS 为空是正常的]

Host Network 模式下 Gateway 的 ADDRESS 为空（因为 Gateway Service 是 ClusterIP 类型，没有外部 IP）。Gateway 的 `Programmed=True` 表示 Envoy 已配置完成，外部 IP 由独立创建的 LoadBalancer Service 提供。

:::

## HTTPS 路由（TLS 终止）

使用 HTTPS 监听器进行 TLS 终止，需要提供 TLS 证书：

```yaml title="gateway-https.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: https-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: my-tls-secret
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-https
  namespace: default
spec:
  parentRefs:
  - name: https-gateway
    sectionName: https
  hostnames:
  - "test.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: nginx
      port: 80
```

提前创建 TLS Secret：

```bash
kubectl create secret tls my-tls-secret \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem
```

同样需要创建 LoadBalancer Service 暴露 443 端口（参考 [HTTP 路由示例](#快速入门http-路由)）。

## TLS Passthrough

使用 TLS 协议的 Gateway 监听器 + TLSRoute 实现 TLS 透传（Envoy 不终止 TLS，根据 SNI 转发原始 TLS 流量）：

```yaml title="gateway-tls-passthrough.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tls-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: tls
    port: 8443
    protocol: TLS
    tls:
      mode: Passthrough
    allowedRoutes:
      namespaces:
        from: Same
      kinds:
      - kind: TLSRoute
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: my-tls-route
  namespace: default
spec:
  parentRefs:
  - name: tls-gateway
    sectionName: tls
  # hostnames:  # 可选：按 SNI 匹配
  # - "secure.example.com"
  rules:
  - backendRefs:
    - name: my-https-service
      port: 443
```

:::note[TLS Passthrough 与源 IP]

TLS Passthrough 模式下，Envoy 使用 TCP 代理转发 TLS 流量。后端看到的源 IP 是 Envoy 的 IP（通常是节点 IP），而非客户端真实 IP。这是因为 TCP 代理会建立新的 TCP 连接到后端。

:::

## 实践：暴露 APIServer

利用 TLS Passthrough 可以将集群 apiserver 通过 Gateway API 暴露出来，无需开启 TKE 集群公网/内网访问。

```yaml title="apiserver-gateway.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: apiserver
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: apiserver
    port: 8443
    protocol: TLS
    tls:
      mode: Passthrough
    allowedRoutes:
      namespaces:
        from: Same
      kinds:
      - kind: TLSRoute
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: apiserver
  namespace: default
spec:
  parentRefs:
  - name: apiserver
    sectionName: apiserver
  rules:
  - backendRefs:
    - name: kubernetes
      port: 443
---
apiVersion: v1
kind: Service
metadata:
  name: apiserver-gw
  namespace: kube-system
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxxxxxxx
    service.cloud.tencent.com/direct-access: "true"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    k8s-app: cilium-envoy
  ports:
  - name: tls
    port: 8443
    targetPort: 8443
    protocol: TCP
```

流量路径：

```text
Client → CLB:8443 → cilium-envoy (hostNetwork:8443)
       → eBPF TPROXY → Envoy TLS Passthrough
       → kubernetes Service → apiserver (169.254.x.x:60002)
```

获取 kubeconfig（通过 tccli 获取后替换 server 地址为 CLB 地址）：

```bash
tccli tke DescribeClusterKubeconfig --region <region> --ClusterId <cluster-id> | \
  python3 -c "
import sys, json, yaml
data = json.load(sys.stdin)
kc = yaml.safe_load(data['Kubeconfig'])
kc['clusters'][0]['cluster']['server'] = 'https://<clb-vip>:8443'
kc['clusters'][0]['cluster']['insecure-skip-tls-verify'] = True
kc['clusters'][0]['cluster'].pop('certificate-authority-data', None)
print(yaml.dump(kc, default_flow_style=False, sort_keys=False))
" > ~/.kube/configs/roc.yaml
```

## 配置参数说明

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `gatewayAPI.enabled` | `false` | 启用 Gateway API |
| `gatewayAPI.hostNetwork.enabled` | `false` | Host Network 模式，Envoy 直接绑定节点端口（**TKE 环境必须启用**） |
| `gatewayAPI.hostNetwork.nodes.matchLabels` | `{}` | 限制 Envoy 监听器仅在特定节点上运行 |
| `gatewayAPI.externalTrafficPolicy` | `Cluster` | 非 Host Network 模式下 LoadBalancer Service 的外部流量策略（Host Network 模式下忽略） |
| `gatewayAPI.gatewayClass.create` | `auto` | 是否创建 GatewayClass（`auto` 自动检测 CRD） |
| `gatewayAPI.secretsNamespace.name` | `cilium-secrets` | TLS Secret 同步的目标 namespace |
| `gatewayAPI.secretsNamespace.sync` | `true` | 自动同步 TLS Secret 到 `secretsNamespace` |

## 支持的协议

| 协议 | Gateway Listener | Route 类型 | 说明 |
| --- | --- | --- | --- |
| HTTP | `protocol: HTTP` | HTTPRoute | 七层 HTTP 路由 |
| HTTPS | `protocol: HTTPS` + `tls.mode: Terminate` | HTTPRoute | TLS 终止 + 七层路由 |
| TLS | `protocol: TLS` + `tls.mode: Passthrough` | TLSRoute | TLS 透传（按 SNI 路由） |
| GRPC | `protocol: HTTP` / `HTTPS` | GRPCRoute | gRPC 路由 |
| TCP | `protocol: TCP` | TCPRoute | ❌ 不可用（Cilium 报错 `model source can't be empty`） |

:::warning[TCP 协议不可用]

Cilium 1.19.5 虽然在实验性 CRD 中支持 TCPRoute，但实际创建 TCP 协议的 Gateway listener 会报错 `model source can't be empty, 0 listeners`。如需纯 TCP 代理，请使用 TLS Passthrough（TLS 协议 + TLSRoute，不指定 `hostnames` 可匹配所有 SNI），或使用独立的 TCP 代理。

:::

## 流量路径

```text
Host Network 模式（TKE 推荐）：
  Client → CLB → cilium-envoy (hostNetwork, 0.0.0.0:port)
         → eBPF TPROXY → Envoy 处理（HTTP 路由 / TLS 终止 / TLS 透传）
         → Backend Pod

  CLB 后端由 LoadBalancer Service + direct-access 自动管理：
  service-controller 将 cilium-envoy Pod IP（=节点 IP）:targetPort 注册到 CLB
  节点扩缩容时自动更新
```

## 常见问题

### Gateway 状态一直是 Pending？

检查 cilium-operator 日志：

```bash
kubectl -n kube-system logs deploy/cilium-operator | grep gateway
```

常见原因：

1. **Gateway API CRD 未安装**：安装 CRD 后重启 cilium-operator
2. **RBAC 权限不足**：如果手动 patch 过 ClusterRole 导致 helm apply 冲突，删除 ClusterRole 后重新 helm upgrade
3. **`enable-envoy-config` 未生效**：重启 cilium-agent 使配置生效

### Gateway 已 Programmed 但无法从外部访问？

1. **未创建 LoadBalancer Service**：Host Network 模式下需手动创建 LoadBalancer Service 暴露 Gateway（参考[快速入门](#快速入门http-路由)）
2. **CLB 后端为空**：确认 Service 使用了 `direct-access: "true"` 注解，且 selector 正确匹配 cilium-envoy Pod
3. **CLB 返回 502**：安全组拦截了 CLB 到后端的流量，在 CLB 上设置 `LoadBalancerPassToTarget=true`（参考[CLB 安全组放通](#clb-安全组放通)）

### Gateway ADDRESS 为空？

Host Network 模式下 Gateway 的 ADDRESS 为空是正常的。Gateway Service 是 ClusterIP 类型（无外部 IP），外部 IP 由独立创建的 LoadBalancer Service 提供。`Programmed=True` 表示 Envoy 已配置完成。

### Host Network 模式下端口冲突？

Host Network 模式下 Envoy 直接绑定节点端口。如果端口被占用，cilium-envoy Pod 会持续重启。解决方法：

1. 使用不同的端口
2. 停止占用端口的进程
3. 使用 `hostNetwork.nodes.matchLabels` 限制 Envoy 仅在特定节点运行

如果需要使用 1024 以下的特权端口，需额外配置 `envoy.securityContext.capabilities.keepCapNetBindService=true`。

### 如何查看 Envoy 配置？

```bash
# 查看 CiliumEnvoyConfig（CEC）
kubectl get cec -A
kubectl get cec <cec-name> -n <namespace> -o yaml

# 查看 Envoy 运行状态
kubectl -n kube-system exec ds/cilium-envoy -- cilium-dbg status
```

### 非 Host Network 模式下 CLB 后端为空？

这是 TKE 环境下的已知限制。非 Host Network 模式下，Cilium 创建的 Gateway Service 的 Endpoints 是虚拟地址（`192.192.192.192:9999`），TKE 的 service-controller 无法将其注册为 CLB 后端。**必须在 TKE 环境中使用 Host Network 模式**，并通过独立 LoadBalancer Service + `direct-access` 注解暴露 Gateway。
