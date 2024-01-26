# 工作负载

## 测试 nginx 服务

<Tabs>
  <TabItem value="without-service" label="Deployment">
    <FileBlock file="nginx.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="with-service" label="Deployment+Service">
    <FileBlock file="nginx-with-service.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 调度

<Tabs>
  <TabItem value="eklet" label="调度到超级节点">
    <FileBlock file="nginx-eklet.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="instance-type" label="调度指定机型">
    <FileBlock file="nginx-instance-type.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 弹性网卡

如果集群网络模式是 Global Router，且启用了 VPC-CNI (两种模式混用)，Pod 调度到普通节点默认使用 Global Router 模式，如需使用 VPC-CNI (弹性网卡)，需显式指定：

<FileBlock file="nginx-eni.yaml" showLineNumbers />

## EIP (弹性公网IP)

<Tabs>
  <TabItem value="eip" label="声明使用 EIP">
    <FileBlock file="nginx-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="retain" label="保留 EIP">
    <FileBlock file="nginx-retain-eip.yaml" showLineNumbers />
  </TabItem>
</Tabs>
