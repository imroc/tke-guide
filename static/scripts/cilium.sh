#!/bin/bash
set -euo pipefail

# TKE Cilium Toolkit
# Docs: https://imroc.cc/tke/networking/cilium/install
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh | bash -s install-cilium
#   curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh | bash -s install-localdns
#   curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh | bash -s help

DEFAULT_CILIUM_VERSION="1.19.4"
DEFAULT_POD_CIDR="10.244.0.0/16"
DEFAULT_POD_CIDR_MASK="24"
NODE_LOCAL_DNS_IMAGE="docker.io/k8smirror/k8s-dns-node-cache:1.26.4"

# ====== i18n ======

is_zh() {
  [[ "${LANG:-}" == zh_CN* ]] || [[ "${LANG:-}" == zh_TW* ]] || [[ "${LC_ALL:-}" == zh* ]] || [[ "${LANGUAGE:-}" == zh* ]]
}

# msg KEY - print localized message
msg() {
  local key="$1"
  shift
  if is_zh; then
    eval "echo -e \"\${MSG_ZH_${key}}\""
  else
    eval "echo -e \"\${MSG_EN_${key}}\""
  fi
}

# --- Messages ---
# Help
MSG_ZH_HELP_TITLE="TKE Cilium 工具脚本"
MSG_EN_HELP_TITLE="TKE Cilium Toolkit"
MSG_ZH_HELP_USAGE="用法:"
MSG_EN_HELP_USAGE="Usage:"
MSG_ZH_HELP_COMMANDS="命令:"
MSG_EN_HELP_COMMANDS="Commands:"
MSG_ZH_HELP_EXAMPLES="示例:"
MSG_EN_HELP_EXAMPLES="Examples:"
MSG_ZH_HELP_CMD_CILIUM="  install-cilium     安装 Cilium 到 TKE 集群（自动检测网络模式，交互选择方案）"
MSG_EN_HELP_CMD_CILIUM="  install-cilium     Install Cilium to TKE cluster (auto-detect network mode, interactive)"
MSG_ZH_HELP_CMD_LOCALDNS="  install-localdns   安装 Nodelocal DNSCache 并配置与 Cilium 共存"
MSG_EN_HELP_CMD_LOCALDNS="  install-localdns   Install Nodelocal DNSCache with Cilium integration"
MSG_ZH_HELP_CMD_HELP="  help               显示本帮助信息"
MSG_EN_HELP_CMD_HELP="  help               Show this help message"
# Check
MSG_ZH_CHECK_PREREQ="检查前置条件..."
MSG_EN_CHECK_PREREQ="Checking prerequisites..."
MSG_ZH_CHECK_PREREQ_OK="前置条件检查通过"
MSG_EN_CHECK_PREREQ_OK="Prerequisites check passed"
MSG_ZH_NO_KUBECTL="kubectl 未安装，请先安装: https://kubernetes.io/docs/tasks/tools/"
MSG_EN_NO_KUBECTL="kubectl not installed. Install: https://kubernetes.io/docs/tasks/tools/"
MSG_ZH_NO_HELM="helm 未安装，请先安装: https://helm.sh/docs/intro/install/"
MSG_EN_NO_HELM="helm not installed. Install: https://helm.sh/docs/intro/install/"
MSG_ZH_NO_CLUSTER="无法连接集群，请检查 kubeconfig 配置"
MSG_EN_NO_CLUSTER="Cannot connect to cluster. Check kubeconfig."
MSG_ZH_CHECK_NODES="检查集群节点..."
MSG_EN_CHECK_NODES="Checking cluster nodes..."
MSG_ZH_NO_NODES="集群当前无节点，符合要求"
MSG_EN_NO_NODES="No nodes in cluster, OK"
MSG_ZH_NODES_OK="节点检查通过（仅存在超级节点）"
MSG_EN_NODES_OK="Node check passed (only super nodes)"
MSG_ZH_BAD_NODES="集群中存在非超级节点，安装 cilium 前请先移除以下节点（避免残留规则和配置）:"
MSG_EN_BAD_NODES="Non-super nodes detected. Remove them before installing cilium:"
# Detect
MSG_ZH_DETECT="检测集群网络模式..."
MSG_EN_DETECT="Detecting cluster network mode..."
MSG_ZH_DETECT_GR="检测到网络模式: GlobalRouter (GR)"
MSG_EN_DETECT_GR="Detected network mode: GlobalRouter (GR)"
MSG_ZH_DETECT_VPCCNI="检测到网络模式: VPC-CNI"
MSG_EN_DETECT_VPCCNI="Detected network mode: VPC-CNI"
MSG_ZH_ERR_DPV2="检测到 DataPlaneV2 集群（VPC-CNI + TKE 内置 cilium），本脚本不支持此类集群。"
MSG_EN_ERR_DPV2="DataPlaneV2 cluster detected (VPC-CNI + built-in cilium). Not supported."
MSG_ZH_ERR_CILIUM_EXISTS="检测到集群中已安装 cilium，请先卸载后再运行本脚本。"
MSG_EN_ERR_CILIUM_EXISTS="Cilium already installed in cluster. Please uninstall first."
MSG_ZH_ERR_CILIUMOVERLAY="检测到 CiliumOverlay 集群（TKE 内置 cilium），本脚本不支持此类集群。"
MSG_EN_ERR_CILIUMOVERLAY="CiliumOverlay cluster detected (built-in cilium). Not supported."
MSG_ZH_ERR_UNKNOWN_NET="无法识别集群网络模式（未找到 tke-bridge-agent 或 tke-eni-agent），请确认是 TKE 集群。"
MSG_EN_ERR_UNKNOWN_NET="Cannot identify network mode (no tke-bridge-agent or tke-eni-agent). Is this a TKE cluster?"
# Install cilium
MSG_ZH_SELECT_MODE="请选择安装模式:"
MSG_EN_SELECT_MODE="Select installation mode:"
MSG_ZH_MODE_NATIVE="  1) Native Routing - 与 TKE CNI 共存，Pod 使用 TKE 分配的 IP"
MSG_EN_MODE_NATIVE="  1) Native Routing - Coexist with TKE CNI, Pods use TKE-assigned IPs"
MSG_ZH_MODE_OVERLAY="  2) Overlay (vxlan) - 完全替代 TKE CNI，Pod IP 不占用 VPC IP"
MSG_EN_MODE_OVERLAY="  2) Overlay (vxlan) - Replace TKE CNI entirely, Pod IPs independent of VPC"
MSG_ZH_INPUT_OPTION="请输入选项 [1/2]: "
MSG_EN_INPUT_OPTION="Enter option [1/2]: "
MSG_ZH_INVALID_OPTION="无效选项，请输入 1 或 2"
MSG_EN_INVALID_OPTION="Invalid option, enter 1 or 2"
MSG_ZH_INPUT_VERSION="请输入 Cilium 版本"
MSG_EN_INPUT_VERSION="Enter Cilium version"
MSG_ZH_INPUT_POD_CIDR="请输入 Overlay Pod CIDR"
MSG_EN_INPUT_POD_CIDR="Enter Overlay Pod CIDR"
MSG_ZH_INPUT_MASK="每节点子网掩码"
MSG_EN_INPUT_MASK="Per-node subnet mask size"
MSG_ZH_UNINSTALL_TKE="卸载 TKE 组件 (kube-proxy, tke-cni-agent, ip-masq-agent)..."
MSG_EN_UNINSTALL_TKE="Uninstalling TKE components (kube-proxy, tke-cni-agent, ip-masq-agent)..."
MSG_ZH_UNINSTALL_TKE_OK="TKE 组件已卸载"
MSG_EN_UNINSTALL_TKE_OK="TKE components uninstalled"
MSG_ZH_HELM_INSTALL="执行 helm install..."
MSG_EN_HELM_INSTALL="Running helm install..."
MSG_ZH_CILIUM_DONE="Cilium 安装完成！请添加节点后验证:"
MSG_EN_CILIUM_DONE="Cilium installed! Add nodes and verify:"
# Localdns
MSG_ZH_NO_CILIUM="未检测到 cilium，请先安装 cilium (install-cilium) 再安装 localdns。"
MSG_EN_NO_CILIUM="Cilium not detected. Run install-cilium first."
MSG_ZH_NO_CLRP_CRD="CiliumLocalRedirectPolicy CRD 不存在，请确保安装 cilium 时启用了 localRedirectPolicies.enabled=true"
MSG_EN_NO_CLRP_CRD="CiliumLocalRedirectPolicy CRD not found. Ensure localRedirectPolicies.enabled=true in cilium install."
MSG_ZH_LOCALDNS_DONE="Nodelocal DNSCache 安装完成！"
MSG_EN_LOCALDNS_DONE="Nodelocal DNSCache installed!"

