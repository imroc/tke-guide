# 调度相关

Kubernetes 的调度配置有 `nodeSelector` 和 `nodeAffinity` 两种方式，其中 `nodeSelector` 是最简单的，而 `nodeAffinity` 则更灵活强大，本文涉及的例子，两种方式均会提供。

## 只调度到超级节点

如果集群中有超级节点和非超级节点，又希望将 Pod 只调度到超级节点上，可以这样配置：

<Tabs>
  <TabItem value="nginx-eklet-nodeselector" label="nodeSelector 写法">
    <FileBlock file="scheduling/nginx-eklet-nodeselector.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="nginx-eklet-nodeaffinity" label="nodeAffinity 写法">
    <FileBlock file="scheduling/nginx-eklet-nodeaffinity.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 调度到指定机型

节点可能有多种机型，如果希望将 Pod 调度到指定机型的节点上，可以这样配置：

<Tabs>
  <TabItem value="nginx-eklet-nodeselector" label="nodeSelector 写法">
    <FileBlock file="scheduling/nginx-instance-type-nodeselector.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="nginx-eklet-nodeaffinity" label="nodeAffinity 写法">
    <FileBlock file="scheduling/nginx-instance-type-nodeaffinity.yaml" showLineNumbers />
  </TabItem>
</Tabs>

前面说的节点不包含超级节点，因为超级节点是个虚拟的节点，并不是实体节点，可以认为底层是个无限大的计算资源池，调度到超级节点上的 Pod，分配的机器是随机的，机型也是随机的。

如果 Pod 一定要在超级节点，且业务对机型又有要求，也可以用如下注解显式声明超级节点中的 Pod 的机型：

<FileBlock file="scheduling/nginx-cpu-type-supernode.yaml" showLineNumbers />