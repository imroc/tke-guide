# 可观测性集成

## 概述

本文介绍如何配置 Nginx Ingress 来集成监控和日志系统来提升可观测性，包括与腾讯云上托管的 Prometheus、Grafana 和 CLS 这些产品的集成，也包括与自建的 Prometheus 和 Grafana 的集成。

## 集成 Prometheus 监控

如果你使用了 [腾讯云 Prometheus 监控服务关联 TKE 集群](https://cloud.tencent.com/document/product/1416/72037)，或者是自己安装了 Prometheus Operator 来监控集群，都可以启用 ServiceMonitor 来采集 Nginx Ingress 的监控数据，只需在 `values.yaml` 中打开这个开关即可：

```yaml
commonLabels:
  prom_id: prom-xxx # 通过这个 label 指定 Prometheus 实例的 ID，以便被 Prometheus 实例识别到 ServiceMonitor
controller:
  metrics:
    enabled: true # 专门创建一个 service 给 Prometheus 用作 Nginx Ingress 的服务发现
    serviceMonitor:
      enabled: true # 下发 ServiceMonitor 自定义资源，启用监控采集规则
```

## 集成 Grafana 监控面板

如果你使用了 [腾讯云 Prometheus 监控服务关联 TKE 集群](https://cloud.tencent.com/document/product/1416/72037) 且关联了 [腾讯云 Grafana 服务](https://cloud.tencent.com/product/tcmg) ，可以直接在 Prometheus 集成中心安装 Nginx Ingress 的监控面板：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F22%2F20240322194119.png)

如果是自建的 Grafana，直接将 Nginx Ingress 官方提供的 [Grafana Dashboards](https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards) 中两个监控面板 (json文件) 导入 Grafana 即可。

## 集成 CLS 日志服务

下面介绍如何将 Nginx Ingress Controller 的 access log 采集到 CLS，并结合 CLS 的仪表盘分析日志。

1. 在 `values.yaml` 中配一下 nginx 访问日志的格式，也设置下时区以便时间戳能展示当地时间（增强可读性）：

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

2. 确保集群启用了日志采集功能，参考官方文档 [开启日志采集](https://cloud.tencent.com/document/product/457/83871#.E5.BC.80.E5.90.AF.E6.97.A5.E5.BF.97.E9.87.87.E9.9B.86)。

3. 为 Nginx Ingress Controller 准备好 CLS 日志集和日志主题，如果没有，可以去 [CLS 控制台](https://console.cloud.tencent.com/cls/topic) 根据自己的需求来创建，然后记录下日志主题的 ID。

4. 按照截图指引为日志主题开启索引：
    * 进入日志主题的【索引配置】页面，点击【编辑】：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201551.png)
    * 启用索引，全文分词符为：`@&?|#()='",;:<>[]{}/ \n\t\r\\`：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201658.png)
    * 批量添加索引字段 (与截图中配置保持一致)：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201739.png)
    * 高级设置：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326201802.png)

5. 创建 TKE 日志采集规则：

<Tabs>
  <TabItem value="stdout" label="采集标准输出">
    <FileBlock file="nginx-ingress-logconfig-stdout.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="file" label="采集日志文件">
    <FileBlock file="nginx-ingress-logconfig-files.yaml" showLineNumbers />
  </TabItem>
</Tabs>
    * 必须替换的配置是 `topicId`，即日志主题 ID，表示采集的日志将会吐到该 CLS 日志主题里。
    * 根据自己实际情况选择配置采集标准输出还是日志文件，nginx ingress 默认是将日志输出到标准输出，但也可以像 [日志轮转](high-concurrency.md#日志轮转) 这里介绍的一样将日志落盘到日志文件。

6. 测试一波 Ingress 请求，产生日志数据。
7. 进入日志服务控制台的 [检索分析](https://console.cloud.tencent.com/cls/search) 页面，选择 nginx ingress 所使用的日志主题，确认日志能够被正常检索。
8. 如果一切正常，可以使用日志服务的 [Nginx 访问大盘](https://console.cloud.tencent.com/cls/dashboard/d?templateId=nginx-ingress-access-dashboard&var-ds=&time=now-d,now) 和 [Nginx 监控大盘](https://console.cloud.tencent.com/cls/dashboard/d?templateId=nginx-ingress-monitor-dashboard&var-ds=&time=now-d,now) 两个预置仪表盘并选择 nginx ingress 所使用的日志主题来展示nginx访问日志的分析面板:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203343.png)

    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203353.png)

你甚至还可以直接通过面板来设置告警规则：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F26%2F20240326203154.png)