# ====== Utility ======

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
fatal() { error "$*"; exit 1; }

# ====== Help ======

show_help() {
  local script_name="cilium.sh"
  local url="https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh"
  echo ""
  msg HELP_TITLE
  echo ""
  msg HELP_USAGE
  echo "  $script_name <command>"
  echo ""
  msg HELP_COMMANDS
  msg HELP_CMD_CILIUM
  msg HELP_CMD_LOCALDNS
  msg HELP_CMD_HELP
  echo ""
  msg HELP_EXAMPLES
  echo "  ./$script_name install-cilium"
  echo "  ./$script_name install-localdns"
  echo "  curl -sfL $url | bash -s install-cilium"
  echo "  curl -sfL $url | bash -s install-localdns"
  echo ""
  if is_zh; then
    echo "文档:"
    echo "  Cilium 安装: https://imroc.cc/tke/networking/cilium/install"
    echo "  Localdns:    https://imroc.cc/tke/networking/cilium/with-node-local-dns"
  else
    echo "Docs:"
    echo "  Cilium Install: https://imroc.cc/tke/en/networking/cilium/install"
    echo "  Localdns:       https://imroc.cc/tke/en/networking/cilium/with-node-local-dns"
  fi
  echo ""
}

# ====== Common Checks ======

check_prerequisites() {
  info "$(msg CHECK_PREREQ)"
  command -v kubectl &>/dev/null || fatal "$(msg NO_KUBECTL)"
  command -v helm &>/dev/null || fatal "$(msg NO_HELM)"
  kubectl cluster-info &>/dev/null || fatal "$(msg NO_CLUSTER)"
  info "$(msg CHECK_PREREQ_OK)"
}

