# 使用 Gateway API

[Cilium Gateway API](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/) 是 Cilium 内置的 Gateway API 实现，无需额外部署 Ingress Controller，由 Cilium 的 eBPF 数据平面和内置 Envoy 代理直接处理流量路由。

与独立的 Ingress Controller（如 Envoy Gateway、Nginx Ingress）相比，Cilium Gateway API 与 CNI 深度集成——流量到达 Gateway Service 后，eBPF 通过 TPROXY 机制透明转发给节点上的 Envoy 代理，无需额外的一跳。

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

在已有的 Cilium 安装基础上，通过 helm 启用 Gateway API：

```bash
helm upgrade cilium cilium/cilium --version 1.19.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true

# 重启 cilium-operator 和 cilium-agent 使配置生效
kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium
```

也可以将配置写入 values.yaml：

```yaml title="gateway-api-values.yaml"
gatewayAPI:
  enabled: true
  # externalTrafficPolicy: Local  # 保留客户端源 IP（默认 Cluster）
```

更新时追加 `-f gateway-api-values.yaml`：

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.5 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f gateway-api-values.yaml
```

### 验证

启用后，cilium-operator 会自动创建 `cilium` GatewayClass：

```bash
$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       1m
```

## 快速入门：HTTP 路由

以下示例创建一个 HTTP Gateway，将 `test.cilium.local` 的流量路由到 nginx 服务：

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

创建后，cilium 会自动创建一个 LoadBalancer 类型的 Service（`cilium-gateway-<name>`），TKE 的 service-controller 会自动为其创建 CLB：

```bash
$ kubectl get gateway,httproute,svc
NAME                                        CLASS    ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/my-gateway   cilium   43.141.204.235   True         30s

NAME                                        HOSTNAMES               AGE
httproute.gateway.networking.k8s.io/nginx   ["test.cilium.local"]   30s

NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
cilium-gateway-my-gateway  LoadBalancer   172.28.84.187   43.141.204.235   80:32676/TCP   30s
```

测试访问：

```bash
curl -s -H "Host: test.cilium.local" http://43.141.204.235/
```

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

## Host Network 模式

:::tip[适用场景]

Host Network 模式适用于有外部负载均衡器（如 TKE CLB）的环境，Cilium Envoy 直接在节点网络上监听，无需 LoadBalancer Service。适用于：

- 复用已有 CLB（通过 `service.kubernetes.io/tke-load-balancer-id` 注解或手动配置 CLB 后端）
- 需要直接控制 CLB 后端注册的场景
- 减少一层 Service 转发

:::

启用 Host Network 模式：

```yaml
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
    # nodes:  # 可选：仅在特定节点上暴露 Gateway 监听器
    #   matchLabels:
    #     role: gateway
```

```bash
helm upgrade cilium cilium/cilium --version 1.19.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true \
  --set gatewayAPI.hostNetwork.enabled=true

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
```

Host Network 模式下：

- Envoy 直接绑定到 `0.0.0.0:<listener-port>`（每个节点上都有）
- Cilium 创建的 Service 类型为 ClusterIP（非 LoadBalancer），不会自动创建 CLB
- 需要手动配置外部 CLB，将流量转发到节点 IP:监听端口

:::warning[端口冲突]

Host Network 模式下 Envoy 会直接占用节点端口。确保 Gateway 中配置的监听端口未被其它进程使用。如果需要使用 1024 以下的特权端口，需额外配置 `envoy.securityContext.capabilities.keepCapNetBindService=true`。

:::

### 配置 CLB 转发到 Host Network 监听器

以 TKE CLB 为例，手动配置 CLB 将流量转发到各节点的 Envoy 监听端口：

```bash
# 假设 Gateway 监听端口为 8443，CLB ID 为 lb-xxxxx

# 1. 创建 TCP 监听器
tccli clb CreateListener \
  --region <region> \
  --LoadBalancerId lb-xxxxx \
  --Ports 8443 \
  --Protocol TCP \
  --ListenerName gateway

# 2. 注册后端（各节点 IP + Gateway 监听端口）
tccli clb RegisterTargets \
  --region <region> \
  --LoadBalancerId lb-xxxxx \
  --ListenerId lbl-xxxxx \
  --cli-unfold-argument \
  --Targets.0.EniIp <node1-ip> --Targets.0.Port 8443 --Targets.0.Weight 10 \
  --Targets.1.EniIp <node2-ip> --Targets.1.Port 8443 --Targets.1.Weight 10 \
  --Targets.2.EniIp <node3-ip> --Targets.2.Port 8443 --Targets.2.Weight 10
