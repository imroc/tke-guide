# 接入腾讯云 WAF

## 背景

[腾讯云 WAF](https://cloud.tencent.com/product/waf) (Web 应用防火墙) 支持接入腾讯云负载均衡（CLB），但需要使用七层的监听器（HTTP/HTTPS），而 Nginx Ingress 默认使用四层的 CLB 监听器：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401120854.png)

本文主要介绍将 Nginx Ingress 所使用的 CLB 监听器改为七层监听器：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401154831.png)

## 使用 specify-protocol 注解

TKE 的 Service 支持使用 `service.cloud.tencent.com/specify-protocol` 这个注解来修改 CLB 监听器协议，参考 [Service 扩展协议](https://cloud.tencent.com/document/product/457/51259)。

`values.yaml` 配置示例：

```yaml
controller:
  service:
    enableHttp: false # 如果只允许 HTTPS 访问，可以置为 false 来禁用 80 监听器
    targetPorts:
      https: http # 让 CLB 443 监听器绑后端 nginx ingress 的 80 （CLB 到后端默认通过 HTTP 转发）
    annotations:
      service.cloud.tencent.com/specify-protocol: |
        {
          "80": {
            "protocol": [
              "HTTP"
            ],
            "hosts": {
              "a.example.com": {},
              "b.example.com": {}
            }
          },
          "443": {
            "protocol": [
              "HTTPS"
            ],
            "hosts": {
              "a.example.com": {
                "tls": "cert-secret-a"
              },
              "b.example.com": {
                "tls": "cert-secret-b"
              }
            }
          }
        }
```

* 实际 Ingress 规则里用到了哪些域名，也需要在注解里的 `hosts` 配一下。
* HTTPS 监听器需要证书，先在 [我的证书](https://console.cloud.tencent.com/ssl) 里创建好证书，然后在 TKE 集群中创建 Secret (需在 Nginx Ingress 所在命名空间)，Secret 的 Key 为 `qcloud_cert_id`，Value 为对应的证书 ID，然后在注解里引用 secret 名称。
* `targetPorts` 需要将 https 端口指向 nginx ingress 的 80 (http)，避免 CLB 的 443 流量转到 nginx ingress 的 443 端口（会导致双重证书，转发失败）。
* 不需要 HTTP 流量可以将 `enableHttp` 置为 false。

:::tip

如果需要将 HTTP 的流量重定向到 HTTPS，可以在 CLB 控制台找到 nginx ingress 使用的 CLB 实例（实例 ID 可通过查看 nginx ingress controller 的 service 的 yaml 获取），在实例页面手动配置下重定向规则：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413111751.png)

:::

## 操作步骤

1. 在 [我的证书](https://console.cloud.tencent.com/ssl) 里上传证书并复制证书 ID。
2. 在 nginx ingress 所在 namespace 创建对应的证书 secret（引用证书 ID）:
    ```yaml showLineNumbers
    apiVersion: v1
    kind: Secret
    metadata:
      name: cert-secret-test
      namespace: ingress-nginx
    stringData: # 用 stringData 就不需要手动 base64 转码
      # highlight-next-line
      qcloud_cert_id: E2pcp0Fy
    type: Opaque
    ```
3. 配置 `values.yaml`:
    ```yaml showLineNumbers
    controller: # 以下配置将依赖镜像替换为了 docker hub 上的 mirror 镜像以保证在国内环境能正常拉取
      image:
        registry: docker.io
        image: k8smirror/ingress-nginx-controller
      admissionWebhooks:
        patch:
          image:
            registry: docker.io
            image: k8smirror/ingress-nginx-kube-webhook-certgen
      defaultBackend:
        image:
          registry: docker.io
          image: k8smirror/defaultbackend-amd64
      opentelemetry:
        image:
          registry: docker.io
          image: k8smirror/ingress-nginx-opentelemetry
      service:
        enableHttp: false
        targetPorts:
          https: http
        annotations:
          service.cloud.tencent.com/specify-protocol: |
            {
              "80": {
                "protocol": [
                  "HTTP"
                ],
                "hosts": {
                  "test.example.com": {}
                }
              },
              "443": {
                "protocol": [
                  "HTTPS"
                ],
                "hosts": {
                  "test.example.com": {
                    "tls": "cert-secret-test"
                  }
                }
              }
            }
    ```
4. 如果需要，将 HTTP 自动重定向到 HTTPS，去 CLB 控制台配置下重定向规则：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413112551.png)
5. 部署测试应用和 Ingress 规则：
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      labels:
        app: nginx
      name: nginx
    spec:
      ports:
        - port: 80
          protocol: TCP
          targetPort: 80
      selector:
        app: nginx
      type: NodePort
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: nginx
      template:
        metadata:
          labels:
            app: nginx
        spec:
          containers:
            - image: nginx:latest
              name: nginx
    ---
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: nginx
    spec:
      ingressClassName: nginx
      rules:
        - host: test.example.com
          http:
            paths:
              - backend:
                  service:
                    name: nginx
                    port:
                      number: 80
                path: /
                pathType: Prefix
    ```
6. 配置 hosts 或域名解析后，测试功能是否正常：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413115358.png)
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413115447.png)

## 配置 WAF

Nginx Ingress 配置好后，如果确认对应的 CLB 监听器已经改为了 HTTP/HTTPS，至此 Nginx Ingress 接入 WAF 的前提条件就算是满足了，接下来就可以根据 [WAF 官方文档](https://cloud.tencent.com/document/product/627/40765) 的指引来进行配置，最终完成 Nginx Ingress 的 WAF 接入。
