# 使用 tke-autoscaling-placeholder 实现秒级弹性伸缩

## 操作场景

如 TKE 集群配置了节点池并启用弹性伸缩，则在节点资源不够时可以触发节点的自动扩容（自动购买机器并加入集群），该扩容流程需要一定的时间才能完成，在一些流量突高的场景，该扩容速度可能会显得太慢，影响业务正常运行。而 `tke-autoscaling-placeholder` 可以用于在 TKE 上实现秒级伸缩，应对流量突高场景。本文将介绍如何使用 `tke-autoscaling-placeholder` 实现秒级弹性伸缩。  

## 实现原理

`tke-autoscaling-placeholder` 利用低优先级的 Pod（带有 request 的 pause 容器，实际资源消耗较低）对资源进行提前占位，为可能出现流量突增的高优先级业务预留一部分资源作为缓冲。当需要扩容 Pod 时，高优先级的 Pod 可以快速抢占低优先级 Pod 的资源进行调度，这将导致低优先级的 `tke-autoscaling-placeholder` 的 Pod 进入 Pending 状态，如果配置了节点池并启用弹性伸缩，将会触发节点的扩容。通过这种资源缓冲机制，即使节点扩容速度较慢，也能确保部分 Pod 能够迅速扩容并调度，实现秒级伸缩。根据实际需求，可以调整 `tke-autoscaling-placeholder` 的 request 或副本数，以便调整预留的缓冲资源量。

## 使用限制

使用 `tke-autoscaling-placeholder` 应用，集群版本需要在1.18以上。  

## 操作步骤

### 安装 tke-autoscaling-placeholder

