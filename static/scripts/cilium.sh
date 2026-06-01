#!/bin/bash
set -euo pipefail

###############################################################################
# TKE Cilium Toolkit
#
# A multi-function script for installing and managing Cilium on Tencent Cloud
# TKE (Tencent Kubernetes Engine) clusters.
#
# Docs:
#   Chinese: https://imroc.cc/tke/networking/cilium/install
#   English: https://imroc.cc/tke/en/networking/cilium/install
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
#   bash cilium.sh <command>
#
# Note: install-cilium is interactive (asks for routing mode etc.). Do NOT use
# `curl ... | bash -s install-cilium` — bash's stdin gets consumed by curl's
# pipe output, so `read` returns EOF immediately and the script exits right
# after printing the menu. Always download first, then run.
# For non-interactive batch deployment, see the env var section at the bottom.
#
# Commands:
#   install-cilium          Install Cilium (auto-detect network mode, interactive)
#   install-localdns        Install Nodelocal DNSCache with Cilium integration
#   e2e-test                Run Cilium connectivity end-to-end tests
#   enable-egress-gateway   Enable Cilium Egress Gateway
#   help                    Show help message
#
###############################################################################
#
# MODIFICATION GUIDE (for AI agents and human contributors)
# =========================================================
#
# 1. I18N (Internationalization)
#    - The script auto-detects locale via LANG/LC_ALL/LANGUAGE env vars.
#    - Chinese locale (zh_CN*, zh_TW*) shows Chinese; everything else shows English.
#    - All user-facing strings MUST have both ZH and EN variants:
#        MSG_ZH_<KEY>="中文消息"
#        MSG_EN_<KEY>="English message"
#      Then use: msg <KEY>  OR  $(is_zh && echo "中文" || echo "English")
#    - When adding/modifying any user-facing text, always update BOTH languages.
#
# 2. ADDING A NEW SUBCOMMAND
#    - Define a function: cmd_<name>() { ... }
#    - Add MSG_ZH/EN_HELP_CMD_<NAME> for help text.
#    - Add `msg HELP_CMD_<NAME>` in show_help() between the last command and HELP_CMD_HELP.
#    - Add a case branch in main(): <name>) cmd_<name> ;;
#    - If the command should be optionally triggered from install-cilium,
#      extract core logic into a separate function (like install_localdns_internal)
#      and add an interactive confirm_enable_<name>() + call it from cmd_install_cilium.
#
# 3. IMAGE REFERENCES
#    - TKE nodes can pull from: docker.io (direct), quay.tencentcloudcr.com (quay.io mirror).
#    - Images from registry.k8s.io / gcr.io are NOT accessible; sync them to docker.io/k8smirror:
#        skopeo copy -a docker://<source> docker://docker.io/k8smirror/<name>:<tag>
#    - Update image references in: helm_install_cilium() image_args, cmd_e2e_test(), NODE_LOCAL_DNS_IMAGE.
#
# 4. NETWORK MODE DETECTION (detect_network_mode)
#    Detection logic for TKE cluster network type:
#    - ds/tke-bridge-agent exists        → GlobalRouter (GR)
#    - ds/tke-eni-agent exists           → VPC-CNI
#    - ds/cilium exists (tkeimages)      → CiliumOverlay (built-in, not supported)
#    - ds/cilium exists (non-tkeimages)  → Already installed (not supported)
#    - VPC-CNI + ds/cilium (tkeimages)   → DataPlaneV2 (not supported)
#
# 5. INSTALL MODES (4 combinations: NETWORK_MODE x ROUTING_MODE)
#    ┌──────────────────┬──────────────────────────────────────────────────┐
#    │ VPC-CNI + native │ CNI chaining via ConfigMap (cni-config)         │
#    │ GR + native      │ CNI chaining via chainingTarget=tke-bridge      │
#    │                  │ + keep tke-cni-agent + enable masquerade        │
#    │                  │ + disable portmap + create ip-masq-agent CM     │
#    │ VPC-CNI + overlay│ Full cilium CNI (tunnel/vxlan, cluster-pool)    │
#    │                  │ + delete mutatingwebhookconfiguration           │
#    │ GR + overlay     │ Full cilium CNI (tunnel/vxlan, cluster-pool)    │
#    └──────────────────┴──────────────────────────────────────────────────┘
#
# 6. CILIUM VERSION
#    - DEFAULT_CILIUM_VERSION is the recommended version tested with this script.
#    - When upgrading, test all 4 install modes before updating the default.
#
# 7. NON-INTERACTIVE MODE (environment variables)
#    All interactive prompts in install-cilium can be skipped by setting env vars:
#      ROUTING_MODE     "native" or "overlay" (required)
#      CILIUM_VERSION   e.g. "1.19.4" (optional, defaults to DEFAULT_CILIUM_VERSION)
#      POD_CIDR         e.g. "10.244.0.0/16" (only for overlay mode)
#      POD_CIDR_MASK    e.g. "24" (only for overlay mode)
#      ENABLE_EGRESS    "true" or "false" (optional, default false)
#      ENABLE_LOCALDNS  "true" or "false" (optional, default false)
#    NETWORK_MODE is always auto-detected and cannot be overridden.
#    When adding a new interactive prompt, follow the pattern:
#      - Check if the env var is already set → if yes, skip the prompt.
#      - Add the env var to print_replay_command() output.
#      - Document the env var in this section.
#
# 8. STYLE
#    - Comments in English only.
#    - Use info/warn/error/fatal for output (colored, prefixed).
#    - Interactive prompts use blue color (${BLUE}...${NC}) and read -rp.
#    - Default answers for optional features (egress, localdns): N (no).
#    - set -euo pipefail is on; use `|| true` or `; exit 0` to suppress errors in pipes.
#
###############################################################################

