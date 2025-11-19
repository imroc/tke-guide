---
sidebar_position: 1
---

# Building Monitoring System Using kube-prometheus-stack

## Overview

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) is a helm chart in the Prometheus ecosystem for deploying Prometheus-related components in Kubernetes, covering Prometheus Operator, Prometheus, Thanos, Grafana, node-exporter, kube-state-metrics, and various Grafana dashboards provided by the community. This article describes how to use this chart to build a monitoring system.

## Custom Configuration Methods

Since the `kube-prometheus-stack` chart is very large and contains many other dependent charts, the configuration is also extensive. If we have many custom configurations, maintaining them in a single `values.yaml` file can be cumbersome. We can split them into multiple files and specify multiple configuration files during installation:

* If installing directly with helm, you can specify multiple `-f` parameters:
  ```bash
  helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    -f image-values.yaml \
    -f grafana-values.yaml
  ```
* If using kustomize to reference this chart for installation, you can use `additionalValuesFiles` to specify multiple `values` configuration files:
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
      # highlight-start
  ```
  > kustomize is built into kubectl and can be installed via `kubectl apply -k .`.

## Replacing Image Addresses for Domestic Environments

Many of the dependent images for `kube-prometheus-stack` are located in foreign image repositories such as `quay.io` and `registry.k8s.io`. Pulling these images may fail in a domestic environment. If your cluster is located in China, you can replace the images on `quay.io` with the TKE-accelerated mirror address `quay.tencentcloudcr.com`, and replace the images on `registry.k8s.io` with the corresponding automatically synchronized mirror images from Docker Hub:


| Foreign Dependency Images                             | DockerHub Automatically Synchronized Mirror Images     |
| :---------------------------------------------------- | :----------------------------------------------------- |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | docker.io/k8smirror/kube-state-metrics                 |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen    | docker.io/k8smirror/ingress-nginx-kube-webhook-certgen |

:::tip

The above mirror images are all long-term automatically synchronized images and can be safely used and updated.

:::

Create corresponding `values` configuration:

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

## Configuring Grafana

Grafana is a subchart in `kube-prometheus-stack`. All its configurations are placed under the `grafana` field, such as:

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

For specific configuration recommendations, refer to [Self-hosting Grafana on TKE](grafana).
