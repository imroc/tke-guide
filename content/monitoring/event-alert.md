# 统一配置事件告警


## Kubenretes 事件日志

Kubenretes 的资源会产生事件日志，分 Normal 和 Warning 两类，其中 Normal 类型是一般的事件日志，比如 Pod 调度成功，拉取镜像等；Warning 类型是异常事件日志，比如 Pod 启动失败，Node 磁盘紧张等。

事件日志是 Kubernetes 提供的标准接口，除了 Kubernetes 自身组件会产生事件日志外，其它组件也可以通过相同方式发送事件日志给 Kubernetes 集群，比如 cert-manager：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331200805.png)

## 采集事件日志

TKE 支持一键开启事件日志采集，将 Kubernetes 事件日志采集到 CLS 中进行存储、检索和告警，详情请参考 [集群运维：事件日志](https://cloud.tencent.com/document/product/457/32091)。

## 配置事件日志告警

通常我们重点关注 Warning 类型的日志，可以统一配置事件日志告警。

操作步骤：
1. 在 [告警策略](https://console.cloud.tencent.com/cls/alarm/list) 页面单击**新建**。
2. **监控对象** 选择 TKE 集群事件日志的日志主题。
3. **执行语句** 填写 `event.type:Warning`。
4. **附加通知内容**:

```txt
{{- range .QueryLog }}
集群 cls-xxxxxxxx 发生异常事件:
  {{- range . }}
    {{.content.event.reason}} {{ .content.event.involvedObject.kind }}/{{ .content.event.involvedObject.name }} {{ .content.event.message }}
  {{- end}}
{{- end}}
```

> 注意替换下集群 ID。

其余配置项可按需配置。

## 告警效果

邮件告警：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331204018.png)

微信告警：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F03%2F31%2F20250331204531.png)

## 参考资料

- [TKE实践教程：使用 CLS 告警异常资源](https://cloud.tencent.com/document/product/457/82037)
