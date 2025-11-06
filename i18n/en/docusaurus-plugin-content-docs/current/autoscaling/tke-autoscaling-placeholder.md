---
sidebar_position: 2
---

# Achieving Second-level Elastic Scaling with tke-autoscaling-placeholder

## Operation Scenario

If a TKE cluster is configured with node pools and elastic scaling is enabled, automatic node expansion can be triggered when node resources are insufficient (automatically purchasing machines and joining the cluster). This expansion process requires some time to complete. In scenarios with sudden traffic spikes, this expansion speed may appear too slow, affecting normal business operations. `tke-autoscaling-placeholder` can be used on TKE to achieve second-level scaling to handle sudden traffic spike scenarios. This article describes how to use `tke-autoscaling-placeholder` to achieve second-level elastic scaling.

## Implementation Principle

`tke-autoscaling-placeholder` uses low-priority Pods (pause containers with requests, actual resource consumption is low) to pre-allocate resources, reserving a portion of resources as a buffer for potentially traffic-spiking high-priority businesses. When Pod scaling is needed, high-priority Pods can quickly preempt resources from low-priority Pods for scheduling, which will cause low-priority `tke-autoscaling-placeholder` Pods to enter Pending state. If node pools are configured and elastic scaling is enabled, node expansion will be triggered. Through this resource buffering mechanism, even if node expansion is slow, it ensures that some Pods can be quickly scaled and scheduled, achieving second-level scaling. According to actual needs, you can adjust the request or replica count of `tke-autoscaling-placeholder` to adjust the reserved buffer resource amount.

## Usage Limitations

Using the `tke-autoscaling-placeholder` application requires cluster version 1.18 or above.

## Operation Steps

### Installing tke-autoscaling-placeholder

