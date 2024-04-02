# 策略实践：只允许部分账号创建公网 Ingress

## 创建策略

使用 kubectl apply 以下两个 YAML：

<Tabs>
  <TabItem value="template" label="ConstraintTemplate">
    <FileBlock file="opa/block-public-ingress-constraint-template.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="constraint" label="Constraint">
    **注意修改高亮部分**
    <FileBlock file="opa/block-public-ingress-constraint.yaml" showLineNumbers />
  </TabItem>
</Tabs>

## 创建 Ingress 注意事项

1. 如果在控制台创建 Ingress，且集群是当前子账号创建的，会使用 admin 权限，将不受此策略限制。
2. 如果通过 kubectl 创建，获取 kubeconfig 时也需要使用子账号的 kubeconfig。

## 效果

如果使用的子账号不在 `allowedUins` 列表中，创建公网 Ingress 时将会报错。

控制台报错：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F02%2F20240402173609.png)

kubectl apply 报错：

```text
Error from server (Forbidden): error when creating "STDIN": admission webhook "validation.gatekeeper.sh" denied the request: [block-public-ingress] User '100009022548' is not allowed to create Ingress resources
```
