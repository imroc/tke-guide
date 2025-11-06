---
sidebar_position: 4
---

# TKE Event Log Alerts

## Kubernetes Event Logs

Kubernetes resources generate event logs, divided into Normal and Warning types. Normal type logs are general event logs, such as Pod scheduling success, image pulling, etc. Warning type logs are abnormal event logs, such as Pod startup failure, Node disk pressure, etc.

Event logs are standard interfaces provided by Kubernetes. Besides Kubernetes components generating event logs, other components can also send event logs to Kubernetes clusters in the same way, such as cert-manager:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331200805.png)

## Collecting Event Logs

TKE supports one-click enabling of event log collection, collecting Kubernetes event logs to CLS for storage, retrieval, and alerting. For details, refer to [Cluster Operations: Event Logs](https://cloud.tencent.com/document/product/457/32091).

## Configuring Event Log Alerts

Usually we focus on Warning type logs and can configure unified event log alerts.

Operation steps:
1. Click **Create** on the [Alert Policy](https://console.cloud.tencent.com/cls/alarm/list) page.
2. **Monitoring Object** selects the log topic of TKE cluster event logs.
3. **Execution Statement** fills in `event.type:Warning`.
4. **Additional Notification Content**:

```txt
{{- range .QueryLog }}
Cluster cls-xxxxxxxx has abnormal events:
  {{- range . }}
    {{.content.event.reason}} {{ .content.event.involvedObject.kind }}/{{ .content.event.involvedObject.name }} {{ .content.event.message }}
  {{- end}}
{{- end}}
```

> Note to replace the cluster ID.

Other configuration items can be configured as needed.

## Alert Effects

### Email Alert

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331204018.png)

### WeChat Alert

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331204531.png)

## References

- [TKE Practice Tutorial: Using CLS to Alert Abnormal Resources](https://cloud.tencent.com/document/product/457/82037)