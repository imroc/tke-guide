# Service

## 测试 Service

<FileBlock file="nginx-service.yaml" showLineNumbers />

## CLB 直连 Pod

<FileBlock file="nginx-service-direct-access.yaml" showLineNumbers />

## 使用已有 CLB

<Tabs>
  <TabItem value="single" label="使用已有 CLB">
    让 Service 使用指定已经创建好的 CLB:
    <FileBlock file="nginx-service-reuse.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="multi" label="多个 Service 复用同一个 CLB">
    多个 Service 可以使用同一个 CLB (前提是端口不冲突):
    <FileBlock file="nginx-service-reuse.yaml" showLineNumbers />
    <FileBlock file="nginx2-service-reuse.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 指定 CLB 属性

<Tabs>
  <TabItem value="subnet" label="内网 CLB">
    默认创建的 CLB 是公网类型，如果要内网类型，需传入子网 ID：
    <FileBlock file="nginx-service-subnet.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="multi-zone" label="多可用区">
    <FileBlock file="nginx-service-multi-zone.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="vip" label="指定 VIP">
    指定 CLB 要使用的 VIP（误删恢复时很有用），前提是 VIP 还没有被占用:
    <FileBlock file="nginx-service-vip.yaml" showLineNumbers />
  </TabItem>
</Tabs>

