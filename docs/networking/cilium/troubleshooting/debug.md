# Cilium 调试技巧

## 查看 cilium 功能状态

查看当前部署的 cilium 的各项功能实际状态：

<Tabs>
  <TabItem value="1" label="简洁">

```bash
kubectl exec ds/cilium -- cilium status
```

  </TabItem>
  <TabItem value="2" label="详细">

```bash
kubectl exec ds/cilium -- cilium status --verbose
```

  </TabItem>
</Tabs>

## 监控指定节点的 cilium 网络

<Tabs>
  <TabItem value="bash" label="bash">

```bash
NODE=172.22.48.23
POD=$(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium monitor
```

  </TabItem>

  <TabItem value="fish" label="fish">

```bash
set NODE 172.22.48.23
set POD $(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium monitor
```

:::info[注意]

替换 `NODE` 的值为实际需要监控的节点名称。

:::

  </TabItem>
</Tabs>
