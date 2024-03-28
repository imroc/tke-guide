# IPVS 模式安装 NodeLocalDNS

## 背景

TKE 对 NodeLocalDNS 进行了产品化支持，直接在扩展组件里面就可以一键安装到集群，参考 [NodeLocalDNSCache 扩展组件说明](https://cloud.tencent.com/document/product/457/49423) ，但是有一种情况不支持：集群网络是 GlobalRouter 且 kube-proxy 转发模式 IPVS。

本文介绍如何为 GlobalRouter + IPVS 的 TKE 集群安装 NodeLocalDNS。

## 前提条件

1. 集群网络模式为 GlobalRouter。
2. kube-proxy 的模式为 IVPS。
3. 配置好了 TKE 集群的 kubeconfig，可以用 [kubectl](kubednsIphttps://kustomize.io/) 操作 TKE 集群。
4. 安装了 [helm](https://helm.sh/) 和 [kustomize](https://kustomize.io/)。

## 安装方法

```bash
git clone --depth 1 https://github.com/tke-apps/nodelocaldns.git
cd nodelocaldns
make
```

## 修改 kubelet 参数

如果要让 DNS 缓存组件生效，还需要配置节点上的 kubelet 参数：`--cluster-dns=169.254.20.10`。

> IPVS 模式集群由于需要为所有 Service 在 `kube-ipvs0` 这个 dummy 网卡上绑对应的 Cluster IP，以实现 IPVS 转发，所以 localdns 就无法再监听集群 DNS 的 Cluster IP。而 kubelet 的 `--cluster-dns` 默认指向的是集群 DNS 的 Cluster IP 而不是 localdns 监听的地址，安装 localdns 之后集群中的 Pod 默认还是使用的集群 DNS 解析，所以我们需要修改 kubelet 的 `--cluster-dns` 参数。

可以通过以下脚本进行修改并重启 kubelet 来生效:

```bash
sed -i 's/CLUSTER_DNS.*/CLUSTER_DNS="--cluster-dns=169.254.20.10"/' /etc/kubernetes/kubelet
systemctl restart kubelet
```

挨个手动配置不太现实，下面介绍自动化的配置方法。

### 配置增量节点

新建节点或节点池里指定节点初始化后的【自定义脚本】，这样就可以让节点初始化后自动执行脚本来配置 kubelet 参数：

![](./img/custom-script.png)

> 已有的节点池也可以通过修改节点池配置来指定自定义脚本。

### 修改存量节点

可以 ansible 来批量修改，ansible 安装方式参考 [官方文档: Installing Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) 。

安装好 ansible 之后，按照以下步骤操作:

1. 导出所有节点 IP 到 `hosts.ini`:

```bash
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n' | grep -vE '^169\.254\.*' > hosts.ini
```

2. 准备脚本 `modify-kubelet.sh`:

```bash
sed -i 's/CLUSTER_DNS.*/CLUSTER_DNS="--cluster-dns=169.254.20.10"/' /etc/kubernetes/kubelet
systemctl restart kubelet
```

3. 准备可以用于节点登录的 ssh 秘钥或密码 (秘钥改名为 key，并执行 `chmod 0600 key`)
4. 使用 ansible 在所有节点上运行脚本 `modify-kubelet.sh`:
    * 使用秘钥的示例:
      ```bash
      ansible all -i hosts.ini --ssh-common-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --user root --private-key=key -m script -a "mo  dify-kubelet.sh"
      ```
    * 使用密码的示例:
      ```bash
      ansible all -i hosts.ini --ssh-common-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" -m script --extra-vars "ansible_user=root an  sible_password=yourpassword" -a "modify-kubelet.sh"
      ```
   > **注:** 如果节点使用的 ubuntu 系统，默认 user 是 ubuntu，可以自行替换下，另外 ansible 参数再加上 `--become --become-user=root` 以便让 ansible 执行脚本时拥有 root 权限，避免操作失败。

## 关于存量 Pod

集群中正在运行的存量 Pod 还是会使用旧的集群 DNS，等重建后会自动切换到 localdns，新创建的 Pod 也都会默认使用 localdns。

一般没特别需要的情况下，可以不管存量 Pod，等下次更新， Pod 重建后就会自动切换到 localdns；如果想要立即切换，可以将工作负载滚动更新触发 Pod 重建来实现手动切换。

## 关于 NodeLocalDNS 版本

本项目所使用的 NodeLocalDNS addon 的 YAML 是 Kubernetes [官方提供的 YAML](https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml) 自动替换生成的，实时保持最新版本。

> 官方的依赖镜像 `registry.k8s.io/dns/k8s-dns-node-cache` 在国内无法拉取，已替换为 DockerHub 上的 mirror 镜像 [k8smirror/k8s-dns-node-cache](https://hub.docker.com/repository/docker/k8smirror/k8s-dns-node-cache)，会周期性的自动同步最新的 tag，可放心使用。

## 参考资料

* [Using NodeLocal DNSCache in Kubernetes clusters](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/)