1. Log in to the container service console and select [Application Market](https://console.cloud.tencent.com/tke2/market) in the left navigation bar.
2. On the **Application Market** page, enter the keyword **tke-autoscaling-placeholder** to search and find the application. As shown below:
   ![](https://write-document-release-1258344699.cos.ap-guangzhou.tencentcos.cn/100025015611/773e9db5724b11ee96775254009b3d14.png?q-sign-algorithm=sha1&q-ak=AKID6CC7TgSCCJkhExRyWEXhdsOsPjKcjkhtP341MJoOdhczRrVff1i5Fdg_UNXaYT2a&q-sign-time=1712903586;1712907186&q-key-time=1712903586;1712907186&q-header-list=&q-url-param-list=&q-signature=938ed958f0ba79b17f0aa1c6678a6a00a2f248df&x-cos-security-token=W3MdAaSfHfKqnaGh3VQvZwK3cjkodfsa08071c370db1b0c9c772d9112e96afcd6FObJ56STxBjA227oWj8cx2-5MorjKJZboeMWANU6oj6rB1DcIk3kSGvINvmIQH3xlV5O-9KCTiWAdioeASDJh2reXZQdTh93-37Z_VYnZ9ftQjnI4yHfoq2EprulticEvP0mlF-CwFyf47Te3EUkZpb769sHNptK69qX2oIC_pp7sqxU2so61DcDn0HoSCJodNR4VTprgfN8VBiOHOTY4EzXpdBoyzqLVVLpDVrUeG32T7T4zQa4oT4vL7rWgXM9kcLXZu_XWXEwj-k9BBXZcFZCr2Wgm5Ikl2od1wGimMKsIwK2ya3CTpnbdpgv2qk)
3. Click the application, and in the application details, click **Create Application** in the basic information module.
4. On the **Create Application** page, configure and create the application as needed. As shown below:
![](https://write-document-release-1258344699.cos.ap-guangzhou.tencentcos.cn/100022348635/a5fe0aefa5c911eda61e525400463ef7.png?q-sign-algorithm=sha1&q-ak=AKIDc1yjglqsQKIgiBrYKLeuOmqSwFifspF045kVlXwTsLx53kntZXmElXg18KNtBzB2&q-sign-time=1712903586;1712907186&q-key-time=1712903586;1712907186&q-header-list=&q-url-param-list=&q-signature=35b4aaa3192808c3ccc891d7af8c06165c49824c&x-cos-security-token=W3MdAaSfHfKqnaGh3VQvZwK3cjkodfsaaf115838b591fe67ae627a1da492e03e6FObJ56STxBjA227oWj8cx2-5MorjKJZboeMWANU6oj6rB1DcIk3kSGvINvmIQH3xlV5O-9KCTiWAdioeASDJh2reXZQdTh93-37Z_VYnZ9ftQjnI4yHfoq2EprulticEvP0mlF-CwFyf47Te3EUkZpb769sHNptK69qX2oIC_pp7sqxU2so61DcDn0HoSCJodNR4VTprgfN8VBiOHOTY4EzXpdBoyzqLVVLpDVrUeG32T7T4zQa4oT4vL7rWgXM9kcLXZu_XWXEwj-k9BBXZX-b69xz4cEx2CZqKBPx7Up-aayFg82pbSxUBl0IHI0W)
Configuration description:
  - **Name**: Enter application name. Maximum 63 characters, can only contain lowercase letters, numbers, and separator "-", and must start with lowercase letter, end with number or lowercase letter.
  - **Region**: Select deployment region.
  - **Cluster Type**: Select **Standard Cluster**.
  - **Cluster**: Select cluster ID to deploy.
  - **Namespace**: Select namespace to deploy.
  - **Chart Version**: Select chart version to deploy.
  - **Parameters**: The most important parameters in configuration are `replicaCount` and `resources.request`, representing the replica count of `tke-autoscaling-placeholder` and the resource size occupied by each replica. Together they determine the buffer resource size, which can be estimated and set based on the additional resources needed for traffic spikes. Complete parameter configuration description for `tke-autoscaling-placeholder`:

<table>
<tr>
<td rowspan="1" colSpan="1" >Parameter Name</td>

<td rowspan="1" colSpan="1" >Description</td>

<td rowspan="1" colSpan="1" >Default Value</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >replicaCount</td>

<td rowspan="1" colSpan="1" >placeholder replica count</td>

<td rowspan="1" colSpan="1" >10</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >image</td>

<td rowspan="1" colSpan="1" >placeholder image address</td>

<td rowspan="1" colSpan="1" >ccr.ccs.tencentyun.com/tke-market/pause:latest</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >resources.requests.cpu</td>

<td rowspan="1" colSpan="1" >CPU resource size occupied by single placeholder replica</td>

<td rowspan="1" colSpan="1" >300m</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >resources.requests.memory</td>

<td rowspan="1" colSpan="1" >Memory size occupied by single placeholder replica</td>

<td rowspan="1" colSpan="1" >600Mi</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >lowPriorityClass.create</td>

<td rowspan="1" colSpan="1" >Whether to create low-priority PriorityClass (referenced by placeholder)</td>

<td rowspan="1" colSpan="1" >true</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >lowPriorityClass.name</td>

<td rowspan="1" colSpan="1" >Low-priority PriorityClass name</td>

<td rowspan="1" colSpan="1" >low-priority</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >nodeSelector</td>

<td rowspan="1" colSpan="1" >Specify placeholder to be scheduled to nodes with specific labels</td>

<td rowspan="1" colSpan="1" >{}</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >tolerations</td>

<td rowspan="1" colSpan="1" >Specify taints placeholder should tolerate</td>

<td rowspan="1" colSpan="1" >[]</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >affinity</td>

<td rowspan="1" colSpan="1" >Specify placeholder affinity configuration</td>

<td rowspan="1" colSpan="1" >{}</td>
</tr>
</table>

5. Click **Create** to deploy the tke-autoscaling-placeholder application.
6. Execute the following command to check if resource-occupying Pods started successfully.

   ```bash
   kubectl get pod -n default
   ```

   Example:

   ```plaintext
   $ kubectl get pod -n default
   tke-autoscaling-placeholder-b58fd9d5d-2p6ww   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-55jw7   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-6rq9r   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-7c95t   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-bfg8r   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-cfqt6   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-gmfmr   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-grwlh   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-ph7vl   1/1     Running   0          8s
   tke-autoscaling-placeholder-b58fd9d5d-xmrmv   1/1     Running   0          8s
   ```

### Deploying High-Priority Pods

`tke-autoscaling-placeholder` has low priority by default. Business Pods can specify a high-priority PriorityClass to facilitate resource preemption for rapid scaling. If PriorityClass hasn't been created, you can refer to the following example:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "high priority class"
```

Specify `priorityClassName` as high-priority PriorityClass in business Pods. Example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 8
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      priorityClassName: high-priority # Specify high-priority PriorityClass here
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: 400m
            memory: 800Mi
```

When cluster node resources are insufficient, scaled high-priority business Pods can preempt resources from low-priority `tke-autoscaling-placeholder` Pods and be scheduled. At this point, `tke-autoscaling-placeholder` Pod status will become Pending. Example:

```bash
$ kubectl get pod -n default
NAME                                          READY   STATUS    RESTARTS   AGE
nginx-bf79bbc8b-5kxcw                         1/1     Running   0          23s
nginx-bf79bbc8b-5xhbx                         1/1     Running   0          23s
nginx-bf79bbc8b-bmzff                         1/1     Running   0          23s
nginx-bf79bbc8b-l2vht                         1/1     Running   0          23s
nginx-bf79bbc8b-q84jq                         1/1     Running   0          23s
nginx-bf79bbc8b-tq2sx                         1/1     Running   0          23s
nginx-bf79bbc8b-tqgxg                         1/1     Running   0          23s
nginx-bf79bbc8b-wz5w5                         1/1     Running   0          23s
tke-autoscaling-placeholder-b58fd9d5d-255r8   0/1     Pending   0          23s
tke-autoscaling-placeholder-b58fd9d5d-4vt8r   0/1     Pending   0          23s
tke-autoscaling-placeholder-b58fd9d5d-55jw7   1/1     Running   0          94m
tke-autoscaling-placeholder-b58fd9d5d-7c95t   1/1     Running   0          94m
tke-autoscaling-placeholder-b58fd9d5d-ph7vl   1/1     Running   0          94m
tke-autoscaling-placeholder-b58fd9d5d-qjrsx   0/1     Pending   0          23s
tke-autoscaling-placeholder-b58fd9d5d-t5qdm   0/1     Pending   0          23s
tke-autoscaling-placeholder-b58fd9d5d-tgvmw   0/1     Pending   0          23s
tke-autoscaling-placeholder-b58fd9d5d-xmrmv   1/1     Running   0          94m
tke-autoscaling-placeholder-b58fd9d5d-zxtwp   0/1     Pending   0          23s
```

If node pool elastic scaling is configured, node expansion will be triggered. Although node speed is slow, since buffer resources have been allocated to business Pods, businesses can quickly scale, thus not affecting normal business operations.

## Summary

This article introduced the tool `tke-autoscaling-placeholder` for achieving second-level scaling, cleverly using Pod priority and preemption characteristics to pre-deploy some low-priority "empty Pods" for resource allocation as buffer resource filling. In scenarios with sudden traffic spikes and insufficient cluster resources, preempt resources from these low-priority "empty Pods" while triggering node expansion, achieving second-level scaling even in resource-constrained situations without affecting normal business operations.

## Related Documentation

- [Pod Priority and Preemption](https://kubernetes.io/zh/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [Creating Node Pools](https://cloud.tencent.com/document/product/457/43735)