# Quick Start

:::warning[warning]

Nginx Ingress will be deprecated and will no longer be maintained by the Kubernetes community: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/

It is recommended to migrate to Ingresss for the Gateway API, such as using EnvoyGateway as the Gateway API implementation (see [Using EnvoyGateway Traffic Gateway on TKE](../envoygateway.md)).

:::

## Overview

[Nginx Ingress Controller](https://github.com/kubernetes/ingress-nginx) is a Kubernetes Ingress controller implemented based on the high-performance NGINX reverse proxy, and is the most commonly used open-source Ingress implementation. This article describes how to self-build Nginx Ingress Controller in a TKE environment, primarily using helm for installation, and provides some `values.yaml` configuration guidance.

## Prerequisites

* A TKE cluster has been created.
* [helm](https://helm.sh/) is installed.
* The kubeconfig of the TKE cluster is configured with permissions to operate the TKE cluster (refer to [Connecting to Cluster](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)).

## Installing with Helm

Add helm repo:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

:::tip[Note]

If the machine where the helm command is located cannot connect to GitHub, adding will fail. Refer to the later section [FAQ: Installation Failure Due to GitHub Connection Issues](#faq-installation-failure-due-to-github-connection-issues) for a solution.

:::

View default configuration:

```bash
helm show values ingress-nginx/ingress-nginx
```

Nginx Ingress depends on images under the `registry.k8s.io` registry, which cannot be pulled in domestic network environments. They can be replaced with mirror images on Docker Hub.

Prepare `values.yaml`:

```yaml
controller: # The following configuration replaces dependent images with mirror images on docker hub to ensure normal pulling in domestic environments
  image:
    registry: docker.io
    image: k8smirror/ingress-nginx-controller
  admissionWebhooks:
    patch:
      image:
        registry: docker.io
        image: k8smirror/ingress-nginx-kube-webhook-certgen
  defaultBackend:
    image:
      registry: docker.io
      image: k8smirror/defaultbackend-amd64
  opentelemetry:
    image:
      registry: docker.io
      image: k8smirror/ingress-nginx-opentelemetry
```

> Mirror images in the configuration are all automatically synchronized long-term using [image-porter](https://github.com/imroc/image-porter), and can be safely installed and upgraded.

Install:

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

> If you need to modify values configuration or upgrade versions later, you can update Nginx Ingress Controller by executing this command.

View traffic entry point (CLB VIP or domain):

```bash
$ kubectl get services -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   172.16.145.161   162.14.91.101   80:30683/TCP,443:32111/TCP   53s
ingress-nginx-controller-admission   ClusterIP      172.16.166.237   <none>          443/TCP                      53s
```

> The `EXTERNAL-IP` of the `LoadBalancer` type Service is the CLB's VIP or domain, which can be configured for DNS resolution. If it's a VIP, configure an A record; if it's a CLB domain, configure a CNAME record.

## FAQ: Installation Failure Due to GitHub Connection Issues

The `ingress-nginx` helm chart repository address is on GitHub. If the environment where the helm command is located cannot connect to GitHub, the chart package cannot be downloaded, and the `helm repo add` operation will also fail.

If you encounter this issue, you can download the chart on a machine that can connect to GitHub first, then copy it to the machine where the helm command is located.

Download method:

```bash showLineNumbers
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm fetch ingress-nginx/ingress-nginx
```

> To download a specific version of the chart, add the `--version` parameter to the fetch subcommand, e.g.: `helm fetch ingress-nginx/ingress-nginx --version 4.7.5`

View the downloaded chart package:

```bash
$ ls
ingress-nginx-4.11.2.tgz
```

Copy this archive to the machine where the helm command is located, and replace the chart name with the archive file path in the installation command:

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx-4.11.2.tgz \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

## Versions and Upgrades

The Nginx Ingress version needs to be compatible with the Kubernetes cluster version. Refer to the official [Supported Versions table](https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table) to confirm whether the current cluster version supports the latest nginx ingress. If not supported, specify the chart version during installation.

For example, if the current TKE cluster version is 1.24, the chart version can only go up to `4.7.*`. Check which versions are available with the following command:

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions | grep 4.7.
ingress-nginx/ingress-nginx     4.7.5           1.8.5           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.3           1.8.4           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.2           1.8.2           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.1           1.8.1           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.0           1.8.0           Ingress controller for Kubernetes using NGINX a...
```

You can see that the highest version of `4.7.*` is `4.7.5`. Add the version number during installation:

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  # highlight-next-line
  --version 4.7.5 \
  -f values.yaml
```

:::info[Note]

Before upgrading the TKE cluster, first check whether the current Nginx Ingress version is compatible with the cluster version after upgrade. If not compatible, upgrade Nginx Ingress first (use the above command to specify the chart version number).

:::

## Using Ingress

Nginx Ingress implements the standard capabilities defined by Kubernetes' Ingress API. Basic usage of Ingress can be found in the [Kubernetes Official Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/).

When creating an Ingress, you must specify `ingressClassName` as the IngressClass used by the Nginx Ingress instance (default is `nginx`):

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  # highlight-next-line
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

In addition, Nginx Ingress has many other unique features that extend Ingress functionality through Ingress annotations. Refer to [Nginx Ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/).

## More Customization

If you need more customization of Nginx Ingress, refer to the next few guidance documents and merge the `values.yaml` configurations according to your needs. The last article also provides a complete example of the merged `values.yaml` configuration.

Alternatively, you can maintain `values.yaml` split into multiple files. When executing installation or update commands, use multiple `-f` parameters to specify multiple configuration files:

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  # highlight-start
  -f image-values.yaml \
  -f prom-values.yaml \
  -f logrotate-values.yaml \
  -f autoscaling-values.yaml
  # highlight-end
```
