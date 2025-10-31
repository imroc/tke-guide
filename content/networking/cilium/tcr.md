# 使用 TCR 托管 Cilium 镜像

## 概述

如果对集群有较高的可用性要求，需要确保扩容节点时能够快速完成初始化并就绪，建议将 Cilium 的依赖镜像同步到 TCR 镜像仓库，安装 Cilium 时也指定使用 TCR 镜像仓库中的镜像，避免因 Cilium 镜像拉取慢或拉取不到导致节点迟迟不能 Ready。

本文将介绍如何实现将 Cilium 的依赖镜像改为用 TCR 镜像仓库托管。

## 创建 TCR 镜像仓库

要想快速拉取镜像，肯定要在集群所在地域创建 TCR 镜像仓库，如果你在多个地域都有集群需要安装 Cilium，可以利用 TCR 的 [同实例多地域复制镜像](https://cloud.tencent.com/document/product/1141/52095) 或 [跨实例（账号）同步镜像](https://cloud.tencent.com/document/product/1141/41945) 的能力来实现将 Cilium 依赖镜像上传到一个镜像仓库后自动同步到其它地域的镜像仓库中。

## 新建命名空间

TCR 镜像仓库创建完成后，新建一个命名空间：
1. **名称**: cilium。
1. **访问级别**：公开。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031125444.png)

## 配置访问控制