1. 登录容器服务控制台，选择左侧导航栏中的 [应用市场](https://console.cloud.tencent.com/tke2/market)**。**
2. 在**应用市场**页面，输入关键词 **tke-autoscaling-placeholder** 进行搜索，找到该应用。如下图所示：
   ![](https://write-document-release-1258344699.cos.ap-guangzhou.tencentcos.cn/100025015611/773e9db5724b11ee96775254009b3d14.png?q-sign-algorithm=sha1&q-ak=AKID6CC7TgSCCJkhExRyWEXhdsOsPjKcjkhtP341MJoOdhczRrVff1i5Fdg_UNXaYT2a&q-sign-time=1712903586;1712907186&q-key-time=1712903586;1712907186&q-header-list=&q-url-param-list=&q-signature=938ed958f0ba79b17f0aa1c6678a6a00a2f248df&x-cos-security-token=W3MdAaSfHfKqnaGh3VQvZwK3cjkodfsa08071c370db1b0c9c772d9112e96afcd6FObJ56STxBjA227oWj8cx2-5MorjKJZboeMWANU6oj6rB1DcIk3kSGvINvmIQH3xlV5O-9KCTiWAdioeASDJh2reXZQdTh93-37Z_VYnZ9ftQjnI4yHfoq2EprulticEvP0mlF-CwFyf47Te3EUkZpb769sHNptK69qX2oIC_pp7sqxU2so61DcDn0HoSCJodNR4VTprgfN8VBiOHOTY4EzXpdBoyzqLVVLpDVrUeG32T7T4zQa4oT4vL7rWgXM9kcLXZu_XWXEwj-k9BBXZcFZCr2Wgm5Ikl2od1wGimMKsIwK2ya3CTpnbdpgv2qk)
3. 单击应用，在应用详情中，单击基本信息模块中的**创建应用**。  
4. 在**创建应用**页面，按需配置并创建应用。如下图所示：
![](https://write-document-release-1258344699.cos.ap-guangzhou.tencentcos.cn/100022348635/a5fe0aefa5c911eda61e525400463ef7.png?q-sign-algorithm=sha1&q-ak=AKIDc1yjglqsQKIgiBrYKLeuOmqSwFifspF045kVlXwTsLx53kntZXmElXg18KNtBzB2&q-sign-time=1712903586;1712907186&q-key-time=1712903586;1712907186&q-header-list=&q-url-param-list=&q-signature=35b4aaa3192808c3ccc891d7af8c06165c49824c&x-cos-security-token=W3MdAaSfHfKqnaGh3VQvZwK3cjkodfsaaf115838b591fe67ae627a1da492e03e6FObJ56STxBjA227oWj8cx2-5MorjKJZboeMWANU6oj6rB1DcIk3kSGvINvmIQH3xlV5O-9KCTiWAdioeASDJh2reXZQdTh93-37Z_VYnZ9ftQjnI4yHfoq2EprulticEvP0mlF-CwFyf47Te3EUkZpb769sHNptK69qX2oIC_pp7sqxU2so61DcDn0HoSCJodNR4VTprgfN8VBiOHOTY4EzXpdBoyzqLVVLpDVrUeG32T7T4zQa4oT4vL7rWgXM9kcLXZu_XWXEwj-k9BBXZX-b69xz4cEx2CZqKBPx7Up-aayFg82pbSxUBl0IHI0W)
配置说明如下：
  - **名称**：输入应用名称。最长63个字符，只能包含小写字母、数字及分隔符“-”，且必须以小写字母开头，数字或小写字母结尾。  
  - **地域**：选择需要部署的所在地域。  
  - **集群类型**：选择**标准集群**。  
  - **集群**：选择需要部署的集群 ID。  
  - **Namespace**：选择需要部署的 namespace。  
  - **Chart 版本**：选择需要部署的 Chart 版本。
  - **参数**：配置参数中最重要的是 `replicaCount` 与 `resources.request`，分别表示 `tke-autoscaling-placeholder` 的副本数与每个副本占位的资源大小，它们共同决定缓冲资源的大小，可以根据流量突高需要的额外资源量来估算进行设置。`tke-autoscaling-placeholder`  完整参数配置说明请参考如下表格：

<table>
<tr>
<td rowspan="1" colSpan="1" >参数名称</td>

<td rowspan="1" colSpan="1" >描述</td>

<td rowspan="1" colSpan="1" >默认值</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >replicaCount</td>

<td rowspan="1" colSpan="1" >placeholder 的副本数</td>

<td rowspan="1" colSpan="1" >10</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >image</td>

<td rowspan="1" colSpan="1" >placeholder 的镜像地址</td>

<td rowspan="1" colSpan="1" >ccr.ccs.tencentyun.com/tke-market/pause:latest</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >resources.requests.cpu</td>

<td rowspan="1" colSpan="1" >单个 placeholder 副本占位的 CPU 资源大小</td>

<td rowspan="1" colSpan="1" >300m</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >resources.requests.memory</td>

<td rowspan="1" colSpan="1" >单个 placeholder 副本占位的内存大小</td>

<td rowspan="1" colSpan="1" >600Mi</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >lowPriorityClass.create</td>

<td rowspan="1" colSpan="1" >是否创建低优先级的 PriorityClass (用于被 placeholder 引用)</td>

<td rowspan="1" colSpan="1" >true</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >lowPriorityClass.name</td>

<td rowspan="1" colSpan="1" >低优先级的 PriorityClass 的名称</td>

<td rowspan="1" colSpan="1" >low-priority</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >nodeSelector</td>

<td rowspan="1" colSpan="1" >指定 placeholder 被调度到带有特定 label 的节点</td>

<td rowspan="1" colSpan="1" >{}</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >tolerations</td>

<td rowspan="1" colSpan="1" >指定 placeholder 要容忍的污点</td>

<td rowspan="1" colSpan="1" >[]</td>
</tr>

<tr>
<td rowspan="1" colSpan="1" >affinity</td>

<td rowspan="1" colSpan="1" >指定 placeholder 的亲和性配置</td>

<td rowspan="1" colSpan="1" >{}</td>
</tr>
</table>

5. 单击**创建**，部署 tke-autoscaling-placeholder 应用。  
6. 执行如下命令，查看进行资源占位的 Pod 是否启动成功。

   ``` bash
   kubectl get pod -n default
   ```

   示例如下：

   ``` plaintext
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

### 部署高优先级 Pod

`tke-autoscaling-placeholder` 默认优先级较低，其中业务 Pod 可以指定一个高优先的 PriorityClass，方便抢占资源实现快速扩容。如果还未创建 PriorityClass，您可以参考如下示例进行创建：
``` yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
description: "high priority class"
```

在业务 Pod 中指定 `priorityClassName` 为高优先的 PriorityClass。示例如下：
``` yaml
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
      priorityClassName: high-priority # 这里指定高优先的 PriorityClass
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: 400m
            memory: 800Mi
```

当集群节点资源不够时，扩容出来的高优先级业务 Pod 就可以将低优先级的 `tke-autoscaling-placeholder` 的 Pod 资源抢占过来并调度上，此时 `tke-autoscaling-placeholder`  的 Pod 状态将变成 Pending。示例如下：
``` bash
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

如果配置了节点池弹性伸缩，则将触发节点的扩容，虽然节点速度慢，但由于缓冲资源已分配到业务 Pod，业务能够快速得到扩容，因此不会影响业务的正常运行。  

## 总结

本文介绍了用于实现秒级伸缩的工具  `tke-autoscaling-placeholder`，巧妙的利用了 Pod 优先级与抢占的特点，提前部署一些用于占位资源的低优先级“空 Pod” 作为缓冲资源填充，在流量突高并且集群资源不够的情况下抢占这些低优先级的“空 Pod” 的资源，同时触发节点扩容，实现在资源紧张的情况下也能做到秒级伸缩，不影响业务正常运行。  

## 相关文档

- [Pod 优先级与抢占](https://kubernetes.io/zh/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [创建节点池](https://cloud.tencent.com/document/product/457/43735)
