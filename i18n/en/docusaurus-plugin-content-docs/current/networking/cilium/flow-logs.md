# Auditing Network Flow Logs with Cilium + CLS

## Overview

Cilium's cilium-agent can write network flow logs (Hubble Flows) to files, recording detailed metadata for every network connection in the cluster, including source/destination Pod, IP, port, protocol, policy verdict (allow/deny), and more.

Common use cases for network flow logs include:

- **Security Auditing**: Record all network connections to meet compliance requirements and trace abnormal access.
- **Troubleshooting**: Search flow logs for specific Pods or IPs to quickly locate network connectivity issues or connection timeouts.
- **Network Policy Validation**: Check which traffic was denied by NetworkPolicy (verdict=DROPPED) to verify that policies work as expected.
- **Traffic Analysis**: Analyze intra-cluster and external traffic patterns to identify anomalies.

This article describes how to export Cilium network flow logs to files and use Tencent Cloud CLS (Cloud Log Service) for collection and search analysis.

## Architecture

The overall data flow is as follows:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│    Hubble    │    │  Export to   │    │  CLS Agent   │    │  CLS Search  │
│    Server    │───▶│  Log Files   │───▶│  Collect     │───▶│  & Analyze   │
│  (per node)  │    │ (cilium pod) │    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

- **Hubble Server**: Built into each node's cilium-agent, enabled by default, responsible for observing and recording network flow logs.
- **Log Export**: Using Hubble's dynamic export feature, network flow logs are written to local files inside the cilium pod.
- **CLS Agent**: TKE's log collection component, responsible for collecting log files from cilium pods and reporting them to CLS.
- **CLS Search & Analysis**: Search, filter, and analyze network flow logs in the CLS console.

## Exporting Network Flow Logs to Files

### Basic Configuration

Enable Hubble dynamic log export and configure export rules:

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.enabled=true \
   --set hubble.export.dynamic.enabled=true \
   --set hubble.export.dynamic.config.content[0].name=all \
   --set hubble.export.dynamic.config.content[0].filePath=/var/run/cilium/hubble/events-all.log \
   --set hubble.export.dynamic.config.content[0].excludeFilters[0].source_ip[0]=169.254.0.71 \
   --set hubble.export.dynamic.config.content[0].excludeFilters[1].destination_ip[0]=169.254.0.71
```

This configuration:

- Exports all network flow logs to `/var/run/cilium/hubble/events-all.log`.
- Excludes traffic with source or destination IP `169.254.0.71` (the CLS API address; see **FAQ** section **Why add 169.254.0.71 to excludeFilters?** for details).

### Export Configuration Details

Hubble supports two export methods: **static export** and **dynamic export**:

| Comparison     | Static Export                       | Dynamic Export                       |
| -------------- | ----------------------------------- | ------------------------------------ |
| Enable Method  | `hubble.export.static.enabled=true` | `hubble.export.dynamic.enabled=true` |
| Rule Count     | Only one set of filter rules        | Multiple rules, each exporting to a different file |
| Config Changes | Requires cilium pod restart         | No restart needed, auto-applies after ConfigMap change |
| Filter Syntax  | `allowList` / `denyList`            | `includeFilters` / `excludeFilters`  |

**Dynamic export** is recommended as it is more flexible, supports multiple rules, and does not require pod restarts when configuration changes.

#### Filters

For the complete list of filter fields supported by `includeFilters` and `excludeFilters`, refer to the `FlowFilter` message in [flow.proto](https://github.com/cilium/cilium/blob/main/api/v1/flow/flow.proto). Common fields include:

| Field             | Description                            | Example                        |
| ----------------- | -------------------------------------- | ------------------------------ |
| `source_pod`      | Source Pod (`namespace/pod-name`)      | `["kube-system/coredns"]`      |
| `destination_pod` | Destination Pod                        | `["default/nginx"]`            |
| `source_ip`       | Source IP                              | `["10.0.1.100"]`           |
| `destination_ip`  | Destination IP                         | `["10.0.2.200"]`             |
| `verdict`         | Policy verdict                         | `["DROPPED"]`, `["FORWARDED"]` |
| `event_type`      | Event type                             | `[{"type": 1}]`               |

Multiple fields within the same filter object have an **AND** relationship, while multiple filter objects in the same array have an **OR** relationship.

#### fieldMask (Field Trimming)

If you don't need to export all fields, use `fieldMask` to keep only the fields you need, reducing log size:

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.enabled=true \
   --set hubble.export.dynamic.enabled=true \
   --set hubble.export.dynamic.config.content[0].name=dropped \
   --set hubble.export.dynamic.config.content[0].filePath=/var/run/cilium/hubble/dropped.log \
   --set hubble.export.dynamic.config.content[0].includeFilters[0].verdict[0]=DROPPED \
   --set hubble.export.dynamic.config.content[0].fieldMask[0]=time \
   --set hubble.export.dynamic.config.content[0].fieldMask[1]=source.namespace \
   --set hubble.export.dynamic.config.content[0].fieldMask[2]=source.pod_name \
   --set hubble.export.dynamic.config.content[0].fieldMask[3]=destination.namespace \
   --set hubble.export.dynamic.config.content[0].fieldMask[4]=destination.pod_name \
   --set hubble.export.dynamic.config.content[0].fieldMask[5]=IP \
   --set hubble.export.dynamic.config.content[0].fieldMask[6]=l4 \
   --set hubble.export.dynamic.config.content[0].fieldMask[7]=verdict \
   --set hubble.export.dynamic.config.content[0].fieldMask[8]=drop_reason_desc
```