# ====== Defaults ======

# Cilium helm chart version. Bump this when a new version is tested and verified.
DEFAULT_CILIUM_VERSION="1.19.4"
# Default image registry prefix for cilium images (TKE internal mirror).
DEFAULT_IMAGE_REGISTRY="quay.tencentcloudcr.com/cilium"
# Default Pod CIDR for overlay mode. Only used when ROUTING_MODE=overlay.
DEFAULT_POD_CIDR="10.244.0.0/16"
# Default per-node subnet mask for overlay mode (24 = max 254 pods per node).
DEFAULT_POD_CIDR_MASK="24"
# Nodelocal DNSCache image. Synced from registry.k8s.io/dns/k8s-dns-node-cache to dockerhub mirror.
NODE_LOCAL_DNS_IMAGE="docker.io/k8smirror/k8s-dns-node-cache:1.26.4"

# ====== I18N ======
# Locale detection: checks LANG, LC_ALL, LANGUAGE for Chinese locale prefixes.
# Returns 0 (true) for Chinese, 1 (false) for everything else.

is_zh() {
  [[ "${LANG:-}" == zh_CN* ]] || [[ "${LANG:-}" == zh_TW* ]] || [[ "${LC_ALL:-}" == zh* ]] || [[ "${LANGUAGE:-}" == zh* ]]
}

# msg KEY — prints the localized message for the given key.
# Looks up MSG_ZH_<KEY> or MSG_EN_<KEY> based on locale.
# Usage: msg CHECK_PREREQ  →  prints "检查前置条件..." or "Checking prerequisites..."
msg() {
  local key="$1"
  shift
  if is_zh; then
    eval "echo -e \"\${MSG_ZH_${key}}\""
  else
    eval "echo -e \"\${MSG_EN_${key}}\""
  fi
}

# --- Localized Messages ---
# Convention: MSG_ZH_<KEY> for Chinese, MSG_EN_<KEY> for English.
# When adding a new message, always add BOTH variants.

# Help messages
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
MSG_ZH_HELP_CMD_E2ETEST="  e2e-test           运行 Cilium 连通性端到端测试"
MSG_EN_HELP_CMD_E2ETEST="  e2e-test           Run Cilium connectivity end-to-end tests"
MSG_ZH_HELP_CMD_EGRESS="  enable-egress-gateway  启用 Cilium Egress Gateway 功能"
MSG_EN_HELP_CMD_EGRESS="  enable-egress-gateway  Enable Cilium Egress Gateway"
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
MSG_ZH_INPUT_IMAGE_REGISTRY="请输入 Cilium 镜像地址前缀"
MSG_EN_INPUT_IMAGE_REGISTRY="Enter Cilium image registry prefix"
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
# Egress Gateway
MSG_ZH_EGRESS_DONE="Egress Gateway 已启用！"
MSG_EN_EGRESS_DONE="Egress Gateway enabled!"

# ====== Utility ======
# Colored log output functions. All user-facing output should go through these.
# info: green [INFO], warn: yellow [WARN], error: red [ERROR], fatal: error + exit 1.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
fatal() {
  error "$*"
  exit 1
}

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
  msg HELP_CMD_E2ETEST
  msg HELP_CMD_EGRESS
  msg HELP_CMD_HELP
  echo ""
  msg HELP_EXAMPLES
  echo "  ./$script_name install-cilium"
  echo "  ./$script_name install-localdns"
  echo "  curl -sfL $url -o $script_name && bash $script_name install-cilium"
  echo "  curl -sfL $url -o $script_name && bash $script_name install-localdns"
  echo ""
  if is_zh; then
    echo "提示:"
    echo "  install-cilium 是交互式命令，请先下载脚本再执行（不要用 \`curl ... | bash\`，"
    echo "  否则 bash 的 stdin 会被 curl 占用，read 立即收到 EOF，菜单弹出后脚本会自动退出）。"
  else
    echo "Note:"
    echo "  install-cilium is interactive. Download the script first, then run it (do NOT use"
    echo "  \`curl ... | bash\` — bash's stdin gets consumed by curl, read hits EOF immediately,"
    echo "  and the script exits right after printing the menu)."
  fi
  echo ""
  if is_zh; then
    echo "文档:"
    echo "  安装 cilium:   https://imroc.cc/tke/networking/cilium/install"
    echo "  安装 localdns: https://imroc.cc/tke/networking/cilium/with-node-local-dns"
  else
    echo "Docs:"
    echo "  Install cilium:   https://imroc.cc/tke/en/networking/cilium/install"
    echo "  Install localdns: https://imroc.cc/tke/en/networking/cilium/with-node-local-dns"
  fi
  echo ""
}

# ====== Common Checks ======
# Shared validation functions used by multiple subcommands.

check_prerequisites() {
  info "$(msg CHECK_PREREQ)"
  command -v kubectl &>/dev/null || fatal "$(msg NO_KUBECTL)"
  command -v helm &>/dev/null || fatal "$(msg NO_HELM)"
  kubectl cluster-info &>/dev/null || fatal "$(msg NO_CLUSTER)"
  info "$(msg CHECK_PREREQ_OK)"
}