check_nodes() {
  info "$(msg CHECK_NODES)"
  local nodes
  nodes=$(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  if [[ -z "$nodes" ]]; then
    info "$(msg NO_NODES)"
    return
  fi
  local bad_nodes=()
  while IFS= read -r node; do
    if [[ ! "$node" =~ ^eklet- ]]; then
      bad_nodes+=("$node")
    fi
  done <<< "$nodes"
  if [[ ${#bad_nodes[@]} -gt 0 ]]; then
    local node_list
    node_list=$(printf '  - %s\n' "${bad_nodes[@]}")
    fatal "$(msg BAD_NODES)\n${node_list}"
  fi
  info "$(msg NODES_OK)"
}

detect_network_mode() {
  info "$(msg DETECT)"
  local has_bridge_agent has_eni_agent has_cilium cilium_image
  has_bridge_agent=$(kubectl -n kube-system get ds tke-bridge-agent --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  has_eni_agent=$(kubectl -n kube-system get ds tke-eni-agent --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  has_cilium=$(kubectl -n kube-system get ds cilium --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

  if [[ "$has_cilium" -gt 0 ]]; then
    cilium_image=$(kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
  fi

  if [[ "$has_bridge_agent" -gt 0 ]]; then
    if [[ "$has_cilium" -gt 0 ]]; then
      if [[ "$cilium_image" == *tkeimages* ]]; then
        fatal "$(msg ERR_CILIUMOVERLAY)"
      else
        fatal "$(msg ERR_CILIUM_EXISTS) ($cilium_image)"
      fi
    fi
    NETWORK_MODE="GR"
    info "$(msg DETECT_GR)"
  elif [[ "$has_eni_agent" -gt 0 ]]; then
    if [[ "$has_cilium" -gt 0 ]]; then
      if [[ "$cilium_image" == *tkeimages* ]]; then
        fatal "$(msg ERR_DPV2)"
      else
        fatal "$(msg ERR_CILIUM_EXISTS) ($cilium_image)"
      fi
    fi
    NETWORK_MODE="VPC-CNI"
    info "$(msg DETECT_VPCCNI)"
  else
    if [[ "$has_cilium" -gt 0 ]]; then
      if [[ "$cilium_image" == *tkeimages* ]]; then
        fatal "$(msg ERR_CILIUMOVERLAY)"
      else
        fatal "$(msg ERR_CILIUM_EXISTS) ($cilium_image)"
      fi
    fi
    fatal "$(msg ERR_UNKNOWN_NET)"
  fi
}

get_apiserver_ip() {
  kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null
}

# ====== install-cilium ======

select_routing_mode() {
  echo ""
  echo -e "${BLUE}$(msg SELECT_MODE)${NC}"
  msg MODE_NATIVE
  msg MODE_OVERLAY
  echo ""
  while true; do
    read -rp "$(msg INPUT_OPTION)" choice
    case "$choice" in
      1) ROUTING_MODE="native"; break ;;
      2) ROUTING_MODE="overlay"; break ;;
      *) msg INVALID_OPTION ;;
    esac
  done
  info "$(is_zh && echo "已选择:" || echo "Selected:") $( [[ $ROUTING_MODE == "native" ]] && echo "Native Routing" || echo "Overlay (vxlan)" )"
}

confirm_cilium_version() {
  echo ""
  read -rp "$(echo -e "${BLUE}$(msg INPUT_VERSION)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_CILIUM_VERSION}]: ")" version_input
  CILIUM_VERSION="${version_input:-$DEFAULT_CILIUM_VERSION}"
  info "Cilium: $CILIUM_VERSION"
}

confirm_pod_cidr() {
  if [[ "$ROUTING_MODE" != "overlay" ]]; then
    return
  fi
  echo ""
  read -rp "$(echo -e "${BLUE}$(msg INPUT_POD_CIDR)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_POD_CIDR}]: ")" cidr_input
  POD_CIDR="${cidr_input:-$DEFAULT_POD_CIDR}"
  read -rp "$(echo -e "${BLUE}$(msg INPUT_MASK)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_POD_CIDR_MASK}]: ")" mask_input
  POD_CIDR_MASK="${mask_input:-$DEFAULT_POD_CIDR_MASK}"
  info "Pod CIDR: $POD_CIDR, mask: /$POD_CIDR_MASK"
}