This configuration exports only DROPPED traffic and keeps only the key fields: time, source/destination Pod, IP, L4 protocol, verdict, and drop reason.

fieldMask field paths use dots (`.`) to separate nested fields. The complete list of available fields is based on the `Flow` message in [flow.proto](https://github.com/cilium/cilium/blob/main/api/v1/flow/flow.proto). Common fields include:

| Field Path                      | Description                                              |
| ------------------------------- | -------------------------------------------------------- |
| `time`                          | Time when the flow occurred                              |
| `verdict`                       | Policy verdict (FORWARDED / DROPPED / TRACED / ERROR)    |
| `drop_reason_desc`              | Drop reason description                                  |
| `IP`                            | Full IP info (source/destination IP)                     |
| `IP.source`                     | Source IP                                                |
| `IP.destination`                | Destination IP                                           |
| `l4`                            | Full L4 protocol info                                    |
| `l4.TCP.source_port`            | TCP source port                                          |
| `l4.TCP.destination_port`       | TCP destination port                                     |
| `l4.UDP.source_port`            | UDP source port                                          |
| `l4.UDP.destination_port`       | UDP destination port                                     |
| `source`                        | Full source endpoint info                                |
| `source.namespace`              | Source Pod namespace                                     |
| `source.pod_name`               | Source Pod name                                          |
| `source.labels`                 | Source endpoint labels                                   |
| `source.identity`               | Source endpoint Cilium Identity                          |
| `source.workloads`              | Source endpoint workload info                            |
| `destination`                   | Full destination endpoint info                           |
| `destination.namespace`         | Destination Pod namespace                                |
| `destination.pod_name`          | Destination Pod name                                     |
| `destination.labels`            | Destination endpoint labels                              |
| `destination.identity`          | Destination endpoint Cilium Identity                     |
| `destination.workloads`         | Destination endpoint workload info                       |
| `node_name`                     | Node name                                                |
| `node_labels`                   | Node labels                                              |
| `is_reply`                      | Whether this is a reply packet                           |
| `traffic_direction`             | Traffic direction (INGRESS / EGRESS)                     |
| `trace_reason`                  | Trace reason                                             |
| `event_type`                    | Event type                                               |
| `source_service.name`           | Source Service name                                      |
| `source_service.namespace`      | Source Service namespace                                 |
| `destination_service.name`      | Destination Service name                                 |
| `destination_service.namespace` | Destination Service namespace                            |
| `l7`                            | L7 protocol info (DNS/HTTP, etc.)                        |
| `l7.dns`                        | DNS request/response info                                |
| `l7.http`                       | HTTP request/response info                               |
| `interface`                     | Network interface info                                   |
| `Summary`                       | Flow summary (deprecated)                                |

#### Multiple Rule Configuration

Dynamic export supports configuring multiple rules simultaneously, each exporting to a different file, suitable for categorized export by scenario:

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.enabled=true \
   --set hubble.export.dynamic.enabled=true \
   # highlight-next-line
   --set hubble.export.dynamic.config.content[0].name=all \
   --set hubble.export.dynamic.config.content[0].filePath=/var/run/cilium/hubble/events-all.log \
   --set hubble.export.dynamic.config.content[0].excludeFilters[0].source_ip[0]=169.254.0.71 \
   --set hubble.export.dynamic.config.content[0].excludeFilters[1].destination_ip[0]=169.254.0.71 \
   # highlight-next-line
   --set hubble.export.dynamic.config.content[1].name=dropped \
   --set hubble.export.dynamic.config.content[1].filePath=/var/run/cilium/hubble/dropped.log \
   --set hubble.export.dynamic.config.content[1].includeFilters[0].verdict[0]=DROPPED
```

This configuration defines two rules:

- **all**: Export all traffic (excluding CLS API address).
- **dropped**: Export only denied traffic, useful for quickly identifying NetworkPolicy-related issues.

#### Log Rotation

Exported log files are automatically rotated. Configure with the following parameters:

| Parameter                      | Description                          | Default |
| ------------------------------ | ------------------------------------ | ------- |
| `hubble.export.fileMaxSizeMb`  | Max size per log file (MB)           | 10      |
| `hubble.export.fileMaxBackups` | Number of rotated files to keep      | 5       |
| `hubble.export.fileCompress`   | Whether to compress rotated files    | false   |

For high log volumes, you can increase the file size and backup count:

```bash
helm upgrade cilium cilium/cilium --version 1.19.1 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.export.fileMaxSizeMb=50 \
   --set hubble.export.fileMaxBackups=10 \
   --set hubble.export.fileCompress=true
```

### Log Format

Each exported line is a JSON object containing the full network flow log. Below is a formatted sample log entry — a `curl` Pod in the `test` namespace sending an HTTP request to an `nginx` Pod:

```json
{
  "flow": {
    "IP": {
      "destination": "10.20.0.9",
      "ipVersion": "IPv4",
      "source": "10.20.0.10"
    },
    "Summary": "TCP Flags: ACK",
    "Type": "L3_L4",
    "destination": {
      "cluster_name": "default",
      "identity": 27312,
      "labels": [
        "k8s:app=nginx",
        "k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=test",
        "k8s:io.cilium.k8s.policy.cluster=default",
        "k8s:io.cilium.k8s.policy.serviceaccount=default",
        "k8s:io.kubernetes.pod.namespace=test"
      ],
      "namespace": "test",
      "pod_name": "nginx-54c98b4f84-sw9q9"
    },
    "emitter": {
      "name": "Hubble",
      "version": "1.19.1+gd0d0c879"
    },
    "ethernet": {
      "destination": "02:21:a9:ff:89:f4",
      "source": "ce:0a:b9:d8:63:61"
    },
    "event_type": {
      "sub_type": 3,
      "type": 4
    },
    "is_reply": false,
    "l4": {
      "TCP": {
        "destination_port": 80,
        "flags": {
          "ACK": true
        },
        "source_port": 56598
      }
    },
    "node_labels": [
      "beta.kubernetes.io/arch=amd64",
      "beta.kubernetes.io/instance-type=S5.MEDIUM4",
      "beta.kubernetes.io/os=linux",
      "cloud.tencent.com/auto-scaling-group-id=asg-q9zxcooe",
      "cloud.tencent.com/node-instance-id=ins-f5wpfrc5",
      "failure-domain.beta.kubernetes.io/region=cd",
      "failure-domain.beta.kubernetes.io/zone=160001",
      "kubernetes.io/arch=amd64",
      "kubernetes.io/hostname=10.10.21.35",
      "kubernetes.io/os=linux",
      "node.kubernetes.io/instance-type=S5.MEDIUM4",
      "node.tke.cloud.tencent.com/accelerator-type=cpu",
      "node.tke.cloud.tencent.com/cpu=2",
      "node.tke.cloud.tencent.com/memory=4",
      "os=tencentos4",
      "tke.cloud.tencent.com/cbs-mountable=true",
      "tke.cloud.tencent.com/nodepool-id=np-p8uyib3x",
      "tke.cloud.tencent.com/route-eni-subnet-ids=subnet-fg9qdb1f",
      "topology.com.tencent.cloud.csi.cbs/zone=ap-chengdu-1",
      "topology.kubernetes.io/region=cd",
      "topology.kubernetes.io/zone=160001"
    ],
    "node_name": "10.10.21.35",
    "source": {
      "ID": 3863,
      "cluster_name": "default",
      "identity": 4368,
      "labels": [
        "k8s:app=curl",
        "k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=test",
        "k8s:io.cilium.k8s.policy.cluster=default",
        "k8s:io.cilium.k8s.policy.serviceaccount=default",
        "k8s:io.kubernetes.pod.namespace=test"
      ],
      "namespace": "test",
      "pod_name": "curl-7d4d858f75-j76f7",
      "workloads": [
        {
          "kind": "Deployment",
          "name": "curl"
        }
      ]
    },
    "time": "2026-02-25T03:25:54.227004477Z",
    "trace_observation_point": "TO_STACK",
    "trace_reason": "ESTABLISHED",
    "traffic_direction": "EGRESS",
    "uuid": "a38e44fa-b7b7-4f8f-a40b-2c1dd2621140",
    "verdict": "FORWARDED"
  },
  "node_name": "10.10.21.35",
  "time": "2026-02-25T03:25:54.227004477Z"
}
```

Key field descriptions:

| Field                              | Description                                                                   |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| `flow.time`                        | Time when the flow occurred                                                   |
| `flow.verdict`                     | Policy verdict: `FORWARDED` (allowed), `DROPPED` (denied), `TRACED` (traced), `ERROR` (error) |
| `flow.IP`                          | Source/destination IP addresses                                               |
| `flow.l4`                          | L4 protocol info (TCP/UDP ports, flags, etc.)                                 |
| `flow.source` / `flow.destination` | Source/destination Pod name, namespace, labels, workload, etc.                |
| `flow.traffic_direction`           | Traffic direction: `INGRESS` or `EGRESS`                                      |
| `flow.drop_reason_desc`            | Drop reason description (only present when verdict is DROPPED)                |
| `flow.is_reply`                    | Whether this is a reply packet                                                |
| `flow.Summary`                     | Flow summary info                                                             |

## Delivering Network Flow Logs to CLS

Configure TKE log collection to collect log files from all cilium-agents and deliver them to CLS.

### Enable Log Collection

Before configuring log collection rules, ensure that the cluster has enabled the log collection feature. Console path: **Monitoring and alarms > Log > Business Logs**.

### Configure via YAML (Recommended)

TKE uses the LogConfig CRD to configure log collection rules. This method allows quick index configuration and avoids extensive manual operations in the console. Use the following YAML:

> Configure with `kubectl apply -f <your-logconfig-yaml-file>`.

```yaml
apiVersion: cls.cloud.tencent.com/v1
kind: LogConfig
metadata:
  name: cilium-network-logs
spec:
  clsDetail:
    region: ap-chengdu # Replace with your CLS region. See https://cloud.tencent.com/document/product/614/18940 for available regions.
    logsetName: "TKE-cls-k398qwbj-102564" # Replace with your CLS logset name. If a logset with this name exists, it will be used; otherwise, a new one will be created.
    topicName: "tke-cls-k398qwbj-cilium-network-logs" # Replace with your CLS topic name. Auto-created topics will use this name.
    extractRule:
      backtracking: "0"
      isGBK: "false"
      jsonStandard: "true"
      timeFormat: '%Y-%m-%dT%H:%M:%S.%f%z'
      timeKey: time
      unMatchUpload: "true"
      unMatchedKey: LogParseFailure
    indexStatus: "on"
    indexs:
    - indexName: namespace
    - indexName: pod_name
    - indexName: container_name
    - indexName: flow.verdict
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.uuid
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.drop_reason_desc
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.source.pod_name
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.source.namespace
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.source.cluster_name
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.source.labels
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.source.identity
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination.pod_name
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination.namespace
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination.cluster_name
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination.labels
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination.identity
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination_service.name
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.destination_service.namespace
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.IP.ipVersion
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.IP.source
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.IP.destination
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.l4
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.l7
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.l4.TCP.source_port
      indexType: long
    - indexName: flow.l4.TCP.destination_port
      indexType: long
    - indexName: flow.l4.UDP.source_port
      indexType: long
      containZH: false
    - indexName: flow.l4.UDP.destination_port
      indexType: long
    - indexName: flow.event_type.type
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.event_type.sub_type
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.Summary
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.traffic_direction
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.trace_reason
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.is_reply
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.Type
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.node_labels
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    - indexName: flow.file
      indexType: text
      tokenizer: "@&?|#()='\",;:<>[]{}/ \n\t\r\\"
      containZH: false
    autoIndex: "true"
    logFormat: default
    logType: json_log
    maxSplitPartitions: 0
    period: 30
    storageType: ""
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

### Configure via Console

If needed, you can also configure log collection rules in the TKE console. Create a new log rule under **Monitoring and alarms > Log > Business Logs** in the TKE cluster. Refer to the following screenshots for configuration:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F02%2F24%2F20260224170002.png)

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F02%2F24%2F20260224170258.png)

