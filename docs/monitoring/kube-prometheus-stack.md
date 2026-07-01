# 使用 kube-prometheus-stack 搭建监控系统

## 概述

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 是 Prometheus 生态中用于在 Kubernetes 部署 Prometheus 相关组件的 helm chart，涵盖 Prometheus Operator、Prometheus、Alertmanager、Grafana、node-exporter、kube-state-metrics 以及社区提供的各种 Grafana 面板等，本文介绍如何使用这个 chart 在 TKE 集群中搭建监控系统。

## 安装

添加 helm repo：

```bash
helm repo add prom https://prometheus-community.github.io/helm-charts
helm repo update
```

安装：

```bash
helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version <chart-version> \
  -f image-values.yaml \
  -f grafana-values.yaml
```

:::tip[选择合适的 chart 版本]

`kube-prometheus-stack` 的 chart 版本与 app 版本（Prometheus Operator 版本）一一对应。不同版本之间的 CRD、默认配置、镜像版本可能有较大差异。

选择 chart 版本后，`image-values.yaml` 中的镜像 tag 必须与 chart 对应的 app 版本一致，否则可能出现兼容性问题。

:::

## 自定义配置的方法

`kube-prometheus-stack` chart 非常庞大，配置项极多。建议将自定义配置拆分为多个 `values.yaml` 文件分别维护，安装时指定多个 `-f` 参数：

- `image-values.yaml`：镜像替换配置
- `grafana-values.yaml`：Grafana 和其它自定义配置

```bash
helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f image-values.yaml \
  -f grafana-values.yaml
```

如果使用 kustomize 管理，可以用 `additionalValuesFiles`：

```yaml title="kustomization.yaml"
helmCharts:
- repo: https://prometheus-community.github.io/helm-charts
  name: kube-prometheus-stack
  releaseName: kube-prometheus-stack
  namespace: monitoring
  includeCRDs: true
  version: "80.14.4"
  additionalValuesFiles:
  - image-values.yaml
  - grafana-values.yaml
```

## 国内环境替换镜像地址

`kube-prometheus-stack` 依赖的镜像主要来自 `quay.io`，国内拉取可能失败或超时。有两种解决方案：

### 使用 TKE 内网 mirror（推荐）

TKE 提供了 `quay.tencentcloudcr.com` 作为 `quay.io` 的内网 mirror，将镜像 registry 替换即可：

```yaml title="image-values.yaml"
grafana:
  sidecar:
    image:
      registry: quay.tencentcloudcr.com
alertmanager:
  alertmanagerSpec:
    image:
      registry: quay.tencentcloudcr.com
prometheus:
  prometheusSpec:
    image:
      registry: quay.tencentcloudcr.com
prometheusOperator:
  image:
    registry: quay.tencentcloudcr.com
  prometheusConfigReloader:
    image:
      registry: quay.tencentcloudcr.com
  thanosImage:
    registry: quay.tencentcloudcr.com
kube-state-metrics:
  image:
    registry: docker.io
    repository: k8smirror/kube-state-metrics
  kubeRBACProxy:
    image:
      registry: quay.tencentcloudcr.com
prometheus-node-exporter:
  image:
    registry: quay.tencentcloudcr.com
  kubeRBACProxy:
    image:
      registry: quay.tencentcloudcr.com
```

部分不在 `quay.io` 上的镜像可替换为 DockerHub 上的社区 mirror：

| 原始镜像                                               | DockerHub mirror 镜像                                  |
| :---------------------------------------------------- | :----------------------------------------------------- |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | docker.io/k8smirror/kube-state-metrics                 |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen    | docker.io/k8smirror/ingress-nginx-kube-webhook-certgen |

## 配置 Grafana

grafana 是 `kube-prometheus-stack` 的一个 subchart，所有 grafana 配置放在 `grafana` 字段下：

```yaml title="grafana-values.yaml"
grafana:
  adminUser: "roc"
  adminPassword: "<your-password>"
  defaultDashboardsTimezone: "Asia/Shanghai"
  sidecar:
    dashboards:
      folderAnnotation: "grafana_folder"
      provider:
        foldersFromFilesStructure: true
  testFramework:
    enabled: false
```

