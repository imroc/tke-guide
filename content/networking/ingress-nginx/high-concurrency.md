# 高并发场景优化

## 调大 CLB 规格和带宽

高并发场景的流量吞吐需求较高，对 CLB 的转发性能要求也较高，可以在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 手动创建一个 CLB，实例规格选择性能容量型，型号根据自己需求来选，另外也将带宽上限调高（注意 VPC 要与 TKE 集群一致）。

CLB 创建好后，用 [自定义负载均衡器(CLB)](#自定义负载均衡器clb) 中的方法让 nginx ingress 复用这个 CLB 作为流量入口。

## 调优内核参数与 Nginx 配置

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

## 日志轮转

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
        - name: LOGROTATE_FILE_PATTERN # 轮转的日志文件 pattern，与 nginx 配置的日志文件路径相匹配
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
