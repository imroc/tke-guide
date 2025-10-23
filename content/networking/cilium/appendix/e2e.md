# E2E 测试

## 概述

cilium 早期使用 ginkgo 框架做 e2e 测试，参考 [End-To-End Testing Framework (Legacy)](https://docs.cilium.io/en/stable/contributing/testing/e2e_legacy/)，后来将 e2e 测试做到了 cilium-cli 中，本文介绍如何使用 cilium-cli 在现有的 k8s 集群中跑 cilium 的 e2e 测试，以判断当前环境的 cilium 是否可以正常工作。

## 测试方法

首先确保在 TKE 集群在海外，避免拉不到测试依赖的容器镜像，然后确保 TKE 集群中已经安装了 cilium，且节点有公网，然后执行以下命令：

- `cilium connectivity test`: 用于测试 cilium 的功能在当前环境能否正常工作。会根据当前环境的 cilium 配置跑 e2e 测试（某些条件不满足时会跳过某些测试，比如 Egress Gateway 特性没启用时就不会测试 Egress Gateway），原理是在集群中下发一些测试 Pod，跑一些 e2e 测试用例，然后搜集测试结果，最后汇总输出在命令行，全部跑完需要较长时间，需耐心等待。
- `cilium connectivity perf`: 用于在当前环境压测 cilium 的性能。

## 参考资料

- [End-To-End Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

