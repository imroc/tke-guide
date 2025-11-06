---
sidebar_position: 3
---

# Prometheus TKE Monitoring Data Collection Best Practices

How to configure collection rules when using Prometheus to collect monitoring data from Tencent Cloud Container Service? The main considerations are monitoring metric collection for kubelet and cadvisor. This article shares methods for configuring `scrape_config` for Prometheus to collect monitoring data from Tencent Cloud Container Service clusters.

## TKE Cluster Regular Node Collection Rules

If you use [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) or [victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/README.md) to build your monitoring system, then regular node monitoring data does not need to be configured manually.

If manually maintaining Prometheus collection rules, you can refer to the following collection rules:

```yaml
    - job_name: "tke-cadvisor"
      scheme: https
      metrics_path: /metrics/cadvisor # Collect container cadvisor monitoring data
      tls_config:
        insecure_skip_verify: true # TKE's kubelet uses self-signed certificates, ignore certificate verification
      authorization:
        credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - role: node
      relabel_configs:
      - source_labels: [__meta_kubernetes_node_label_node_kubernetes_io_instance_type]
        regex: eklet # Exclude super nodes
        action: drop
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    - job_name: "tke-kubelet"
      scheme: https
      metrics_path: /metrics # Collect kubelet's own monitoring data
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
    - job_name: "tke-probes" # Collect container health check data
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

* Use node service discovery (`kubernetes_sd_configs` with role as `node`) to scrape several types of monitoring data exposed by `kubelet:10250` on all nodes.
* If the cluster mixes regular nodes and super nodes, exclude super nodes (in `relabel_configs`, drop nodes with label `node.kubernetes.io/instance-type: eklet`).
* kubelet certificates on TKE nodes are self-signed, so `insecure_skip_verify` needs to be set to true.
* kubelet exposes container cadvisor monitoring data, kubelet's own monitoring data, and container health check data through `/metrics/cadvisor`, `/metrics`, and `/metrics/probes` paths respectively. Configure separate collection jobs for these three different paths.

## TKE Cluster Super Node Collection Rules

Super nodes are virtual nodes where each Pod occupies an exclusive virtual machine. Monitoring data is exposed on port `9100` of each Pod. Use the following collection rules for collection:

```yaml
    - job_name: serverless-pod # Collect super node Pod monitoring data
      honor_timestamps: true
      metrics_path: '/metrics' # All health data is on this path
      params: # Usually need to add parameters to filter out ipvs-related metrics as they may have large data volume, increasing Pod load.
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
      - role: pod # Super node Pod monitoring data is exposed on Pod's own IP port 9100, so use Pod service discovery
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_tke_cloud_tencent_com_pod_type]
        regex: eklet # Only collect super node Pods
        action: keep
      - source_labels: [__meta_kubernetes_pod_phase]
        regex: Running # Pods not in Running state have released machine resources, no need to collect
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        separator: ;
        regex: (.*)
        target_label: __address__
        replacement: ${1}:9100 # Monitoring metrics exposed on Pod's 9100 port
        action: replace
      - source_labels: [__meta_kubernetes_pod_name]
        separator: ;
        regex: (.*)
        target_label: pod # Write Pod name to "pod" label
        replacement: ${1}
        action: replace
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: namespace # Write Pod's namespace to "namespace" label
        replacement: ${1}
        action: replace
      metric_relabel_configs:
      - source_labels: [__name__]
        separator: ;
        regex: (container_.*|pod_.*|kubelet_.*)
        replacement: $1
        action: keep
```

* Super node monitoring data is exposed on port 9100 of each Pod through the `/metrics` HTTP API path (not HTTPS). Use Pod service discovery (`kubernetes_sd_configs` with role as `pod`) to collect everything with one job.
* Super node Pods support filtering out unwanted metrics using the `collect[]` query parameter, avoiding excessive metric data volume that could increase Pod load. Usually need to filter out `ipvs` metrics.
* If the cluster mixes regular nodes and super nodes, ensure only super node Pods are collected (in `relabel_configs`, only keep Pods with annotation `tke.cloud.tencent.com/pod-type:eklet`).
* If Pod's phase is not Running, collection is impossible, so exclude them.
* Metrics starting with `container_` are cadvisor monitoring data, `pod_` prefix metrics are monitoring data of the super node Pod's machine (equivalent to replacing `node_exporter`'s `node_` prefix metrics with `pod_`), `kubelet_` prefix metrics are kubelet-compatible metrics within super node Pod machines (mainly PVC storage monitoring).

If you use [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) to deploy the monitoring system, super node collection configuration can be written under the `prometheus.prometheusSpec.additionalScrapeConfigs` field. Example:

```yaml title="values.yaml"
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: serverless-pod
        ...
```

## TKE Serverless Cluster Collection Rules

TKE Serverless clusters only have super nodes. Pods don't have the `tke.cloud.tencent.com/pod-type` annotation, so this filtering condition is not needed. Collection rules are:

```yaml
    - job_name: serverless-pod # Collect super node Pod monitoring data
      honor_timestamps: true
      metrics_path: '/metrics' # All health data is on this path
      params: # Usually need to add parameters to filter out ipvs-related metrics as they may have large data volume, increasing Pod load.
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
      - role: pod # Super node Pod monitoring data is exposed on Pod's own IP port 9100, so use Pod service discovery
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_phase]
        regex: Running # Pods not in Running state have released machine resources, no need to collect
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        separator: ;
        regex: (.*)
        target_label: __address__
        replacement: ${1}:9100 # Monitoring metrics exposed on Pod's 9100 port
        action: replace
      - source_labels: [__meta_kubernetes_pod_name]
        separator: ;
        regex: (.*)
        target_label: pod # Write Pod name to "pod" label
        replacement: ${1}
        action: replace
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: namespace # Write Pod's namespace to "namespace" label
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

### Why Use the Strange collect[] Parameter to Filter Metrics?

Super node Pod monitoring metrics use the `collect[]` query parameter to filter unwanted monitoring metrics:

```bash
curl ${IP}:9100/metrics?collect[]=ipvs&collect[]=vmstat
```

Why use such a strange parameter name? This is because `node_exporter` uses this parameter, and super node Pods internally reference `node_exporter` logic. [Here](https://github.com/prometheus/node_exporter#filtering-enabled-collectors) is the `node_exporter`'s `collect[]` parameter usage description.