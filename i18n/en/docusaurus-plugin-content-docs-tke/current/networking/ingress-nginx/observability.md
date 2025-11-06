# Observability Integration

## Overview

This article describes how to configure Nginx Ingress to integrate with monitoring and logging systems to enhance observability, including integration with Tencent Cloud's managed Prometheus, Grafana, and CLS products, as well as integration with self-built Prometheus and Grafana.

## Integrating Prometheus Monitoring

If you use [Tencent Cloud Prometheus Monitoring Service associated with TKE cluster](https://cloud.tencent.com/document/product/1416/72037), or have installed Prometheus Operator yourself to monitor the cluster, you can enable ServiceMonitor to collect Nginx Ingress monitoring data. Simply turn on this switch in `values.yaml`:

```yaml
commonLabels:
  prom_id: prom-xxx # Specify Prometheus instance ID through this label so the ServiceMonitor can be recognized by the Prometheus instance
controller:
  metrics:
    enabled: true # Create a dedicated service for Prometheus to use for Nginx Ingress service discovery
    serviceMonitor:
      enabled: true # Deploy ServiceMonitor custom resource to enable monitoring collection rules
```

## Integrating Grafana Monitoring Dashboards

If you use [Tencent Cloud Prometheus Monitoring Service associated with TKE cluster](https://cloud.tencent.com/document/product/1416/72037) and have associated [Tencent Cloud Grafana Service](https://cloud.tencent.com/product/tcmg), you can directly install Nginx Ingress monitoring dashboards in the Prometheus integration center:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F22%2F20240322194119.png)

If using self-built Grafana, simply import the two monitoring dashboards (json files) from Nginx Ingress's official [Grafana Dashboards](https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards) into Grafana.

## Integrating CLS Log Service

Below describes how to collect Nginx Ingress Controller's access logs to CLS and analyze logs using CLS dashboards.

1. Configure the nginx access log format in `values.yaml`, and set the timezone so timestamps display local time (enhancing readability):

```yaml
controller:
  config:
    log-format-upstream:
      $remote_addr - $remote_user [$time_local] "$request"
      $status $body_bytes_sent "$http_referer" "$http_user_agent"
      $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr
      $upstream_response_length $upstream_response_time $upstream_status $req_id $host
  extraEnvs:
    - name: TZ
      value: Asia/Shanghai
```

2. Ensure log collection is enabled for the cluster. Refer to official documentation [Enabling Log Collection](https://cloud.tencent.com/document/product/457/83871#.E5.BC.80.E5.90.AF.E6.97.A5.E5.BF.97.E9.87.87.E9.9B.86).

3. Prepare CLS logset and log topic for Nginx Ingress Controller. If you don't have them, go to [CLS Console](https://console.cloud.tencent.com/cls/topic) to create them according to your needs, then record the log topic ID.

4. Follow the screenshot guide to enable indexing for the log topic:
    * Enter the log topic's **Index Configuration** page and click **Edit**:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201551.png)
    * Enable indexing, full-text delimiters: `@&?|#()='",;:<>[]{}/ \n\t\r\\`:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201658.png)
    * Batch add index fields (keep configuration consistent with the screenshot):
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201739.png)
    * Advanced settings:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201802.png)

5. Create TKE log collection rules:

<Tabs>
  <TabItem value="stdout" label="Collect Standard Output">
    <FileBlock file="nginx-ingress-logconfig-stdout.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="file" label="Collect Log Files">
    <FileBlock file="nginx-ingress-logconfig-files.yaml" showLineNumbers />
  </TabItem>
</Tabs>
    * The configuration that must be replaced is `topicId`, i.e., the log topic ID, indicating that collected logs will be sent to this CLS log topic.
    * Choose to configure collection of standard output or log files according to your actual situation. Nginx ingress outputs logs to standard output by default, but you can also write logs to log files as described in [Log Rotation](high-concurrency.md#log-rotation).

6. Test Ingress requests to generate log data.
7. Go to the [Search and Analysis](https://console.cloud.tencent.com/cls/search) page in the log service console, select the log topic used by nginx ingress, and confirm logs can be searched normally.
8. If everything is normal, you can use the log service's [Nginx Access Dashboard](https://console.cloud.tencent.com/cls/dashboard/d?templateId=nginx-ingress-access-dashboard&var-ds=&time=now-d,now) and [Nginx Monitoring Dashboard](https://console.cloud.tencent.com/cls/dashboard/d?templateId=nginx-ingress-monitor-dashboard&var-ds=&time=now-d,now) preset dashboards and select the log topic used by nginx ingress to display nginx access log analysis panels:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203343.png)

    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203353.png)

You can even set up alert rules directly through the dashboard:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203154.png)
