# 使用 Cilium 增强可观测性

## 一键启用 Hubble

如果安装 cilium 时未启用 Hubble Relay 和 Hubble UI，可使用一键脚本快速启用：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- enable-hubble
```

脚本会执行 `helm upgrade --reuse-values --set hubble.relay.enabled=true --set hubble.ui.enabled=true`，并重启 cilium-agent / operator。下列章节是不使用脚本时手工启用各个组件的命令，按需查阅。

## 启用 Hubble Relay

Hubble 包括 Hubble Server 和 Hubble Relay，其中 Hubble Server 已内置到每个节点的 cilium-agent 中并默认开启，Hubble Relay 是一个需要单独部署的组件，用于聚合集群所有节点 Hubble Server 的数据，提供统一的 API 入口。

使用下面的命令启用 Hubble Relay：

```bash
helm upgrade cilium cilium/cilium --version 1.20.1 \
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
Helm chart version:    1.20.1
Image versions         cilium             quay.tencentcloudcr.com/cilium/cilium:v1.20.1@sha256:ae9ea21f7427fe24bc6ea7247eb552157a1b0a431744045d3f641545ca71d11b: 3
                       cilium-envoy       quay.tencentcloudcr.com/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7@sha256:75b8094c7127736a2ffd2dce3945e0931cb6df21b0372ff661940eca26730b91: 3
                       cilium-operator    quay.tencentcloudcr.com/cilium/operator-generic:v1.20.1@sha256:6c3885fc7b629099fdbe2a5c87869c86feb825fa18fae299eac0f61918d16ecf: 2
                       hubble-relay       quay.tencentcloudcr.com/cilium/hubble-relay:v1.20.1@sha256:59be0ae7d475ab9011a5e954618c0f27b5778b17140381425b308b55ba4917f4: 1
```

## 安装 Hubble 客户端

Hubble 客户端用于与 Hubble Relay 提供的接口进行交互，参考 [Install the Hubble Client](https://docs.cilium.io/en/stable/observability/hubble/setup/#install-the-hubble-client) 将 `hubble` 二进制 (Hubble 客户端) 安装到本机。

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
helm upgrade cilium cilium/cilium --version 1.20.1 \
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

## 审计网络日志流

如果希望对网络数据包进行审计（比如需要排障或进行安全审计），可参考 [使用 Cilium + CLS 实现网络流日志审计](flow-logs.md)。