## CLS Search Examples

After logs are delivered to CLS, you can perform multi-dimensional search and analysis in the CLS console. Here are some common search queries:

### Query All Flow Logs for a Specific Pod

```
flow.source.pod_name:"nginx-deployment-abc123" OR flow.destination.pod_name:"nginx-deployment-abc123"
```

### Query Denied Traffic

```
flow.verdict:"DROPPED"
```

View detailed drop reasons:

```
flow.verdict:"DROPPED" | select flow.drop_reason_desc, flow.source.namespace, flow.source.pod_name, flow.destination.namespace, flow.destination.pod_name, count(*) as cnt group by flow.drop_reason_desc, flow.source.namespace, flow.source.pod_name, flow.destination.namespace, flow.destination.pod_name order by cnt desc
```

### Filter by Namespace

Query all traffic originating from the `default` namespace:

```
flow.source.namespace:"default"
```

Query all traffic destined for the `kube-system` namespace:

```
flow.destination.namespace:"kube-system"
```

### Filter by Port

Query traffic with destination port 80:

```
flow.l4.TCP.destination_port:80
```

### Query All Traffic for a Specific IP

```
flow.IP.source:"10.0.1.100" OR flow.IP.destination:"10.0.1.100"
```

### Filter by Traffic Direction

View only ingress traffic:

```
flow.traffic_direction:"INGRESS"
```

## Related Products

[Tencent Cloud Flow Logs (FL)](https://cloud.tencent.com/product/fl) also provides similar network flow log capabilities. It collects flow logs at the VPC level. Here are the differences compared to Cilium Hubble flow logs:

| Comparison       | Cilium Hubble Flow Logs                                             | Tencent Cloud Flow Logs (FL)            |
| ---------------- | ------------------------------------------------------------------- | --------------------------------------- |
| Collection Level | Pod level, based on eBPF                                            | VPC level, based on ENI                 |
| Information      | Includes Pod name, labels, Namespace, NetworkPolicy verdict, etc.   | Mainly IP, port, protocol info          |
| Filtering        | Supports filtering by Pod, labels, verdict, and other K8s dimensions | Supports filtering by VPC, subnet, ENI  |
| Use Case         | Kubernetes cluster network observability                            | VPC-level network traffic auditing      |

Choose based on your needs. The two can also complement each other: Cilium provides fine-grained K8s-level flow logs, while FL provides global VPC-level flow logs.

## FAQ

### Where is the Hubble dynamic log export configuration stored?

It is stored in the `kube-system/cilium-flowlog-config` ConfigMap. You can view the current configuration with kubectl:

```bash
$ kubectl -n kube-system get cm cilium-flowlog-config -o yaml
apiVersion: v1
data:
  flowlogs.yaml: |
    flowLogs:
      - excludeFilters:
        - source_ip:
          - 169.254.0.71
        - destination_ip:
          - 169.254.0.71
        filePath: /var/run/cilium/hubble/events-all.log
        name: all
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: cilium
    meta.helm.sh/release-namespace: kube-system
  creationTimestamp: "2026-02-24T08:35:22Z"
  labels:
    app.kubernetes.io/managed-by: Helm
  name: cilium-flowlog-config
  namespace: kube-system
  resourceVersion: "3969239884"
  uid: 87978d03-638a-4c31-80d2-0a3e0fe17049
```

### Why didn't CLS automatically create the log topic?

Ensure both `logsetName` and `topicName` are configured, there is no existing log topic with the same name as `topicName`, and do not specify `topicId` or `logsetId`.

### Where can I find the complete LogConfig field reference?

For the complete TKE LogConfig field reference, see [LogConfig JSON Format Reference](https://cloud.tencent.com/document/product/457/111541)

### Why add 169.254.0.71 to excludeFilters?

169.254.0.71 is the destination IP of the CLS API. Collected logs are ultimately reported through this IP. If no `includeFilters` are specified, you need to add this `excludeFilters` entry to prevent the CLS log reporting traffic from being recorded as Cilium network flow logs, which would then be collected again, reported again, and cause an infinite collection-reporting loop. Even without other network traffic, this would continuously generate and collect new logs, causing unnecessary overhead.

## References

- [Configuring Hubble exporter](https://docs.cilium.io/en/latest/observability/hubble/configuration/export/)
- [LogConfig JSON Format Reference](https://cloud.tencent.com/document/product/457/111541)
- [CLS Available Regions](https://cloud.tencent.com/document/product/614/18940)
