# 在 TKE 上自建 Grafana

## 概述

腾讯云提供了托管的 [Grafana 服务](https://cloud.tencent.com/product/tcmg)，并且支持与 TKE 高度集成，能够覆盖绝大部分使用场景。如果对版本要求，或者有很多个性化需求的场景，也可以考虑在 TKE 上自建 Grafana，本文介绍具体方法。

## 使用 helm 安装

Grafana 提供了官方的 helm chart，用法参考 [官方文档](https://github.com/grafana/helm-charts/blob/main/charts/grafana/README.md)。

如果你使用 [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 或 [victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/README.md) 自建监控系统，它们也都依赖了 Grafana 官方的 chart，其中 Grafana 是作为一个子 chart，Grafana 相关的 `values` 配置，放到 `grafana` 字段下即可。

## 配置 Grafana 

下面是一些建议加上的配置：

```yaml title="grafana-values.yaml"
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

* `adminUser` 和 `adminPassword` 分别设置管理员的账号和密码。
* `defaultDashboardsTimezone` 设置展示面板所用的时区，国内固定使用 `Asia/Shanghai`。
* `folderAnnotation` 是存储 dashboard 的 ConfigMap 的一个注解名称，用于标识该 ConfigMap 下面板 json 文件存储的目录，结合 `foldersFromFilesStructure` 置为 true，可实现 ConfigMap 中的面板按目录组织。

## 声明式配置 Grafana Dashboard

如果在 Grafana 上新建 Dashboard 并保存，这个 Dashboard 会被持久化到 Grafana 的存储，但假如希望这些 Dashboard 被多个 Grafana 共用，就需要手动导入再导入，维护起来比较麻烦。

下面介绍声明式配置 Dashboard 的方法，可以让你的 Dashboard 在多个 Grafana 之间共享，无需繁琐的手动导出导入的操作。

首先说下思路：Dashboard 配置的本质是 json 文件，我们可以将 json 存储到 ConfigMap，利用 Grafana Chart 中自带的 sidecar，将 ConfigMap 中的 json 自动同步到 Grafana 保存 Dashboard 的目录中。

制作好 Dashboard 后，我们可以导出 Dashboard 的 json 文件到本地，通过 `kustomize` 引用并统一加上 `grafana_dashboard: 1` 的 label，比如要为 `EnvoyGateway` 加 Dashboard，使用以下 kustomize 的结构组织文件:

```txt
envoygateway
├── dashboards
│   ├── envoy-clusters.json
│   ├── envoy-global.json
│   └── envoy-pod-resource.json
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

## 配置 TKE 监控面板

在 GitHub 上有开源的 TKE Grafana 监控面板 [grafana-dashboards/tke](https://github.com/grafana-dashboards/tke)，通过以下命令将面板添加到 Grafana：

```bash
git clone git@github.com:grafana-dashboards/tke.git
kubectl apply -k ./tke
```
