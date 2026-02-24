# 使用 Cilium 增强可观测性

:::info[注意]

本文正在起草中，请等完善后再参考。

:::

## 启用 Hubble Ralay

Hubble 包括 Hubble Server 和 Hubble Relay，其中 Hubble Server 已内置到每个节点的 cilium-agent 中并默认开启，Hubble Relay 是一个需要单独部署的组件，用于聚合集群所有节点 Hubble Server 的数据，提供统一的 API 入口。

使用下面的命令启用 Hubble Relay：

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
   --set hubble.relay.enabled=true
```

通过 `cilium status` 可验证 hubble 开启并正常运行：

```bash showLineNumbers
$ cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
               # highlight-next-line
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
                       # highlight-next-line
Deployment             hubble-relay             Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       # highlight-next-line
                       hubble-relay             Running: 1
Cluster Pods:          4/4 managed by Cilium
Helm chart version:    1.19.1
Image versions         cilium             quay.tencentcloudcr.com/cilium/cilium:v1.19.1@sha256:5649db451c88d928ea585514746d50d91e6210801b300c897283ea319d68de15: 3
                       cilium-envoy       quay.tencentcloudcr.com/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222@sha256:ca76eb4e9812d114c7f43215a742c00b8bf41200992af0d21b5561d46156fd15: 3
                       cilium-operator    quay.tencentcloudcr.com/cilium/operator-generic:v1.19.1@sha256:b5a0138e1a38e4437c5215257ff4e35373619501f4877dbaf92c89ecfad81797: 2
                       hubble-relay       quay.tencentcloudcr.com/cilium/hubble-relay:v1.19.1@sha256:e53e00c47fe4ffb9c086bad0c1c77f23cb968be4385881160683d9e15aa34dc3: 1
```

## 安装 Hubble 客户端

Hubble 客户端用于与 Hubble Ralay 提供的接口进行交互，参考 [Install the Hubble Client](https://docs.cilium.io/en/stable/observability/hubble/setup/#install-the-hubble-client) 将 `hubble` 二进制 (Hubble 客户端) 安装到本机。

安装完成后，验证下 Hubble 客户端可正常访问 Hubble API：

```bash
$ hubble status -P
Healthcheck (via 127.0.0.1:4245): Ok
Current/Max Flows: 12,285/12,285 (100.00%)
Flows/s: 26.42
Connected Nodes: 3/3
```

## 启用 Hubble UI

Hubble UI 可用于可视化查看集群中的服务拓扑。

使用下面的命令启用 Hubble UI：

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.enabled=true \
   --set hubble.ui.enabled=true \
   --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
   --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui
```

确认 Hubble UI 的 Pod 正常运行：

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/name=hubble-ui
NAME                         READY   STATUS    RESTARTS   AGE
hubble-ui-5dd5877df5-8c69k   2/2     Running   0          5m41s

```

然后就可以执行 `cilium hubble ui` 自动打开浏览器查看集群的服务拓扑了。

```bash
$ cilium hubble ui
ℹ  Opening "http://localhost:12000" in your browser...
```

更多请参考 [Network Observability with Hubble / Service Map & Hubble UI](https://docs.cilium.io/en/stable/observability/hubble/hubble-ui/)。

## 网络日志流检索分析

cilium 支持将网络日志流导出到文件，可结合腾讯云 CLS 日志服务采集网络日志流日志文件并进行检索分析，在排障分析时很有用，下面介绍如何操作。

### 将网络日志流导出到文件

启用 hubble 日志动态导出并配置日志规则：

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.enabled=true \
   --set hubble.export.dynamic.enabled=true \
   --set hubble.export.dynamic.config.content[0].name=all \
   --set hubble.export.dynamic.config.content[0].filePath=/var/run/cilium/hubble/events-all.log \
   --set hubble.export.dynamic.config.content[0].excludeFilters[0].source_ip="169.254.0.71" \
   --set hubble.export.dynamic.config.content[0].excludeFilters[1].destination_ip="169.254.0.71"
```

日志文件示例：