# check_nodes — Ensures no non-super nodes exist before cilium install.
# Only eklet-* prefixed nodes (super nodes) are allowed. Regular/native nodes
# should be added AFTER cilium is installed to avoid leftover iptables rules.
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
  done <<<"$nodes"
  if [[ ${#bad_nodes[@]} -gt 0 ]]; then
    local node_list
    node_list=$(printf '  - %s\n' "${bad_nodes[@]}")
    fatal "$(msg BAD_NODES)\n${node_list}"
  fi
  info "$(msg NODES_OK)"
}

# detect_network_mode — Identifies the TKE cluster's network type.
# Sets global variable NETWORK_MODE to "GR" or "VPC-CNI".
# Exits with error if the cluster is CiliumOverlay, DataPlaneV2, or already has cilium.
# Detection order: tke-bridge-agent → GR, tke-eni-agent → VPC-CNI, cilium → error.
detect_network_mode() {
  info "$(msg DETECT)"
  local has_bridge_agent has_eni_agent has_cilium cilium_image
  has_bridge_agent=$(kubectl -n kube-system get ds tke-bridge-agent --no-headers 2>/dev/null | wc -l | tr -d ' '; exit 0)
  has_eni_agent=$(kubectl -n kube-system get ds tke-eni-agent --no-headers 2>/dev/null | wc -l | tr -d ' '; exit 0)
  has_cilium=$(kubectl -n kube-system get ds cilium --no-headers 2>/dev/null | wc -l | tr -d ' '; exit 0)

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
  local ip
  for i in $(seq 1 5); do
    ip=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
    sleep 2
  done
}

# ====== install-cilium subcommand ======
# Interactive functions for gathering user input during cilium installation.

# select_routing_mode — Prompts user to choose Native Routing or Overlay.
# Sets global variable ROUTING_MODE to "native" or "overlay".
# Skipped if ROUTING_MODE env var is already set.

select_routing_mode() {
  if [[ -n "${ROUTING_MODE:-}" ]]; then
    info "$(is_zh && echo "已选择:" || echo "Selected:") $([[ $ROUTING_MODE == "native" ]] && echo "Native Routing" || echo "Overlay (vxlan)")"
    return
  fi
  echo ""
  echo -e "${BLUE}$(msg SELECT_MODE)${NC}"
  msg MODE_NATIVE
  msg MODE_OVERLAY
  echo ""
  while true; do
    read -rp "$(msg INPUT_OPTION)" choice
    case "$choice" in
    1)
      ROUTING_MODE="native"
      break
      ;;
    2)
      ROUTING_MODE="overlay"
      break
      ;;
    *) msg INVALID_OPTION ;;
    esac
  done
  info "$(is_zh && echo "已选择:" || echo "Selected:") $([[ $ROUTING_MODE == "native" ]] && echo "Native Routing" || echo "Overlay (vxlan)")"
}

# confirm_cilium_version — Prompts user to confirm or override Cilium version.
# Skipped if CILIUM_VERSION env var is already set.
confirm_cilium_version() {
  if [[ -n "${CILIUM_VERSION:-}" ]]; then
    info "Cilium: $CILIUM_VERSION"
    return
  fi
  echo ""
  read -rp "$(echo -e "${BLUE}$(msg INPUT_VERSION)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_CILIUM_VERSION}]: ")" version_input
  CILIUM_VERSION="${version_input:-$DEFAULT_CILIUM_VERSION}"
  info "Cilium: $CILIUM_VERSION"
}

# confirm_image_registry — Prompts user to confirm or override the image registry prefix.
# Skipped if IMAGE_REGISTRY env var is already set.
# After confirmation, displays all image addresses that will be used.
confirm_image_registry() {
  if [[ -z "${IMAGE_REGISTRY:-}" ]]; then
    echo ""
    read -rp "$(echo -e "${BLUE}$(msg INPUT_IMAGE_REGISTRY)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_IMAGE_REGISTRY}]: ")" registry_input
    IMAGE_REGISTRY="${registry_input:-$DEFAULT_IMAGE_REGISTRY}"
  fi
  # Display all images that will be used
  echo ""
  if is_zh; then
    info "镜像地址:"
  else
    info "Image repositories:"
  fi
  local -a images=(
    "cilium:              ${IMAGE_REGISTRY}/cilium"
    "cilium-envoy:        ${IMAGE_REGISTRY}/cilium-envoy"
    "operator:            ${IMAGE_REGISTRY}/operator"
    "certgen:             ${IMAGE_REGISTRY}/certgen"
    "hubble-relay:        ${IMAGE_REGISTRY}/hubble-relay"
    "hubble-ui-backend:   ${IMAGE_REGISTRY}/hubble-ui-backend"
    "hubble-ui:           ${IMAGE_REGISTRY}/hubble-ui"
    "startup-script:      ${IMAGE_REGISTRY}/startup-script"
    "clustermesh:         ${IMAGE_REGISTRY}/clustermesh-apiserver"
    "spire-agent:         docker.io/k8smirror/spire-agent"
    "spire-server:        docker.io/k8smirror/spire-server"
  )
  for img in "${images[@]}"; do
    echo "  $img"
  done
}

