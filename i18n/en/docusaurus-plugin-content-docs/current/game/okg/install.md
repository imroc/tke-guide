# Installing OpenKruiseGame on TKE

## Installation Methods

Two methods:
1. Install through TKE Application Marketplace. The advantage is simplicity and convenience - you can install directly by clicking in the console.
2. Install using helm commands provided by OKG officially. The advantages are timely version updates and the ability to install and manage through GitOps methods (such as ArgoCD), offering more flexibility.

## Installing Through TKE Application Marketplace

Search for `kruise` in the [TKE Application Marketplace](https://console.cloud.tencent.com/tke2/helm), and you can see `kruise` and `kruise-game`. Install them to the cluster.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226161254.png)

## Installing with Helm

[OpenKruiseGame](https://openkruise.io/kruisegame/introduction) and its dependency [OpenKruise](https://openkruise.io/docs/) both have their images on DockerHub, and in TKE environments, DockerHub images can be pulled directly without any configuration. Therefore, installing `OpenKruiseGame` on TKE has no special requirements - simply follow the [Official Installation Documentation](https://openkruise.io/kruisegame/installation/) for installation.

### Prerequisites

Before installation, ensure the following prerequisites are met:
1. A [TKE](https://cloud.tencent.com/product/tke) cluster has been created with a cluster version greater than or equal to 1.18.
2. The [helm](https://helm.sh) command is installed locally and can operate the TKE cluster through helm commands (refer to [Connecting Local Helm Client to Cluster](https://cloud.tencent.com/document/product/457/32731)).

### Installing Kruise and Kruise-Game

Refer to the [Official Installation Documentation](https://openkruise.io/kruisegame/installation/) for installation.

### What if the helm command environment cannot connect to GitHub?

When installing using helm commands, it depends on helm repos hosted on GitHub. If the environment where helm commands are executed cannot connect to GitHub, installation will fail.

If you cannot solve the network issue of the machine where helm is located, you can try executing helm commands on a machine that can connect to GitHub to download the dependent chart packages:

```bash
$ helm repo add openkruise https://openkruise.github.io/charts/
$ helm fetch openkruise/kruise
$ helm fetch openkruise/kruise-game
$ ls kruise-*.tgz
kruise-1.6.3.tgz  kruise-game-0.8.0.tgz
```

Then copy the downloaded `tgz` archive to the machine where the helm command is originally located, and execute helm commands to install:

```bash
helm install kruise kruise-1.6.3.tgz
helm install kruise-game kruise-game-0.8.0.tgz
```

> Note: Replace the filenames.

### kruise-game-controller-manager reports client-side throttling error

When installing `OpenKruiseGame` on TKE with default configuration (v0.8.0), the `kruise-game-controller-manager` Pod may fail to start:

```log
I0708 03:28:11.315405       1 request.go:601] Waited for 1.176544858s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/operators.coreos.com/v1alpha2?timeout=32s
I0708 03:28:21.315900       1 request.go:601] Waited for 11.176584459s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/install.istio.io/v1alpha1?timeout=32s
```

This is because the default local APIServer rate limiting in `OpenKruiseGame`'s helm chart package is too low (`values.yaml`):

```yaml
kruiseGame:
  apiServerQps: 5
  apiServerQpsBurst: 10
```

You can increase it:

```yaml
kruiseGame:
  apiServerQps: 50
  apiServerQpsBurst: 100
```

## Installing tke-extend-network-controller Network Plugin

If you need to use OKG's [TencentCloud-CLB](https://openkruise.io/kruisegame/user-manuals/network#tencentcloud-clb) network access, ensure that `tke-extend-network-controller` is installed. Refer to [Installing tke-extend-network-controller](../../networking/tke-extend-network-controller) for details.
