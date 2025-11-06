# High Concurrency Scenario Optimization

## Overview

This article describes how to tune Nginx Ingress configuration for high concurrency scenarios.

## Increasing CLB Specification and Bandwidth

High concurrency scenarios have high traffic throughput requirements and high demands on CLB forwarding performance. You can manually create a CLB in the [CLB Console](https://console.cloud.tencent.com/clb/instance), select performance capacity type for instance specification, choose the model according to your needs, and also increase the bandwidth limit (note that VPC must be consistent with the TKE cluster).

After the CLB is created, use the method in [Customizing Cloud Load Balancer (CLB)](./clb.md) to make nginx ingress reuse this CLB as the traffic entry point.

## Tuning Kernel Parameters and Nginx Configuration

For high concurrency scenarios, tune kernel parameters and nginx's own configuration. Configuration method in `values.yaml`:

```yaml
controller:
  extraInitContainers:
    - name: sysctl
      image: busybox
      imagePullPolicy: IfNotPresent
      securityContext:
        privileged: true
      command:
        - sh
        - -c
        - |\n          sysctl -w net.core.somaxconn=65535 # Increase connection queue to prevent overflow
          sysctl -w net.ipv4.ip_local_port_range="1024 65535" # Expand source port range to prevent port exhaustion
          sysctl -w net.ipv4.tcp_tw_reuse=1 # TIME_WAIT reuse to avoid inability to create new connections after port exhaustion
          sysctl -w fs.file-max=1048576 # Increase file handle count to prevent file handle exhaustion from too many connections
  config:
    # Number of requests a long connection between nginx and client can handle, default 100. Recommended to increase for high concurrency, but too high may cause load imbalance after nginx ingress scaling.
    # Reference: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#keep-alive-requests
    keep-alive-requests: "1000"
    # Maximum idle connections (not maximum connections) that nginx maintains with upstream, default 320. Increase in high concurrency scenarios to avoid TIME_WAIT spikes from frequent connection establishment.
    # Reference: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#upstream-keepalive-connections
    upstream-keepalive-connections: "2000"
    # Maximum number of connections each worker process can open, default 16384.
    # Reference: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#max-worker-connections
    max-worker-connections: "65536"
```

> Reference: [Nginx Ingress High Concurrency Practice](https://cloud.tencent.com/document/product/457/48142).

## Log Rotation

Nginx Ingress prints logs to container standard output by default, logs are automatically managed by the container runtime, which may lead to high CPU usage in high concurrency scenarios.

The solution is to output Nginx Ingress logs to log files, then use a sidecar to automatically rotate log files to avoid filling up disk space.

Configuration method in `values.yaml`:

```yaml
controller:
  config:
    # Write nginx logs to log files to avoid excessive CPU usage in high concurrency
    access-log-path: /var/log/nginx/nginx_access.log
    error-log-path: /var/log/nginx/nginx_error.log
  extraVolumes:
    - name: log # Controller mounts log directory
      emptyDir: {}
  extraVolumeMounts:
    - name: log # Logrotate and controller share log directory
      mountPath: /var/log/nginx
  extraContainers: # Logrotate sidecar container for log rotation
    - name: logrotate
      image: imroc/logrotate:latest # https://github.com/imroc/docker-logrotate
      imagePullPolicy: IfNotPresent
      env:
        - name: LOGROTATE_FILE_PATTERN # Log file pattern to rotate, matching nginx configured log file paths
          value: "/var/log/nginx/nginx_*.log"
        - name: LOGROTATE_FILESIZE # File size threshold for rotation
          value: "100M"
        - name: LOGROTATE_FILENUM # Number of rotations for each log file
          value: "3"
        - name: CRON_EXPR # Crontab expression for logrotate periodic execution, here once per minute
          value: "*/1 * * * *"
        - name: CROND_LOGLEVEL # crond log level, 0~8, smaller means more detailed
          value: "8"
      volumeMounts:
        - name: log
          mountPath: /var/log/nginx
```
