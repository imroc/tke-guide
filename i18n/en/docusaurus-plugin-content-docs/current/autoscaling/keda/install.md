# Deploying KEDA on TKE

## Add helm repo

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

## Prepare values.yaml

First check the default values.yaml (to see what configuration options can be customized)

```bash
helm show values kedacore/keda
```

The default dependency images cannot be pulled in domestic environments. You can replace them with mirror images from Docker Hub by configuring `values.yaml`:

```yaml
image:
  keda:
    registry: docker.io
    repository: imroc/keda
  metricsApiServer:
    registry: docker.io
    repository: imroc/keda-metrics-apiserver
  webhooks:
    registry: docker.io
    repository: imroc/keda-admission-webhooks
```

:::tip[Note]

The above mirror images are automatically synced long-term and can be used and updated with confidence.

:::

## Install

```bash
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace \
  -f values.yaml
```

## Versioning and Upgrades

Each KEDA version has a corresponding supported K8S version range. If your TKE cluster version is not particularly new, installing the latest KEDA version may not be compatible. You can check [KEDA Kubernetes Compatibility](https://keda.sh/docs/latest/operate/cluster/#kubernetes-compatibility) to confirm which KEDA version is compatible with your current cluster version.

For example, if the TKE cluster version is 1.26, the latest compatible KEDA version is v2.12. Then query to find that KEDA v2.12 (APP VERSION) corresponds to the highest Chart version (CHART VERSION) of 2.12.1:

```bash
$ helm search repo keda --versions
NAME                                            CHART VERSION   APP VERSION     DESCRIPTION
kedacore/keda                                   2.13.2          2.13.1          Event-based autoscaler for workloads on Kubernetes
kedacore/keda                                   2.13.1          2.13.0          Event-based autoscaler for workloads on Kubernetes
kedacore/keda                                   2.13.0          2.13.0          Event-based autoscaler for workloads on Kubernetes
# highlight-next-line
kedacore/keda                                   2.12.1          2.12.1          Event-based autoscaler for workloads on Kubernetes
kedacore/keda                                   2.12.0          2.12.0          Event-based autoscaler for workloads on Kubernetes
kedacore/keda                                   2.11.2          2.11.2          Event-based autoscaler for workloads on Kubernetes
kedacore/keda                                   2.11.1          2.11.1          Event-based autoscaler for workloads on Kubernetes
```

Specify the version when installing KEDA:

```bash
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace \
  # highlight-next-line
  --version 2.12.1 \
  -f values.yaml
```

For subsequent version upgrades, you can reuse the above installation command, only modifying the version number.

**Note**: Before upgrading the TKE cluster, also use this method to first confirm whether the upgraded cluster version can be compatible with the current KEDA version. If not, please upgrade KEDA in advance to the latest KEDA version compatible with the current cluster version.

## Uninstall

Refer to [official uninstall documentation](https://keda.sh/docs/latest/deploy/#uninstall).

## References

* [KEDA Official Documentation: Deploying KEDA](https://keda.sh/docs/latest/deploy/)