uninstall_tke_components() {
  info "$(msg UNINSTALL_TKE)"
  kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  info "$(msg UNINSTALL_TKE_OK)"
}

setup_native_vpccni() {
  info "$(is_zh && echo "创建 CNI 配置 ConfigMap..." || echo "Creating CNI ConfigMap...")"
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-config
  namespace: kube-system
data:
  cni-config: |-
    {
      "cniVersion": "0.3.1",
      "name": "generic-veth",
      "plugins": [
        {
          "type": "tke-route-eni",
          "routeTable": 1,
          "disableIPv6": true,
          "mtu": 1500,
          "ipam": {
            "type": "tke-eni-ipamc",
            "backend": "127.0.0.1:61677"
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
EOF
}

setup_native_gr() {
  info "$(is_zh && echo "配置 tke-bridge-agent 输出目录..." || echo "Configuring tke-bridge-agent output directory...")"
  local master_addr
  master_addr=$(kubectl -n kube-system get ds tke-bridge-agent -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -oP '(?<=--master=)\S+' | tr -d '"]')
  if [[ -z "$master_addr" ]]; then
    fatal "$(is_zh && echo "无法从 tke-bridge-agent 获取 --master 参数" || echo "Cannot get --master from tke-bridge-agent")"
  fi
  kubectl -n kube-system patch ds tke-bridge-agent --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":[\"--cni-conf-dir\",\"/host/etc/cni/net.d\",\"--master=$master_addr\"]}]"
  info "$(is_zh && echo "等待 tke-bridge-agent 滚动重启..." || echo "Waiting for tke-bridge-agent rollout...")"
  kubectl -n kube-system rollout status ds/tke-bridge-agent --timeout=120s
  info "$(is_zh && echo "删除残留的 multus 配置..." || echo "Removing leftover multus config...")"
  local pods
  pods=$(kubectl -n kube-system get pod --no-headers 2>/dev/null | grep tke-bridge-agent | awk '{print $1}')
  for pod in $pods; do
    kubectl -n kube-system exec "$pod" -- rm -f /host/etc/cni/net.d/00-multus.conf 2>/dev/null || true
  done
}

setup_overlay_vpccni() {
  info "$(is_zh && echo "禁用 add-pod-eni-ip-limit-webhook..." || echo "Disabling add-pod-eni-ip-limit-webhook...")"
  kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook 2>/dev/null || true
}

helm_install_cilium() {
  info "$(is_zh && echo "添加 Cilium Helm 仓库..." || echo "Adding Cilium Helm repo...")"
  helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
  helm repo update cilium 2>/dev/null || true

  local apiserver_ip
  apiserver_ip=$(get_apiserver_ip)
  if [[ -z "$apiserver_ip" ]]; then
    fatal "$(is_zh && echo "无法获取 apiserver 地址" || echo "Cannot get apiserver IP")"
  fi
  info "APIServer: $apiserver_ip"

  local -a image_args=(
    --set image.repository=quay.tencentcloudcr.com/cilium/cilium
    --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy
    --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator
    --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen
    --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay
    --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend
    --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui
    --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script
    --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium
    --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy
    --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver
    --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent
    --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
  )

  local -a common_args=(
    --set sysctlfix.enabled=false
    --set localRedirectPolicies.enabled=true
    --set kubeProxyReplacement=true
    --set k8sServiceHost="$apiserver_ip"
    --set k8sServicePort=60002
  )

  local -a toleration_args=(
    --set 'operator.tolerations[0].key=node-role.kubernetes.io/control-plane,operator.tolerations[0].operator=Exists'
    --set 'operator.tolerations[1].key=node-role.kubernetes.io/master,operator.tolerations[1].operator=Exists'
    --set 'operator.tolerations[2].key=node.kubernetes.io/not-ready,operator.tolerations[2].operator=Exists'
    --set 'operator.tolerations[3].key=node.cloudprovider.kubernetes.io/uninitialized,operator.tolerations[3].operator=Exists'
    --set 'operator.tolerations[4].key=tke.cloud.tencent.com/uninitialized,operator.tolerations[4].operator=Exists'
  )

  local -a mode_args=()
  case "${NETWORK_MODE}_${ROUTING_MODE}" in
    VPC-CNI_native)
      toleration_args+=(--set 'operator.tolerations[5].key=tke.cloud.tencent.com/eni-ip-unavailable,operator.tolerations[5].operator=Exists')
      mode_args=(--set routingMode=native --set endpointRoutes.enabled=true --set ipam.mode=delegated-plugin --set enableIPv4Masquerade=false --set devices=eth+ --set cni.chainingMode=generic-veth --set cni.customConf=true --set cni.configMap=cni-config --set cni.externalRouting=true --set extraConfig.local-router-ipv4=169.254.32.16)
      ;;
    GR_native)
      mode_args=(--set cni.chainingMode=generic-veth --set cni.chainingTarget=tke-bridge --set cni.exclusive=false --set routingMode=native --set endpointRoutes.enabled=true --set ipam.mode=delegated-plugin --set enableIPv4Masquerade=false --set devices=eth+ --set cni.externalRouting=true --set extraConfig.local-router-ipv4=169.254.32.16)
      ;;
    VPC-CNI_overlay)
      toleration_args+=(--set 'operator.tolerations[5].key=tke.cloud.tencent.com/eni-ip-unavailable,operator.tolerations[5].operator=Exists')
      mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=cluster-pool --set "ipam.operator.clusterPoolIPv4PodCIDRList={${POD_CIDR}}" --set ipam.operator.clusterPoolIPv4MaskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true)
      ;;
    GR_overlay)
      mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=cluster-pool --set "ipam.operator.clusterPoolIPv4PodCIDRList={${POD_CIDR}}" --set ipam.operator.clusterPoolIPv4MaskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true)
      ;;
  esac

  info "$(msg HELM_INSTALL) (${NETWORK_MODE} + ${ROUTING_MODE}, cilium ${CILIUM_VERSION})"
  helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" \
    --namespace kube-system \
    "${image_args[@]}" "${toleration_args[@]}" "${common_args[@]}" "${mode_args[@]}"
}

