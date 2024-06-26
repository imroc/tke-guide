# Prometheus 采集 TKE 监控数据最佳实践

使用 Prometheus 采集腾讯云容器服务的监控数据时如何配置采集规则？主要需要注意的是 kubelet 与 cadvisor 的监控指标采集，本文分享为 Prometheus 配置 `scrape_config` 来采集腾讯云容器服务集群的监控数据的方法。

## TKE 集群普通节点采集规则

如果你使用 [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 或 [victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/README.md) 搭建的监控系统，那么普通节点的监控数据无需自行配置。

如果是自行手动维护 Prometheus 的采集规则，可参考下面的采集规则：

```yaml
    - job_name: "tke-cadvisor"
      scheme: https
      metrics_path: /metrics/cadvisor # 采集容器 cadvisor 监控数据
      tls_config:
        insecure_skip_verify: true # tke 的 kubelet 使用自签证书，忽略证书校验
      authorization:
        credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__meta_kubernetes_node_label_node_kubernetes_io_instance_type]
        regex: eklet # 排除超级节点
        action: drop
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    - job_name: "tke-kubelet"
      scheme: https
      metrics_path: /metrics # 采集 kubelet 自身的监控数据
      tls_config:
        insecure_skip_verify: true
      authorization:
        credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__meta_kubernetes_node_label_node_kubernetes_io_instance_type]
        regex: eklet
        action: drop
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    - job_name: "tke-probes" # 采集容器健康检查健康数据
      scheme: https
      metrics_path: /metrics/probes
      tls_config:
        insecure_skip_verify: true
      authorization:
        credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__meta_kubernetes_node_label_node_kubernetes_io_instance_type]
        regex: eklet
        action: drop
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
```

* 使用节点服务发现 (`kubernetes_sd_configs` 的 role 为 `node`)，抓取所有节点 `kubelet:10250` 暴露的几种监控数据。
* 如果集群是普通节点与超级节点混用，排除超级节点 (`relabel_configs` 中将带 `node.kubernetes.io/instance-type: eklet` 这种 label 的 node 排除)。
* TKE 节点上的 kubelet 证书是自签的，需要忽略证书校验，所以 `insecure_skip_verify` 要置为 true。
* kubelet 通过 `/metrics/cadvisor`, `/metrics` 与 `/metrics/probes` 路径分别暴露了容器 cadvisor 监控数据、kubelet 自身监控数据以及容器健康检查健康数据，为这三个不同路径分别配置采集 job 进行采集。

## TKE 集群超级节点采集规则

超级节点是虚拟的节点，每个 Pod 都是独占虚拟机，监控数据暴露在每个 Pod 的 `9100` 端口下，使用以下采集规则进行采集：

```yaml
    - job_name: serverless-pod # 采集超级节点的 Pod 监控数据
      honor_timestamps: true
      metrics_path: '/metrics' # 所有健康数据都在这个路径
      params: # 通常需要加参数过滤掉 ipvs 相关的指标，因为可能数据量较大，打高 Pod 负载。
        collect[]:
        - 'ipvs'
        # - 'cpu'
        # - 'meminfo'
        # - 'diskstats'
        # - 'filesystem'
        # - 'load0vg'
        # - 'netdev'
        # - 'filefd'
        # - 'pressure'
        # - 'vmstat'
      scheme: http
      kubernetes_sd_configs:
      - role: pod # 超级节点 Pod 的监控数据暴露在 Pod 自身 IP 的 9100 端口，所以使用 Pod 服务发现
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_tke_cloud_tencent_com_pod_type]
        regex: eklet # 只采集超级节点的 Pod
        action: keep
      - source_labels: [__meta_kubernetes_pod_phase]
        regex: Running # 非 Running 状态的 Pod 机器资源已释放，不需要采集
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        separator: ;
        regex: (.*)
        target_label: __address__
        replacement: ${1}:9100 # 监控指标暴露在 Pod 的 9100 端口
        action: replace
      - source_labels: [__meta_kubernetes_pod_name]
        separator: ;
        regex: (.*)
        target_label: pod # 将 Pod 名字写到 "pod" label
        replacement: ${1}
        action: replace
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: namespace # 将 Pod 所在 namespace 写到 "namespace" label
        replacement: ${1}
        action: replace
      metric_relabel_configs:
      - source_labels: [__name__]
        separator: ;
        regex: (container_.*|pod_.*|kubelet_.*)
        replacement: $1
        action: keep
```

* 超级节点的监控数据暴露在每个 Pod 的 9100 端口的 `/metrics` 这个 HTTP API 路径(非 HTTPS)，使用 Pod 服务发现(`kubernetes_sd_configs` 的 role 为 `pod`)，用一个 job 就可以采集完。
* 超级节点的 Pod 支持通过 `collect[]` 这个查询参数来过滤掉不希望采集的指标，这样可以避免指标数据量过大，导致 Pod 负载升高，通常要过滤掉 `ipvs` 的指标。
* 如果集群是普通节点与超级节点混用，确保只采集超级节点的 Pod (`relabel_configs` 中只保留有 `tke.cloud.tencent.com/pod-type:eklet` 这个注解的 Pod)。
* 如果 Pod 的 phase 不是 Running 也无法采集，可以排除。
* `container_` 开头的指标是 cadvisor 监控数据，`pod_` 前缀指标是超级节点 Pod 所在子机的监控数据(相当于将 `node_exporter` 的 `node_` 前缀指标替换成了 `pod_`)，`kubelet_` 前缀指标是超级节点 Pod 子机内兼容 kubelet 的指标(主要是 pvc 存储监控)。

如果你是用 [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 部署的监控系统，超级节点的采集配置可写到 `prometheus.prometheusSpec.additionalScrapeConfigs` 字段下，下面是示例:

```yaml title="values.yaml"
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: serverless-pod
        ...
```

## TKE Serverless 集群采集规则

TKE Serverless 集群只有超级节点，Pod 上不存在 `tke.cloud.tencent.com/pod-type` 这个注解，也就不需要这个过滤条件，采集规则为：

```yaml
    - job_name: serverless-pod # 采集超级节点的 Pod 监控数据
      honor_timestamps: true
      metrics_path: '/metrics' # 所有健康数据都在这个路径
      params: # 通常需要加参数过滤掉 ipvs 相关的指标，因为可能数据量较大，打高 Pod 负载。
        collect[]:
        - 'ipvs'
        # - 'cpu'
        # - 'meminfo'
        # - 'diskstats'
        # - 'filesystem'
        # - 'load0vg'
        # - 'netdev'
        # - 'filefd'
        # - 'pressure'
        # - 'vmstat'
      scheme: http
      kubernetes_sd_configs:
      - role: pod # 超级节点 Pod 的监控数据暴露在 Pod 自身 IP 的 9100 端口，所以使用 Pod 服务发现
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_phase]
        regex: Running # 非 Running 状态的 Pod 机器资源已释放，不需要采集
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        separator: ;
        regex: (.*)
        target_label: __address__
        replacement: ${1}:9100 # 监控指标暴露在 Pod 的 9100 端口
        action: replace
      - source_labels: [__meta_kubernetes_pod_name]
        separator: ;
        regex: (.*)
        target_label: pod # 将 Pod 名字写到 "pod" label
        replacement: ${1}
        action: replace
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: namespace # 将 Pod 所在 namespace 写到 "namespace" label
        replacement: ${1}
        action: replace
      metric_relabel_configs:
      - source_labels: [__name__]
        separator: ;
        regex: (container_.*|pod_.*|kubelet_.*)
        replacement: $1
        action: keep
```

## FAQ

### 为什么使用 collect[] 这种奇怪的参数过滤指标？

超级节点的 Pod 监控指标使用 `collect[]` 查询参数来过滤不需要的监控指标:

```bash
curl ${IP}:9100/metrics?collect[]=ipvs&collect[]=vmstat
```

为什么要使用这么奇怪的参数名？这是因为 `node_exporter` 就是用的这个参数，超级节点的 Pod 内部引用了 `node_exporter` 的逻辑，[这里](https://github.com/prometheus/node_exporter#filtering-enabled-collectors) 是 `node_exporter` 的 `collect[]` 参数用法说明。