```

:::warning[安全组放行]

TKE 节点的安全组默认只放行内网网段（10.0.0.0/8 等）。如果 CLB 使用 `SourceIpType=1`（保留客户端真实 IP），来自公网 IP 的流量会被安全组拦截，导致 CLB 返回 502 Bad Gateway。

解决方案（任选其一）：

1. **修改 CLB 的 SourceIpType 为 0**（SNAT 模式，CLB 用自身 IP 访问后端）：
   ```bash
   tccli clb ModifyListener \
     --region <region> \
     --cli-input-json '{"LoadBalancerId":"lb-xxxxx","ListenerId":"lbl-xxxxx","SourceIpType":0}'
   ```
2. **在安全组中放行 Gateway 监听端口**：
   ```bash
   tccli vpc CreateSecurityGroupPolicies \
     --region <region> \
     --SecurityGroupId sg-xxxxx \
     --SecurityGroupPolicySet.Ingress.0.Protocol TCP \
     --SecurityGroupPolicySet.Ingress.0.Port <gateway-port> \
     --SecurityGroupPolicySet.Ingress.0.CidrBlock 0.0.0.0/0 \
     --SecurityGroupPolicySet.Ingress.0.Action ACCEPT \
     --cli-unfold-argument
   ```

:::

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

## 配置参数说明

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `gatewayAPI.enabled` | `false` | 启用 Gateway API |
| `gatewayAPI.externalTrafficPolicy` | `Cluster` | LoadBalancer Service 的外部流量策略（`Local` 保留源 IP） |
| `gatewayAPI.hostNetwork.enabled` | `false` | Host Network 模式，Envoy 直接监听节点端口 |
| `gatewayAPI.hostNetwork.nodes.matchLabels` | `{}` | 限制 Envoy 监听器仅在特定节点上运行 |
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
| TCP | `protocol: TCP` | TCPRoute | 实验性，TCP 路由 |

:::warning[TCP 协议支持]

Cilium 1.19.5 对 TCPRoute 的支持为实验性。如果需要纯 TCP 代理（无需七层路由），可使用 TLS Passthrough（TLS 协议 + TLSRoute，不指定 `hostnames` 可匹配所有 SNI），或使用独立的 TCP 代理（如 socat、nginx stream）。

:::

## 流量路径

```text
非 Host Network 模式：
  Client → CLB → NodePort → eBPF TPROXY → Envoy → Backend Pod
                                     ↑
                        Cilium 自动创建 LoadBalancer Service

Host Network 模式：
  Client → CLB → Node:Port → Envoy → Backend Pod
                    ↑
          Envoy 直接监听节点端口（0.0.0.0:port）
          无需 LoadBalancer Service，需手动配置 CLB
```

## 常见问题

### Gateway 状态一直是 Pending？

检查 cilium-operator 日志：

```bash
kubectl -n kube-system logs deploy/cilium-operator | grep gateway
```

常见原因：

1. **Gateway API CRD 未安装**：安装 CRD 后重启 cilium-operator
2. **RBAC 权限不足**：确保 helm install 时没有手动修改 ClusterRole，如有冲突可删除后重新 helm upgrade
3. **`enable-envoy-config` 未生效**：重启 cilium-agent 使配置生效

### Gateway 已 Programmed 但无法从外部访问？

1. **LoadBalancer Service 未分配 External IP**：检查 TKE service-controller 是否正常运行
2. **安全组未放行端口**：确保节点安全组允许 CLB 访问 Gateway 监听端口
3. **CLB SourceIpType 导致 502**：详见 [Host Network 模式 - 安全组放行](#配置-clb-转发到-host-network-监听器)

### Host Network 模式下端口冲突？

Host Network 模式下 Envoy 直接绑定节点端口。如果端口被占用，Envoy Pod 会持续重启。解决方法：

1. 使用不同的端口
2. 停止占用端口的进程
3. 使用 `hostNetwork.nodes.matchLabels` 限制 Envoy 仅在特定节点运行

### 如何查看 Envoy 配置？

```bash
# 查看 CiliumEnvoyConfig（CEC）
kubectl get cec -A
kubectl get cec <cec-name> -n <namespace> -o yaml

# 查看 Envoy 运行状态
kubectl -n kube-system exec ds/cilium-envoy -- cilium-dbg status
```
