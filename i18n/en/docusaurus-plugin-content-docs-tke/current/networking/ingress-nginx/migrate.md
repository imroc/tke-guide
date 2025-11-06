# Migrating from TKE Nginx Ingress Plugin to Self-built Nginx Ingress

## Benefits of Migration

What are the benefits of migrating to self-built Nginx Ingress? Nginx Ingress provides many features and configurations that are very flexible and can meet various use scenarios. Self-building can unlock all features of Nginx Ingress, allowing you to customize configurations according to your needs and update versions in a timely manner.

## Migration Strategy

Create a new Nginx Ingress instance and Ingress rules using the self-building method described in this article, allowing both traffic entry points to coexist. Finally, modify DNS to point to the new entry address, completing a smooth migration.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F01%2F20240401143927.png)

## Confirming Installed Nginx Ingress Information

1. First confirm the IngressClass name of the installed Nginx Ingress instance, for example:

```bash
$ kubectl get deploy -A | grep nginx
kube-system            extranet-ingress-nginx-controller           1/1     1            1           216d
```

In this example, there is only one instance. The Deployment name is `extranet-ingress-nginx-controller`, and the IngressClass is the part before `-ingress-nginx-controller`, which is `extranet` here.

2. Then confirm the current nginx ingress image version:

```yaml
$ kubectl -n kube-system get deploy extranet-ingress-nginx-controller -o yaml | grep image:
        image: ccr.ccs.tencentyun.com/tkeimages/nginx-ingress-controller:v1.9.5
```

In this example, the version is `v1.9.5`. Check which chart version corresponds to it:

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions  | grep 1.9.5
ingress-nginx/ingress-nginx     4.9.0           1.9.5           Ingress controller for Kubernetes using NGINX a...
```

Here we see it's `4.9.0`. Remember this version as it will be needed when installing the new version with helm.

## Preparing values.yaml

Configure `values.yaml` below to ensure that the new Nginx Ingress instance created by helm does not share the same IngressClass as the Nginx Ingress instance created by the TKE plugin:

```yaml
controller:
  ingressClass: extranet-new # New IngressClass name to avoid conflicts
  ingressClassResource:
    name: extranet-new
    enabled: true
    controllerValue: k8s.io/extranet-new
```

## Installing New Nginx Ingress Controller

```bash
helm upgrade --install new-extranet-ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version 4.9.0 \
  -f values.yaml
```

* Avoid having the release name with `-controller` suffix match the existing Nginx Ingress Deployment name, mainly because the same named ClusterRole would exist causing helm installation failure.
* Specify the chart version obtained in the previous step (the chart version corresponding to the current nginx ingress instance version) with version.

Get the traffic entry point of the new Nginx Ingress:

```bash
$ kubectl -n ingress-nginx get svc
NAME                                              TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
new-extranet-ingress-nginx-controller             LoadBalancer   172.16.165.100   43.136.214.239   80:31507/TCP,443:31116/TCP   9m37s
```

`EXTERNAL-IP` is the new traffic entry point. Verify and confirm that it can forward normally.

## Copying Ingress Resources

Save the YAML files of Ingress resources using the old IngressClass and modify their names (for example, add the suffix `-new`). Then apply the modified YAML files to the cluster. This way, the forwarding rules of the new and old Nginx Ingress instances will remain consistent, ensuring that the traffic effect is the same when entering through either entry point.

## Switching DNS

At this point, the new and old Nginx Ingress coexist, and traffic can be forwarded normally through either traffic entry point.

Next, modify the domain's DNS resolution to point to the new Nginx Ingress traffic entry point. Before DNS resolution is fully effective, both traffic entry points can forward normally. Regardless of which traffic entry point is used, forwarding works properly. This process will be very smooth, and production environment traffic will not be affected.

## Deleting Old Nginx Ingress Instance and Plugin

Finally, when the old Nginx Ingress instance has completely no traffic, go to the TKE console to delete the Nginx Ingress instance:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F28%2F20240328105512.png)

Then go to **Component Management** to delete `ingressnginx` to completely finish the migration:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F28%2F20240328104308.png)
