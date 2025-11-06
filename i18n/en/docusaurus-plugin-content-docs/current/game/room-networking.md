---
sidebar_position: 2
---

# Room-Based Game Network Access

## Network Model

For games that require room creation, we typically need to assign an independent public address (`IP:Port`) for each room. After successful player matching, players are assigned to the same room, and before the game starts, game clients connect to the room through this public address:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822161108.png)

Below we introduce methods for assigning independent public addresses for each room in TKE.

## EIP Solution

TKE supports binding EIPs to Pods. Each Pod is assigned an independent public IP, and the room's public address becomes the Pod's EIP + the port number monitored by the room process.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822172226.png)

Configuration method reference: [Pod Binding EIP](../networking/pod-eip.md).

## CLB Mapping Solution

Install the [tke-extend-network-controller](https://github.com/tkestack/tke-extend-network-controller) plugin to implement public address mapping for each Pod using CLB layer 4 listeners. Each Pod occupies one port on the CLB, and the room's public address within the Pod becomes the public IP or domain name of the CLB instance bound to the Pod, along with the corresponding listener port number.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822165733.png)

Installation and configuration method reference: [Using CLB to Assign Public Address Mapping for Pods](clb-pod-mapping.md).

## Solution Comparison and Selection

| Solution | Cost | Resource Consumption | Usage Limitations |
| -------- | ---- | -------------------- | ----------------- |
| EIP | IP resource fees (charged when idle) + network fees, refer to [EIP Billing Overview](https://cloud.tencent.com/document/product/1199/41692) | One EIP can only bind to one Pod, requiring more EIP resources | EIP resources are relatively limited, with application quantity limits and daily application frequency limits (refer to [EIP Quota Limits](https://cloud.tencent.com/document/product/1199/41648#eip-.E9.85.8D.E9.A2.9D.E9.99.90.E5.88.B6)), making it less suitable for large-scale use |
| CLB Mapping | Instance fees + network fees, refer to [CLB Billing Overview](https://cloud.tencent.com/document/product/214/42934) | One CLB can bind to many Pods, controllable CLB instance consumption | CLB has listener quantity and instance quantity quota limits, mainly listener quantity limits (default 50), meaning a single CLB can map addresses for 50 Pods (refer to [CLB General Limits](https://cloud.tencent.com/document/product/214/6187)), but these limits can be adjusted based on demand through support tickets, making it suitable for large-scale use |