```json
{"flow":{"time":"2026-02-24T08:47:58.042012383Z","uuid":"c938628b-0c3a-4440-9ecd-3e3ca00d3a16","emitter":{"name":"Hubble","version":"1.19.1+gd0d0c879"},"verdict":"FORWARDED","ethernet":{"source":"9a:4b:92:54:a9:62","destination":"72:59:04:fd:68:13"},"IP":{"source":"169.254.128.9","destination":"10.20.0.4","ipVersion":"IPv4"},"l4":{"TCP":{"source_port":60002,"destination_port":57706,"flags":{"PSH":true,"ACK":true}}},"source":{"identity":16777217,"labels":["reserved:kube-apiserver","reserved:world"]},"destination":{"ID":3106,"identity":20252,"cluster_name":"default","namespace":"kube-system","labels":["k8s:app=cbs-csi-controller","k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=kube-system","k8s:io.cilium.k8s.policy.cluster=default","k8s:io.cilium.k8s.policy.serviceaccount=cbs-csi-controller-sa","k8s:io.kubernetes.pod.namespace=kube-system","k8s:metrics=cbs-csi-controller"],"pod_name":"csi-cbs-controller-7788964bc-lsfw5","workloads":[{"name":"csi-cbs-controller","kind":"Deployment"}]},"Type":"L3_L4","node_name":"10.10.21.166","node_labels":["beta.kubernetes.io/arch=amd64","beta.kubernetes.io/instance-type=S5.MEDIUM4","beta.kubernetes.io/os=linux","cloud.tencent.com/auto-scaling-group-id=asg-q9zxcooe","cloud.tencent.com/node-instance-id=ins-h857yc7d","failure-domain.beta.kubernetes.io/region=cd","failure-domain.beta.kubernetes.io/zone=160001","kubernetes.io/arch=amd64","kubernetes.io/hostname=10.10.21.166","kubernetes.io/os=linux","node.kubernetes.io/instance-type=S5.MEDIUM4","node.tke.cloud.tencent.com/accelerator-type=cpu","node.tke.cloud.tencent.com/cpu=2","node.tke.cloud.tencent.com/memory=4","os=tencentos4","tke.cloud.tencent.com/cbs-mountable=true","tke.cloud.tencent.com/nodepool-id=np-p8uyib3x","tke.cloud.tencent.com/route-eni-subnet-ids=subnet-fg9qdb1f","topology.com.tencent.cloud.csi.cbs/zone=ap-chengdu-1","topology.kubernetes.io/region=cd","topology.kubernetes.io/zone=160001"],"reply":true,"event_type":{"type":4},"traffic_direction":"EGRESS","trace_observation_point":"TO_ENDPOINT","trace_reason":"REPLY","is_reply":true,"interface":{"index":6,"name":"eni07eaad73233"},"Summary":"TCP Flags: ACK, PSH"},"node_name":"10.10.21.166","time":"2026-02-24T08:47:58.042012383Z"}
{"flow":{"time":"2026-02-24T08:43:39.070396373Z","uuid":"d54c1e24-8985-4710-b275-b19b15aed350","emitter":{"name":"Hubble","version":"1.19.1+gd0d0c879"},"verdict":"FORWARDED","ethernet":{"source":"52:54:00:c8:b1:e7","destination":"fe:ee:b0:19:ec:8f"},"IP":{"source":"10.10.21.241","destination":"9.134.108.44","ipVersion":"IPv4"},"l4":{"TCP":{"source_port":58012,"destination_port":9922,"flags":{"SYN":true}}},"source":{"identity":1,"labels":["reserved:host","reserved:remote-node"]},"destination":{"identity":2,"labels":["reserved:world"]},"Type":"L3_L4","node_name":"10.10.21.241","node_labels":["beta.kubernetes.io/arch=amd64","beta.kubernetes.io/instance-type=S5.MEDIUM4","beta.kubernetes.io/os=linux","cloud.tencent.com/auto-scaling-group-id=asg-q9zxcooe","cloud.tencent.com/node-instance-id=ins-ivb2d91n","failure-domain.beta.kubernetes.io/region=cd","failure-domain.beta.kubernetes.io/zone=160001","kubernetes.io/arch=amd64","kubernetes.io/hostname=10.10.21.241","kubernetes.io/os=linux","node.kubernetes.io/instance-type=S5.MEDIUM4","node.tke.cloud.tencent.com/accelerator-type=cpu","node.tke.cloud.tencent.com/cpu=2","node.tke.cloud.tencent.com/memory=4","os=tencentos4","tke.cloud.tencent.com/cbs-mountable=true","tke.cloud.tencent.com/nodepool-id=np-p8uyib3x","topology.com.tencent.cloud.csi.cbs/zone=ap-chengdu-1","topology.kubernetes.io/region=cd","topology.kubernetes.io/zone=160001"],"event_type":{"type":4,"sub_type":11},"traffic_direction":"EGRESS","trace_observation_point":"TO_NETWORK","trace_reason":"NEW","is_reply":false,"interface":{"index":2,"name":"eth0"},"Summary":"TCP Flags: SYN"},"node_name":"10.10.21.241","time":"2026-02-24T08:43:39.070396373Z"}
{"flow":{"time":"2026-02-24T08:43:37.094908659Z","uuid":"8ee10b71-95e4-4ddd-835e-5010599212ba","emitter":{"name":"Hubble","version":"1.19.1+gd0d0c879"},"verdict":"FORWARDED","ethernet":{"source":"52:54:00:c8:b1:e7","destination":"fe:ee:b0:19:ec:8f"},"IP":{"source":"10.10.21.241","destination":"183.47.117.75","ipVersion":"IPv4"},"l4":{"TCP":{"source_port":52662,"destination_port":9988,"flags":{"PSH":true,"ACK":true}}},"source":{"identity":1,"labels":["reserved:host","reserved:remote-node"]},"destination":{"identity":2,"labels":["reserved:world"]},"Type":"L3_L4","node_name":"10.10.21.241","node_labels":["beta.kubernetes.io/arch=amd64","beta.kubernetes.io/instance-type=S5.MEDIUM4","beta.kubernetes.io/os=linux","cloud.tencent.com/auto-scaling-group-id=asg-q9zxcooe","cloud.tencent.com/node-instance-id=ins-ivb2d91n","failure-domain.beta.kubernetes.io/region=cd","failure-domain.beta.kubernetes.io/zone=160001","kubernetes.io/arch=amd64","kubernetes.io/hostname=10.10.21.241","kubernetes.io/os=linux","node.kubernetes.io/instance-type=S5.MEDIUM4","node.tke.cloud.tencent.com/accelerator-type=cpu","node.tke.cloud.tencent.com/cpu=2","node.tke.cloud.tencent.com/memory=4","os=tencentos4","tke.cloud.tencent.com/cbs-mountable=true","tke.cloud.tencent.com/nodepool-id=np-p8uyib3x","topology.com.tencent.cloud.csi.cbs/zone=ap-chengdu-1","topology.kubernetes.io/region=cd","topology.kubernetes.io/zone=160001"],"event_type":{"type":4,"sub_type":11},"traffic_direction":"EGRESS","trace_observation_point":"TO_NETWORK","trace_reason":"ESTABLISHED","is_reply":false,"interface":{"index":2,"name":"eth0"},"Summary":"TCP Flags: ACK, PSH"},"node_name":"10.10.21.241","time":"2026-02-24T08:43:37.094908659Z"}
```