# confirm_pod_cidr — Prompts user for overlay Pod CIDR (only when ROUTING_MODE=overlay).
# Skipped if POD_CIDR env var is already set.
confirm_pod_cidr() {
  if [[ "$ROUTING_MODE" != "overlay" ]]; then
    return
  fi
  if [[ -n "${POD_CIDR:-}" ]]; then
    POD_CIDR_MASK="${POD_CIDR_MASK:-$DEFAULT_POD_CIDR_MASK}"
    info "Pod CIDR: $POD_CIDR, mask: /$POD_CIDR_MASK"
    return
  fi
  echo ""
  read -rp "$(echo -e "${BLUE}$(msg INPUT_POD_CIDR)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_POD_CIDR}]: ")" cidr_input
  POD_CIDR="${cidr_input:-$DEFAULT_POD_CIDR}"
  read -rp "$(echo -e "${BLUE}$(msg INPUT_MASK)${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_POD_CIDR_MASK}]: ")" mask_input
  POD_CIDR_MASK="${mask_input:-$DEFAULT_POD_CIDR_MASK}"
  info "Pod CIDR: $POD_CIDR, mask: /$POD_CIDR_MASK"
}

# confirm_enable_egress — Asks user whether to enable Egress Gateway (default: N).
# Sets ENABLE_EGRESS=true/false. If true, egress params are merged into helm install.
# Skipped if ENABLE_EGRESS env var is already set.
confirm_enable_egress() {
  if [[ -n "${ENABLE_EGRESS:-}" ]]; then
    return
  fi
  echo ""
  local prompt
  if is_zh; then
    prompt="是否启用 Egress Gateway？[y/N]: "
  else
    prompt="Enable Egress Gateway? [y/N]: "
  fi
  read -rp "$(echo -e "${BLUE}${prompt}${NC}")" egress_input
  egress_input=$(echo "$egress_input" | tr '[:upper:]' '[:lower:]')
  if [[ "$egress_input" == "y" || "$egress_input" == "yes" ]]; then
    ENABLE_EGRESS=true
  else
    ENABLE_EGRESS=false
  fi
}

# confirm_enable_localdns — Asks user whether to install Nodelocal DNSCache (default: N).
# Sets ENABLE_LOCALDNS=true/false. If true, localdns is deployed after cilium install.
# Skipped if ENABLE_LOCALDNS env var is already set.
confirm_enable_localdns() {
  if [[ -n "${ENABLE_LOCALDNS:-}" ]]; then
    return
  fi
  echo ""
  local prompt
  if is_zh; then
    prompt="是否安装 Nodelocal DNSCache？[y/N]: "
  else
    prompt="Install Nodelocal DNSCache? [y/N]: "
  fi
  read -rp "$(echo -e "${BLUE}${prompt}${NC}")" localdns_input
  localdns_input=$(echo "$localdns_input" | tr '[:upper:]' '[:lower:]')
  if [[ "$localdns_input" == "y" || "$localdns_input" == "yes" ]]; then
    ENABLE_LOCALDNS=true
  else
    ENABLE_LOCALDNS=false
  fi
}

# uninstall_tke_components — Disables TKE built-in networking components.
# - kube-proxy: always disabled (cilium replaces it via kubeProxyReplacement).
# - tke-cni-agent: disabled EXCEPT for GR+native (needed to copy CNI binaries like bridge).
# - ip-masq-agent: disabled (cilium has its own BPF-based masquerade).
# Uses nodeSelector trick to prevent scheduling without deleting the DaemonSet.
uninstall_tke_components() {
  info "$(msg UNINSTALL_TKE)"
  kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  # GR + native routing 模式需要保留 tke-cni-agent（负责拷贝 CNI 二进制到节点）
  if [[ "${NETWORK_MODE}_${ROUTING_MODE}" != "GR_native" ]]; then
    kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  fi
  kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
  info "$(msg UNINSTALL_TKE_OK)"
}

# setup_native_vpccni — Creates CNI ConfigMap for VPC-CNI + cilium chaining.
# The ConfigMap defines the CNI plugin chain: tke-route-eni → cilium-cni.
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

# setup_native_gr — Configures tke-bridge-agent for GR + cilium chaining.
# Three changes are made to tke-bridge-agent DaemonSet args:
#   1. --cni-conf-dir: /host/etc/cni/net.d/multus → /host/etc/cni/net.d
#      (move bridge conflist to CNI root so cilium's chainingTarget can find it)
#   2. --port-mapping=false: disable portmap plugin (cilium handles HostPort via
#      kubeProxyReplacement; portmap depends on kube-proxy's KUBE-MARK-MASQ iptables chain)
# Also creates ip-masq-agent ConfigMap for BPF masquerade:
#   - Reads NonMasqueradeCIDRs from TKE's auto-generated ip-masq-agent-config
#     (contains VPC CIDR + all auxiliary CIDRs including GR subnets)
#   - GR Pod IPs need SNAT to node IP when accessing CVM metadata (169.254.x.x)
setup_native_gr() {
  info "$(is_zh && echo "配置 tke-bridge-agent..." || echo "Configuring tke-bridge-agent...")"
  local current_args patched_args needs_patch=false
  current_args=$(kubectl -n kube-system get ds tke-bridge-agent -o jsonpath='{.spec.template.spec.containers[0].args}')
  patched_args="$current_args"
  # 修改 CNI 配置输出到根目录
  if echo "$patched_args" | grep -q '/host/etc/cni/net.d/multus'; then
    patched_args=$(echo "$patched_args" | sed 's|/host/etc/cni/net.d/multus|/host/etc/cni/net.d|g')
    needs_patch=true
  fi
  # 禁用 portmap（cilium 的 kubeProxyReplacement 已包含 HostPort 能力，portmap 依赖已被卸载的 kube-proxy 的 iptables chain）
  if ! echo "$patched_args" | grep -q 'port-mapping=false'; then
    patched_args=$(echo "$patched_args" | sed 's/\]$/,"--port-mapping=false"]/')
    needs_patch=true
  fi
  if [[ "$needs_patch" == "true" ]]; then
    kubectl -n kube-system patch ds tke-bridge-agent --type='json' \
      -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${patched_args}}]"
    info "$(is_zh && echo "等待 tke-bridge-agent 滚动重启..." || echo "Waiting for tke-bridge-agent rollout...")"
    kubectl -n kube-system rollout status ds/tke-bridge-agent --timeout=120s
  else
    info "$(is_zh && echo "tke-bridge-agent 已配置完毕，跳过" || echo "tke-bridge-agent already configured, skipping")"
  fi

  # 配置 IP masquerade（GR Pod IP 访问 CVM metadata 等公共服务需要 SNAT 为节点 IP）
  info "$(is_zh && echo "配置 IP masquerade..." || echo "Configuring IP masquerade...")"
  local non_masq_cidrs=""
  # 从 TKE 自动生成的 ip-masq-agent-config 中获取 NonMasqueradeCIDRs
  local tke_cidrs
  tke_cidrs=$(kubectl -n kube-system get cm ip-masq-agent-config -o jsonpath='{.data.config}' 2>/dev/null | grep -A100 'NonMasqueradeCIDRs:' | grep '^\s*-' | sed 's/.*- //' || true)
  if [[ -n "$tke_cidrs" ]]; then
    while IFS= read -r cidr; do
      [[ -z "$cidr" ]] && continue
      non_masq_cidrs="${non_masq_cidrs}    - ${cidr}\n"
    done <<< "$tke_cidrs"
  fi
  # 创建 cilium 的 ip-masq-agent ConfigMap
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
$(echo -e "$non_masq_cidrs" | sed '/^$/d')
    masqLinkLocal: true
