# Overview

[Cilium](https://cilium.io/) is an open-source cloud-native networking solution that provides advanced networking capabilities for Kubernetes clusters.

This series of practical tutorials will describe how to install and use Cilium on TKE clusters according to your specific requirements.

## Native Routing

Cilium supports two routing modes:
1. `Encapsulation` (Encapsulation Mode): Adds an additional layer of network encapsulation on top of the existing network for forwarding. The advantage is good compatibility and adaptability to various network environments, but the performance is relatively poor.
2. `Native-Routing` (Native Routing): Pod IPs are directly routed on the underlying network, and Cilium doesn't handle it. The advantage is excellent performance, but it depends on the underlying network's support for Pod IP routing and is not universal.

In cloud-hosted Kubernetes clusters including TKE, the VPC underlying network already supports Pod IP routing forwarding, eliminating the need for an additional overlay layer, thus achieving optimal network performance. Therefore, Cilium is typically installed using the `Native-Routing` mode, and the installation methods described in this tutorial series also use the `Native-Routing` mode.

> For more details, refer to the official Cilium documentation: [Routing](https://docs.cilium.io/en/stable/network/concepts/routing/).

## Prerequisites

To install Cilium on a TKE cluster, the following prerequisites must be met:
- Cluster Version: TKE 1.30 and above, refer to [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/).
- Network Mode: VPC-CNI with shared ENI multiple IPs.
- Node Type: Regular nodes or native nodes.
- Operating System: TencentOS 4 or Ubuntu >=22.04.
