# Policy Practice: Only Allow Specific Accounts to Create Public Ingress

## Creating Policy

Use kubectl apply for the following two YAMLs:

<Tabs>
  <TabItem value="template" label="ConstraintTemplate">
    <FileBlock file="opa/block-public-ingress-constraint-template.yaml" showLineNumbers title="constraint-template.yaml"/>
  </TabItem>
  <TabItem value="constraint" label="Constraint">
    **Note: Modify highlighted parts**
    <FileBlock file="opa/block-public-ingress-constraint.yaml" showLineNumbers title="constraint.yaml" />
  </TabItem>
</Tabs>

## Creating Ingress Notes

1. If creating Ingress through console, and cluster created by current sub-account, will use admin permissions, not restricted by this policy.
2. If creating via kubectl, need sub-account's kubeconfig when obtaining kubeconfig.

## Effect

If used sub-account not in `allowedUins` list, creating public Ingress will report error.

Console error:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F02%2F20240402173609.png)

kubectl apply error:

```text
Error from server (Forbidden): error when creating "STDIN": admission webhook "validation.gatekeeper.sh" denied the request: [block-public-ingress] User '100009022548' is not allowed to create Ingress resources
```