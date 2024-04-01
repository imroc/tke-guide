# 安装多个 NginxIngress

如果要安装多个 Nginx Ingress Controller 实例，需要在 `values.yaml` 指定下 `ingressClassName` (注意不要冲突)：

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
