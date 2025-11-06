# Integrating Tencent Cloud WAF

## Background

[Tencent Cloud WAF](https://cloud.tencent.com/product/waf) (Web Application Firewall) supports integration with Tencent Cloud Load Balancer (CLB), but requires using Layer 7 listeners (HTTP/HTTPS), while Nginx Ingress uses Layer 4 CLB listeners by default:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401120854.png)

This article mainly describes how to change the CLB listener used by Nginx Ingress to a Layer 7 listener:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401154831.png)

## Using the specify-protocol Annotation

TKE Service supports using the `service.cloud.tencent.com/specify-protocol` annotation to modify the CLB listener protocol. Reference: [Service Extended Protocol](https://cloud.tencent.com/document/product/457/51259).

`values.yaml` configuration example:

```yaml
controller:
  service:
    enableHttp: false # If only HTTPS access is allowed, you can set enableHttp to false to disable the port 80 listener
    targetPorts:
      https: http # Make CLB 443 listener bind to nginx ingress's port 80 (CLB to backend forwards through HTTP by default)
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

* Whatever domains are used in actual Ingress rules also need to be configured in the annotation's `hosts`.
* HTTPS listeners require certificates. First create certificates in [My Certificates](https://console.cloud.tencent.com/ssl), then create a Secret in the TKE cluster (must be in the same namespace as Nginx Ingress). The Secret's Key is `qcloud_cert_id`, and the Value is the corresponding certificate ID. Then reference the secret name in the annotation.
* `targetPorts` needs to point the https port to nginx ingress's port 80 (http), to avoid CLB's 443 traffic being forwarded to nginx ingress's 443 port (which would cause double certificates and forwarding failure).
* If HTTP traffic is not needed, set `enableHttp` to false.

:::tip

If you need to redirect HTTP traffic to HTTPS, you can find the CLB instance used by nginx ingress in the CLB console (the instance ID can be obtained from the nginx ingress controller's service yaml), and manually configure the redirect rule on the instance page:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413111751.png)

:::

## Operation Steps

1. Upload certificates in [My Certificates](https://console.cloud.tencent.com/ssl) and copy the certificate ID.
2. Create the corresponding certificate secret (referencing the certificate ID) in the nginx ingress namespace:
    ```yaml showLineNumbers
    apiVersion: v1
    kind: Secret
    metadata:
      name: cert-secret-test
      namespace: ingress-nginx
    stringData: # Using stringData eliminates the need for manual base64 encoding
      # highlight-next-line
      qcloud_cert_id: E2pcp0Fy # Replace with certificate ID
    type: Opaque
    ```
3. Configure `values.yaml`:
    ```yaml showLineNumbers
    controller: # The following configuration replaces dependent images with mirror images on docker hub to ensure normal pulling in domestic environments
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
4. If needed, automatically redirect HTTP to HTTPS by configuring redirect rules in the CLB console:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413112551.png)
5. Deploy test application and Ingress rules:
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
6. After configuring hosts or DNS resolution, test if functionality is normal:
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413115358.png)
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F13%2F20240413115447.png)

## Configuring WAF

After Nginx Ingress is configured, if you confirm that the corresponding CLB listener has been changed to HTTP/HTTPS, the prerequisites for Nginx Ingress integration with WAF are met. You can then follow the guidance in [WAF Official Documentation](https://cloud.tencent.com/document/product/627/40765) to configure and complete Nginx Ingress WAF integration.
