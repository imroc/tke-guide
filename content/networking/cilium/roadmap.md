# Roadmap

- [x] 概述
- [x] 适配自建 cilium 的 TKE 集群创建指引
- [x] 适配自建 cilium 的节点池创建指引：原生节点池、普通节点池、Karpenter 节点池
- [x] 核心：支持使用 TKE VPC-CNI 共享网卡模式集群自建单集群 cilium
- [x] 常见问题
- [x] e2e 功能测试，确保各项功能没有问题
- [x] Egress Gateway
- [x] NetworkPolicy 应用实践
- [ ] 使用 Cilium 增强可观测性
- [ ] TKE 侧适配：ipamd 默认容忍 cilium 污点
- [ ] TKE 侧适配：tke-eni-agent 避开使用 cilium 的路由表 ID （2003/2004）
- [ ] e2e 性能测试
- [ ] 与 kube-proxy 共存方案
- [ ] 与 istio 共存方案
- [ ] 支持使用 ENI Trunking 网络模式自建 cilium
- [ ] Cilium 多集群组网（Cluster Mesh）
- [ ] Cilium [Multi-Cluster Services](https://docs.cilium.io/en/latest/network/clustermesh/mcsapi/)
- [ ] Gateway API 启用
