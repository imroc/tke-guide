---
sidebar_position: 2
---

# Using Foreign Container Images

## Background

When deploying open-source applications on TKE, you often encounter issues where dependent images cannot be pulled or are very slow to download, such as from foreign public image registries like gcr.io, quay.io, etc. Actually, TKE provides acceleration capabilities for foreign images. This article describes how to use this capability to deploy open-source applications.

## Image Address Mapping

Here are the supported image registries and their mapping addresses:

| Foreign Image Registry Address | Tencent Cloud Mapping Address |
|:----|:----|
| quay.io | quay.tencentcloudcr.com |
| nvcr.io | nvcr.tencentcloudcr.com |

## Modifying Image Addresses

When deploying applications, modify the image addresses by replacing the image registry domain with Tencent Cloud's mapping address (see table above). For example, change `quay.io/prometheus/node-exporter:v0.18.1` to `quay.tencentcloudcr.com/prometheus/node-exporter:v0.18.1`. This way, image pulls will go through the accelerated address.

## Don't Want to Modify Image Addresses?

If there are too many images and modifying addresses is too cumbersome (e.g., when using helm to deploy with many images), you can utilize containerd's mirror configuration to avoid modifying image addresses (prerequisite: container runtime uses containerd).

> Docker only supports mirror configuration for docker hub, so if the container runtime is Docker, you must modify image addresses.

The specific method is to modify containerd configuration (`/etc/containerd/config.toml`) and add Tencent Cloud mapping addresses to the mirrors section:

```toml
    [plugins.cri.registry]
      [plugins.cri.registry.mirrors]
        [plugins.cri.registry.mirrors."quay.io"]
          endpoint = ["https://quay.tencentcloudcr.com"]
        [plugins.cri.registry.mirrors."nvcr.io"]
          endpoint = ["https://nvcr.tencentcloudcr.com"]
        [plugins.cri.registry.mirrors."docker.io"]
          endpoint = ["https://mirror.ccs.tencentyun.com"]
```

However, manually modifying each node is too cumbersome. We can specify custom data (i.e., custom scripts that run during node initialization) when adding nodes or creating node pools to automatically modify containerd configuration:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925161649.png)

Paste the following script:

```bash
sed -i '/\[plugins\.cri\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins.cri.registry.mirrors."quay.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://quay.tencentcloudcr.com"]' /etc/containerd/config.toml
sed -i '/\[plugins\.cri\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins.cri.registry.mirrors."nvcr.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://nvcr.tencentcloudcr.com"]' /etc/containerd/config.toml
systemctl restart containerd
```

> It's recommended to use node pools. When scaling nodes, the script will run automatically, eliminating the need to configure custom data each time you add nodes.

## References

* [TKE Official Documentation: Foreign Image Pull Acceleration](https://cloud.tencent.com/document/product/457/51237)