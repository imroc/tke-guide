# Service

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
