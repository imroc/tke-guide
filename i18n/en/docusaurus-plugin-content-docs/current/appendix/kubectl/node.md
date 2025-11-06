# 节点


## 普通节点与原生节点

### 查看可用区分布

<Tabs>
  <TabItem value="1" label="可用区 ID">

  ```bash
  kubectl get node -o custom-columns=NAME:.metadata.name,ZONE:".metadata.labels.topology\.kubernetes\.io/zone"
  ```

  </TabItem>
  <TabItem value="2" label="可用区名称">

  ```bash
  kubectl get node -o custom-columns=NAME:.metadata.name,ZONE:".metadata.labels.topology\.com\.tencent\.cloud\.csi\.cbs/zone"
  ```

  </TabItem>
</Tabs>

### 查看节点池分布

<Tabs>
  <TabItem value="1" label="原生节点池">

  ```bash
  kubectl get node -o custom-columns=节点名称:.metadata.name,原生节点池:".metadata.labels.node\.tke\.cloud\.tencent\.com/machineset"
  ```
  </TabItem>

  <TabItem value="2" label="普通节点池">

  ```bash
  kubectl get node -o custom-columns=节点名称:.metadata.name,普通节点池:".metadata.labels.tke\.cloud\.tencent\.com/nodepool-id",伸缩组ID:".metadata.labels.cloud\.tencent\.com/auto-scaling-group-id"
  ```

  </TabItem>

  <TabItem value="3" label="通用">

  ```bash
  kubectl get node -o custom-columns=节点名称:.metadata.name,原生节点池:".metadata.labels.node\.tke\.cloud\.tencent\.com/machineset",普通节点池:".metadata.labels.tke\.cloud\.tencent\.com/nodepool-id"
  ```

  </TabItem>
</Tabs>

### 查看节点实例 ID

```bash
kubectl get node -o custom-columns=节点名称:.metadata.name,实例ID:".metadata.labels.cloud\.tencent\.com/node-instance-id"
```

### 查看节点机型分布

```bash
kubectl get node -o custom-columns=节点名称:.metadata.name,机型:".metadata.labels.node\.kubernetes\.io/instance-type"
```

### 查看节点类型分布

检查集群中原生节点和普通节点的分布情况：

```bash
kubectl get node -o custom-columns=节点名称:.metadata.name,节点类型:".spec.providerID"
```

## 超级节点
查看 eks 集群子网剩余 ip 数量:

```bash
kubectl get node -o json | jq -r '.items[] | {subnet: .metadata.annotations."eks.tke.cloud.tencent.com/subnet-id", ip: .metadata.labels."eks.tke.cloud.tencent.com/available-ip-count"} |  "\(.subnet)\t\(.ip)"'
```

查看指定子网剩余 ip 数量:

```bash
# 直接替换子网 id 查
kubectl get node -o json | jq -r '.items[] | select(.metadata.annotations."eks.tke.cloud.tencent.com/subnet-id"=="subnet-1p9zhi9g") | {ip: .metadata.labels."eks.tke.cloud.tencent.com/available-ip-count"} |  "\(.ip)"'

# 使用变量查
subnet="subnet-1p9zhi9g"
kubectl get node -o json | jq -r '.items[] | {subnet: .metadata.annotations."eks.tke.cloud.tencent.com/subnet-id", ip: .metadata.labels."eks.tke.cloud.tencent.com/available-ip-count"} |  "\(.subnet)\t\(.ip)"' | grep $subnet | awk '{print $2}'
```

查看指定固定 IP 的 Pod 所在子网剩余 IP 数量:

```bash
pod="wedata-lineage-service-test-env-48872523-0"
kubectl get cm static-addresses -o json | jq -r ".data.\"${pod}\"" | xargs kubectl get node -o json | jq -r '{ip: .metadata.labels."eks.tke.cloud.tencent.com/available-ip-count"} |  "\(.ip)"'
```

