# 使用 kube-prometheus-stack 搭建监控系统

## 概述

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 是 Prometheus 生态中用于在 Kubernetes 部署 Prometheus 相关组件的 helm chart，涵盖 Prometheus Operator、Prometheus、Thanos、Grafana、node-exporter、kube-state-metrics 以及社区提供的各种 Grafana 面板等，本文介绍如何使用这个 chart 来搭建监控系统。

## 自定义配置的方法

由于 `kube-prometheus-stack` 这个 chart 非常庞大，还包含了很多其它依赖的 chart，配置也就非常多，如果我们要自定义的配置也很多，写到一个 `values.yaml` 中维护起来比较麻烦，我们可以拆成多个，在安装的时候指定多个配置文件就可以了：
* 如果你直接用 helm 进行安装，可以指定多次 `-f` 参数:
  ```bash
  helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    -f image-values.yaml \
    -f grafana-values.yaml
  ```
* 如果你用 kustomize 引用该 chart 安装，可以用 `additionalValuesFiles` 指定多个 `values` 配置文件:
  ```yaml showLineNumbers title="kustomization.yaml"
  helmCharts:
    - repo: https://prometheus-community.github.io/helm-charts
      name: kube-prometheus-stack
      releaseName: kube-prometheus-stack
      namespace: monitoring
      includeCRDs: true
      # highlight-start
      additionalValuesFiles:
        - image-values.yaml
        - grafana-values.yaml
      # highlight-start
  ```
  > kustomize 内置到了 kubectl，可通过 `kubectl apply -k .` 进行安装。

## 国内环境替换镜像地址

`kube-prometheus-stack` 很多依赖镜像在 `quay.io` 和 `registry.k8s.io` 这些国外的镜像仓库，国内环境拉取会失败，如果你的集群在国内，可以将国外的依赖镜像替换为 DockerHub 中相应的自动同步的 mirror 镜像：

| 国外的依赖镜像                                         | DockerHub 中自动同步的 mirror 镜像                     |
| :----------------------------------------------------- | :----------------------------------------------------- |
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
  admissionWebhooks:
    deployment:
      image:
        registry: quay.tencentcloudcr.com
    patch:
      image:
        registry: docker.io
        repository: k8smirror/ingress-nginx-kube-webhook-certgen
  prometheusConfigReloader:
    image:
      registry: quay.tencentcloudcr.com
  thanosImage:
    registry: quay.tencentcloudcr.com
thanosRuler:
  thanosRulerSpec:
    image:
      registry: docker.io
      repository: imroc/thanos
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

## 配置 Grafana 

grafana 是 `kube-prometheus-stack` 中的一个 subchart，它所有的配置都放到 `grafana` 字段下面，如：

```yaml title="grafana-values.yaml"
grafana:
  adminUser: "admin"
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

具体配置建议参考 [在 TKE 上自建 Grafana](grafana)。
