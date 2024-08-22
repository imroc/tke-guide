# Pod 绑 EIP

腾讯云容器服务的 Pod 如果调度到超级节点，是支持给 Pod 绑 EIP 的，本文介绍如何操作。

## EIP 授权

集群中的 ipamd 组件通过调用相关云 API 为 Pod 分配 EIP，需要 ipamd 有相关的权限，具体授权方法：
1. 在 [角色列表](https://console.cloud.tencent.com/cam/role) 页面找到 `IPAMDofTKE_QCSRole` 这个角色，点进去。
2. 点击关联策略：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100010.png)
3. 选择 `QcloudAccessForIPAMDRoleInQcloudAllocateEIP` 进行关联：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100056.png)

## 超级节点与非超级节点

TKE 的节点有超级节点和非超级节点之分，在为 Pod 绑 EIP 时，Pod 调度到超级节点和非超级节点时，配置方式是不一样的。

## 如何为 Pod 绑 EIP ?

为 Pod 加 `eip-attributes` 注解以声明需要绑定 EIP，超级节点与非超级节点的写法不同，但值都为 JSON 格式，填写创建 EIP 接口的相关的参数，详细参数列表可参考 [这里](https://cloud.tencent.com/document/api/215/16699#2.-.E8.BE.93.E5.85.A5.E5.8F.82.E6.95.B0) 。

YAML 写法示例：

<Tabs>
  <TabItem value="eip-supernode" label="超级节点写法">
    <FileBlock file="nginx-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="eip-vpc-cni" label="非超级节点写法">
    <FileBlock file="nginx-eip-vpc-cni.yaml" showLineNumbers />
  </TabItem>
</Tabs>

> 如果 Pod 在非超级节点，要求 Pod 使用 `VPC-CNI` 网络模式（更多参考 [这里的说明](https://cloud.tencent.com/document/product/457/64886)）。

## 如何保留 EIP ?

如果希望 Pod 重建后能复用重建之前的 EIP，需要在创建集群的时候启用 `固定 Pod IP` 并设置 `IP 回收策略`:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711102603.png)

Pod 被删除后 EIP 会被释放，EIP 在未绑定状态下会产生费用（在和Pod绑定时EIP不计费），这个 `IP 回收策略` 配置的是 EIP 回收的时间阈值，EIP 在未绑定状态超过该时间阈值就会被销毁，避免因某些问题导致 EIP 长时间处于未绑定状态而产生更多额外费用。

那如何声明让 Pod 保留 EIP 呢？

首先需要使用 `StatefulSet` 部署或其它第三方有状态工作负载（如 `OpenKruise` 的 `Advanced StatefulSet`、`OpenKruiseGame` 的 `GameServerSet`）。

> 为什么要用 `StatefulSet` 才可以？因为 `StatefulSet` 的 Pod 是有状态的，Pod 名称有序号，可通过 Pod 名称与 EIP 的关联关系实现固定 EIP，无状态的 Pod 就无法实现了。

其次如果在 Pod 在超级节点，加上 `eks.tke.cloud.tencent.com/eip-claim-delete-policy: "Never"` 这个注解即可实现:

<FileBlock file="nginx-retain-eip.yaml" showLineNumbers />

如果 Pod 不在超级节点，则使用 `tke.cloud.tencent.com/eip-claim-delete-policy: "Never"`：

<FileBlock file="nginx-eip-vpc-cni-retain-ip.yaml" showLineNumbers />

## 如何在容器内获取自身公网 IP ？

可以利用 K8S 的 [Downward API](https://kubernetes.io/zh/docs/tasks/inject-data-application/environment-variable-expose-pod-information/) ，将 Pod 上的一些字段注入到环境变量或挂载到文件，Pod 的 EIP 信息最终会写到 Pod 的 `tke.cloud.tencent.com/eip-public-ip` 这个 annotation 上，但不会 Pod 创建时就写上，是在启动过程写上去的，所以如果注入到环境变量最终会为空，挂载到文件就没问题，以下是使用方法:

<FileBlock file="nginx-eip-mount-podinfo.yaml" showLineNumbers />

容器内进程启动时可以读取 `/etc/podinfo/eip` 中的内容来获取 EIP。

## 参考资料

* [非超级节点下 Pod 绑 EIP 官方文档: Pod 直接绑定弹性公网 IP 使用说明](https://cloud.tencent.com/document/product/457/64886)
* [超级节点下 Pod 绑 EIP 相关注解](https://cloud.tencent.com/document/product/457/44173#.E7.BB.91.E5.AE.9A-eip)
