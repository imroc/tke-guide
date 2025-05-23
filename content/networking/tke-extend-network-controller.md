# 安装 tke-extend-network-controller

## 概述

tke-extend-network-controller 是腾讯云 TKE 集群的一个网络插件。本文将介绍如何在 TKE 安装 `tke-extend-network-controller`。

## 前提条件

安装 `tke-extend-network-controller` 前请确保满足以下前提条件：
1. 确保腾讯云账号是带宽上移账号，参考 [账户类型说明](https://cloud.tencent.com/document/product/1199/49090) 进行判断或升级账号类型（如果账号创建的时间很早，有可能是传统账号）。
2. 创建了 [TKE](https://cloud.tencent.com/product/tke) 集群，且集群版本大于等于 1.26。
3. 集群中安装了 [cert-manager](https://cert-manager.io/docs/installation/) (webhook 依赖证书)，参考 [在 TKE 上安装 cert-manager](../deploy/cert-manager)。
4. 需要一个腾讯云子账号的访问密钥(SecretID、SecretKey)，参考[子账号访问密钥管理](https://cloud.tencent.com/document/product/598/37140)，要求账号至少具有以下权限：
    ```json
    {
        "version": "2.0",
        "statement": [
            {
                "effect": "allow",
                "action": [
                    "clb:DescribeLoadBalancerBackends",
                    "clb:DescribeLoadBalancerListeners",
                    "clb:DescribeLoadBalancers",
                    "clb:CreateLoadBalancer",
                    "clb:DescribeTargets",
                    "clb:DeleteLoadBalancer",
                    "clb:DeleteLoadBalancerListeners",
                    "clb:BatchDeregisterTargets",
                    "clb:BatchRegisterTargets",
                    "clb:DeregisterTargets",
                    "clb:CreateLoadBalancerListeners",
                    "clb:CreateListener",
                    "clb:RegisterTargets",
                    "clb:DeleteLoadBalancers",
                    "clb:DescribeLoadBalancersDetail",
                    "clb:DescribeQuota",
                    "clb:DescribeListeners"
                ],
                "resource": [
                    "*"
                ]
            }
        ]
    }
    ```

## 安装 tke-extend-network-controller

在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm/market) 的 `网络` 分类中找到 `tke-extend-network-controller`，编辑 `values.yaml`，根据自己需求进行配置，以下几个参数是必填的：

```yaml
region: "" # TKE 集群所在地域（如 ap-hongkong)，所有地域列表参考: https://cloud.tencent.com/document/product/213/6091.
vpcID: "" # TKE 集群所在 VPC ID (vpc-xxx)
clusterID: "" # TKE 集群 ID (cls-xxx)
secretID: "" # 腾讯云子账号的 SecretID
secretKey: "" # 腾讯云子账号的 SecretKey
```

配置完成后点【完成】即可安装到集群。

如果您使用 GitOps 管理应用，不想通过 TKE 应用市场安装，也可以从 [GitHub](https://github.com/tkestack/charts/tree/main/incubator/tke-extend-network-controller) 下载 chart 然后通过 helm 安装。
