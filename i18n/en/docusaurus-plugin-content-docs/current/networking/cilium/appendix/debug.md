# Cilium Debugging Tips

## Check Cilium Feature Status

Check the actual status of various cilium features in the current deployment:

<Tabs>
  <TabItem value="1" label="Summary">

```bash
kubectl exec ds/cilium -- cilium status
```

  </TabItem>
  <TabItem value="2" label="Verbose">

```bash
kubectl exec ds/cilium -- cilium status --verbose
```

  </TabItem>
</Tabs>

## Monitor Cilium Network on a Specific Node

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

  </TabItem>
</Tabs>

:::info[Note]

Replace `NODE` with the actual name of the node you want to monitor.

:::