apply_apf() {
  info "$(is_zh && echo "应用 APF 限速规则..." || echo "Applying APF rate limiting...")"
  kubectl apply -f - <<'EOF'
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: cilium
spec:
  distinguisherMethod:
    type: ByUser
  matchingPrecedence: 2
  priorityLevelConfiguration:
    name: cilium
  rules:
  - resourceRules:
    - apiGroups: ['cilium.io']
      clusterScope: true
      namespaces: ['*']
      resources: ['*']
      verbs: [list]
    - apiGroups: ['']
      clusterScope: true
      namespaces: ['*']
      resources: [pods]
      verbs: [list]
    subjects:
    - kind: ServiceAccount
      serviceAccount:
        name: cilium
        namespace: kube-system
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata:
  name: cilium
spec:
  limited:
    nominalConcurrencyShares: 2
    borrowingLimitPercent: 0
    lendablePercent: 0
    limitResponse:
      queuing:
        handSize: 6
        queueLengthLimit: 50
        queues: 64
      type: Queue
  type: Limited
EOF
}

cmd_install_cilium() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      TKE Cilium Install Wizard      ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites
  check_nodes
  detect_network_mode
  select_routing_mode
  confirm_cilium_version
  confirm_pod_cidr

  echo ""
  info "$(is_zh && echo "安装方案" || echo "Plan"): ${ROUTING_MODE} (${NETWORK_MODE}), Cilium ${CILIUM_VERSION}"
  echo ""

  uninstall_tke_components
  case "${NETWORK_MODE}_${ROUTING_MODE}" in
    VPC-CNI_native)  setup_native_vpccni ;;
    GR_native)       setup_native_gr ;;
    VPC-CNI_overlay) setup_overlay_vpccni ;;
    GR_overlay)      ;;
  esac

  helm_install_cilium
  apply_apf

  echo ""
  info "============================================"
  info "$(msg CILIUM_DONE)"
  info "  kubectl -n kube-system get pod -l app.kubernetes.io/part-of=cilium"
  info "  kubectl -n kube-system exec ds/cilium -- cilium status --brief"
  info "============================================"
  echo ""
}