具体配置建议参考 [在 TKE 上自建 Grafana](./grafana)。

## 在自建 Cilium Overlay 集群中的特殊配置

:::warning[Overlay 模式的 Webhook 兼容性问题]

在 TKE 自建 Cilium Overlay 模式的托管集群中，apiserver 运行在管控面（无 cilium-agent），无法路由到 overlay Pod IP（如 `10.244.x.x`）。这导致 apiserver 调用 ValidatingWebhook / MutatingWebhook 时连接超时。

详见 [安装 Cilium FAQ - Overlay 模式下 Webhook 连接超时](../networking/cilium/install.md#overlay-模式下-webhookvalidatingmutating连接超时)。

:::

### 禁用 Admission Webhooks

`kube-prometheus-stack` 的 Prometheus Operator 默认启用 admission webhooks，其 certgen job 需要拉取额外镜像（如 `kube-webhook-certgen`），且 webhook 服务本身也会遇到上述 overlay 不可达问题。建议在 Overlay 模式下禁用：

```yaml title="grafana-values.yaml"
prometheusOperator:
  admissionWebhooks:
    enabled: false
```

禁用后，operator 的 deployment 仍会引用 `kube-prometheus-stack-admission` TLS Secret 作为 volume。需手动创建一个自签名证书 Secret：

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt \
  -days 365 -nodes -subj "/CN=kube-prometheus-stack-operator"

kubectl -n monitoring create secret generic kube-prometheus-stack-admission \
  --from-file=cert=/tmp/tls.crt \
  --from-file=key=/tmp/tls.key
```

### cert-manager Webhook

如果集群中安装了 cert-manager，其 webhook 同样受 overlay 不可达影响。解决方案：

1. **将 cert-manager webhook 配置为 `hostNetwork: true`**（推荐）
2. **临时删除 ValidatingWebhookConfiguration**（绕过验证，适合初始部署阶段）

```bash
# 临时绕过 cert-manager webhook 验证
kubectl delete validatingwebhookconfiguration cert-manager-webhook
```

## 暴露 Grafana

### 通过 Gateway API 暴露

如果集群中已部署 EnvoyGateway，可以通过 HTTPRoute 暴露 Grafana：

```yaml title="grafana-httproute.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: eg
    namespace: envoy-gateway-system
    sectionName: https
  hostnames:
  - "grafana.imroc.cc"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - group: ""
      kind: Service
      name: kube-prometheus-stack-grafana
      port: 80
      weight: 1
```

### 通过 port-forward 临时访问

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

访问 `http://localhost:3000`，使用 `grafana-values.yaml` 中配置的账号密码登录。

## 验证

```bash
# 检查所有 Pod 是否就绪
kubectl -n monitoring get pod

# 验证 Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
curl http://localhost:9090/-/healthy

# 验证 Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
curl http://localhost:3000/api/health

# 获取 Grafana 密码
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## 常见问题

### Pod 一直 ImagePullBackOff？

检查 `image-values.yaml` 中的镜像配置是否正确：

1. 镜像 tag 是否与 chart 版本对应的 app 版本一致
2. 镜像仓库是否在集群节点上可达（参考[国内环境替换镜像地址](#国内环境替换镜像地址)）

### Prometheus Operator CrashLoopBackOff？

如果禁用了 admission webhooks 但未创建 `kube-prometheus-stack-admission` Secret，operator 会因缺少 TLS 证书文件而启动失败。参考[禁用 Admission Webhooks](#禁用-admission-webhooks)章节创建 Secret。

### Grafana sidecar CrashLoopBackOff？

Grafana sidecar（`grafana-sc-dashboard` / `grafana-sc-datasources`）通过 Kubernetes API 列举 Secret 和 ConfigMap。在自建 Cilium Overlay 集群中，如果 sidecar Pod 无法连接 apiserver（虽然 Overlay Pod 到 apiserver 的 169.254 地址通常可达，但可能因证书验证失败而报错），可设置环境变量跳过 TLS 验证：

```yaml
grafana:
  env:
    - name: SKIP_TLS_VERIFY
      value: "true"
```
