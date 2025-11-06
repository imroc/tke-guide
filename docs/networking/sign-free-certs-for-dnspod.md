# 为 dnspod 的域名签发免费证书

如果你的域名使用 [DNSPod](https://docs.dnspod.cn/) 管理，想在 Kubernetes 上为域名自动签发免费证书，可以使用 cert-manager 来实现。

如果域名通过 dnspod 管理，cert-manager 自身并未实现 dnspod 的 provider， 但提供了 webhook 扩展机制，通过 [cert-manager-webhook-dnspod](https://github.com/imroc/cert-manager-webhook-dnspod) 可以实现为 dnspod 上的域名自动签发免费证书，还可以自动续期。

## 操作步骤

### 安装 cert-manager

确保 [cert-manager](https://cert-manager.io/) 已安装到集群，且版本 >= 1.13.0，可通过 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 安装。

### 安装 cert-manager-webhook-dnspod

在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 中搜索 `cert-manager-webhook-dnspod` 并安装到 cert-manager 所在命名空间。

> 如有需要，你也可以参考 [cert-manager-webhook-dnspod 文档](https://github.com/imroc/cert-manager-webhook-dnspod) 用 helm 安装。

### 创建腾讯云 API 密钥

登录腾讯云控制台，在 [API密钥管理](https://console.cloud.tencent.com/cam/capi) 中新建密钥，然后复制自动生成的 `SecretId` 和 `SecretKey` 并保存下来，以备后面的步骤使用。

要求账号至少具有以下权限：

```json
{
    "version": "2.0",
    "statement": [
        {
            "effect": "allow",
            "action": [
                "dnspod:CreateRecord",
                "dnspod:DescribeRecordList",
                "dnspod:DeleteRecord",
            ],
            "resource": [
                "*"
            ]
        }
    ]
}
```

### 创建 Secret

在 cert-manager 所在命名空间中创建一个 `Secret` 对象，用于保存前面创建的腾讯云 API 密钥:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dnspod-secret
  namespace: cert-manager
type: Opaque
stringData:
  secretId: xxx
  secretKey: xxx
```

> 替换 `xxx` 为你自己生成的 `SecretId` 和 `SecretKey`。

### 创建 ClusterIssuer

创建一个 dnspod 的 `ClusterIssuer` 对象，用于为 dnspod 管理的域名签发免费证书:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: dnspod
spec:
  acme:
    email: your-email-address@example.com
    privateKeySecretRef:
      name: dnspod-letsencrypt
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          webhook:
            config:
              secretIdRef:
                key: secretId
                name: dnspod-secret
              secretKeyRef:
                key: secretKey
                name: dnspod-secret
              ttl: 600
              recordLine: ""
            groupName: acme.dnspod.com
            solverName: dnspod
```

> `email` 可替换成你自己的邮箱地址，用于接收来自 Let's Encrypt 的证书过期提醒（只有没正常自动续期的情况才会有通知）。

### 创建 Certificate

创建 `Certificate` 对象来签发你想要的免费证书:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-crt
  namespace: istio-system
spec:
  secretName: example-crt-secret # 证书签发后会保存到这个 Secret 中
  issuerRef:
    name: dnspod # 这里引用前面创建的 ClusterIssuer 名称
    kind: ClusterIssuer
    group: cert-manager.io
  dnsNames: # 填入需要签发证书的域名列表，支持泛域名，确保域名是使用当前账号下的 dnspod 管理的
  - "example.com"
  - "*.example.com"
```

等待状态变成 Ready 表示签发成功:

```bash
$ kubectl -n istio-system get certificates.cert-manager.io
NAME          READY   SECRET               AGE
example-crt   True    example-crt-secret   25d
```

若签发失败可 describe 一下看下原因:

```bash
kubectl -n istio-system describe certificates.cert-manager.io example-crt
```

## 使用证书

证书签发成功后会保存到我们指定的 secret 中，下面给出一些使用示例。

### 在 Ingress 中使用

如果集群中安装了 Ingress Controller （如 [Nginx Ingress](https://github.com/kubernetes/ingress-nginx)），可在 `Ingress` 中引用证书 secret：

```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: web
          servicePort: 80
  tls:
    hosts:
    - test.example.com
    secretName: example-crt-secret # 引用证书 secret
```

### 在 Istio 的 IngressGateway 中使用

如果集群中安装了 Istio，可在 `Gateway` 中引用证书 secret：

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: example-gw
  namespace: istio-system
spec:
  selector:
    app: istio-ingressgateway
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: HTTP-80
      protocol: HTTP
    hosts:
    - example.com
    - "*.example.com"
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: HTTPS-443
      protocol: HTTPS
    hosts:
    - example.com
    - "*.example.com"
    tls:
      mode: SIMPLE
      credentialName: example-crt-secret # 引用证书 secret
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: example-vs
  namespace: test
spec:
  gateways:
  - istio-system/example-gw # 将转发规则应用到指定 IngressGateway
  hosts:
  - 'test.example.com'
  http:
  - route:
    - destination:
        host: example
        port:
          number: 80
```

### 在 Gateway API 中使用

如果集群中安装了 [Gateway API](https://gateway-api.sigs.k8s.io/) 的实现（如 [envoygateway](https://gateway.envoyproxy.io/)），在定义 `Gateway` 时可引用证书 secret：


```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  listeners:
  - allowedRoutes:
      namespaces:
        from: All
    name: https
    port: 443
    protocol: HTTPS
    tls:
      certificateRefs:
      - group: ""
        kind: Secret
        name: example-crt-secret # 引用证书 secret
      mode: Terminate
  - allowedRoutes:
      namespaces:
        from: All
    name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
  namespace: test
spec:
  hostnames:
  - example.com
  parentRefs: # 将转发规则应用到指定 Gateway
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: eg
    namespace: envoy-gateway-system
    sectionName: https
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: website
      port: 80
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
```

## 注意事项

### private dns 与 dnspod 的 zone 需保持一致

如果满足以下条件：
1. 使用了 [private dns](https://cloud.tencent.com/product/privatedns) 管理域名解析。
2. private dns 关联了当前 TKE 集群所在 VPC。
3. private dns 中也配置了要签发免费证书的域名的解析。
4. dnspod 中有将子域名独立出来（单独成 zone）管理域名解析。

那么一定确保 private dns 中也要有相同的 zone 配置，即也将相同子域名独立出来管理解析，在 private dns 控制台点击【新建私有域】，输入与 dnspod 中相同的子域名。

这是因为在签发证书时，cert-manager 会通过 SOA 查询要签发的域名的 zone，在有 private dns 的环境中，如果  private dns 里也配置了相同的域名，会优先根据 private dns 中的配置返回，如果与 dnspod 中配置的 zone 不一致，最终校验就会失败，导致一直无法签发成功。