# ====== install-localdns ======

cmd_install_localdns() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   Nodelocal DNSCache Install        ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  local has_cilium
  has_cilium=$(kubectl -n kube-system get ds cilium --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$has_cilium" -eq 0 ]]; then
    fatal "$(msg NO_CILIUM)"
  fi
  if ! kubectl get crd ciliumlocalredirectpolicies.cilium.io &>/dev/null; then
    fatal "$(msg NO_CLRP_CRD)"
  fi

  info "$(is_zh && echo "检测到 cilium 已安装，开始部署 Nodelocal DNSCache..." || echo "Cilium detected. Deploying Nodelocal DNSCache...")"

  local kubedns_ip
  kubedns_ip=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ -z "$kubedns_ip" ]]; then
    fatal "$(is_zh && echo "无法获取 kube-dns ClusterIP" || echo "Cannot get kube-dns ClusterIP")"
  fi
  info "kube-dns ClusterIP: $kubedns_ip"

  info "$(is_zh && echo "创建 Services..." || echo "Creating Services...")"
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: node-local-dns
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns-upstream
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "KubeDNSUpstream"
spec:
  ports:
  - {name: dns, port: 53, protocol: UDP, targetPort: 53}
  - {name: dns-tcp, port: 53, protocol: TCP, targetPort: 53}
  selector:
    k8s-app: kube-dns
---
apiVersion: v1
kind: Service
metadata:
  name: node-local-dns
  namespace: kube-system
  annotations: {prometheus.io/port: "9253", prometheus.io/scrape: "true"}
  labels: {k8s-app: node-local-dns}
spec:
  clusterIP: None
  ports:
  - {name: metrics, port: 9253, targetPort: 9253}
  selector:
    k8s-app: node-local-dns
EOF

  local upstream_ip
  upstream_ip=$(kubectl -n kube-system get svc kube-dns-upstream -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ -z "$upstream_ip" ]]; then
    fatal "$(is_zh && echo "无法获取 kube-dns-upstream ClusterIP" || echo "Cannot get kube-dns-upstream ClusterIP")"
  fi
  info "kube-dns-upstream ClusterIP: $upstream_ip"

  info "$(is_zh && echo "创建 ConfigMap..." || echo "Creating ConfigMap...")"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-local-dns
  namespace: kube-system
