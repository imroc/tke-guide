# 在 TKE 自建 Nginx Ingress Controller

## 概述

[Nginx Ingress Controller](https://github.com/kubernetes/ingress-nginx) 是基于高性能 NGINX 反向代理实现的 Kubernetes Ingress 控制器，也是最常用的开源 Ingress 实现。本文介绍如何在 TKE 环境中自建 Nginx Ingress Controller，主要使用 helm 进行安装，提供一些 `values.yaml` 配置指引，可根据自己需求合并下配置，文末也会提供合并后的 `values.yaml` 完整配置示例。

## 前提条件

* 创建了 TKE 集群。
* 安装了 [helm](https://helm.sh/)。
* 配置了 TKE 集群的 kubeconfig，且有权限操作 TKE 集群（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。

## 使用 helm 安装

添加 helm repo:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

查看默认配置:

```bash
helm show values ingress-nginx/ingress-nginx
```

Nginx Ingress 依赖的镜像在 `registry.k8s.io` 这个 registry 下，国内网络环境无法拉取，可替换为 docker hub 中的 mirror 镜像。

准备 `values.yaml`:

```yaml
controller: # 默认的镜像在境内无法拉取，可替换为 docker hub 上的 mirror 镜像
  image:
    registry: docker.io
    image: k8smirror/ingress-nginx-controller
  admissionWebhooks:
    patch:
      image:
        registry: docker.io
        image: k8smirror/ingress-nginx-kube-webhook-certgen
  defaultBackend:
    image:
      registry: docker.io
      image: k8smirror/defaultbackend-amd64
  opentelemetry:
    image:
      registry: docker.io
      image: k8smirror/ingress-nginx-opentelemetry
```

> 配置中的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

安装：

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

> 后续如果需要修改 values 配置，或者升级版本，都可以通过执行用个命令来更新 Nginx Ingress Controller。

查看流量入口(CLB VIP 或域名)：

```bash
$ kubectl get services -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   172.16.145.161   162.14.91.101   80:30683/TCP,443:32111/TCP   53s
ingress-nginx-controller-admission   ClusterIP      172.16.166.237   <none>          443/TCP                      53s
```

> `LoadBalancer` 类型 Service 的 `EXTERNAL-IP` 就是 CLB 的 VIP 或域名，可以配置下 DNS 解析。如果是 VIP，就配 A 记录；如果是 CLB 域名，就配置 CNAME 记录。

## 版本与升级

Nginx Ingress 的版本需要与 Kubernetes 集群版本能够兼容，可参考官方 [Supported Versions table](https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table) 确认下当前集群版本能否支持最新的 nginx ingress，如果不支持，安装的时候指定下 chart 版本。

比如当前的 TKE 集群版本是 1.24，chart 版本最高只能到 `4.7.*`，检查下有哪些可用版本：

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions | grep 4.7.
ingress-nginx/ingress-nginx     4.7.5           1.8.5           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.3           1.8.4           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.2           1.8.2           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.1           1.8.1           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.0           1.8.0           Ingress controller for Kubernetes using NGINX a...
```

可以看到 `4.7.*` 版本最高是 `4.7.5`，安装的时候我们加上版本号：

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  # highlight-next-line
  --version 4.7.5 \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

**注意：** TKE 集群升级前，先检查下当前 Nginx Ingress 版本能否兼容升级后的集群版本，如果不能兼容，先升级下 Nginx Ingress（用上面的命令指定 chart 版本号）。

## 自定义负载均衡器(CLB)

默认安装会自动创建出一个公网 CLB 来接入流量，你可以利用 Service 注解对 Nginx Ingress Controller 的 CLB 进行自定义，比如改成内网 CLB，在 `values.yaml` 中这样定义:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: 'subnet-xxxxxx' # 内网 CLB 需指定 CLB 实例所在的子网 ID
```

你也可以直接在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 根据自身需求创建一个 CLB （比如自定义实例规格、运营商类型、计费模式、带宽上限等），然后在 `values.yaml` 中用注解复用这个 CLB:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/tke-existed-lbid: 'lb-xxxxxxxx' # 指定已有 CLB 的实例 ID
```

> 参考文档 [Service 使用已有 CLB](https://cloud.tencent.com/document/product/457/45491)。
>
> **注意:** 在 CLB 控制台创建 CLB 实例时，选择的 VPC 需与集群一致。

## 启用 CLB 直连

CLB --> Nginx Ingress 这段链路可以直连（不走 NodePort），带来更好的性能，也可以实现获取真实源 IP 的需求。

如果你使用的 TKE Serverless 集群或者能确保所有 Nginx Ingress Pod 调度到超级节点，这时本身就是直连的，不需要做什么。

其它情况下，这段链路中间默认会走 NodePort，以下是启用直连的方法（根据自己的集群环境对号入座）。

> 参考[使用 LoadBalancer 直连 Pod 模式 Service](https://cloud.tencent.com/document/product/457/41897)。

### GlobalRouter+VPC-CNI 网络模式启用直连

如果集群网络模式是 GlobalRouter，且启用了 VPC-CNI：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321194833.png)

这种情况建议为 Nginx Ingress 声明用 VPC-CNI 网络，同时启用 CLB 直连，`values.yaml` 配置方法：

```yaml
controller:
  podAnnotations:
    tke.cloud.tencent.com/networks: tke-route-eni # 声明使用 VPC-CNI 网络
  resources: #  resources 里声明使用弹性网卡
    requests:
      tke.cloud.tencent.com/eni-ip: "1"
    limits:
      tke.cloud.tencent.com/eni-ip: "1"
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

### GlobalRouter 网络模式启用直连

如果集群网络是 GlobalRouter，但没有启用 VPC-CNI，建议最好是为集群开启 VPC-CNI，然后按照上面的方法启用 CLB 直连。如果实在不好开启，且腾讯云账号是带宽上移类型（参考[账号类型说明](https://cloud.tencent.com/document/product/1199/49090)），也可以有方法启用直连，只是有一些限制 (具体参考 [这里的说明](https://cloud.tencent.com/document/product/457/41897#.E4.BD.BF.E7.94.A8.E9.99.90.E5.88.B62))。

如果确认满足条件且接受使用限制，参考以下步骤启用直连：

1. 修改 configmap 开启 GlobalRouter 集群维度的直连能力:

```bash
kubectl edit configmap tke-service-controller-config -n kube-system
```

将 `GlobalRouteDirectAccess` 置为 true:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321200716.png)

2. 配置 `values.yaml` 启用 CLB 直连：

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

### VPC-CNI 网络模式启用直连

如果集群网络本身就是 VPC-CNI，那就比较简单了，直接配置 `values.yaml` 启用 CLB 直连即可：

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

## 高并发场景优化

### 调大 CLB 规格和带宽

高并发场景的流量吞吐需求较高，对 CLB 的转发性能要求也较高，可以在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 手动创建一个 CLB，实例规格选择性能容量型，型号根据自己需求来选，另外也将带宽上限调高（注意 VPC 要与 TKE 集群一致）。

CLB 创建好后，用 [自定义负载均衡器(CLB)](#自定义负载均衡器clb) 中的方法让 nginx ingress 复用这个 CLB 作为流量入口。

### 调优内核参数与 Nginx 配置


针对高并发场景调优内核参数和 nginx 自身的配置，`values.yaml` 配置方法:

```yaml
controller:
  extraInitContainers:
    - name: sysctl
      image: busybox
      imagePullPolicy: IfNotPresent
      command:
        - sh
        - -c
        - |
          sysctl -w net.core.somaxconn=65535 # 调大链接队列，防止队列溢出
          sysctl -w net.ipv4.ip_local_port_range="1024 65535" # 扩大源端口范围，防止端口耗尽
          sysctl -w net.ipv4.tcp_tw_reuse=1 # TIME_WAIT 复用，避免端口耗尽后无法新建连接
          sysctl -w fs.file-max=1048576 # 调大文件句柄数，防止连接过多导致文件句柄耗尽
  config:
    # nginx 与 client 保持的一个长连接能处理的请求数量，默认100，高并发场景建议调高，但过高也可能导致 nginx ingress 扩容后负载不均。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#keep-alive-requests
    keep-alive-requests: "1000"
    # nginx 与 upstream 保持长连接的最大空闲连接数 (不是最大连接数)，默认 320，在高并发下场景下调大，避免频繁建联导致 TIME_WAIT 飙升。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#upstream-keepalive-connections
    upstream-keepalive-connections: "2000"
    # 每个 worker 进程可以打开的最大连接数，默认 16384。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#max-worker-connections
    max-worker-connections: "65536"
```

> 参考 [Nginx Ingress 高并发实践](https://cloud.tencent.com/document/product/457/48142)。

### 日志轮转

Nginx Ingress 默认会将日志打印到容器标准输出，日志由容器运行时自动管理，在高并发场景可能会导致 CPU 占用较高。

解决方案是将 Nginx Ingress 日志输出到日志文件中，然后用 sidecar 对日志文件做自动轮转避免日志打满磁盘空间。

`values.yaml` 配置方法：

```yaml
controller:
  config:
    # nginx 日志落盘到日志文件，避免高并发下占用过多 CPU
    access-log-path: /var/log/nginx/nginx_access.log
    error-log-path: /var/log/nginx/nginx_error.log
  extraVolumes:
    - name: log # controller 挂载日志目录
      emptyDir: {}
  extraVolumeMounts:
    - name: log # logratote 与 controller 共享日志目录
      mountPath: /var/log/nginx
  extraContainers: # logrotate sidecar 容器，用于轮转日志
    - name: logrotate
      image: imroc/logrotate:latest # https://github.com/imroc/docker-logrotate
      imagePullPolicy: IfNotPresent
      env:
        - name: LOGROTATE_FILE_PATTERN # 轮转的日志文件pattern，与 nginx 配置的日志文件路径相匹配
          value: "/var/log/nginx/nginx_*.log"
        - name: LOGROTATE_FILESIZE # 日志文件超过多大后轮转
          value: "100M"
        - name: LOGROTATE_FILENUM # 每个日志文件轮转的数量
          value: "3"
        - name: CRON_EXPR # logrotate 周期性运行的 crontab 表达式，这里每分钟一次
          value: "*/1 * * * *"
        - name: CROND_LOGLEVEL # crond 日志级别，0~8，越小越详细
          value: "8"
      volumeMounts:
        - name: log
          mountPath: /var/log/nginx
```

## 高可用配置优化

### 调高副本数

配置自动扩缩容：

```yaml
controller:
  autoscaling:
    enabled: true
    minReplicas: 10
    maxReplicas: 100
    behavior: # 快速扩容应对流量洪峰，缓慢缩容预留 buffer 避免流量异常
      scaleDown:
        stabilizationWindowSeconds: 300
        policies:
          - type: Percent
            value: 900
            periodSeconds: 15 # 每 15s 最多允许扩容 9 倍于当前副本数
      scaleUp:
        stabilizationWindowSeconds: 300
        policies:
          - type: Pods
            value: 1
            periodSeconds: 600 # 每 10 分钟最多只允许缩掉 1 个 Pod
```

如果希望固定副本数，直接配置 `replicaCount`:

```yaml
controller:
  replicaCount: 50
```

### 打散调度

使用拓扑分布约束将 Pod 打散以支持容灾，避免单点故障：

```yaml
controller:
  topologySpreadConstraints: # 尽量打散的策略
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: '{{ include "ingress-nginx.name" . }}'
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: controller
      topologyKey: topology.kubernetes.io/zone
      maxSkew: 1
      whenUnsatisfiable: ScheduleAnyway
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: '{{ include "ingress-nginx.name" . }}'
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: controller
      topologyKey: kubernetes.io/hostname
      maxSkew: 1
      whenUnsatisfiable: ScheduleAnyway
```

### 调度专用节点

通常 Nginx Ingress Controller 的负载跟流量成正比，而 Nginx Ingress Controller 作为网关又特别重要，可以考虑将其调度到专用的节点或者超级节点，避免干扰业务 Pod 或被业务 Pod 干扰。

调度到指定节点池：

```yaml
controller:
  nodeSelector:
    tke.cloud.tencent.com/nodepool-id: np-********
```

> 超级节点的效果更好，所有 Pod 独占虚拟机，不会相互干扰。

### 合理设置 request limit

如果 Nginx Ingress 不是调度到超级节点，需合理设置下 request 和 limit，保证有足够的资源的同时，也保证不要用太多的资源导致节点负载过高:

```yaml
controller:
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

如果是用的超级节点，只需要定义下 requests，即声明每个 Pod 的虚拟机规格：

```yaml
controller:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
```

## 可观测性集成

### 集成 Prometheus 监控

如果你使用了 [腾讯云 Prometheus 监控服务关联 TKE 集群](https://cloud.tencent.com/document/product/1416/72037)，或者是自己安装了 Prometheus Operator 来监控集群，都可以启用 ServiceMonitor 来采集 Nginx Ingress 的监控数据，只需在 `values.yaml` 中打开这个开关即可：

```yaml
controller:
  metrics:
    enabled: true # 专门创建一个 service 给 Prometheus 用作 Nginx Ingress 的服务发现
    serviceMonitor:
      enabled: true # 下发 ServiceMonitor 自定义资源，启用监控采集规则
```

### 集成 Grafana 监控面板

如果你使用了 [腾讯云 Prometheus 监控服务关联 TKE 集群](https://cloud.tencent.com/document/product/1416/72037) 且关联了 [腾讯云 Grafana 服务](https://cloud.tencent.com/product/tcmg) ，可以直接在 Prometheus 集成中心安装 Nginx Ingress 的监控面板：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F22%2F20240322194119.png)

如果是自建的 Grafana，直接将 Nginx Ingress 官方提供的 [Grafana Dashboards](https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards) 中两个监控面板 (json文件) 导入 Grafana 即可。

### 集成 CLS 日志服务

TODO

## values.yaml 完整配置示例

<FileBlock file="nginx-ingress-values.yaml" showLineNumbers title="values.yaml" />
