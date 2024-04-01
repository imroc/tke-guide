# 安装多个 Nginx Ingress Controller

## 概述

如果你需要部署多个 Nginx Ingress Controller，即希望不同的 Ingress 规则可能使用不同的流量入口：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401141614.png)

你可以为集群部署多个 Nginx Ingress Controler，不同的 Ingress 指定不同的 `ingressClassName` 来实现。

本文介绍安装多个 Nginx Ingress Controller 的配置方法。

## 配置方法

如果要安装多个 Nginx Ingress Controller，需要在 `values.yaml` 指定下 `ingressClassName` (注意不要冲突)：

```yaml
controller:
  ingressClassName: prod
  ingressClassResource:
    name: prod
```

> 两个字段需同时改。

另外多实例的 release 名称也不能与已安装的相同，示例：

```bash
helm upgrade --install prod ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

创建 Ingress 资源时也指定对应的 `ingressClassName`：

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  # highlight-next-line
  ingressClassName: prod
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```