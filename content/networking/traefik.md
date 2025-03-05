# 在 TKE 使用 Traefik 流量网关

## 概述

[Traefik](https://doc.traefik.io/traefik/) 是一款现代化的云原生反向代理工具，与 Nginx 相比具有以下显著优势：

- 同时支持 Kubernetes Ingress API、Traefik CRD 和 Gateway API 三种流量管理配置方式。
- 提供功能丰富的 Dashboard 管理界面，支持路由可视化配置与监控。
- 深度集成 Prometheus 提供完整的 Metrics 数据，便于监控告警。
- 支持丰富的流量治理功能，包括：多版本灰度发布、流量镜像复制、自动签发 Let's Encrypt HTTPS 证书、灵活的中间件机制等。

本文将介绍如何在 TKE 集群中部署 Traefik 并通过多种配置方式管理流量。

## 安装 Traefik

1. 在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 搜索 `traefik`。
2. 单击 `traefik` 进入应用详情页。
3. 单击**创建应用**。
4. 应用名称建议填 `traefik`，选择需要安装 traefik 的目标集群。
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F03%2F20250303153635.png)
5. 可参考后文的**Traefik 参数配置**，根据需求配置完参数后，单击**创建**即可将 traefik 安装到集群中。
6. 安装完后在[应用管理](https://console.cloud.tencent.com/tke2/helm)中找到 traefik 应用，单击应用名称进入应用详情页，在**Service**中可以查到 traefik 的 CLB 地址信息，将需要用到的域名配置下 DNS 解析，确保域名能解析到 traefik 的 CLB 地址。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F03%2F20250303171704.png)

后续若想更改配置，可在[应用管理](https://console.cloud.tencent.com/tke2/helm)中找到 traefik 应用，单击**更新应用**并编辑参数即可。

## Traefik 参数配置

以下是关于安装 Traefik 的一些参数配置建议，可根据需求进行修改。

:::tip[说明]

本文使用 TKE 应用市场安装 traefik，TKE 应用市场安装的应用是 helm chart，其中 traefik 应用搬运自开源社区的 [traefik-helm-chart](https://github.com/traefik/traefik-helm-chart)，参数配置（`values.yaml`）与社区完全一致（镜像地址除外），如果你通过 helm 来安装，也可以这里的参数配置建议。

:::

### 启用 CLB 直连 Pod

建议启用 CLB 直连 Pod，这样 CLB 就可以将流量直接转发给 Pod，无需经过 NodePort，延迟更低，且 Traefik 自身可以感知真实源 IP，后端的业务 Pod 可通过 header 获取真实源 IP。

:::tip[说明]

更多详情参考 [使用 LoadBalancer 直连 Pod 模式 Service](https://cloud.tencent.com/document/product/457/41897)。

:::

配置方法如下：

```yaml
service:
  annotations:
    service.cloud.tencent.com/direct-access: "true"
```

### 使用已有的 CLB

如果已经创建了 CLB，可以指定下 CLB 实例 ID，配置方法如下：

:::tip[说明]

更多详情参考 [Service 使用已有 CLB](https://cloud.tencent.com/document/product/457/45491)。

:::

:::info[注意]

注意替换 `lb-xxx` 为已有的 CLB 实例 ID。

:::

```yaml
service:
  annotations:
    service.kubernetes.io/tke-existed-lbid: lb-xxx
```

### 公网和内网同时接入

默认创建的是公网 CLB，可通过类似如下配置实现内网和公网双 CLB 同时接入：

:::info[注意]

自动创建内网 CLB 需指定子网 ID，注意替换 `subnet-xxxxxxxx`。

:::

<Tabs>
  <TabItem value="1" label="自动创建">
    <FileBlock file="traefik/dubble-clb-autocreate-values.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="2" label="使用已有CLB">

  :::info[注意]
  
  需自行创建内网 CLB，获取实例 ID 并替换配置中的 `lb-xxx`。
  
  :::

  <FileBlock file="traefik/dubble-clb-use-exsisted-values.yaml" showLineNumbers />

  </TabItem>
</Tabs>

### IPV4 和 IPV6 同时接入

默认创建的是 IPV4 的 CLB，可通过类似如下配置实现 IPV6 和 IPV4 双 CLB 同时接入：

:::tip[说明]

更多详情请参考 [在 TKE 上使用 IPv6](ipv6)。

:::

<Tabs>
  <TabItem value="1" label="自动创建">
    <FileBlock file="traefik/dualstack-clb-autocreate-values.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="2" label="使用已有CLB">

  :::info[注意]
  
  需自行创建 IPV6 的 CLB，获取实例 ID 并替换配置中的 `lb-xxx`。
  
  :::

  <FileBlock file="traefik/dualstack-clb-use-exsisted-values.yaml" showLineNumbers />

  </TabItem>
</Tabs>

### 启用 Gateway API

默认没启用 Gateway API 的支持，可通过以下配置启用：

```yaml
providers:
  kubernetesGateway:
    enabled: true
```

如果同时想禁用 Ingress 和 Traefik 自身 CRD 的支持，可以用如下的配置：

```yaml
providers:
  kubernetesGateway:
    enabled: true
  kubernetesIngress:
    enabled: false
  kubernetesCRD:
    enabled: false
```


## 使用 Ingress

Traefik 支持使用 Kubernetes 的 Ingress 资源作为动态配置，可直接在集群中创建 Ingress 资源用于对外暴露集群，需要加上指定的 IngressClass（安装 Traefik 时可自定义，默认为 traefik）。示例如下：

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata: 
  name: test-ingress
spec:
  # highlight-add-line
  ingressClassName: traefik
  rules:
  - host: traefik.demo.com
    http:
      paths:
      - path: /test
        backend:
          serviceName: nginx
          servicePort: 80
```


:::info[注意]

TKE 暂未将 Traefik 产品化，无法直接在 TKE 控制台进行可视化创建 Ingress，需要使用 YAML 进行创建。  

:::

## 使用 IngressRoute

Traefik 不仅支持标准的 Kubernetes Ingress 资源，也支持 Traefik 特有的 CRD 资源，例如 IngressRoute，可以支持更多 Ingress 不具备的高级功能。IngressRoute 使用示例如下：

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata: 
  name: test-ingressroute
spec: 
  entryPoints: 
    - web
  routes: 
    - match: Host(`traefik.demo.com`) && PathPrefix(`/test`)
      kind: Rule
      services: 
        - name: nginx
          port: 80
```

:::tip[说明]

Traefik 更多用法请参见 [Traefik 官方文档](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)。  

:::
