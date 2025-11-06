---
sidebar_position: 1
---

# Using CLB to Assign Public Address Mapping for Pods

## Overview

Room-based games generally require each room to have an independent public address. TKE clusters by default only support the EIP solution, but EIP resources are limited with application quantity limits and daily application frequency limits (refer to [EIP Quota Limits](https://cloud.tencent.com/document/product/1199/41648#eip-.E9.85.8D.E9.A2.9D.E9.99.90.E5.88.B6)). At a certain scale, or with frequent scaling and EIP replacement, it's easy to hit these limits causing EIP allocation failures. Additionally, if EIPs are retained, they incur idle fees when not bound.

> For TKE Pod EIP binding, refer to [Pod Binding EIP](https://imroc.cc/tke/networking/pod-eip).
>
> For detailed comparison between EIP and CLB mapping solutions, refer to [TKE Gaming Solution: Room-Based Game Network Access](https://imroc.cc/tke/game/room-networking).

Besides the EIP solution, you can also use the `tke-extend-network-controller` plugin solution. This article introduces how to use the `tke-extend-network-controller` plugin to assign independent public address mappings (public `IP:Port` to internal Pod `IP:Port` mappings) for each Pod's specified ports.

> The `tke-extend-network-controller` code is open source, hosted on GitHub: https://github.com/tkestack/tke-extend-network-controller

## Installing tke-extend-network-controller

Refer to [Installing tke-extend-network-controller](../networking/tke-extend-network-controller).

## Ensuring Pods Schedule to Native Nodes or Super Nodes

To use CLB's capability to assign public address mappings for Pods, you need to ensure that the Pods carrying game rooms are scheduled to native nodes or super nodes. If Pods are on regular nodes (CVM), they will not be assigned CLB public address mappings.

## Using CLB Port Pool for Pod Public Address Mapping

Refer to [Using CLB Port Pool for Pod Public Address Mapping](https://github.com/tkestack/tke-extend-network-controller/blob/main/docs/clb-port-pool.md).