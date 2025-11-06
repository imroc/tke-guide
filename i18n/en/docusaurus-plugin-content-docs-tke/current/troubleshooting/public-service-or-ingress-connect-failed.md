---
sidebar_position: 1
---

# Troubleshooting Public Service or Ingress Connectivity Issues

## Problem Description

Services deployed in TKE clusters using public exposure (LoadBalancer type Service or Ingress) cannot be accessed externally.

## Common Causes

### Node Security Group Not Allowing NodePort Access

If services use TKE's default public Service or Ingress exposure, CLB forwards traffic to NodePort. The traffic forwarding path is: client → CLB → NodePort → ...

CLB forwarded data packets don't perform SNAT, so when packets reach the node, the source IP is the client's public IP. If the node security group inbound rules don't allow client → NodePort traffic, access will fail.

**Solution 1:** Configure node security group inbound rules to allow public access to NodePort range ports (30000-32768):

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162137.png)

**Solution 2:** If concerned about security risks of opening the entire NodePort range, only expose the specific NodePort used by the service (more cumbersome).

**Solution 3:** If only allowing specific IP ranges of clients to access ingressgateway, only open the entire NodePort range for that IP range.

**Solution 4:** Enable CLB direct-to-pod, so traffic bypasses NodePort and avoids this security group issue. Enabling CLB direct-to-pod requires cluster network support for VPC-CNI. For details, refer to [How to Enable CLB Direct-to-Pod](https://imroc.cc/k8s/tke/faq/loadblancer-to-pod-directly/).

### Using ClusterIP Type Service

If using TKE's default CLB Ingress to expose services, it depends on backend Services having NodePort. If the Service is ClusterIP type, it cannot be forwarded and will fail.

**Solution 1:** Change the Service type involved in Ingress to NodePort.

**Solution 2:** Don't use TKE's default CLB Ingress, use other types of Ingress like [Nginx Ingress](https://cloud.tencent.com/document/product/457/50502).