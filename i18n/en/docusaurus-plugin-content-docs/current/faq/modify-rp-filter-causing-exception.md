---
sidebar_position: 3
---

# Network Exception Caused by Modifying rp_filter

## Background

If TKE uses VPC-CNI network mode, the node's rp_filter will be disabled:

```bash
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.eth0.rp_filter=0
```

If for some reason, rp_filter is enabled (parameter set to 1), it will cause various abnormal phenomena. Troubleshooting will reveal network connectivity issues, and the cause is that rp_filter has been enabled.

## Under What Circumstances Might It Be Enabled?

Usually, there are two reasons:
1. Custom initialization scripts have been added to the node, modifying default kernel parameters and enabling rp_filter.
2. [Custom images](https://cloud.tencent.com/document/product/457/39563) are used, and custom kernel parameters in the custom image have enabled rp_filter.

## Why Does Enabling rp_filter Cause Connectivity Issues?

rp_filter is a switch that controls whether the kernel validates the source address of data packets. If enabled, when the path for sending and receiving data packets is different, packets will be discarded, mainly to prevent DDoS or IP spoofing. In TKE VPC-CNI network implementation mechanism, when pods communicate directly with IPs outside the VPC CIDR, data packets are sent through separate elastic network interfaces but received through the primary network interface (eth0). If rp_filter is enabled, this will cause network connectivity issues.

Summary of common scenarios:
1. Pods accessing the internet (public destination IPs are outside the VPC CIDR)
2. Using public [Enable CLB Direct-to-Pod](../networking/clb-to-pod-directly) (public source IPs are outside the VPC CIDR)
3. Pods accessing apiserver (169 IPs are outside the VPC CIDR)