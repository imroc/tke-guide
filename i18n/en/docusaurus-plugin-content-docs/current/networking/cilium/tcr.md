# Host Cilium Images Using TCR

## Overview

If you have high availability requirements for your cluster and need to ensure that nodes can complete initialization and become ready quickly during scaling, it is recommended to synchronize Cilium's dependency images to a TCR image repository. When installing Cilium, specify the use of images from the TCR image repository to avoid delays in node readiness caused by slow or failed Cilium image pulls.

This article will describe how to change Cilium's dependency images to be hosted by the TCR image repository.

## Create TCR Image Repository

To achieve fast image pulls, you must create a TCR image repository in the same region as your cluster. If you have clusters in multiple regions that need to install Cilium, you can utilize TCR's [Cross-Region Image Replication](https://cloud.tencent.com/document/product/1141/52095) or [Cross-Instance (Account) Image Synchronization](https://cloud.tencent.com/document/product/1141/41945) capabilities to automatically synchronize Cilium dependency images to other regional image repositories after uploading them to one repository.

## Create Namespace

After the TCR image repository is created, create a new namespace:
1. **Name**: quay.io
1. **Access Level**: Public

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F11%2F07%2F20251107105451.png)

## Configure Access Control

Uploading Cilium images requires that the client uploading the images can access the TCR image repository:
1. For public network image pushes: Refer to [Configuring Public Network Access Control](https://cloud.tencent.com/document/product/1141/41837) to enable the image repository's public network access capability.
2. For private network image pushes: Refer to [Configuring Private Network Access Control](https://cloud.tencent.com/document/product/1141/41838) to enable the image repository's private network access capability, ensuring that the VPC where the Cilium upload client is located establishes a private network access link with the TCR image repository.

Additionally, TKE cluster nodes pulling Cilium dependency images also need to be able to access the TCR image repository. Refer to [Configuring Private Network Access Control](https://cloud.tencent.com/document/product/1141/41838) to enable private network access between the image repository and the VPC where the TKE cluster is located, ensure that the VPC where the Cilium upload client is located establishes a private network access link with the TCR image repository, and make sure to check **Auto Resolution**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F11%2F07%2F20251107105604.png)

## Install TCR Plugin

In the cluster's **Component Management** page, search for tcr, install this component, open **Advanced Settings** in the parameter configuration, ensure that the **Private Network Access Link** shows the link is normal, and do not check **Enable Private Network Resolution Function** (we have already configured auto resolution when we set up the TCR private network access link earlier, so there's no need to deploy hosts to nodes for TCR domain name resolution):

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031144916.png)

## Configure and Obtain Access Credentials

Before uploading Cilium images, you need to configure TCR access credentials. Refer to [User Account Management](https://cloud.tencent.com/document/product/1141/41829) and [Service Account Management](https://cloud.tencent.com/document/product/1141/89137) to obtain access credentials that can log in to the TCR image repository.

## Transfer Cilium Images

Before uploading Cilium images, you need to confirm which images your current installation configuration depends on. You can use `helm template` with the planned installation parameters to see which images are actually used in the rendered YAML:

```bash
$ helm template cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=169.254.128.125 \
  --set k8sServicePort=60002 \
  | grep image: | awk -F 'image: "' '/image:/ {gsub(/@sha256:[^"]+"/, ""); print $2}' | sort | uniq
quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222
quay.io/cilium/cilium:v1.18.4
quay.io/cilium/operator-generic:v1.18.4
```

Next, prepare to upload the images. You can use [skopeo](https://github.com/containers/skopeo) to transfer Cilium dependency images to the TCR image repository. Refer to [Installing Skopeo](https://github.com/containers/skopeo/blob/main/install.md) for installation instructions.

Then use skopeo to log in to the TCR image repository (replace the repository domain, username, and password):

```bash
skopeo login xxx.tencentcloudcr.com --username xxx --password xxx
```

Finally, use skopeo to synchronize all Cilium dependency images to the TCR image repository:

```bash
skopeo copy -a docker://quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222  docker://your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222
skopeo copy -a docker://quay.io/cilium/cilium:v1.18.4  docker://your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium:v1.18.4
skopeo copy -a docker://quay.io/cilium/operator-generic:v1.18.4  docker://your-tcr-name.tencentcloudcr.com/quay.io/cilium/operator-generic:v1.18.4
```

If your installation configuration depends on many images, you can also use a script to synchronize all dependency images to the TCR image repository with one click. Save the following script content to a file named `sync-cilium-images.sh`:

:::info[Note]

1. `TARGET_REGISTRY` is the target TCR image repository address, replace it with your own repository address.
2. Modify the installation parameters used after `helm template` according to your actual deployment configuration needs.

:::

 ```bash title="sync-cilium-images.sh"
#!/bin/bash

set -e

TARGET_REGISTRY="your-tcr-name.tencentcloudcr.com"

source_images=$(helm template cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=169.254.128.125 \
  --set k8sServicePort=60002 \
  | grep image: | awk -F 'image: "' '/image:/ {gsub(/@sha256:[^"]+"/, ""); print $2}' | sort | uniq)

if [[ -z "${source_images}" ]]; then
  echo "No images found"
  exit 1
fi

echo "The following image synchronization operations will be performed:"
while IFS= read -r source_image; do
  if [[ -n "${source_image}" ]]; then
    target_image="${TARGET_REGISTRY}/${source_image}"
    echo "${source_image} --> ${target_image}"
  fi
done <<<"${source_images}"

read -p "Confirm to start synchronization? (y/n): " confirm
if [ "$confirm" != "y" ]; then
  echo "Cancelled"
  exit 0
fi

while IFS= read -r source_image; do
  if [[ -n "${source_image}" ]]; then
    target_image="${TARGET_REGISTRY}/${source_image}"
    echo "Synchronizing image ${source_image} to ${target_image}"
    skopeo copy -a "docker://${source_image}" "docker://${target_image}"
  fi
done <<<"${source_images}"
```

Grant execution permissions and execute:

```bash
chmod +x sync-cilium-images.sh
./sync-cilium-images.sh
```

## Install Cilium Using TCR Images

Refer to [Installing Cilium](https://imroc.cc/tke/networking/cilium/install) for installation, replacing the dependency images with the corresponding image addresses from the TCR image repository:

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  # highlight-add-start
  --set image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium \
  --set envoy.image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium-envoy \
  --set operator.image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/operator \
  # highlight-add-end
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

If you have already performed the installation, you can modify the dependency image addresses in the following way:

```bash
helm upgrade cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium \
  --set envoy.image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/cilium-envoy \
  --set operator.image.repository=your-tcr-name.tencentcloudcr.com/quay.io/cilium/operator
```