data:
  Corefile: |
    cluster.local:53 {
        errors
        cache { success 9984 30; denial 9984 5 }
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} { force_tcp }
        prometheus :9253
        health
    }
    in-addr.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} { force_tcp }
        prometheus :9253
    }
    ip6.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} { force_tcp }
        prometheus :9253
    }
    .:53 {
        template ANY HINFO . { rcode NXDOMAIN }
        errors
        cache 30
        reload
        loop
        bind 0.0.0.0
        forward . /etc/resolv.conf
        prometheus :9253
    }
EOF

  info "$(is_zh && echo "部署 DaemonSet..." || echo "Deploying DaemonSet...")"
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-local-dns
  namespace: kube-system
  labels: {k8s-app: node-local-dns}
spec:
  updateStrategy: {rollingUpdate: {maxUnavailable: "10%"}}
  selector: {matchLabels: {k8s-app: node-local-dns}}
  template:
    metadata:
      labels: {k8s-app: node-local-dns}
      annotations: {prometheus.io/port: "9253", prometheus.io/scrape: "true"}
    spec:
      priorityClassName: system-node-critical
      serviceAccountName: node-local-dns
      hostNetwork: false
      dnsPolicy: Default
      tolerations:
      - {key: "CriticalAddonsOnly", operator: "Exists"}
      - {effect: "NoExecute", operator: "Exists"}
      - {effect: "NoSchedule", operator: "Exists"}
      containers:
      - name: node-cache
        image: ${NODE_LOCAL_DNS_IMAGE}
        resources: {requests: {cpu: 25m, memory: 5Mi}}
        args: ["-localip", "${kubedns_ip}", "-conf", "/etc/Corefile", "-upstreamsvc", "kube-dns-upstream", "-skipteardown=true", "-setupinterface=false", "-setupiptables=false"]
        securityContext: {capabilities: {add: [NET_ADMIN]}}
        ports:
        - {containerPort: 53, name: dns, protocol: UDP}
        - {containerPort: 53, name: dns-tcp, protocol: TCP}
        - {containerPort: 9253, name: metrics, protocol: TCP}
        livenessProbe: {httpGet: {path: /health, port: 8080}, initialDelaySeconds: 60, timeoutSeconds: 5}
        volumeMounts:
        - {mountPath: /run/xtables.lock, name: xtables-lock}
        - {name: config-volume, mountPath: /etc/coredns}
        - {name: kube-dns-config, mountPath: /etc/kube-dns}
      volumes:
      - {name: xtables-lock, hostPath: {path: /run/xtables.lock, type: FileOrCreate}}
      - {name: kube-dns-config, configMap: {name: kube-dns, optional: true}}
      - name: config-volume
        configMap: {name: node-local-dns, items: [{key: Corefile, path: Corefile.base}]}
EOF

  info "$(is_zh && echo "创建 CiliumLocalRedirectPolicy..." || echo "Creating CiliumLocalRedirectPolicy...")"
  kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumLocalRedirectPolicy
metadata:
  name: nodelocaldns
  namespace: kube-system
spec:
  redirectFrontend:
    serviceMatcher: {serviceName: kube-dns, namespace: kube-system}
  redirectBackend:
    localEndpointSelector: {matchLabels: {k8s-app: node-local-dns}}
    toPorts:
    - {port: "53", name: dns, protocol: UDP}
    - {port: "53", name: dns-tcp, protocol: TCP}
EOF

  echo ""
  info "============================================"
  info "$(msg LOCALDNS_DONE)"
  info "  kubectl -n kube-system get pod -l k8s-app=node-local-dns"
  info "  kubectl -n kube-system get ciliumlocalredirectpolicy"
  info "============================================"
  echo ""
}

# ====== Main ======

main() {
  local cmd="${1:-}"
  case "$cmd" in
    install-cilium)  cmd_install_cilium ;;
    install-localdns) cmd_install_localdns ;;
    help|--help|-h|"") show_help ;;
    *)
      error "$(is_zh && echo "未知命令" || echo "Unknown command"): $cmd"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

main "$@"