EOF
  info "$(is_zh && echo "ip-masq-agent ConfigMap 已创建" || echo "ip-masq-agent ConfigMap created")"
}

# setup_overlay_vpccni — Deletes webhook that auto-injects ENI IP resource requests.
# Without this, pods would be blocked by ip-scheduler waiting for ENI IP allocation.
setup_overlay_vpccni() {
  info "$(is_zh && echo "禁用 add-pod-eni-ip-limit-webhook..." || echo "Disabling add-pod-eni-ip-limit-webhook...")"
  kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook 2>/dev/null || true
}

# helm_install_cilium — Runs helm upgrade --install with mode-specific parameters.
# Assembles 4 argument arrays:
#   - image_args: TKE-accessible mirror image repos (quay.tencentcloudcr.com, k8smirror)
#   - common_args: shared params (kubeProxyReplacement, APF, etc.)
#   - toleration_args: operator tolerations for TKE-specific taints
#   - mode_args: routing/IPAM/CNI params specific to NETWORK_MODE x ROUTING_MODE
# If ENABLE_EGRESS=true, egress gateway params are merged into the install.
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
    --set image.repository="${IMAGE_REGISTRY}/cilium"
    --set envoy.image.repository="${IMAGE_REGISTRY}/cilium-envoy"
    --set operator.image.repository="${IMAGE_REGISTRY}/operator"
    --set certgen.image.repository="${IMAGE_REGISTRY}/certgen"
    --set hubble.relay.image.repository="${IMAGE_REGISTRY}/hubble-relay"
    --set hubble.ui.backend.image.repository="${IMAGE_REGISTRY}/hubble-ui-backend"
    --set hubble.ui.frontend.image.repository="${IMAGE_REGISTRY}/hubble-ui"
    --set nodeinit.image.repository="${IMAGE_REGISTRY}/startup-script"
    --set preflight.image.repository="${IMAGE_REGISTRY}/cilium"
    --set preflight.envoy.image.repository="${IMAGE_REGISTRY}/cilium-envoy"
    --set clustermesh.apiserver.image.repository="${IMAGE_REGISTRY}/clustermesh-apiserver"
    --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent
    --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
  )

  local -a common_args=(
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
    mode_args=(--set sysctlfix.enabled=false --set routingMode=native --set endpointRoutes.enabled=true --set ipam.mode=delegated-plugin --set enableIPv4Masquerade=false --set devices=eth+ --set cni.chainingMode=generic-veth --set cni.customConf=true --set cni.configMap=cni-config --set cni.externalRouting=true --set extraConfig.local-router-ipv4=169.254.32.16)
    ;;
  GR_native)
    mode_args=(--set sysctlfix.enabled=false --set cni.chainingMode=generic-veth --set cni.chainingTarget=tke-bridge --set routingMode=native --set endpointRoutes.enabled=true --set ipam.mode=delegated-plugin --set enableIPv4Masquerade=true --set bpf.masquerade=true --set ipMasqAgent.enabled=true --set devices=eth+ --set cni.externalRouting=true --set extraConfig.local-router-ipv4=169.254.32.16)
    ;;
  VPC-CNI_overlay)
    toleration_args+=(--set 'operator.tolerations[5].key=tke.cloud.tencent.com/eni-ip-unavailable,operator.tolerations[5].operator=Exists')
    mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=cluster-pool --set "ipam.operator.clusterPoolIPv4PodCIDRList={${POD_CIDR}}" --set ipam.operator.clusterPoolIPv4MaskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true)
    ;;
  GR_overlay)
    mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=cluster-pool --set "ipam.operator.clusterPoolIPv4PodCIDRList={${POD_CIDR}}" --set ipam.operator.clusterPoolIPv4MaskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true)
    ;;
  esac

  # Egress Gateway: merge params into helm install if enabled.
  # NOTE: egress_args is appended LAST in helm call below — its --set values
  # take precedence over both common_args and mode_args (helm last-wins).
  local -a egress_args=()
  if [[ "${ENABLE_EGRESS:-false}" == "true" ]]; then
    egress_args+=(--set egressGateway.enabled=true)
    # masquerade params - only add if not already in mode_args (GR_native already has them)
    if [[ "${NETWORK_MODE}_${ROUTING_MODE}" != "GR_native" ]]; then
      egress_args+=(--set enableIPv4Masquerade=true --set bpf.masquerade=true --set ipMasqAgent.enabled=true --set ipMasqAgent.config.masqLinkLocal=true)
    fi
  fi

  info "$(msg HELM_INSTALL) (${ROUTING_MODE} (${NETWORK_MODE}), cilium ${CILIUM_VERSION})"
  helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" \
    --namespace kube-system \
    "${image_args[@]}" "${toleration_args[@]}" "${common_args[@]}" "${mode_args[@]}" ${egress_args[@]+"${egress_args[@]}"}
}

