# Customizing Cloud Load Balancer (CLB)

## Overview

By default, installation will automatically create a public CLB for traffic access, but you can also use TKE Service annotations to customize the CLB of Nginx Ingress Controller. This article describes the customization methods.

## Using Internal CLB

For example, to change to internal CLB, define it in `values.yaml` as follows:

```yaml showLineNumbers
controller:
  service:
    annotations:
      service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: 'subnet-xxxxxx' # Internal CLB requires specifying the subnet ID where the CLB instance is located
```

## Using Existing CLB

You can also create a CLB directly in the [CLB Console](https://console.cloud.tencent.com/clb/instance) according to your needs (such as customizing instance specifications, operator type, billing mode, bandwidth limit, etc.), and then reuse this CLB with an annotation in `values.yaml`:

```yaml showLineNumbers
controller:
  service:
    annotations:
      service.kubernetes.io/tke-existed-lbid: 'lb-xxxxxxxx' # Specify the instance ID of the existing CLB
```

> Reference documentation: [Service Using Existing CLB](https://cloud.tencent.com/document/product/457/45491).

:::info[Note]

When creating a CLB instance in the CLB console, the selected VPC must be consistent with the cluster.

:::

## Accessing Both Public and Internal IPs Simultaneously

Sometimes you need nginx ingress to use both public and internal IPs for traffic access. There are two solutions to achieve this.

### Solution 1: Dual Service

The first approach is to configure nginx ingress with two services. By default, one public CLB Service is created. If you also need an internal CLB Service, you can configure the internal service:

```yaml showLineNumbers
controller:
  service:
    internal:
      # highlight-start
      enabled: true # Create internal CLB Service
      annotations:
        service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-xxxxxxxx" # Configure subnet for internal CLB
      # highlight-end
```

### Solution 2: Internal CLB Binding EIP

Another approach is to [use internal CLB](#using-internal-clb), then go to the CLB console and bind an EIP to the CLB (refer to CLB official documentation: [Internal Load Balancer Instance Binding EIP](https://cloud.tencent.com/document/product/214/65682)).

:::tip[Note]

This feature is a beta feature of CLB and requires submitting a ticket to apply for activation.

:::

## CLB Cross-Region Binding

If you want to use a CLB from another region or VPC for traffic access, you can use CLB's [Cross-Region Binding 2.0](https://cloud.tencent.com/document/product/214/48180) and TKE's [Service Cross-Region Binding](https://cloud.tencent.com/document/product/457/59094) capabilities. The following prerequisites must be met:
1. The account is of bandwidth upper shift type.
2. The two VPCs are connected through CCN.
3. CLB's cross-region binding 2.0 feature is enabled (apply via ticket).

Then configure the CLB ID, region, and VPC information in the annotations:

```yaml showLineNumbers
controller:
  service:
    # highlight-start
    annotations:
      service.cloud.tencent.com/cross-region-id: "ap-guangzhou"  # If CLB is in another region, specify the region where CLB is located
      service.cloud.tencent.com/cross-vpc-id: "vpc-xxx" # Specify the VPC where CLB is located
      service.kubernetes.io/tke-existed-lbid: "lb-xxx" # If using an existing CLB, specify the CLB ID
    # highlight-end
```
