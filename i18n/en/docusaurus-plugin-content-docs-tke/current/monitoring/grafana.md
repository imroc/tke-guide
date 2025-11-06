---
sidebar_position: 2
---

# Self-hosting Grafana on TKE

## Overview

Tencent Cloud provides managed [Grafana service](https://cloud.tencent.com/product/tcmg) with high integration with TKE, covering most usage scenarios. If you have specific version requirements or many personalized needs, you can also consider self-hosting Grafana on TKE. This article describes the specific methods.

## Installation Using Helm

Grafana provides an official helm chart. Usage reference: [Official Documentation](https://github.com/grafana/helm-charts/blob/main/charts/grafana/README.md).

If you use [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) or [victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/README.md) to build your monitoring system, they also depend on Grafana's official chart, where Grafana is a subchart. Grafana-related `values` configurations can be placed under the `grafana` field.

## Configuring Grafana

Here are some recommended configurations to add:

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

* `adminUser` and `adminPassword` set the administrator account and password respectively.
* `defaultDashboardsTimezone` sets the timezone used for dashboard display. In China, fixedly use `Asia/Shanghai`.
* `folderAnnotation` is an annotation name for ConfigMaps storing dashboard files, used to identify the directory where dashboard json files are stored in the ConfigMap. Combined with `foldersFromFilesStructure` set to true, it enables organizing dashboards in ConfigMaps by directories.

## Declarative Configuration of Grafana Dashboards

If you create new dashboards in Grafana and save them, these dashboards will be persisted to Grafana's storage. However, if you want these dashboards to be shared among multiple Grafana instances, you need to manually export and import them, which is cumbersome to maintain.

Below describes the declarative configuration method for dashboards, allowing your dashboards to be shared among multiple Grafana instances without tedious manual export/import operations.

First, the idea: Dashboard configurations are essentially json files. We can store json in ConfigMaps and use the sidecar included in the Grafana Chart to automatically synchronize json from ConfigMaps to the directory where Grafana saves dashboards.

After creating dashboards, we can export dashboard json files locally and reference them via `kustomize`, uniformly adding the `grafana_dashboard: 1` label. For example, to add dashboards for `EnvoyGateway`, use the following kustomize file structure:

```txt
envoygateway
├── dashboards
│   ├── envoy-clusters.json
│   ├── envoy-global.json
│   └── envoy-pod-resource.json
└── kustomization.yaml
```

In `kustomization.yaml`, use `configMapGenerator` to generate ConfigMaps from these dashboard json files, and uniformly apply the `grafana_dashboard: 1` label and `grafana_folder: Envoy` annotation:

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

## Configuring Grafana Default Dashboard

Sometimes we want to display a default dashboard on the Grafana homepage that can intuitively show the overview of our cluster or system. You can use the following method to configure the default dashboard.

First, enter Grafana and select the dashboard you want to set as default, then copy the path and paste it into the `values` configuration. Example:

```yaml title="grafana-homepage-values.yaml"
grafana:
  grafana.ini:
    users:
      home_page: /d/G9PMkKi7k/e99b86-e7bea4-e6a682-e8a788 # Path for automatic homepage redirection to this dashboard
```

## Configuring TKE Monitoring Dashboards

There are open-source TKE Grafana monitoring dashboards on GitHub [grafana-dashboards/tke](https://github.com/grafana-dashboards/tke). Add dashboards to Grafana with the following command:

```bash
git clone --depth 1 git@github.com:grafana-dashboards/tke.git grafana-dashboards-tke
kubectl apply -k ./grafana-dashboards-tke
```