# apply_apf — Creates APF (API Priority and Fairness) rate limiting rules for cilium.
# Prevents cilium from overwhelming the apiserver in large clusters.
# FlowSchema matches cilium ServiceAccount's list operations on cilium.io/* and pods.
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

# helm_enable_egress — Enables Egress Gateway via helm upgrade --reuse-values.
# Auto-detects current cilium version from helm release.
# Enables: egressGateway, IPv4 masquerade (BPF), ip-masq-agent with masqLinkLocal.
# Restarts cilium ds and operator to apply changes.
helm_enable_egress() {
  local current_version
  current_version=$(helm -n kube-system list -o json | grep -o '"chart":"cilium-[^"]*"' | sed 's/.*cilium-//' | sed 's/"//')
  if [[ -z "$current_version" ]]; then
    fatal "$(is_zh && echo "无法检测当前 Cilium 版本" || echo "Cannot detect current Cilium version")"
  fi
  info "$(is_zh && echo "检测到 Cilium 版本: ${current_version}" || echo "Detected Cilium version: ${current_version}")"

  info "$(is_zh && echo "执行 helm upgrade 启用 Egress Gateway..." || echo "Running helm upgrade to enable Egress Gateway...")"
  helm upgrade cilium cilium/cilium --version "$current_version" \
    --namespace kube-system \
    --reuse-values \
    --set egressGateway.enabled=true \
    --set enableIPv4Masquerade=true \
    --set bpf.masquerade=true \
    --set ipMasqAgent.enabled=true \
    --set ipMasqAgent.config.masqLinkLocal=true

  info "$(is_zh && echo "重启 cilium..." || echo "Restarting cilium...")"
  kubectl -n kube-system rollout restart ds/cilium
  kubectl -n kube-system rollout restart deploy/cilium-operator
  # Only wait for rollout if cluster has nodes (empty clusters can't schedule pods)
  local node_count
  node_count=$(kubectl get node --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$node_count" -gt 0 ]]; then
    kubectl -n kube-system rollout status ds/cilium --timeout=120s
    kubectl -n kube-system rollout status deploy/cilium-operator --timeout=120s
  fi
}

# print_installed_values — Exports the actual helm values used for this installation.
# Uses `helm get values` to show the exact configuration in YAML format.
# Helps users understand what was configured and customize for their own deployment flow.
print_installed_values() {
  echo ""
  if is_zh; then
    info "当前安装使用的 Helm Values（可复制保存为 values.yaml 文件自行管理）:"
  else
    info "Helm values used for this installation (can be saved as values.yaml for self-managed deployments):"
  fi
  echo ""
  echo "---"
  helm get values cilium -n kube-system 2>/dev/null
  echo "---"
  echo ""
  if is_zh; then
    info "导出方法: helm get values cilium -n kube-system > values.yaml"
  else
    info "Export: helm get values cilium -n kube-system > values.yaml"
  fi
}

# print_replay_command — Prints a non-interactive command that reproduces the current install.
# Uses environment variables to skip all interactive prompts on subsequent runs.
# Called at the end of cmd_install_cilium to help users batch-deploy to multiple clusters.
print_replay_command() {
  local script_url="https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh"
  local env_vars="ROUTING_MODE=${ROUTING_MODE} CILIUM_VERSION=${CILIUM_VERSION}"
  if [[ "${IMAGE_REGISTRY}" != "${DEFAULT_IMAGE_REGISTRY}" ]]; then
    env_vars="${env_vars} IMAGE_REGISTRY=${IMAGE_REGISTRY}"
  fi
  if [[ "$ROUTING_MODE" == "overlay" ]]; then
    env_vars="${env_vars} POD_CIDR=${POD_CIDR} POD_CIDR_MASK=${POD_CIDR_MASK}"
  fi
  env_vars="${env_vars} ENABLE_EGRESS=${ENABLE_EGRESS:-false} ENABLE_LOCALDNS=${ENABLE_LOCALDNS:-false}"
  echo ""
  if is_zh; then
    info "如需在其他集群重复相同安装，可直接执行以下命令（无需交互）:"
  else
    info "To repeat this install on other clusters without interaction, run:"
  fi
  echo ""
  echo "  ${env_vars} \\"
  echo "    curl -sfL ${script_url} | bash -s install-cilium"
  echo ""
}

# cmd_install_cilium — Main install wizard. Interactive flow:
#   1. check_prerequisites (kubectl, helm, cluster)
#   2. check_nodes (no non-super nodes)
#   3. detect_network_mode (GR or VPC-CNI)
#   4. select_routing_mode (native or overlay)
#   5. confirm_cilium_version
#   6. confirm_pod_cidr (overlay only)
#   7. confirm_enable_egress (optional)
#   8. confirm_enable_localdns (optional)
#   9. uninstall_tke_components → setup_* → helm_install → apply_apf
#  10. (optional) enable egress / install localdns
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
  confirm_image_registry
  confirm_pod_cidr
  confirm_enable_egress
  confirm_enable_localdns

  echo ""
  info "$(is_zh && echo "安装方案" || echo "Plan"): ${ROUTING_MODE} (${NETWORK_MODE}), Cilium ${CILIUM_VERSION}"
  echo ""

  uninstall_tke_components
  case "${NETWORK_MODE}_${ROUTING_MODE}" in
  VPC-CNI_native) setup_native_vpccni ;;
  GR_native) setup_native_gr ;;
  VPC-CNI_overlay) setup_overlay_vpccni ;;
  GR_overlay) ;;
  esac

  helm_install_cilium
  apply_apf

  # Optional: install localdns (egress is already merged into helm_install_cilium)
  if [[ "${ENABLE_LOCALDNS:-false}" == "true" ]]; then
    install_localdns_internal
  fi

  echo ""
  info "============================================"
  info "$(msg CILIUM_DONE)"
  info "  kubectl -n kube-system get pod -l app.kubernetes.io/part-of=cilium"
  info "  kubectl -n kube-system exec ds/cilium -- cilium status --brief"
  info "============================================"

  # GR native: remind user to add taint to node pools
  if [[ "${NETWORK_MODE}_${ROUTING_MODE}" == "GR_native" ]]; then
    echo ""
    if is_zh; then
      warn "Native Routing (GR) 模式下，节点池必须配置以下污点，避免 Pod 在 cilium 就绪前被调度:"
      echo "    node.cilium.io/agent-not-ready=true:NoSchedule"
      info "cilium agent 启动完成后会自动移除此污点，不影响后续 Pod 调度。"
    else
      warn "Native Routing (GR) requires the following taint on node pools to prevent Pods from being scheduled before cilium is ready:"
      echo "    node.cilium.io/agent-not-ready=true:NoSchedule"
      info "Cilium agent will automatically remove this taint once ready. Normal Pod scheduling is not affected."
    fi
  fi

  # Export installed values as YAML for user reference
  print_installed_values

  # Print non-interactive replay command for batch deployment
  print_replay_command

  echo ""
}