### 将网络日志流投递到 CLS

配置 TKE 日志采集，将所有 cilium-agent 中的日志流文件采集到 CLS。

#### 通过控制台配置

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F02%2F24%2F20260224170002.png)

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F02%2F24%2F20260224170258.png)

#### 通过 YAML 配置

TKE 使用 LogConfig 这个 CRD 配置日志采集规则，参考以下 YAML 进行配置（通过 `kubectl apply -f <your-logconfig-yaml-file>` 进行配置）：

```yaml
apiVersion: cls.cloud.tencent.com/v1
kind: LogConfig
metadata:
  name: cilium-network-flow
spec:
  clsDetail:
    extractRule:
      backtracking: "0"
      isGBK: "false"
      jsonStandard: "true"
      timeFormat: '%Y-%m-%dT%H:%M:%S.%f%z'
      timeKey: time
      unMatchUpload: "true"
      unMatchedKey: LogParseFailure
    indexs:
    - indexName: namespace
    - indexName: pod_name
    - indexName: container_name
    logFormat: default
    logType: json_log
    maxSplitPartitions: 0
    period: 30
    region: ap-chengdu # 替换成你的 CLS 所在地域，可用列表参考 https://cloud.tencent.com/document/product/215/106009
    storageType: ""
    topicId: bcaad2ed-2061-48bc-94b0-a70fb4acc732 # 替换成你的 CLS 主题 ID
  inputDetail:
    type: container_file
    containerFile:
      namespace: kube-system
      workload:
        kind: daemonset
        name: cilium
      container: cilium-agent
      filePaths:
      - file: '*.log'
        path: /var/run/cilium/hubble
      metadataContainer:
      - namespace
      - pod_name
      - pod_ip
      - pod_uid
      - container_id
      - container_name
      - image_name
      - cluster_id
      metadataLabels:
      - __NULL__
      nodeMetadataLabels:
      - __NULL__
```

### 配置自动索引

如果希望在 CLS 中方便的检索集群中的网络日志流，可以配置自动索引，将 cilium 生成的 json 日志的字段自动解析为索引，下面是配置方法。

找到对应的日志主题，在 CLS 控制台的**索引配置**启用索引的自动配置:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F02%2F24%2F20260224171517.png)
