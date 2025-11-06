# 网络相关

## 弹性网卡

如果集群网络模式是 Global Router，且启用了 VPC-CNI (两种模式混用)，Pod 调度到普通节点默认使用 Global Router 模式，如需要 Pod 用 VPC-CNI (弹性网卡)，需显式指定：

<FileBlock file="nginx-eni.yaml" showLineNumbers />

## EIP

> 更详细的说明请参考 [Pod 绑 EIP](../../networking/pod-eip.md)。

### 声明使用 EIP

<Tabs>
  <TabItem value="eip" label="标准集群写法">
    <FileBlock file="eip/nginx-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="eip-serverless" label="Serverless 集群写法">
    <FileBlock file="eip/nginx-eip-serverless.yaml" showLineNumbers />
  </TabItem>
</Tabs>

### 保留 EIP

<Tabs>
  <TabItem value="retain-eip" label="标准集群写法">
    <FileBlock file="eip/nginx-retain-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="retain-eip-serverless" label="Serverless 集群写法">
    <FileBlock file="eip/nginx-retain-eip-serverless.yaml" showLineNumbers />
  </TabItem>
</Tabs>