上传 Cilium 镜像需要让上传镜像的客户端能访问到 TCR 镜像仓库：
1. 从公网推送镜像：参考 [配置公网访问控制](https://cloud.tencent.com/document/product/1141/41837) 开启镜像仓库的公网访问能力。
2. 从内网推送镜像：参考 [配置内网访问控制](https://cloud.tencent.com/document/product/1141/41838) 开启镜像仓库的内网访问能力，确保上传 Cilium 的客户端所在 VPC 与 TCR 镜像仓库建立内网访问链路。

另外 TKE 集群节点拉取 Cilium 依赖镜像也需要让节点能访问到 TCR 镜像仓库，参考 [配置内网访问控制](https://cloud.tencent.com/document/product/1141/41838) 开启镜像仓库与 TKE 集群所在 VPC 建立内网访问能力，确保上传 Cilium 的客户端所在 VPC 与 TCR 镜像仓库建立内网访问链路，并确保勾选 **自动解析**：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031140032.png)

## 安装 TCR 插件

在集群 **组件管理** 页面搜索 tcr，安装该组件，参数配置中点开 **高级设置**，确保 **内网访问链路** 显示链路正常，不要勾选 **启用内网解析功能**（前面我们配置了 TCR 内网访问链路时，已经设置了自动解析，无需向节点下发 hosts 来实现 TCR 域名解析）：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031144916.png)

## 配置并获取访问凭证

上传 Cilium 镜像前，需要先配置 TCR 的访问凭证，参考 [用户级账号管理](https://cloud.tencent.com/document/product/1141/41829) 和 [服务级账号管理](https://cloud.tencent.com/document/product/1141/89137)，获取一个可以登录 TCR 镜像仓库的访问凭证。

## 搬运 Cilium 镜像到 TCR 镜像仓库

上传 Cilium 镜像之前，得先确认当前的安装配置依赖了哪些镜像，可以使用 `helm template` 并加上计划添加的安装参数，看渲染出来的 YAML 实际使用了哪些镜像：

```bash
$ helm template cilium cilium/cilium --version 1.18.3 \
    --namespace kube-system \
    --set routingMode=native \
    --set endpointRoutes.enabled=true \
    --set ipam.mode=delegated-plugin \
    --set enableIPv4Masquerade=false \
    --set devices=eth+ \
    --set cni.chainingMode=generic-veth \
    --set cni.customConf=true \
    --set cni.configMap=cni-config \
    --set cni.externalRouting=true \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=169.254.128.125 \
    --set k8sServicePort=60002 \
    --set extraConfig.local-router-ipv4=169.254.32.16 \
    | grep image: | awk -F 'image: "' '/image:/ {gsub(/@sha256:[^"]+"/, ""); print $2}' | sort | uniq
quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222
quay.io/cilium/cilium:v1.18.3
quay.io/cilium/operator-generic:v1.18.3
```

接着准备上传镜像，可以使用 [skopeo](https://github.com/containers/skopeo) 这个工具将 cilium 依赖镜像搬运到 TCR 镜像仓库中，参考 [Installing Skopeo](https://github.com/containers/skopeo/blob/main/install.md) 进行安装。

然后用 skopeo 登录 TCR 镜像仓库（注意替换仓库域名以及用户名和密码）：

```bash
skopeo login xxx.tencentcloudcr.com --username xxx --password xxx
```

最后使用 skopeo 将 cilium 依赖镜像都同步到 TCR 镜像仓库中：

```bash
skopeo copy -a docker://quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222  docker://your-tcr-name.tencentcloudcr.com/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222
skopeo copy -a docker://quay.io/cilium/cilium:v1.18.3  docker://your-tcr-name.tencentcloudcr.com/cilium/cilium:v1.18.3
skopeo copy -a docker://quay.io/cilium/operator-generic:v1.18.3  docker://your-tcr-name.tencentcloudcr.com/cilium/operator-generic:v1.18.3
```

如果你的安装配置所依赖镜像较多，也可以通过脚本来实现一键将所有依赖镜像全部同步到 TCR 镜像仓库中，保存下面的脚本内容到 `sync-cilium-images.sh` 文件中:

:::info[注意]

1. `TARGET_REGISTRY` 是目标 TCR 镜像仓库地址，替换成自己仓库的地址。
2. 根据自己实际需要的部署配置，修改下 `helm template` 后面使用的安装参数。

:::

 ```bash title="sync-cilium-images.sh"
#!/bin/bash

TARGET_REGISTRY="your-tcr-name.tencentcloudcr.com/cilium"

source_images=$(helm template cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=169.254.128.125 \
  --set k8sServicePort=60002 \
  --set extraConfig.local-router-ipv4=169.254.32.16 |
  grep image: | awk -F 'image: "' '/image:/ {gsub(/@sha256:[^"]+"/, ""); print $2}' | sort | uniq)

echo "将会进行以下的镜像同步操作："
while IFS= read -r source_image; do
  if [[ -n "${source_image}" ]]; then
    image_name=$(basename "$source_image")
    target_image="${TARGET_REGISTRY}/${image_name}"
    echo "${source_image} --> ${target_image}"
  fi
done <<<"${source_images}"

read -p "确认开始同步? (y/n): " confirm
if [ "$confirm" != "y" ]; then
  echo "已取消"
  exit 0
fi

while IFS= read -r source_image; do
  if [[ -n "${source_image}" ]]; then
    image_name=$(basename "$source_image")
    target_image="${TARGET_REGISTRY}/${image_name}"
    echo "同步镜像 ${source_image} 到 ${target_image}"
    skopeo copy -a "docker://${source_image}" "docker://${target_image}"
  fi
done <<<"${source_images}"
```

赋予执行权限并执行：

```bash
chmod +x sync-cilium-images.sh
./sync-cilium-images.sh
```

## 安装 Cilium 指定 TCR 镜像

参考 [安装 cilium](https://imroc.cc/tke/networking/cilium/install)，替换下依赖镜像为 TCR 镜像仓库中对应的镜像地址：

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  # highlight-add-start
  --set image.repository=your-tcr-name.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=your-tcr-name.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=your-tcr-name.tencentcloudcr.com/cilium/operator \
  # highlight-add-end
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002 \
  --set extraConfig.local-router-ipv4=169.254.32.16
```

如果已经执行过安装，可通过以下方式修改依赖镜像地址：

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=your-tcr-name.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=your-tcr-name.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=your-tcr-name.tencentcloudcr.com/cilium/operator
```
