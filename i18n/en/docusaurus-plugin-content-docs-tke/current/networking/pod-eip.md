# Binding EIP to Pods

Tencent Cloud Container Service (TKE) supports binding EIP to Pods. Refer to the official documentation [Instructions for Directly Binding Elastic Public IP to Pods](https://cloud.tencent.com/document/product/457/64886).

This article describes how to bind EIP to Pods in the TKE environment in more accessible language.

## EIP Authorization

The ipamd component in the cluster allocates EIP to Pods by calling related cloud APIs and requires relevant permissions. Specific authorization method:
1. Find the `IPAMDofTKE_QCSRole` role on the [Role List](https://console.cloud.tencent.com/cam/role) page and click into it.
2. Click to associate policy:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100010.png)
3. Select `QcloudAccessForIPAMDRoleInQcloudAllocateEIP` for association:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711100056.png)

## Standard Clusters and Serverless Clusters

TKE clusters are divided into standard clusters and Serverless clusters. The methods for configuring EIP for Pods differ between these two cluster types.

> Serverless cluster capabilities have now been integrated into standard clusters. In the future, there will be no Serverless cluster type.

:::tip[Note]

1. If you are using a standard cluster, regardless of whether the Pod is on a super node, use the standard cluster syntax uniformly.
2. If your existing Serverless cluster needs to use EIP, pay attention to select the Serverless cluster version syntax when viewing YAML examples.

:::

## How to Bind EIP to Pods?

Add the `eip-attributes` annotation to the Pod to declare that it needs to bind an EIP. The value is in JSON format, filling in parameters related to the create EIP interface. For a detailed parameter list, refer to [here](https://cloud.tencent.com/document/api/215/16699#2.-.E8.BE.93.E5.85.A5.E5.8F.82.E6.95.B0).

YAML example:

<Tabs>
  <TabItem value="eip" label="Standard Cluster Syntax">

  :::info[Note]

  When using TKE standard clusters, Pods must use the `VPC-CNI` network mode (refer to [Prerequisites and Limitations](https://cloud.tencent.com/document/product/457/64886) here).

  :::

  <FileBlock file="eip/nginx-eip.yaml" showLineNumbers />

  </TabItem>

  <TabItem value="eip-serverless" label="Serverless Cluster Syntax">
    <FileBlock file="eip/nginx-eip-serverless.yaml" showLineNumbers />
  </TabItem>
</Tabs>


## How to Retain EIP?

If you want the Pod to reuse the EIP from before reconstruction after being rebuilt, you need to enable `Fixed Pod IP` and set `IP Reclaim Policy` when creating the cluster:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F11%2F20240711102603.png)

After the Pod is deleted, the EIP will be released. EIP generates charges when unbound (EIP is not charged when bound to Pods). This `IP Reclaim Policy` configures the time threshold for EIP reclamation. If the EIP remains unbound beyond this time threshold, it will be destroyed to avoid generating more additional costs due to certain issues causing the EIP to remain unbound for an extended period.

So how do you declare that a Pod should retain its EIP?

First, you need to use `StatefulSet` deployment or other third-party stateful workloads (such as `OpenKruise`'s `Advanced StatefulSet`, `OpenKruiseGame`'s `GameServerSet`).

:::tip[Note]

Why must stateful workloads be used? Because stateful workload Pod names have sequence numbers, fixed EIP can be achieved through the association between Pod names and EIPs. This cannot be achieved with stateless Pods.

:::

Below is a YAML example for retaining EIP:

<Tabs>
  <TabItem value="retain-eip" label="Standard Cluster Syntax">
    <FileBlock file="eip/nginx-retain-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="retain-eip-serverless" label="Serverless Cluster Syntax">
    <FileBlock file="eip/nginx-retain-eip-serverless.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## How to Obtain the Public IP within a Container?

You can use Kubernetes' [Downward API](https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/) to inject certain Pod fields into environment variables or mount them to files. The Pod's EIP information will eventually be written to the Pod's `tke.cloud.tencent.com/eip-public-ip` annotation, but not immediately upon Pod creation - it's written during the startup process. Therefore, if injected as an environment variable, it will ultimately be empty. Mounting to a file works fine. Here's how to use it:

<Tabs>
  <TabItem value="mount-eip" label="Standard Cluster Syntax">
    <FileBlock file="eip/nginx-eip-mount-podinfo.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="mount-eip-serverless" label="Serverless Cluster Syntax">
    <FileBlock file="eip/nginx-eip-mount-podinfo-serverless.yaml" showLineNumbers />
  </TabItem>
</Tabs>

When the container process starts, it can read the contents of `/etc/podinfo/eip` to obtain the EIP.

## FAQ: EIP Allocation Failure

Pod EIP allocation fails, the `tke.cloud.tencent.com/eip-public-ip` annotation is not automatically applied, and the Pod cannot obtain its own EIP through the Downward API.

Pod event error:

```txt
  Warning  FailedAllocateEIP  4m58s  tke-eni-ipamd      Failed to create eip: failed to allocate eip: [TencentCloudSDKError] Code=UnauthorizedOperation, Message="[request id:********-****-****-****-************]you are not authorized to perform operation (cvm:AllocateAddresses)\nresource (qcs::cvm:ap-guangzhou:uin\/1000******04:eip\/*) has no permission\n"., RequestId=********-****-****-****-************
```

The reason is that the `ipamd` component was not properly authorized. Follow the steps in [EIP Authorization](#eip-authorization) to operate.

## References

* [Instructions for Directly Binding Elastic Public IP to Pods](https://cloud.tencent.com/document/product/457/64886)
* [Annotations Related to Binding EIP to Pods on Super Nodes](https://cloud.tencent.com/document/product/457/44173#.E7.BB.91.E5.AE.9A-eip)
