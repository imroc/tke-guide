# Using IPv6 on TKE

## Assigning IPv6 Addresses to Pods

Below introduces how to assign IPv6 addresses to Pods in TKE.

### Prerequisites

1. VPC where cluster resides must have IPv6 enabled, and used subnet must obtain IPv6 CIDR.
2. If Pods need scheduling to regular nodes or native nodes, select `IPv4/IPv6 Dual Stack` for cluster IP type during cluster creation.

### Enabling IPv6 for VPC and Subnet

In [VPC](https://console.cloud.tencent.com/vpc/vpc) page, select cluster's VPC, click **More**-**Edit IPv6 CIDR**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164608.png)

Then click **Get**:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164416.png)

Then in [Subnet](https://console.cloud.tencent.com/vpc/subnet) page, select VPC, then click **More**-**Get IPv6 CIDR** for subnets needing IPv6:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709164815.png)

### Using IPv6 with Super Nodes

If IPv6-needed Pods can be scheduled to super nodes, no cluster network requirements - just select subnet with IPv6 CIDR allocated during super node creation, then specify annotation in workload for Pod IPv6 support:

```yaml showLineNumbers
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
      annotations:
        # highlight-start
        tke.cloud.tencent.com/ipv6-attributes: '{"InternetMaxBandwidthOut": 100}'
        tke.cloud.tencent.com/need-ipv6-addr: "true"
        # tke.cloud.tencent.com/ipv6-attributes: '{"BandwidthPackageId":"bwp-xxx","InternetChargeType":"BANDWIDTH_PACKAGE","InternetMaxBandwidthOut":1}' # For bandwidth package, reference this configuration
        # highlight-end
      labels:
        app: nginx
    spec:
      nodeSelector:
        node.kubernetes.io/instance-type: eklet # Force scheduling to super nodes
      containers:
        - image: nginx:latest
          name: nginx
```

### Using IPv6 with Regular or Native Nodes

If Pods schedule to regular or native nodes, need to select operating system supporting `IPv4/IPv6 Dual Stack` when creating `Standard Cluster`, and select **IPv4/IPv6 Dual Stack** for cluster IP type:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F07%2F09%2F20240709165012.png)

Subsequently, any Pods created in cluster will have IPv6.

## Using IPv6 CLB to Expose Services

### Prerequisites

To expose services via IPv6 externally, use IPv6 CLB. IPv6-type CLB's backend addresses must be IPv6, so Pods need IPv6 addresses assigned - method refer to previous **Assigning IPv6 Addresses to Pods**.

### Exposing via LoadBalancer-type Service

Specify using IPv6 CLB via annotations:

```yaml showLineNumbers
apiVersion: v1
kind: Service
metadata:
  name: ipv6-svc
  labels:
    app: foo
  annotations:
    # highlight-add-start
    service.cloud.tencent.com/direct-access: "true"
    service.kubernetes.io/service.extensiveParameters: '{"AddressIPVersion":"IPv6FullChain"}'
    # highlight-add-end
spec:
  type: LoadBalancer
  ports:
  - port: 8000
    protocol: TCP
    targetPort: 8000
  selector:
    app: foo
```

### Exposing via CLB-type Ingress

Specify using IPv6 CLB via annotations:

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # highlight-add-start
    ingress.cloud.tencent.com/direct-access: "true"
    kubernetes.io/ingress.extensiveParameters: '{"AddressIPVersion":"IPv6FullChain"}'
    # highlight-add-end
  name: ipv6-ingress
spec:
  rules:
  - host: example.com
    http:
      paths:
      - backend:
          service:
            name: foo
            port:
              number: 80
        path: /
        pathType: ImplementationSpecific
```