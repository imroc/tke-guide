# 使用 kube-prometheus-stack 搭建监控系统

## 概述

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 是 Prometheus 生态中用于在 Kubernetes 部署 Prometheus 相关组件的 helm chart，涵盖 Prometheus Operator、Prometheus、Thanos、Grafana、node-exporter、kube-state-metrics 以及社区提供的各种 Grafana 面板等，本文介绍如何使用这个 chart 来搭建监控系统。

## 自定义配置的方法

由于 `kube-prometheus-stack` 这个 chart 非常庞大，还包含了很多其它依赖的 chart，配置也就非常多，如果我们要自定义的配置也很多，写到一个 `values.yaml` 中维护起来比较麻烦，我们可以拆成多个，在安装的时候指定多个配置文件就可以了：
* 如果你直接用 helm 进行安装，可以指定多次 `-f` 参数:
  ```bash
  helm upgrade --install eg prom/kube-prometheus-stack -f image-values.yaml -f grafana-values.yaml -f tke-serverless-values.yaml
  ```
* 如果你用 kustomize 引用该 chart 安装，可以用 `additionalValuesFiles` 指定多个 `values` 配置文件:
  ```yaml showLineNumbers title="kustomization.yaml"
  helmCharts:
    - repo: https://prometheus-community.github.io/helm-charts
      name: kube-prometheus-stack
      releaseName: monitoring
      namespace: monitoring
      includeCRDs: true
      # highlight-start
      additionalValuesFiles:
        - image-values.yaml
        - grafana-values.yaml
        - tke-serverless-values.yaml
      # highlight-start
  ```

## 国内环境替换镜像地址

`kube-prometheus-stack` 很多依赖镜像在 `quay.io` 和 `registry.k8s.io` 这些国外的镜像仓库，国内环境拉取会失败，如果你的集群在国内，可以将国外的依赖镜像替换为 DockerHub 中相应的自动同步的 mirror 镜像：

| 国外的依赖镜像                                         | DockerHub 中自动同步的 mirror 镜像                     |
| ------------------------------------------------------ | ------------------------------------------------------ |
| quay.io/prometheus-operator/admission-webhook          | docker.io/imroc/prometheus-operator-admission-webhook  |
| quay.io/prometheus-operator/prometheus-operator        | docker.io/imroc/prometheus-operator                    |
| quay.io/prometheus/node-exporter                       | docker.io/imroc/prometheus-node-exporter               |
| quay.io/prometheus/alertmanager                        | docker.io/imroc/prometheus-alertmanager                |
| quay.io/prometheus/prometheus                          | docker.io/imroc/prometheus                             |
| quay.io/prometheus-operator/prometheus-config-reloader | docker.io/imroc/prometheus-config-reloader             |
| quay.io/thanos/thanos                                  | docker.io/imroc/thanos                                 |
| quay.io/brancz/kube-rbac-proxy                         | docker.io/imroc/kube-rbac-proxy                        |
| quay.io/kiwigrid/k8s-sidecar                           | docker.io/kiwigrid/k8s-sidecar                         |
| registry.k8s.io/kube-state-metrics/kube-state-metrics  | docker.io/k8smirror/kube-state-metrics                 |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen     | docker.io/k8smirror/ingress-nginx-kube-webhook-certgen |

:::tip

以上 mirror 镜像均是长期自动同步的镜像，可放心使用和更新版本。

:::

创建相应的 `values` 配置：

```yaml title="image-values.yaml"
grafana:
  sidecar:
    image:
      registry: docker.io/kiwigrid
      repository: k8s-sidecar
alertmanager:
  alertmanagerSpec:
    image:
      registry: docker.io
      repository: imroc/prometheus-alertmanager
prometheus:
  prometheusSpec:
    image:
      registry: docker.io
      repository: imroc/prometheus
prometheusOperator:
  image:
    registry: docker.io
    repository: imroc/prometheus-operator
  admissionWebhooks:
    deployment:
      image:
        registry: docker.io
        repository: imroc/prometheus-operator-admission-webhook
    patch:
      image:
        registry: docker.io
        repository: k8smirror/ingress-nginx-kube-webhook-certgen
  prometheusConfigReloader:
    image:
      registry: docker.io
      repository: imroc/prometheus-config-reloader
  thanosImage:
    registry: docker.io
    repository: imroc/thanos
thanosRuler:
  thanosRulerSpec:
    image:
      registry: docker.io
      repository: imroc/thanos
kube-state-metrics:
  image:
    registry: docker.io
    repository: k8smirror/kube-state-metrics
prometheus-node-exporter:
  image:
    registry: docker.io
    repository: imroc/prometheus-node-exporter
  kubeRBACProxy:
    image:
      registry: quay.io
      repository: brancz/kube-rbac-proxy
```

## 配置 Grafana 

下面是一些建议加上的配置：

```yaml title="grafana-values.yaml"
grafana:
  adminUser: "roc"
  adminPassword: "123456"
  defaultDashboardsTimezone: "Asia/Shanghai"
  sidecar:
    dashboards:
      folderAnnotation: "grafana_folder"
      provider:
        foldersFromFilesStructure: true
  testFramework:
    enabled: false
```

* `adminUser` 和 `adminPassword` 分别设置管理员的账号和密码。
* `defaultDashboardsTimezone` 设置展示面板所用的时区，国内固定使用 `Asia/Shanghai`。
* `folderAnnotation` 是存储 dashboard 的 ConfigMap 的一个注解名称，用于标识该 ConfigMap 下面板 json 文件存储的目录，结合 `foldersFromFilesStructure` 置为 true，可实现 ConfigMap 中的面板按目录组织。

## 声明式配置 Grafana 面板

`kube-prometheus-stack` 自带了很多常用面板，如果还需要其它自定义面板，可以导出 dashboard 的 json 文件，通过 kustomize 引用并统一加上 `grafana_dashboard: 1` 的 label，比如要为 `EnvoyGateway` 加 dashboard，使用以下 kustomize 结构组织文件:

```txt
envoygateway
├── dashboards
│   ├── envoy-clusters.json
│   ├── envoy-global.json
│   └── envoy-pod-resource.json
└── kustomization.yaml
```

在 `kustomization.yaml` 中用 `configMapGenerator` 用这些 dashboard json 文件生成 ConfigMap，并统一打上 `grafana_dashboard: 1` 的 label 和 `grafana_folder: Envoy` 的 annotation:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

generatorOptions:
  disableNameSuffixHash: true
  labels:
    grafana_dashboard: "1"
commonAnnotations:
  grafana_folder: "Envoy"

configMapGenerator:
  - files:
      - dashboards/envoy-clusters.json
    name: dashboard-envoy-clusters
  - files:
      - dashboards/envoy-global.json
    name: dashboard-envoy-global
  - files:
      - dashboards/envoy-pod-resource.json
    name: dashboard-envoy-pod-resource
```

## 配置 Grafana 默认监控大盘

有时候我们希望进入 Grafana 主页后能展示一个默认的监控大盘，能够比较直观看到我们集群或系统的概况，这时可以用以下方法来配置默认的 dashboard。

首先进入 Grafana 并选择希望设置为默认的面板，然后复制下路径，粘贴到 `values` 配置里，示例：

```yaml title="grafana-homepage-values.yaml"
grafana:
  grafana.ini:
    users:
      home_page: /d/G9PMkKi7k/e99b86-e7bea4-e6a682-e8a788 # 首页自动跳转到该面板的路径
```
