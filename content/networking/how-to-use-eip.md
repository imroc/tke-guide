# Pod 绑 EIP

腾讯云容器服务的 Pod 如果调度到超级节点，是支持给 Pod 绑 EIP 的，本文介绍如何操作。

## EIP 授权

集群中的 ipamd 组件通过调用相关云 API 为 Pod 分配 EIP，需要 ipamd 有相关的权限，具体授权方法：
1. 在 [角色列表](https://console.cloud.tencent.com/cam/role) 页面找到 `IPAMDofTKE_QCSRole` 这个角色，点进去。
2. 点击关联策略：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100010.png)
3. 选择 `QcloudAccessForIPAMDRoleInQcloudAllocateEIP` 进行关联：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100056.png)

## 确保 Pod 调度到超级节点

如果你用的 TKE 标准集群，集群中既包含超级节点，又包含非超级节点，那么一定要确保需要分配 EIP 的 Pod 调度到超级节点上。

示例：

<Tabs>
  <TabItem value="node-selector" label="nodeSelector示例">
    <FileBlock file="nginx-eklet.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="node-affinity" label="nodeAffinity示例">
    <FileBlock file="nginx-eklet-nodeaffinity.yaml" showLineNumbers />
  </TabItem>
</Tabs>

如果你用的 TKE Serverless 集群，只会有超级节点，无需额外的调度配置。

## 如何配置让 Pod 分配 EIP ?

配置 EIP 的核心是使用 `eks.tke.cloud.tencent.com/eip-attributes`  这个 Pod 注解，值为 JSON 格式，填写创建 EIP 接口的相关的参数，详细参数列表参考 [这里](https://cloud.tencent.com/document/api/215/16699#2.-.E8.BE.93.E5.85.A5.E5.8F.82.E6.95.B0) 。

下面给出一个简单示例，为每个 Pod 副本都绑定带宽上限 100Mbps，按流量计费的 EIP:

<FileBlock file="nginx-eip.yaml" showLineNumbers />

## 如何保留 EIP ?

如果希望 Pod 重建后能复用重建之前的 EIP，需要在创建集群的时候启用 `固定 Pod IP` 并设置 `IP 回收策略`:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711102603.png)

Pod 被删除后 EIP 会被释放，EIP 在未绑定状态下会产生费用（在和Pod绑定时EIP不计费），这个 `IP 回收策略` 配置的是 EIP 回收的时间阈值，EIP 在未绑定状态超过该时间阈值就会被销毁，避免因某些问题导致 EIP 长时间处于未绑定状态而产生更多额外费用。

那如何声明让 Pod 保留 EIP 呢？目前需要使用 `StatefulSet` 部署，且加上 `eks.tke.cloud.tencent.com/eip-claim-delete-policy: "Never"` 这个 annotation 来实现:

<FileBlock file="nginx-retain-eip.yaml" showLineNumbers />

> 为什么要用 `StatefulSet` 才可以？因为 `StatefulSet` 的 Pod 是有状态的，Pod 名称有序号，可通过 Pod 名称与 EIP 的关联关系实现固定 EIP，无状态的 Pod 就无法实现了。

## 如何在容器内获取自身公网 IP ？

可以利用 K8S 的 [Downward API](https://kubernetes.io/zh/docs/tasks/inject-data-application/environment-variable-expose-pod-information/) ，将 Pod 上的一些字段注入到环境变量或挂载到文件，Pod 的 EIP 信息最终会写到 Pod 的 `tke.cloud.tencent.com/eip-public-ip` 这个 annotation 上，但不会 Pod 创建时就写上，是在启动过程写上去的，所以如果注入到环境变量最终会为空，挂载到文件就没问题，以下是使用方法:

<FileBlock file="nginx-eip-mount-podinfo.yaml" showLineNumbers />

容器内进程启动时可以读取 `/etc/podinfo/annotations` 中的内容来获取 EIP。