# ====== install-localdns subcommand ======
# Deploys Nodelocal DNSCache with CiliumLocalRedirectPolicy for DNS caching.

# install_localdns_internal — Core deployment logic (no prerequisite checks).
# Called from both cmd_install_localdns (standalone) and cmd_install_cilium (optional).
# Steps:
#   1. Create ServiceAccount + kube-dns-upstream Service + headless Service
#   2. Get kube-dns-upstream ClusterIP (MUST use this instead of kube-dns ClusterIP
#      to avoid CLRP redirect loop — CLRP redirects kube-dns traffic to localdns,
#      so localdns must forward to kube-dns-upstream which is NOT intercepted by CLRP)
#   3. Create ConfigMap with Corefile (forward cluster.local to upstream via TCP)
#   4. Create DaemonSet (non-hostNetwork, listening on kube-dns ClusterIP)
#   5. Create CiliumLocalRedirectPolicy to redirect kube-dns traffic to local pod

install_localdns_internal() {
  info "$(is_zh && echo "开始部署 Nodelocal DNSCache..." || echo "Deploying Nodelocal DNSCache...")"

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
        cache {
                success 9984 30
                denial 9984 5
        }
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} {
                force_tcp
        }
        prometheus :9253
        health
    }
    in-addr.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} {
                force_tcp
        }
        prometheus :9253
    }
    ip6.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 0.0.0.0
        forward . ${upstream_ip} {
                force_tcp
        }
        prometheus :9253
    }
    .:53 {
        template ANY HINFO . {
            rcode NXDOMAIN
        }
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

  # Wait for CiliumLocalRedirectPolicy CRD to be available (created by cilium-operator).
  # In empty clusters, operator may not be scheduled yet — prompt user to add nodes.
  info "$(is_zh && echo "创建 CiliumLocalRedirectPolicy..." || echo "Creating CiliumLocalRedirectPolicy...")"
  if ! kubectl get crd ciliumlocalredirectpolicies.cilium.io &>/dev/null; then
    if is_zh; then
      warn "CiliumLocalRedirectPolicy CRD 尚未就绪（cilium-operator 可能还未启动）。"
      info "请添加节点到集群，等待 cilium-operator 启动后脚本将自动继续..."
    else
      warn "CiliumLocalRedirectPolicy CRD not ready (cilium-operator may not be running yet)."
      info "Please add nodes to the cluster. The script will continue once cilium-operator starts..."
    fi
    while ! kubectl get crd ciliumlocalredirectpolicies.cilium.io &>/dev/null; do
      sleep 5
    done
    info "$(is_zh && echo "CRD 已就绪，继续安装" || echo "CRD ready, continuing")"
  fi
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

# cmd_install_localdns — Standalone localdns install subcommand.
# Checks cilium is installed and CiliumLocalRedirectPolicy CRD exists,
# then delegates to install_localdns_internal().
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

  info "$(is_zh && echo "检测到 cilium 已安装" || echo "Cilium detected")"
  install_localdns_internal
}

