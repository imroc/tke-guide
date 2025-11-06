# Installing Multiple Nginx Ingress Controllers

## Overview

If you need to deploy multiple Nginx Ingress Controllers, i.e., different Ingress rules may use different traffic entry points:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401143628.png)

You can deploy multiple Nginx Ingress Controllers for the cluster, with different Ingress resources specifying different `ingressClassName` to achieve this.

This article describes the configuration method for installing multiple Nginx Ingress Controllers.

## Configuration Method

If you want to install multiple Nginx Ingress Controllers, you need to specify `ingressClass` in `values.yaml` (note to avoid conflicts):

```yaml showLineNumbers
controller:
  # highlight-next-line
  ingressClass: prod
  ingressClassResource:
    # highlight-next-line
    name: prod
    # highlight-next-line
    controllerValue: k8s.io/ingress-prod
```

:::tip

All three fields need to be changed together.

:::

Additionally, the release names for multiple instances cannot be the same as already installed ones, **even if the namespaces are different, release names cannot be the same** (to avoid ClusterRole conflicts). Example:

```bash
helm upgrade --install prod ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

When creating Ingress resources, also specify the corresponding `ingressClassName`:

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
