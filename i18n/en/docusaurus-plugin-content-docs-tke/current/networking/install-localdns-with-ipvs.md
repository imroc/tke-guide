# Installing NodeLocalDNS in IPVS Mode

## Background

TKE has productized support for [NodeLocalDNS](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/), can be installed into cluster with one click in extension components, refer to [NodeLocalDNSCache Extension Component Description](https://cloud.tencent.com/document/product/457/49423). But one scenario is unsupported: cluster network is GlobalRouter and kube-proxy forwarding mode is IPVS.

This article introduces how to install NodeLocalDNS for TKE clusters with GlobalRouter + IPVS.

## Prerequisites

1. Cluster network mode is GlobalRouter.
2. kube-proxy mode is IPVS.
3. Configured TKE cluster kubeconfig, can operate TKE cluster with [kubectl](https://kustomize.io/).
4. Installed [helm](https://helm.sh/) and [kustomize](https://kustomize.io/).

## Installation Method

```bash
git clone --depth 1 https://github.com/tke-apps/nodelocaldns.git
cd nodelocaldns
make
```

Principle:
1. Automatically fetches latest kubernetes nodelocaldns plugin yaml template and current cluster `kube-dns`'s `ClusterIP`, fills template to generate final `nodelocaldns.yaml` in current directory.
2. Automatically deploys generated `nodelocaldns.yaml` to current cluster.

> If using GitOps deployment, only execute `make yaml` to generate `nodelocaldns.yaml`, then put this yaml file into GitOps repository.

## Modifying Kubelet Parameters

For DNS cache component to take effect, need to configure kubelet parameter on nodes: `--cluster-dns=169.254.20.10`.

> IPVS mode clusters need to bind corresponding Cluster IP for all Services on `kube-ipvs0` dummy interface for IPVS forwarding, so localdns cannot listen on cluster DNS's Cluster IP. Kubelet's `--cluster-dns` defaults to cluster DNS's Cluster IP instead of localdns listening address. After installing localdns, cluster Pods still use cluster DNS resolution by default, so we need to modify kubelet's `--cluster-dns` parameter.

Modify and restart kubelet via script:

```bash
sed -i 's/CLUSTER_DNS.*/CLUSTER_DNS="--cluster-dns=169.254.20.10"/' /etc/kubernetes/kubelet
systemctl restart kubelet
```

Manual configuration for each node is impractical. Below introduces automated configuration methods.

### Configuring Incremental Nodes

Specify 【Custom Script】 in new nodes or node pools for node initialization, enabling automatic kubelet parameter configuration after node initialization:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F28%2F20240328180309.png)

> Existing node pools can also specify custom scripts by modifying node pool configuration.

### Modifying Existing Nodes

Use ansible for batch modification. Ansible installation refer to [Official Documentation: Installing Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html).

After installing ansible, follow these steps:

1. Export all node IPs to `hosts.ini`:
    ```bash
    kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n' | grep -vE '^169\.254\.*' > hosts.ini
    ```

2. Prepare script `modify-kubelet.sh`:
    ```bash
    sed -i 's/CLUSTER_DNS.*/CLUSTER_DNS="--cluster-dns=169.254.20.10"/' /etc/kubernetes/kubelet
    systemctl restart kubelet
    ```

3. Prepare ssh key or password for node login (rename key to key, execute `chmod 0600 key`)
4. Use ansible to run script `modify-kubelet.sh` on all nodes:
    * Example using key:
      ```bash
      ansible all -i hosts.ini --ssh-common-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --user root --private-key=key -m script -a "modify-kubelet.sh"
      ```
    * Example using password:
      ```bash
      ansible all -i hosts.ini --ssh-common-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" -m script --extra-vars "ansible_user=root ansible_password=yourpassword" -a "modify-kubelet.sh"
      ```
   > **Note:** If nodes use ubuntu system, default user is ubuntu, can replace accordingly. Also add `--become --become-user=root` to ansible parameters for root privileges during script execution, avoiding operation failures.

## Regarding Existing Pods

Running existing Pods in cluster still use old cluster DNS. After recreation, they automatically switch to localdns. Newly created Pods also default to localdns.

Generally, if no special need, existing Pods can be ignored - they'll automatically switch to localdns after next update when Pods recreate. For immediate switching, trigger Pod recreation via workload rolling updates for manual switching.

## Regarding NodeLocalDNS Version

Installation method uses open-source project employing NodeLocalDNS addon YAML from Kubernetes [Official YAML](https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml) automatically replaced generation, keeping latest version real-time.

> Official dependency image `registry.k8s.io/dns/k8s-dns-node-cache` cannot be pulled domestically, replaced with DockerHub mirror image [k8smirror/k8s-dns-node-cache](https://hub.docker.com/repository/docker/k8smirror/k8s-dns-node-cache), periodically auto-syncing latest tags, safe to use.