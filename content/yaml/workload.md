# 工作负载

## 测试 nginx 服务

<Tabs>
  <TabItem value="with-service" label="Deployment+Service">
    <FileBlock file="nginx-with-service.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="without-service" label="Deployment">
    <FileBlock file="nginx.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 网卡和 IP

<Tabs>
  <TabItem value="eni" label="声明弹性网卡(VPC-CNI)">
    如果集群网络模式是 Global Router，且启用了 VPC-CNI (两种模式混用)，Pod 调度到普通节点默认使用 Global Router 模式，如需使用 VPC-CNI (弹性网卡)，需显式指定：
    <FileBlock file="nginx-eni.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="eip" label="声明使用EIP(弹性公网IP)">
    <FileBlock file="nginx-eip.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="retain" label="保留EIP">
    <FileBlock file="nginx-retain-eip.yaml" showLineNumbers />
  </TabItem>
</Tabs>
