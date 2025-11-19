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

Many dependency images in `kube-prometheus-stack` are in foreign image registries like `quay.io` and `registry.k8s.io`, which may fail to pull in domestic environments. If your cluster is in China, you can replace foreign dependency images with corresponding automatically synchronized mirror images in DockerHub:

| Foreign Dependency Images | DockerHub Automatically Synchronized Mirror Images |
| :----------------------------------------------------- | :----------------------------------------------------- |
| quay.io/prometheus-operator/admission-webhook | docker.io/imroc/prometheus-operator-admission-webhook |
| quay.io/prometheus-operator/prometheus-operator | docker.io/imroc/prometheus-operator |
| quay.io/prometheus/node-exporter | docker.io/imroc/prometheus-node-exporter |
| quay.io/prometheus/alertmanager | docker.io/imroc/prometheus-alertmanager |
| quay.io/prometheus/prometheus | docker.io/imroc/prometheus |
| quay.io/prometheus-operator/prometheus-config-reloader | docker.io/imroc/prometheus-config-reloader |
| quay.io/thanos/thanos | docker.io/imroc/thanos |
| quay.io/brancz/kube-rbac-proxy | docker.io/imroc/kube-rbac-proxy |
| quay.io/kiwigrid/k8s-sidecar | docker.io/kiwigrid/k8s-sidecar |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | docker.io/k8smirror/kube-state-metrics |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen | docker.io/k8smirror/ingress-nginx-kube-webhook-certgen |

:::tip

The above mirror images are all long-term automatically synchronized images and can be safely used and updated.

:::

Create corresponding `values` configuration:

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

## Configuring Grafana

Grafana is a subchart in `kube-prometheus-stack`. All its configurations are placed under the `grafana` field, such as:

```yaml title="grafana-values.yaml"
grafana:
  adminUser: "admin"
  adminPassword: "123456"
```

For specific configuration recommendations, refer to [Self-hosting Grafana on TKE](grafana).
