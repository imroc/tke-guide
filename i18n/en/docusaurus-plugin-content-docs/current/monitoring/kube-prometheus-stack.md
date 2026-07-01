---
sidebar_position: 1
---

# Building Monitoring System Using kube-prometheus-stack

## Overview

[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) is a helm chart in the Prometheus ecosystem for deploying Prometheus-related components in Kubernetes, covering Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, and various Grafana dashboards provided by the community. This article describes how to use this chart to build a monitoring system in a TKE cluster.

## Installation

Add the helm repo:

```bash
helm repo add prom https://prometheus-community.github.io/helm-charts
helm repo update
```

Install:

```bash
helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version <chart-version> \
  -f image-values.yaml \
  -f grafana-values.yaml
```

:::tip[Choose the Right Chart Version]

The chart version of `kube-prometheus-stack` corresponds one-to-one with the app version (Prometheus Operator version). CRDs, default configurations, and image versions may differ significantly between versions.

After selecting a chart version, the image tags in `image-values.yaml` must match the app version corresponding to the chart version, otherwise compatibility issues may arise.

:::

## Custom Configuration Methods

The `kube-prometheus-stack` chart is very large with numerous configuration options. It is recommended to split custom configurations into multiple `values.yaml` files for separate maintenance, and specify multiple `-f` parameters during installation:

- `image-values.yaml`: Image replacement configuration
- `grafana-values.yaml`: Grafana and other custom configurations

```bash
helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f image-values.yaml \
  -f grafana-values.yaml
```

If using kustomize for management, you can use `additionalValuesFiles`:

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

## Replacing Image Addresses for Domestic Environments

The images used by `kube-prometheus-stack` primarily come from `quay.io`, which may fail or timeout when pulling domestically. There are two solutions:

### Option 1: Using TKE Internal Mirror (Recommended)

TKE provides `quay.tencentcloudcr.com` as an internal mirror for `quay.io`. Simply replace the image registry:

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

Some images not on `quay.io` can be replaced with community mirrors on DockerHub:

| Original Image                                        | DockerHub Mirror Image                                  |
| :---------------------------------------------------- | :----------------------------------------------------- |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | docker.io/k8smirror/kube-state-metrics                 |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen    | docker.io/k8smirror/ingress-nginx-kube-webhook-certgen |

### Option 2: Exporting Images from an Existing Cluster

If the target cluster nodes cannot pull any external images (e.g., docker.io is also blocked), you can export images from nodes in an available cluster and import them into the target cluster nodes:

```bash
# 1. Export images on an existing cluster node
NODE_IP=<source-node-ip>
kubectl node-shell $NODE_IP << 'EOF'
ctr -n k8s.io images export /tmp/prometheus.tar \
  quay.io/prometheus/prometheus:latest --platform linux/amd64
EOF

# 2. Import images on the target cluster node
TARGET_NODE_IP=<target-node-ip>
kubectl node-shell $TARGET_NODE_IP << 'EOF'
# Download from source node (requires network connectivity)
curl -o /tmp/prometheus.tar http://$SOURCE_NODE_IP:18080/prometheus.tar
ctr -n k8s.io images import /tmp/prometheus.tar --no-unpack
rm -f /tmp/prometheus.tar
EOF
```

This approach requires setting `imagePullPolicy` to `IfNotPresent` (the default value) to prevent kubelet from attempting to pull from the remote registry.

## Configuring Grafana

Grafana is a subchart of `kube-prometheus-stack`. All Grafana configurations are placed under the `grafana` field:

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

For specific configuration recommendations, refer to [Self-hosting Grafana on TKE](./grafana).

## Special Configuration in Self-managed Cilium Overlay Clusters

:::warning[Webhook Compatibility Issues in Overlay Mode]

In TKE self-managed Cilium Overlay mode managed clusters, the apiserver runs on the control plane (without cilium-agent) and cannot route to overlay Pod IPs (e.g., `10.244.x.x`). This causes connection timeouts when the apiserver calls ValidatingWebhook / MutatingWebhook.

See [Installing Cilium FAQ - Webhook Validating/Mutating Connection Timeout in Overlay Mode](../networking/cilium/install.md#webhook-validatingmutating-connection-timeout-in-overlay-mode).

:::

### Disabling Admission Webhooks

The Prometheus Operator in `kube-prometheus-stack` enables admission webhooks by default. Its certgen job requires pulling additional images (e.g., `kube-webhook-certgen`), and the webhook service itself will also encounter the aforementioned overlay unreachability issue. It is recommended to disable them in Overlay mode:

```yaml title="grafana-values.yaml"
prometheusOperator:
  admissionWebhooks:
    enabled: false
```

After disabling, the operator's deployment will still reference the `kube-prometheus-stack-admission` TLS Secret as a volume. You need to manually create a self-signed certificate Secret:

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt \
  -days 365 -nodes -subj "/CN=kube-prometheus-stack-operator"

kubectl -n monitoring create secret generic kube-prometheus-stack-admission \
  --from-file=cert=/tmp/tls.crt \
  --from-file=key=/tmp/tls.key
```

### cert-manager Webhook

If cert-manager is installed in the cluster, its webhook is also affected by the overlay unreachability. Solutions:

1. **Configure the cert-manager webhook with `hostNetwork: true`** (recommended)
2. **Temporarily delete the ValidatingWebhookConfiguration** (bypasses validation, suitable for initial deployment phase)

```bash
# Temporarily bypass cert-manager webhook validation
kubectl delete validatingwebhookconfiguration cert-manager-webhook
```

## Exposing Grafana

### Exposing via Gateway API

If EnvoyGateway is already deployed in the cluster, you can expose Grafana through an HTTPRoute:

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

### Temporary Access via port-forward

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Access `http://localhost:3000` and log in with the credentials configured in `grafana-values.yaml`.

## Verification

```bash
# Check if all Pods are ready
kubectl -n monitoring get pod

# Verify Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
curl http://localhost:9090/-/healthy

# Verify Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
curl http://localhost:3000/api/health

# Get Grafana password
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## FAQ

### Pod Stuck in ImagePullBackOff?

Check if the image configuration in `image-values.yaml` is correct:

1. Whether the image tags match the app version corresponding to the chart version
2. Whether the image registry is reachable from the cluster nodes (refer to [Replacing Image Addresses for Domestic Environments](#replacing-image-addresses-for-domestic-environments))

### Prometheus Operator CrashLoopBackOff?

If admission webhooks are disabled but the `kube-prometheus-stack-admission` Secret is not created, the operator will fail to start due to missing TLS certificate files. Refer to the [Disabling Admission Webhooks](#disabling-admission-webhooks) section to create the Secret.

### Grafana sidecar CrashLoopBackOff?

Grafana sidecars (`grafana-sc-dashboard` / `grafana-sc-datasources`) list Secrets and ConfigMaps via the Kubernetes API. In self-managed Cilium Overlay clusters, if the sidecar Pod cannot connect to the apiserver (although Overlay Pods can usually reach the apiserver at the 169.254 address, certificate verification failures may cause errors), you can set an environment variable to skip TLS verification:

```yaml
grafana:
  env:
    - name: SKIP_TLS_VERIFY
      value: "true"
```