# ====== e2e-test subcommand ======
# Runs cilium connectivity test with TKE-compatible image overrides.
# Skips external/internet tests (pod-to-world, pod-to-cidr) because:
#   - Nodes may not have public internet bandwidth.
#   - Default external targets (one.one.one.one) may be blocked by GFW in China.
# Image mapping:
#   quay.io/cilium/*           → quay.tencentcloudcr.com/cilium/* (internal mirror)
#   registry.k8s.io/coredns/*  → docker.io/k8smirror/coredns:*   (synced to dockerhub)
#   gcr.io/*/echo-advanced     → docker.io/k8smirror/echo-advanced:* (synced to dockerhub)

cmd_e2e_test() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      Cilium Connectivity Test        ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  command -v cilium &>/dev/null || fatal "$(is_zh && echo "cilium CLI 未安装，请先安装: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli" || echo "cilium CLI not installed. Install: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli")"
  command -v kubectl &>/dev/null || fatal "$(msg NO_KUBECTL)"
  kubectl cluster-info &>/dev/null || fatal "$(msg NO_CLUSTER)"

  # Phase 1: cilium-health per-node verification
  info "$(is_zh && echo "[1/2] 验证 cilium-health 全节点连通性..." || echo "[1/2] Verifying cilium-health per-node connectivity...")"
  echo ""
  local failed=0
  local total=0
  local cilium_pods
  cilium_pods=$(kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  if [[ -z "$cilium_pods" ]]; then
    fatal "$(is_zh && echo "未找到 cilium agent pod" || echo "No cilium agent pods found")"
  fi
  while IFS= read -r pod; do
    [[ -z "$pod" ]] && continue
    total=$((total + 1))
    local node_ip
    node_ip=$(kubectl -n kube-system get pod "$pod" -o jsonpath='{.status.hostIP}')
    local health_output
    health_output=$(kubectl -n kube-system exec "$pod" -- cilium-health status 2>&1)
    local cluster_health
    cluster_health=$(echo "$health_output" | grep "Cluster health:" | awk '{print $3}')
    local localhost_line
    localhost_line=$(echo "$health_output" | grep "localhost")
    local node_probe endpoint_probe
    node_probe=$(echo "$localhost_line" | awk '{print $4}')
    endpoint_probe=$(echo "$localhost_line" | awk '{print $5}')

    local status_icon="✅"
    if [[ "$node_probe" != "1/1" ]]; then
      status_icon="❌"
      failed=$((failed + 1))
    elif [[ -n "$endpoint_probe" && "$endpoint_probe" != "0/0" && "$endpoint_probe" != "1/1" ]]; then
      status_icon="❌"
      failed=$((failed + 1))
    fi
    local kernel
    kernel=$(kubectl get node "$node_ip" -o jsonpath='{.status.nodeInfo.kernelVersion}' 2>/dev/null)
    local os
    os=$(kubectl get node "$node_ip" -o jsonpath='{.status.nodeInfo.osImage}' 2>/dev/null)
    echo "  ${status_icon} ${node_ip} | ${os} (${kernel}) | node=${node_probe} endpoint=${endpoint_probe} | ${cluster_health}"
  done <<< "$cilium_pods"

  echo ""
  if [[ $failed -gt 0 ]]; then
    fatal "$(is_zh && echo "cilium-health 验证失败: ${failed}/${total} 节点异常" || echo "cilium-health verification failed: ${failed}/${total} nodes unhealthy")"
  fi
  info "$(is_zh && echo "cilium-health 验证通过: ${total}/${total} 节点健康" || echo "cilium-health passed: ${total}/${total} nodes healthy")"
  echo ""

  # Phase 2: cilium connectivity test
  info "$(is_zh && echo "[2/2] 运行 cilium connectivity test（跳过公网测试）..." || echo "[2/2] Running cilium connectivity test (skipping external tests)...")"
  echo ""

  cilium connectivity test \
    --test '!/pod-to-world' \
    --test '!/pod-to-cidr' \
    --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
    --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
    --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
    --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1 \
    --test-conn-disrupt-image quay.tencentcloudcr.com/cilium/test-connection-disruption:v0.0.17 \
    "$@"

  echo ""
  info "============================================"
  info "$(is_zh && echo "测试完成！" || echo "Tests completed!")"
  info "============================================"
  echo ""
}

# ====== enable-egress-gateway subcommand ======
# Standalone subcommand to enable Egress Gateway on an existing cilium installation.
# Checks cilium is installed, then delegates to helm_enable_egress().

cmd_enable_egress_gateway() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   Enable Cilium Egress Gateway      ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  local has_cilium
  has_cilium=$(kubectl -n kube-system get ds cilium --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$has_cilium" -eq 0 ]]; then
    fatal "$(msg NO_CILIUM)"
  fi

  info "$(is_zh && echo "添加 Cilium Helm 仓库..." || echo "Adding Cilium Helm repo...")"
  helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
  helm repo update cilium 2>/dev/null || true

  helm_enable_egress

  echo ""
  info "============================================"
  info "$(msg EGRESS_DONE)"
  info "============================================"
  echo ""
}

# ====== Main Entry Point ======
# Dispatches to the appropriate subcommand based on the first argument.

main() {
  local cmd="${1:-}"
  case "$cmd" in
  install-cilium) cmd_install_cilium ;;
  install-localdns) cmd_install_localdns ;;
  e2e-test) shift; cmd_e2e_test "$@" ;;
  enable-egress-gateway) cmd_enable_egress_gateway ;;
  help | --help | -h | "") show_help ;;
  *)
    error "$(is_zh && echo "未知命令" || echo "Unknown command"): $cmd"
    echo ""
    show_help
    exit 1
    ;;
  esac
}

main "$@"
