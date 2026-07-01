#!/usr/bin/env bash
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
#   bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- <command>
#
# Why `bash -c "$(curl ...)"` and not `curl ... | bash`:
#   The interactive subcommands (install etc.) call `read` to ask the
#   user. With `curl ... | bash`, bash's stdin is consumed by curl's pipe
#   output, so `read` returns EOF immediately and the script exits right after
#   printing the menu. With `bash -c "$(curl ...)"`, bash receives the script
#   as a string argument and stdin remains attached to the terminal — `read`
#   works normally. This pattern works for both interactive and non-interactive
#   subcommands, so all docs should use it.
# For non-interactive batch deployment, see the env var section at the bottom.
#
# Commands:
#   install                 Install Cilium (auto-detect network mode, interactive)
#   uninstall               Uninstall Cilium and restore TKE built-in CNI components
#   install-localdns        Install Nodelocal DNSCache with Cilium integration
#   test                    Run Cilium connectivity test (cilium connectivity test)
#   perf                    Run Cilium performance test (cilium connectivity perf)
#   enable-egress-gateway   Enable Cilium Egress Gateway
#   enable-hubble           Enable Hubble (Hubble Relay + Hubble UI)
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
#    - If the command should be optionally triggered from install,
#      extract core logic into a separate function (like install_localdns_internal)
#      and add an interactive confirm_enable_<name>() + call it from cmd_install_cilium.
#
# 3. IMAGE REFERENCES
#    - TKE nodes can pull from: docker.io (direct), quay.tencentcloudcr.com (quay.io mirror).
#    - Images from registry.k8s.io / gcr.io are NOT accessible; sync them to docker.io/k8smirror:
#        skopeo copy -a docker://<source> docker://docker.io/k8smirror/<name>:<tag>
#    - Update image references in: helm_install_cilium() image_args, cmd_test(), NODE_LOCAL_DNS_IMAGE.
#
# 4. NETWORK MODE DETECTION (detect_network_mode)
#    Detection logic for TKE cluster network type:
#    - ds/tke-bridge-agent exists        → GlobalRouter (GR)
#    - ds/tke-eni-agent exists           → VPC-CNI
#    - ds/cilium exists (tkeimages)      → CiliumOverlay (built-in, not supported)
#    - ds/cilium exists (non-tkeimages)  → Already installed (not supported)
#    - VPC-CNI + ds/cilium (tkeimages)   → DataPlaneV2 (not supported)
#
# 5. INSTALL MODES (3 supported combinations)
#    ┌──────────────────┬──────────────────────────────────────────────────┐
#    │ VPC-CNI + native │ CNI chaining via ConfigMap (cni-config)         │
#    │ VPC-CNI + overlay│ Full cilium CNI (tunnel/vxlan, multi-pool)     │
#    │                  │ + delete mutatingwebhookconfiguration           │
#    │ GR + overlay     │ Full cilium CNI (tunnel/vxlan, multi-pool)     │
#    └──────────────────┴──────────────────────────────────────────────────┘
#    GR + native is NOT supported — see appendix/gr-native-not-recommended
#    for the failure modes (cross-node Pod-to-Pod broken, no L7/DNS NP, etc).
#
# 6. CILIUM VERSION
#    - DEFAULT_CILIUM_VERSION is the recommended version tested with this script.
#    - When upgrading, test all 3 supported install modes before updating the default.
#
# 7. NON-INTERACTIVE MODE (environment variables)
#    All interactive prompts in install can be skipped by setting env vars:
#      ROUTING_MODE     "native" or "overlay" (required)
#      CILIUM_VERSION   e.g. "1.19.5" (optional, defaults to DEFAULT_CILIUM_VERSION)
#      POD_CIDR         e.g. "10.244.0.0/16" (only for overlay mode)
#      POD_CIDR_MASK    e.g. "24" (only for overlay mode)
#      ENABLE_EGRESS    "true" or "false" (optional, default false)
#      ENABLE_IP_MASQ   "true" or "false" (optional, only meaningful for Native;
#                       default true when Egress=false, forced true when Egress=true.
#                       When true, cilium SNATs Pod traffic destined OUTSIDE
#                       NON_MASQ_CIDRS to node IP — required for Native Pods to
#                       reach public internet via node EIP without NAT gateway.)
#      NON_MASQ_CIDRS   space-separated, e.g. "10.0.0.0/8 172.16.0.0/12"
#                       (only used when Native + ip-masq-agent enabled; if unset,
#                       reads TKE's ip-masq-agent-config CM, then prompts user)
#      ENABLE_HUBBLE    "true" or "false" (optional, default true — pressing Enter
#                       in the interactive prompt enables hubble; set "false" to
#                       skip Hubble Relay + Hubble UI)
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
# 9. KEEP COMMENTS & DOCS IN SYNC
#    Whenever you change behavior or rename anything, also scan and update:
#    a) This file:
#       - Header "Commands:" list, show_help() output, print_replay_command()
#       - Function docstrings that count things ("Assembles N arrays",
#         "Two concerns drive this", "all M install modes") — easy to miss
#       - Old subcommand-name references (history: e2e-test → test/perf was
#         missed for months)
#       - Helper functions left dead after a feature removal (e.g. when
#         removing an auto-detection branch, also remove the helper it called)
#    b) Sibling docs that reference this script (sync zh + en together):
#       - docs/networking/cilium/{install,with-node-local-dns,observability,
#         egress-gateway}.md
#       - docs/networking/cilium/appendix/{connectivity-test,performance-test,
#         verified-os,host-routing,...}.md
#       - i18n/en/.../same files
#    Mismatched comments/docs are worse than missing ones — they actively
#    mislead the next contributor.
#
###############################################################################

# ====== Defaults ======

# Cilium helm chart version. Bump this when a new version is tested and verified.
DEFAULT_CILIUM_VERSION="1.19.5"
# Default image registry prefix for cilium images (TKE internal mirror).
DEFAULT_IMAGE_REGISTRY="quay.tencentcloudcr.com/cilium"
# Default Pod CIDR for overlay mode. Only used when ROUTING_MODE=overlay.
DEFAULT_POD_CIDR="10.244.0.0/16"
# Default per-node subnet mask for overlay mode (24 = max 254 pods per node).
DEFAULT_POD_CIDR_MASK="24"
# Nodelocal DNSCache image. Synced from registry.k8s.io/dns/k8s-dns-node-cache to dockerhub mirror.
NODE_LOCAL_DNS_IMAGE="docker.io/k8smirror/k8s-dns-node-cache:1.26.4"

# Curl image used by both `test` (passed via --curl-image) and node egress probe.
# Single source of truth so they stay in sync.
CILIUM_CURL_IMAGE="quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0"

# China-mainland-reachable defaults for cilium connectivity test external targets.
# Used when nodes are detected to be in a Chinese region (see is_china_region).
#
# Domain choices:
#   - npmmirror.com    (resolves to a real public-internet ECS IP, NOT a TKE
#                       link-local mirror; supports HTTP/HTTPS/index.html → 200)
#   - mirrors.aliyun.com (resolves to a real public-internet IP; HTTP 301 / HTTPS 200,
#                         used as PodToWorld2's --external-other-target which only
#                         tests one HTTPS request)
#
# IP choices:
#   The connectivity test's pod-to-cidr scenario does `curl https://<IP>` directly,
#   without SNI. Only one CN service was found whose direct-IP HTTPS responds with 2xx:
#   npmmirror.com's backing IP (in 47.96.0.0/16). That IP is dynamic — ECS IPs change.
#   So we resolve npmmirror.com at runtime and reuse its IP as --external-ip, then
#   scan its /16 for another working IP for --external-other-ip. We also set
#   --curl-insecure because direct-IP HTTPS cannot pass SAN validation (no IP-bound
#   cert like Cloudflare's 1.1.1.1).
CN_EXTERNAL_TARGET="npmmirror.com."
CN_EXTERNAL_OTHER_TARGET="mirrors.aliyun.com."
# Domain whose IP we'll resolve and reuse as --external-ip
CN_EXTERNAL_IP_DOMAIN="npmmirror.com"

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
MSG_ZH_HELP_CMD_CILIUM="  install            安装 Cilium 到 TKE 集群（自动检测网络模式，交互选择方案）"
MSG_EN_HELP_CMD_CILIUM="  install            Install Cilium to TKE cluster (auto-detect network mode, interactive)"
MSG_ZH_HELP_CMD_UNINSTALL="  uninstall          卸载 Cilium 并恢复 TKE 内置网络组件"
MSG_EN_HELP_CMD_UNINSTALL="  uninstall          Uninstall Cilium and restore TKE built-in network components"
MSG_ZH_HELP_CMD_LOCALDNS="  install-localdns   安装 Nodelocal DNSCache 并配置与 Cilium 共存"
MSG_EN_HELP_CMD_LOCALDNS="  install-localdns   Install Nodelocal DNSCache with Cilium integration"
MSG_ZH_HELP_CMD_TEST="  test               运行 Cilium 连通性测试"
MSG_EN_HELP_CMD_TEST="  test               Run Cilium connectivity test"
MSG_ZH_HELP_CMD_PERF="  perf               运行 Cilium 性能测试 (cilium connectivity perf)"
MSG_EN_HELP_CMD_PERF="  perf               Run Cilium performance test (cilium connectivity perf)"
MSG_ZH_HELP_CMD_EGRESS="  enable-egress-gateway  启用 Cilium Egress Gateway 功能"
MSG_EN_HELP_CMD_EGRESS="  enable-egress-gateway  Enable Cilium Egress Gateway"
MSG_ZH_HELP_CMD_HUBBLE="  enable-hubble      启用 Hubble (Hubble Relay + Hubble UI)"
MSG_EN_HELP_CMD_HUBBLE="  enable-hubble      Enable Hubble (Hubble Relay + Hubble UI)"
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

# GR cluster + Native Routing not supported reason
MSG_ZH_GR_NATIVE_NOT_SUPPORTED="GR 集群仅支持 Overlay 模式，已自动选择 Overlay (vxlan)。"
MSG_EN_GR_NATIVE_NOT_SUPPORTED="GR clusters only support Overlay mode, automatically selecting Overlay (vxlan)."
MSG_ZH_GR_NATIVE_NOT_SUPPORTED_DETAIL="GR + Native Routing 在 cilium chained CNI 模式下存在严重兼容性问题：\n  - 跨节点 Pod-to-Pod 流量不通\n  - L7 / DNS / toFQDNs NetworkPolicy 不支持\n  - 节点池必须额外打 cilium agent-not-ready 污点\n  - 与 VPC-CNI 共存能力被破坏\n\n本系列教程已不再提供该方案，详见:\nhttps://imroc.cc/tke/networking/cilium/appendix/gr-native-not-recommended\n\n如需 Native Routing 性能，请使用 VPC-CNI 集群。"
MSG_EN_GR_NATIVE_NOT_SUPPORTED_DETAIL="GR + Native Routing has severe compatibility issues with cilium chained CNI:\n  - Cross-node Pod-to-Pod traffic broken\n  - L7 / DNS / toFQDNs NetworkPolicy not supported\n  - Node pools require an extra cilium agent-not-ready taint\n  - VPC-CNI co-existence breaks\n\nThis tutorial no longer offers that option, see:\nhttps://imroc.cc/tke/en/networking/cilium/appendix/gr-native-not-recommended\n\nFor Native Routing performance, please use a VPC-CNI cluster."

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
MSG_ZH_CILIUM_DONE="Cilium 安装完成！请验证:"
MSG_EN_CILIUM_DONE="Cilium installed! Verify with:"
# Localdns
MSG_ZH_NO_CILIUM="未检测到 cilium，请先安装 cilium (install) 再安装 localdns。"
MSG_EN_NO_CILIUM="Cilium not detected. Run install first."
MSG_ZH_NO_CLRP_CRD="CiliumLocalRedirectPolicy CRD 不存在，请确保安装 cilium 时启用了 localRedirectPolicies.enabled=true"
MSG_EN_NO_CLRP_CRD="CiliumLocalRedirectPolicy CRD not found. Ensure localRedirectPolicies.enabled=true in cilium install."
MSG_ZH_LOCALDNS_DONE="Nodelocal DNSCache 安装完成！"
MSG_EN_LOCALDNS_DONE="Nodelocal DNSCache installed!"
# Egress Gateway
MSG_ZH_EGRESS_DONE="Egress Gateway 已启用！"
MSG_EN_EGRESS_DONE="Egress Gateway enabled!"
# Hubble
MSG_ZH_HUBBLE_DONE="Hubble (Relay + UI) 已启用！"
MSG_EN_HUBBLE_DONE="Hubble (Relay + UI) enabled!"

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
  echo "  bash -c \"\$(curl -sfL $url)\" -- <command>"
  echo ""
  msg HELP_COMMANDS
  msg HELP_CMD_CILIUM
  msg HELP_CMD_UNINSTALL
  msg HELP_CMD_LOCALDNS
  msg HELP_CMD_TEST
  msg HELP_CMD_PERF
  msg HELP_CMD_EGRESS
  msg HELP_CMD_HUBBLE
  msg HELP_CMD_HELP
  echo ""
  msg HELP_EXAMPLES
  echo "  bash -c \"\$(curl -sfL $url)\" -- install"
  echo "  bash -c \"\$(curl -sfL $url)\" -- install-localdns"
  echo "  bash -c \"\$(curl -sfL $url)\" -- test"
  echo ""
  if is_zh; then
    echo "提示:"
    echo "  推荐使用 bash -c \"\$(curl ...)\" -- 一行执行的写法（兼容所有交互/非交互子命令）。"
    echo "  不要用 curl ... | bash，否则 bash 的 stdin 会被 curl 占用，交互式 read 立即收到 EOF。"
  else
    echo "Note:"
    echo "  Use bash -c \"\$(curl ...)\" -- <command> (works for both interactive and non-interactive subcommands)."
    echo "  Do NOT use curl ... | bash — bash's stdin gets consumed by curl, breaking interactive prompts."
  fi
  echo ""
  if is_zh; then
    echo "文档:"
    echo "  https://imroc.cc/tke/networking/cilium/install"
  else
    echo "Docs:"
    echo "  https://imroc.cc/tke/en/networking/cilium/install"
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
  has_bridge_agent=$(
    kubectl -n kube-system get ds tke-bridge-agent --no-headers 2>/dev/null | wc -l | tr -d ' '
    exit 0
  )
  has_eni_agent=$(
    kubectl -n kube-system get ds tke-eni-agent --no-headers 2>/dev/null | wc -l | tr -d ' '
    exit 0
  )
  has_cilium=$(
    kubectl -n kube-system get ds cilium --no-headers 2>/dev/null | wc -l | tr -d ' '
    exit 0
  )

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

# ====== install subcommand ======
# Interactive functions for gathering user input during cilium installation.

# select_routing_mode — Prompts user to choose Native Routing or Overlay.
# Sets global variable ROUTING_MODE to "native" or "overlay".
# Skipped if ROUTING_MODE env var is already set.

select_routing_mode() {
  # GR cluster: Native Routing not supported (severe compatibility issues),
  # automatically force Overlay mode and inform the user.
  if [[ "${NETWORK_MODE:-}" == "GR" ]]; then
    if [[ "${ROUTING_MODE:-}" == "native" ]]; then
      error "$(msg GR_NATIVE_NOT_SUPPORTED)"
      echo -e "$(msg GR_NATIVE_NOT_SUPPORTED_DETAIL)"
      fatal "$(is_zh && echo "请取消设置 ROUTING_MODE=native 或在 VPC-CNI 集群上使用。" || echo "Please unset ROUTING_MODE=native or use a VPC-CNI cluster.")"
    fi
    info "$(msg GR_NATIVE_NOT_SUPPORTED)"
    echo -e "$(msg GR_NATIVE_NOT_SUPPORTED_DETAIL)"
    echo ""
    ROUTING_MODE="overlay"
    info "$(is_zh && echo "已选择:" || echo "Selected:") Overlay (vxlan)"
    return
  fi

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

# confirm_enable_ip_masq — Asks user whether to enable cilium's BPF ip-masq-agent
# in the Native + no-Egress combo (default: Y, just press Enter to accept).
#
# Why this prompt exists:
#   In TKE VPC-CNI Native mode, Pod IPs are valid VPC IPs (allocated from a
#   secondary ENI's IP pool), so cilium does NOT SNAT Pod traffic by default
#   (enableIPv4Masquerade=false). This is fine for east-west traffic. But for
#   Pod → public internet:
#     - Pod's source IP is the secondary-ENI IP (no EIP attached to that ENI)
#     - Without SNAT, the packet leaves the node with the secondary-ENI IP
#       as source — there's no return path
#     - Result: Pod cannot reach public internet, even if the node has an EIP
#       on its primary ENI (the EIP only covers the host netns, not Pod IPs)
#   Three ways to fix it:
#     1. Configure a NAT gateway in the VPC for outbound traffic
#     2. Enable Cilium Egress Gateway (sends Pod traffic via a chosen gateway)
#     3. Enable cilium's BPF ip-masq-agent: SNAT Pod traffic destined OUTSIDE
#        NON_MASQ_CIDRS to the node IP (which has the EIP) — this is what TKE's
#        own ip-masq-agent addon does, and what we re-create with cilium here.
#
# This function only triggers for VPC-CNI Native + ENABLE_EGRESS=false. When
# ENABLE_EGRESS=true, ip-masq-agent is forced on by helm_install_cilium and
# this prompt is skipped.
#
# Sets ENABLE_IP_MASQ=true/false. Skipped if ENABLE_IP_MASQ env var is already set.
confirm_enable_ip_masq() {
  if [[ "$ROUTING_MODE" != "native" ]] || [[ "${ENABLE_EGRESS:-false}" == "true" ]]; then
    return
  fi
  if [[ -n "${ENABLE_IP_MASQ:-}" ]]; then
    return
  fi
  echo ""
  if is_zh; then
    info "Native Routing 模式下 Pod IP 是 VPC 内合法 IP，默认不做 SNAT，但这意味着:"
    info "  - 即使节点绑定了 EIP，Pod 也无法访问公网（EIP 只对节点主网卡生效，"
    info "    Pod IP 在辅助网卡的 IP 池里，出公网时不会经过节点 EIP）"
    info "  - 必须满足下列任一条件 Pod 才能出公网:"
    info "      a) VPC 配置 NAT 网关；"
    info "      b) 启用 Cilium Egress Gateway；"
    info "      c) 启用 cilium 的 ip-masq-agent，将 Pod 出 VPC 的流量 SNAT 成节点 IP"
    info "         （走节点主网卡 + 节点 EIP 出公网，相当于自建版 TKE ip-masq-agent）"
  else
    info "In Native Routing mode, Pod IPs are valid VPC IPs and SNAT is off by default."
    info "However this means:"
    info "  - Pods CANNOT reach public internet even if the node has an EIP."
    info "    The EIP only covers the node's primary ENI; Pod IPs live on secondary"
    info "    ENIs and their egress packets do NOT pass through the node EIP."
    info "  - To enable Pod → public internet, you need ONE of:"
    info "      a) A NAT gateway in the VPC; or"
    info "      b) Cilium Egress Gateway; or"
    info "      c) cilium's ip-masq-agent: SNAT Pod traffic leaving the VPC to the"
    info "         node IP (so it goes out via the node's primary ENI + EIP — the"
    info "         self-managed equivalent of TKE's built-in ip-masq-agent)."
  fi
  echo ""
  local prompt
  if is_zh; then
    prompt="是否启用 ip-masq-agent (推荐)？[Y/n]: "
  else
    prompt="Enable ip-masq-agent (recommended)? [Y/n]: "
  fi
  read -rp "$(echo -e "${BLUE}${prompt}${NC}")" masq_input
  masq_input=$(echo "$masq_input" | tr '[:upper:]' '[:lower:]')
  if [[ -z "$masq_input" || "$masq_input" == "y" || "$masq_input" == "yes" ]]; then
    ENABLE_IP_MASQ=true
  else
    ENABLE_IP_MASQ=false
  fi
}

# Default CIDRs to use when neither NON_MASQ_CIDRS env var nor TKE's
# ip-masq-agent-config ConfigMap is available. RFC 1918 covers all valid
# Tencent Cloud VPC ranges (main + secondary CIDRs MUST come from these three).
DEFAULT_NON_MASQ_CIDRS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"

# resolve_non_masq_cidrs — Determines the list of CIDRs that cilium's BPF
# ip-masq-agent should NOT masquerade. Required whenever ip-masq-agent is enabled
# in Native Routing mode.
#
# When this triggers (Native Routing + ip-masq-agent enabled):
#   1. Native + Egress Gateway:
#      cilium source forces enableIPv4Masquerade=true. Without an accurate
#      non-masquerade CIDR list, cilium SNATs cross-node Pod-to-Pod traffic to
#      link-local / node IPs, breaking source-endpoint-label-based NetworkPolicy
#      across nodes.
#   2. Native + ENABLE_IP_MASQ=true (no Egress):
#      We turn ip-masq-agent on so that Pod → public internet egress goes
#      through node EIP via SNAT. nonMasqueradeCIDRs ensures Pod-to-Pod and
#      Pod-to-VPC traffic keeps the original Pod IP (preserves NetworkPolicy
#      source identity) and only public-internet-bound traffic gets SNAT'd.
#
# Resolution priority:
#   1. NON_MASQ_CIDRS env var (space-separated, takes precedence)
#   2. Existing TKE ip-masq-agent-config ConfigMap in kube-system (TKE's
#      built-in ip-masq-agent addon writes VPC main + secondary CIDRs there
#      automatically). Format: data.config is YAML containing list under
#      nonMasqueradeCIDRs / NonMasqueradeCIDRs / nonMasqueradeSrcCIDRs.
#   3. Interactive prompt (default: RFC 1918 three ranges, covers all VPC configs)
#
# Sets global NON_MASQ_CIDRS to a space-separated CIDR list.
# Skipped entirely if not Native or ip-masq-agent disabled.
resolve_non_masq_cidrs() {
  if [[ "$ROUTING_MODE" != "native" ]]; then
    return
  fi
  if [[ "${ENABLE_EGRESS:-false}" != "true" ]] && [[ "${ENABLE_IP_MASQ:-false}" != "true" ]]; then
    return
  fi

  if [[ -n "${NON_MASQ_CIDRS:-}" ]]; then
    info "Non-masquerade CIDRs: $NON_MASQ_CIDRS (from env)"
    return
  fi

  # Try to reuse TKE's ip-masq-agent-config ConfigMap (TKE addon).
  # `|| true` guards against `set -e` exiting on missing cm (the recommended
  # install path uninstalls TKE's ip-masq-agent addon, so the cm often doesn't exist).
  local tke_cm_config
  tke_cm_config=$(kubectl -n kube-system get cm ip-masq-agent-config -o jsonpath='{.data.config}' 2>/dev/null || true)
  if [[ -n "$tke_cm_config" ]]; then
    # Extract CIDRs under any of:
    #   nonMasqueradeCIDRs / NonMasqueradeCIDRs / nonMasqueradeSrcCIDRs
    local cidrs
    cidrs=$(echo "$tke_cm_config" | awk '
      /^[[:space:]]*[Nn]on[Mm]asquerade(Src)?CIDRs[[:space:]]*:/ { in_list=1; next }
      in_list && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
      in_list && /^[[:space:]]*[A-Za-z]/ { in_list=0 }
    ' | tr '\n' ' ' | sed 's/[[:space:]]\+$//')
    if [[ -n "$cidrs" ]]; then
      NON_MASQ_CIDRS="$cidrs"
      info "$(is_zh && echo "检测到 TKE 自带 ip-masq-agent-config，复用其 VPC 网段 (${NON_MASQ_CIDRS// /, })" || echo "Detected TKE's ip-masq-agent-config, reusing VPC CIDRs (${NON_MASQ_CIDRS// /, })")"
      return
    fi
  fi

  # Interactive prompt
  echo ""
  if is_zh; then
    info "需要配置 cilium ip-masq-agent 的 nonMasqueradeCIDRs（保留 Pod 原始 IP，不做 SNAT 的网段）。"
    info "请输入您 VPC 的所有网段（主网段+辅助网段，空格分隔），需覆盖所有节点子网和 Pod 子网，"
    info "确保 Pod-to-Pod / Pod-to-VPC 流量保留原始 Pod IP（NetworkPolicy 才能基于源标签生效）。"
    info "默认使用 RFC 1918 三段全集（覆盖任意合法腾讯云 VPC 配置）。"
  else
    info "Configuring cilium ip-masq-agent's nonMasqueradeCIDRs (CIDRs that keep the original Pod IP, no SNAT)."
    info "Please enter all VPC CIDRs (main + secondary, space-separated) covering all node and Pod subnets,"
    info "so Pod-to-Pod and Pod-to-VPC traffic keeps the original Pod IP (required for source-label NetworkPolicy)."
    info "Default: RFC 1918 three ranges (covers any valid Tencent Cloud VPC config)."
  fi
  read -rp "$(echo -e "${BLUE}VPC CIDRs${NC} [$(is_zh && echo "默认" || echo "default"): ${DEFAULT_NON_MASQ_CIDRS}]: ")" cidrs_input
  NON_MASQ_CIDRS="${cidrs_input:-$DEFAULT_NON_MASQ_CIDRS}"
  info "Non-masquerade CIDRs: $NON_MASQ_CIDRS"
}

# print_ip_masq_summary — Prints a concise summary of what ip-masq-agent will do.
# Shown right before helm install runs whenever ip-masq-agent is enabled (either
# via ENABLE_IP_MASQ=true or implicitly via ENABLE_EGRESS=true).
# Helps the user confirm which CIDRs keep original Pod IP (no SNAT) vs which
# get SNAT'd to node IP (Pod → public internet path).
print_ip_masq_summary() {
  echo ""
  if is_zh; then
    info "ip-masq-agent SNAT 规则总览:"
    info "  ┌─ 不做 SNAT（保留 Pod IP）的网段:"
    for cidr in $NON_MASQ_CIDRS; do
      info "  │    - ${cidr}"
    done
    info "  └─ 其它所有目的（公网）→ SNAT 成节点 IP，走节点主网卡 + 节点 EIP 出公网"
    info "  注意: link-local (169.254.0.0/16) 也会被 SNAT (masqLinkLocal=true)"
  else
    info "ip-masq-agent SNAT rules:"
    info "  ┌─ Keep original Pod IP (no SNAT) for:"
    for cidr in $NON_MASQ_CIDRS; do
      info "  │    - ${cidr}"
    done
    info "  └─ All other destinations (public internet) → SNAT to node IP, egress via primary ENI + node EIP"
    info "  Note: link-local (169.254.0.0/16) is also SNAT'd (masqLinkLocal=true)"
  fi
}

# confirm_enable_hubble — Asks user whether to enable Hubble Relay + Hubble UI
# during install (default: Y, just press Enter). Sets ENABLE_HUBBLE=true/false.
# If true, hubble params are merged into helm install.
# Skipped if ENABLE_HUBBLE env var is already set.
confirm_enable_hubble() {
  if [[ -n "${ENABLE_HUBBLE:-}" ]]; then
    return
  fi
  echo ""
  local prompt
  if is_zh; then
    prompt="是否启用 Hubble (Hubble Relay + Hubble UI)？[Y/n]: "
  else
    prompt="Enable Hubble (Hubble Relay + Hubble UI)? [Y/n]: "
  fi
  read -rp "$(echo -e "${BLUE}${prompt}${NC}")" hubble_input
  hubble_input=$(echo "$hubble_input" | tr '[:upper:]' '[:lower:]')
  # Default Y: empty input or y/yes → enable.
  if [[ -z "$hubble_input" || "$hubble_input" == "y" || "$hubble_input" == "yes" ]]; then
    ENABLE_HUBBLE=true
  else
    ENABLE_HUBBLE=false
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

# format_duration — Pretty-prints SECONDS-style elapsed seconds. Outputs e.g.
# "5m 23s" or "1h 2m 5s" depending on locale (zh suffixes 时/分/秒, en uses h/m/s).
# Used by cmd_test / cmd_perf to report wall-clock duration.
format_duration() {
  local total=$1
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local s=$((total % 60))
  if is_zh; then
    if ((h > 0)); then
      printf '%d时%d分%d秒' "$h" "$m" "$s"
    elif ((m > 0)); then
      printf '%d分%d秒' "$m" "$s"
    else
      printf '%d秒' "$s"
    fi
  else
    if ((h > 0)); then
      printf '%dh %dm %ds' "$h" "$m" "$s"
    elif ((m > 0)); then
      printf '%dm %ds' "$m" "$s"
    else
      printf '%ds' "$s"
    fi
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
  kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
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

# setup_overlay_vpccni — Deletes webhook that auto-injects ENI IP resource requests.
# Without this, pods would be blocked by ip-scheduler waiting for ENI IP allocation.
setup_overlay_vpccni() {
  info "$(is_zh && echo "禁用 add-pod-eni-ip-limit-webhook..." || echo "Disabling add-pod-eni-ip-limit-webhook...")"
  kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook 2>/dev/null || true
}

# helm_install_cilium — Runs helm upgrade --install with mode-specific parameters.
# Assembles the following helm --set argument arrays and concatenates them
# (helm last-wins, so later arrays override earlier ones):
#   - image_args:       TKE-accessible mirror image repos (quay.tencentcloudcr.com, k8smirror)
#   - common_args:      shared params (kubeProxyReplacement, APF, etc.)
#   - toleration_args:  operator tolerations for TKE-specific taints
#   - mode_args:        routing/IPAM/CNI params specific to NETWORK_MODE x ROUTING_MODE
#   - egress_args:      Egress Gateway params (only when ENABLE_EGRESS=true)
#   - ip_masq_args:     ip-masq-agent params (Native only; when ENABLE_IP_MASQ=true
#                       OR ENABLE_EGRESS=true — Egress forces ip-masq-agent on)
#   - hubble_args:      Hubble Relay + UI (only when ENABLE_HUBBLE=true)
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
  VPC-CNI_overlay)
    toleration_args+=(--set 'operator.tolerations[5].key=tke.cloud.tencent.com/eni-ip-unavailable,operator.tolerations[5].operator=Exists')
    # bpf.masquerade=true is required to unlock BPF host routing — cilium falls
    # back to legacy host routing whenever masquerading goes through iptables
    # (see pkg/kpr/initializer/kube_proxy_replacement.go: "BPF host routing
    # requires enable-bpf-masquerade").
    # multi-pool IPAM: supports per-node multiple PodCIDRs, allowing dynamic
    # expansion of single-node Pod capacity (cluster-pool is fixed at install
    # time and cannot be changed per-node).
    mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=multi-pool --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs[0]="$POD_CIDR" --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true --set bpf.masquerade=true)
    ;;
  GR_overlay)
    # See VPC-CNI_overlay note above for why bpf.masquerade=true is needed.
    mode_args=(--set routingMode=tunnel --set tunnelProtocol=vxlan --set ipam.mode=multi-pool --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs[0]="$POD_CIDR" --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize="$POD_CIDR_MASK" --set enableIPv4Masquerade=true --set bpf.masquerade=true)
    ;;
  esac

  # Prevent cilium-operator from scheduling onto super nodes (eklet).
  # cilium-operator uses hostNetwork + 127.0.0.1 readiness probe, which is
  # unreachable on eklet, causing endless crashloop (see install.md FAQ).
  # nodeAffinity merges with the chart's default podAntiAffinity (helm --set
  # merges map fields, so podAntiAffinity is preserved).
  local -a affinity_args=(
    --set 'operator.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=node.kubernetes.io/instance-type'
    --set 'operator.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=NotIn'
    --set 'operator.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=eklet'
  )

  # Egress Gateway: merge params into helm install if enabled.
  # NOTE: egress_args / ip_masq_args / hubble_args are appended LAST in helm call below — their
  # --set values take precedence over both common_args and mode_args (helm last-wins).
  # ENABLE_EGRESS=true implicitly forces ip-masq-agent on (cilium source requires
  # enableIPv4Masquerade=true when egressGateway.enabled=true), so we treat the
  # combo as "ip-masq-agent enabled" for shared config below.
  local ip_masq_effective="false"
  if [[ "${ENABLE_EGRESS:-false}" == "true" ]] || [[ "${ENABLE_IP_MASQ:-false}" == "true" ]]; then
    ip_masq_effective="true"
  fi

  local -a egress_args=()
  if [[ "${ENABLE_EGRESS:-false}" == "true" ]]; then
    egress_args+=(--set egressGateway.enabled=true)
  fi

  # ip-masq-agent: enabled when ENABLE_IP_MASQ=true OR ENABLE_EGRESS=true.
  # Required for Native Routing Pod → public internet via node EIP (without
  # NAT gateway). Skipped for Overlay because Overlay already SNATs Pod traffic
  # at the tunnel boundary anyway.
  local -a ip_masq_args=()
  if [[ "$ip_masq_effective" == "true" ]] && [[ "$ROUTING_MODE" == "native" ]]; then
    ip_masq_args+=(--set enableIPv4Masquerade=true --set bpf.masquerade=true --set ipMasqAgent.enabled=true --set ipMasqAgent.config.masqLinkLocal=true)
    # Add nonMasqueradeCIDRs (resolved earlier by resolve_non_masq_cidrs).
    # Without this, cilium SNATs cross-node Pod-to-Pod traffic, breaking
    # source-endpoint-label-based NetworkPolicy. helm uses array index syntax.
    if [[ -n "${NON_MASQ_CIDRS:-}" ]]; then
      local idx=0
      for cidr in $NON_MASQ_CIDRS; do
        ip_masq_args+=(--set "ipMasqAgent.config.nonMasqueradeCIDRs[${idx}]=${cidr}")
        idx=$((idx + 1))
      done
    fi
  fi

  local -a hubble_args=()
  if [[ "${ENABLE_HUBBLE:-false}" == "true" ]]; then
    # hubble.relay.enabled=true is the minimum to enable Hubble Relay (aggregator).
    # hubble.ui.enabled=true adds the web UI (depends on relay being enabled).
    hubble_args+=(--set hubble.relay.enabled=true --set hubble.ui.enabled=true)
  fi

  info "$(msg HELM_INSTALL) (${ROUTING_MODE} (${NETWORK_MODE}), cilium ${CILIUM_VERSION})"
  helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" \
    --namespace kube-system \
    "${image_args[@]}" "${toleration_args[@]}" "${affinity_args[@]}" "${common_args[@]}" "${mode_args[@]}" \
    ${egress_args[@]+"${egress_args[@]}"} ${ip_masq_args[@]+"${ip_masq_args[@]}"} ${hubble_args[@]+"${hubble_args[@]}"}
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
# Enables: egressGateway, IPv4 masquerade (BPF), ip-masq-agent with masqLinkLocal,
# and nonMasqueradeCIDRs (resolved by resolve_non_masq_cidrs — required only for
# Native Routing to prevent cross-node Pod-to-Pod SNAT breaking NetworkPolicy).
# Restarts cilium ds and operator to apply changes.
helm_enable_egress() {
  local current_version
  current_version=$(helm -n kube-system list -o json | grep -o '"chart":"cilium-[^"]*"' | sed 's/.*cilium-//' | sed 's/"//')
  if [[ -z "$current_version" ]]; then
    fatal "$(is_zh && echo "无法检测当前 Cilium 版本" || echo "Cannot detect current Cilium version")"
  fi
  info "$(is_zh && echo "检测到 Cilium 版本: ${current_version}" || echo "Detected Cilium version: ${current_version}")"

  # Detect routing mode from existing values to decide whether nonMasqueradeCIDRs
  # is needed (only Native + Egress requires it; Overlay is unaffected).
  local routing_mode
  routing_mode=$(helm -n kube-system get values cilium 2>/dev/null | awk '/^routingMode:/ {print $2}' | tr -d '"')
  ROUTING_MODE="$routing_mode"
  ENABLE_EGRESS=true # for resolve_non_masq_cidrs to take effect
  resolve_non_masq_cidrs

  local -a egress_set_args=(
    --set egressGateway.enabled=true
    --set enableIPv4Masquerade=true
    --set bpf.masquerade=true
    --set ipMasqAgent.enabled=true
    --set ipMasqAgent.config.masqLinkLocal=true
  )
  if [[ -n "${NON_MASQ_CIDRS:-}" ]]; then
    local idx=0
    for cidr in $NON_MASQ_CIDRS; do
      egress_set_args+=(--set "ipMasqAgent.config.nonMasqueradeCIDRs[${idx}]=${cidr}")
      idx=$((idx + 1))
    done
    # Egress Gateway forces ip-masq-agent on, so always show the summary so
    # users know which CIDRs keep original Pod IP vs which get SNAT'd.
    if [[ "$ROUTING_MODE" == "native" ]]; then
      print_ip_masq_summary
    fi
  fi

  info "$(is_zh && echo "执行 helm upgrade 启用 Egress Gateway..." || echo "Running helm upgrade to enable Egress Gateway...")"
  helm upgrade cilium cilium/cilium --version "$current_version" \
    --namespace kube-system \
    --reuse-values \
    "${egress_set_args[@]}"

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

# helm_enable_hubble — Enables Hubble Relay + Hubble UI via helm upgrade --reuse-values.
# Auto-detects current cilium version from helm release.
# Hubble Server runs in cilium-agent by default; we enable the cluster-wide Relay
# (aggregator) and the web UI. Restarts cilium ds and operator to apply changes.
helm_enable_hubble() {
  local current_version
  current_version=$(helm -n kube-system list -o json | grep -o '"chart":"cilium-[^"]*"' | sed 's/.*cilium-//' | sed 's/"//')
  if [[ -z "$current_version" ]]; then
    fatal "$(is_zh && echo "无法检测当前 Cilium 版本" || echo "Cannot detect current Cilium version")"
  fi
  info "$(is_zh && echo "检测到 Cilium 版本: ${current_version}" || echo "Detected Cilium version: ${current_version}")"

  info "$(is_zh && echo "执行 helm upgrade 启用 Hubble Relay + Hubble UI..." || echo "Running helm upgrade to enable Hubble Relay + Hubble UI...")"
  helm upgrade cilium cilium/cilium --version "$current_version" \
    --namespace kube-system \
    --reuse-values \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  info "$(is_zh && echo "重启 cilium..." || echo "Restarting cilium...")"
  kubectl -n kube-system rollout restart ds/cilium
  kubectl -n kube-system rollout restart deploy/cilium-operator
  local node_count
  node_count=$(kubectl get node --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$node_count" -gt 0 ]]; then
    kubectl -n kube-system rollout status ds/cilium --timeout=120s
    kubectl -n kube-system rollout status deploy/cilium-operator --timeout=120s
    kubectl -n kube-system rollout status deploy/hubble-relay --timeout=120s 2>/dev/null || true
    kubectl -n kube-system rollout status deploy/hubble-ui --timeout=120s 2>/dev/null || true
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
  local env_vars="ROUTING_MODE=${ROUTING_MODE} CILIUM_VERSION=${CILIUM_VERSION} IMAGE_REGISTRY=${IMAGE_REGISTRY}"
  if [[ "$ROUTING_MODE" == "overlay" ]]; then
    env_vars="${env_vars} POD_CIDR=${POD_CIDR} POD_CIDR_MASK=${POD_CIDR_MASK}"
  fi
  env_vars="${env_vars} ENABLE_EGRESS=${ENABLE_EGRESS:-false} ENABLE_HUBBLE=${ENABLE_HUBBLE:-false} ENABLE_LOCALDNS=${ENABLE_LOCALDNS:-false}"
  # ENABLE_IP_MASQ is only meaningful for Native + no-Egress (Egress forces it on)
  if [[ "$ROUTING_MODE" == "native" ]] && [[ "${ENABLE_EGRESS:-false}" != "true" ]] && [[ -n "${ENABLE_IP_MASQ:-}" ]]; then
    env_vars="${env_vars} ENABLE_IP_MASQ=${ENABLE_IP_MASQ}"
  fi
  if [[ -n "${NON_MASQ_CIDRS:-}" ]] && [[ "$ROUTING_MODE" == "native" ]] &&
    { [[ "${ENABLE_EGRESS:-false}" == "true" ]] || [[ "${ENABLE_IP_MASQ:-false}" == "true" ]]; }; then
    # Quote because list contains spaces
    env_vars="${env_vars} NON_MASQ_CIDRS=\"${NON_MASQ_CIDRS}\""
  fi
  echo ""
  if is_zh; then
    info "如需在其他集群重复相同安装，可直接执行以下命令（无需交互）:"
  else
    info "To repeat this install on other clusters without interaction, run:"
  fi
  echo ""
  echo "  ${env_vars} \\"
  echo "    bash -c \"\$(curl -sfL ${script_url})\" -- install"
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
#   8. confirm_enable_ip_masq (only Native + no Egress)
#   9. resolve_non_masq_cidrs (Native + Egress, OR Native + ip-masq-agent)
#  10. confirm_enable_hubble (optional)
#  11. confirm_enable_localdns (optional)
#  12. uninstall_tke_components → setup_* → helm_install → apply_apf
#  13. (optional) install localdns
#  14. Print "add nodes" guidance and finish. Install no longer chains into
#      connectivity test / perf — run `cilium.sh test` / `cilium.sh perf`
#      separately once nodes are Ready if you want to validate.
cmd_install_cilium() {
  echo ""
  echo -e "${BLUE}╔═════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      TKE Cilium Install Wizard      ║${NC}"
  echo -e "${BLUE}╚═════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites
  check_nodes
  detect_network_mode
  select_routing_mode
  confirm_cilium_version
  confirm_image_registry
  confirm_pod_cidr
  confirm_enable_egress
  confirm_enable_ip_masq
  resolve_non_masq_cidrs
  confirm_enable_hubble
  confirm_enable_localdns

  echo ""
  info "$(is_zh && echo "安装方案" || echo "Plan"): ${ROUTING_MODE} (${NETWORK_MODE}), Cilium ${CILIUM_VERSION}"

  # Show ip-masq SNAT rules summary right before install whenever ip-masq-agent
  # will be enabled (either explicit ENABLE_IP_MASQ=true or implicit via Egress).
  if [[ "$ROUTING_MODE" == "native" ]] &&
    { [[ "${ENABLE_IP_MASQ:-false}" == "true" ]] || [[ "${ENABLE_EGRESS:-false}" == "true" ]]; }; then
    print_ip_masq_summary
  fi
  echo ""

  uninstall_tke_components
  case "${NETWORK_MODE}_${ROUTING_MODE}" in
  VPC-CNI_native) setup_native_vpccni ;;
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

  # Export installed values as YAML for user reference
  print_installed_values

  # Print non-interactive replay command for batch deployment
  print_replay_command

  # ---- Post-install guidance (install ends here) ----
  # The recommended TKE flow is "install cilium on empty cluster first, then
  # add nodes". However, if localdns was enabled, the script may have already
  # waited for the user to add nodes (cilium-operator needs a schedulable node
  # to start and create CRDs). Check whether the cluster now has non-super
  # nodes to give accurate guidance instead of blindly saying "add nodes".
  # The install command no longer chains into connectivity test / perf — those
  # remain available as separate subcommands (`cilium.sh test` / `cilium.sh perf`).
  echo ""
  local has_regular_nodes=false
  local _node
  while IFS= read -r _node; do
    if [[ ! "$_node" =~ ^eklet- ]]; then
      has_regular_nodes=true
      break
    fi
  done < <(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)

  if [[ "$has_regular_nodes" == "true" ]]; then
    if is_zh; then
      info "============================================"
      info "Cilium 安装完成！"
      info "============================================"
      info "集群已有节点，cilium-agent 会随节点就绪自动启动。"
      info "如需验证连通性或性能，可运行: cilium.sh test / cilium.sh perf"
      info "如需添加更多节点，参考: https://imroc.cc/tke/networking/cilium/install#新建节点池"
    else
      info "============================================"
      info "Cilium installation complete!"
      info "============================================"
      info "Cluster has nodes — cilium-agent will auto-launch as nodes become Ready."
      info "To verify connectivity or performance, run: cilium.sh test / cilium.sh perf"
      info "To add more nodes, see: https://imroc.cc/tke/en/networking/cilium/install#create-node-pools"
    fi
  else
    if is_zh; then
      info "============================================"
      info "下一步：向集群添加节点"
      info "============================================"
      info "Cilium 已安装到集群（工作负载已就位），但当前集群还没有可调度的"
      info "节点。请按需创建节点池并添加节点（cilium-agent 会随节点就绪自动启动）。"
      info "节点池选型与创建方法详见: https://imroc.cc/tke/networking/cilium/install#新建节点池"
      info ""
      info "如需验证连通性或性能，可在节点就绪后单独运行: cilium.sh test / cilium.sh perf"
    else
      info "============================================"
      info "Next step: add nodes to the cluster"
      info "============================================"
      info "Cilium is installed (workload ready), but the cluster does not have"
      info "schedulable nodes yet. Create a node pool and add nodes (cilium-agent"
      info "will auto-launch as nodes become Ready)."
      info "Node pool selection and creation guide:"
      info "  https://imroc.cc/tke/en/networking/cilium/install#create-node-pools"
      info ""
      info "To verify connectivity or performance, run separately once nodes are Ready: cilium.sh test / cilium.sh perf"
    fi
  fi

  echo ""
}

# ====== uninstall subcommand ======
# Removes cilium and restores TKE built-in network components by reversing what
# cmd_install_cilium and uninstall_tke_components did. Best-effort — every step
# uses `|| true` so partial states don't abort the rollback.
#
# What this does:
#   1. helm uninstall cilium (removes DaemonSet / Deployment / CRDs created by chart)
#   2. Delete cni-config ConfigMap (only set up for VPC-CNI Native)
#   3. Delete cilium APF FlowSchema + PriorityLevelConfiguration
#   4. Restore TKE DaemonSets by clearing the nodeSelector patch
#      (kube-proxy / tke-cni-agent / tke-eni-agent / ip-masq-agent — only those
#      that exist; the patch sets nodeSelector to a never-matching label)
#   5. Print follow-up actions the script CANNOT do automatically:
#        - Reboot or recreate every node — cilium leaves BPF programs, lxc
#          interfaces, and (depending on chart version) iptables rules that
#          aren't fully cleaned by helm uninstall
#        - Re-enable the ip-masq-agent addon in the TKE console if originally
#          unchecked at cluster creation
#        - Manually remove leftover /etc/cni/net.d/05-cilium.conf* on each node
#          if not rebooting

cmd_uninstall_cilium() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      TKE Cilium Uninstall Wizard     ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  # Confirm — uninstall is destructive (will disrupt cluster networking until
  # nodes are rebuilt or TKE addons fully take over). Skip the prompt if
  # CILIUM_UNINSTALL_YES=true (for non-interactive / CI use).
  if [[ "${CILIUM_UNINSTALL_YES:-false}" != "true" ]]; then
    if is_zh; then
      warn "本操作将卸载 cilium 并恢复 TKE 内置网络组件。"
      warn "  - 集群网络在此过程中会**中断**，直到 TKE 内置 CNI 完全接管"
      warn "  - 强烈建议在 **维护窗口** 执行，并对每个节点 **重启或重建**（cilium"
      warn "    会留下 BPF 程序、lxc 接口、iptables 规则等，helm uninstall 清不干净）"
      warn "  - 控制台手动卸载的 ip-masq-agent 等组件，需在控制台手动重新勾选"
      echo ""
      read -rp "$(echo -e "${BLUE}确认要卸载 cilium？输入 yes 继续，其它取消: ${NC}")" confirm
    else
      warn "This will uninstall cilium and restore TKE built-in network components."
      warn "  - Cluster networking will be DISRUPTED until TKE CNI fully takes over"
      warn "  - Strongly recommend running in a **maintenance window** and"
      warn "    **rebooting or recreating every node** afterwards (cilium leaves"
      warn "    BPF programs, lxc interfaces, and iptables rules that helm"
      warn "    uninstall does NOT fully clean up)"
      warn "  - Components manually unchecked in the TKE console (e.g. ip-masq-agent)"
      warn "    need to be re-enabled in the console"
      echo ""
      read -rp "$(echo -e "${BLUE}Confirm uninstall? Type yes to continue, anything else to cancel: ${NC}")" confirm
    fi
    if [[ "$confirm" != "yes" ]]; then
      info "$(is_zh && echo "已取消" || echo "Cancelled")"
      return
    fi
  fi

  # 1. helm uninstall
  info "$(is_zh && echo "卸载 cilium helm release..." || echo "Uninstalling cilium helm release...")"
  helm uninstall cilium -n kube-system 2>/dev/null || true

  # 2. Clean up cni-config (Native VPC-CNI chaining mode)
  info "$(is_zh && echo "清理 cni-config ConfigMap..." || echo "Cleaning up cni-config ConfigMap...")"
  kubectl -n kube-system delete configmap cni-config 2>/dev/null || true

  # 3. Remove cilium APF rules
  info "$(is_zh && echo "清理 cilium APF 限速规则..." || echo "Removing cilium APF rate limiting rules...")"
  kubectl delete flowschema cilium 2>/dev/null || true
  kubectl delete prioritylevelconfiguration cilium 2>/dev/null || true

  # 4. Restore TKE network DaemonSets by removing the nodeSelector patch.
  # cmd_install_cilium added nodeSelector={label-not-exist:node-not-exist} to
  # prevent scheduling. Setting nodeSelector to {} restores normal scheduling.
  # Use kubectl patch with strategic merge: setting a field to null removes it.
  info "$(is_zh && echo "恢复 TKE 内置网络组件..." || echo "Restoring TKE built-in network components...")"
  for ds in kube-proxy tke-cni-agent tke-eni-agent ip-masq-agent; do
    if kubectl -n kube-system get ds "$ds" >/dev/null 2>&1; then
      # Patch: set spec.template.spec.nodeSelector to null removes the disable patch.
      # Use JSON patch with `replace` op replacing nodeSelector with empty object,
      # which clears the never-matching label set during install.
      kubectl -n kube-system patch daemonset "$ds" \
        --type=json \
        -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/label-not-exist"}]' \
        2>/dev/null ||
        kubectl -n kube-system patch daemonset "$ds" \
          -p='{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true
      info "  - ${ds}: $(is_zh && echo "已恢复调度" || echo "scheduling restored")"
    fi
  done

  # 5. Optional: nudge users to delete add-pod-eni-ip-limit-webhook restoration
  # is NOT done here — that webhook was deleted during install (Overlay VPC-CNI
  # only) and there's no idempotent way to recreate it from the script. Tell
  # the user it'll come back automatically when TKE re-syncs the addon.

  echo ""
  info "============================================"
  info "$(is_zh && echo "Cilium 已卸载。后续手工动作（重要）:" || echo "Cilium uninstalled. Required follow-up actions:")"
  info "============================================"
  if is_zh; then
    info "1. 重启 / 重建每个节点 — cilium 留下的 BPF 程序、lxc 接口、iptables 规则"
    info "   helm uninstall 清不干净，最稳妥是直接重建节点"
    info "2. 控制台检查并重新启用 ip-masq-agent 组件（如果创建集群时取消勾选过）"
    info "3. (Overlay VPC-CNI) add-pod-eni-ip-limit-webhook 会在 TKE 重新下发组件"
    info "   时自动恢复，无需手工干预"
    info "4. 如果不打算重建节点，每个节点上手工清理:"
    info "   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist"
    info "   sudo iptables-save | grep -i cilium  # 检查残留规则"
    info ""
    info "完整回滚指南: https://imroc.cc/tke/networking/cilium/install#回滚到-tke-内置-cni"
  else
    info "1. Reboot or recreate every node — cilium leaves BPF programs, lxc"
    info "   interfaces, and iptables rules that helm uninstall does NOT fully"
    info "   clean. Recreating nodes is the most reliable cleanup."
    info "2. In the TKE console, re-enable the ip-masq-agent addon if you"
    info "   unchecked it at cluster creation."
    info "3. (Overlay VPC-CNI) add-pod-eni-ip-limit-webhook is auto-restored"
    info "   when TKE re-applies its addon manifests; no manual action needed."
    info "4. If NOT recreating nodes, manually clean up on each node:"
    info "   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist"
    info "   sudo iptables-save | grep -i cilium  # check for leftover rules"
    info ""
    info "Full rollback guide: https://imroc.cc/tke/en/networking/cilium/install#rollback-to-tke-built-in-cni"
  fi
  info "============================================"
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

# ====== test subcommand ======
# Runs cilium connectivity test with TKE-compatible image overrides and
# region-aware external target defaults.
#
# Two TKE-environment-specific concerns drive this logic:
#
# 1. External target reachability (pod-to-world / pod-to-cidr / to-fqdns / etc.)
#    These scenarios curl external IPs/domains. cilium-cli has NO automatic
#    "is external reachable" pre-check — connections that fail simply count as
#    failed actions. The defaults `1.1.1.1` / `one.one.one.one.` / `k8s.io.` are
#    blocked by GFW from China-mainland networks, so:
#      - China-mainland regions (auto-detected via topology.kubernetes.io/region)
#        get China-reachable substitutes: 223.5.5.5 / www.aliyun.com. / www.qq.com.
#      - Overseas regions keep cilium defaults.
#    Detection uses the SHORT region code (e.g. "cd", "bj", "hk"), which is what
#    TKE actually puts on the label — see is_china_region() below.
#
# 2. Node public-internet egress (Pod → external)
#    If nodes lack public egress (no NAT gateway, no node EIP, no Egress Gateway),
#    every external-target action will fail. We probe egress via a temporary Pod
#    and emit a WARNING listing the affected scenarios — no auto-skip, because
#    "node has no public internet" is the user's deployment choice, not a
#    cilium-environment incompatibility. User can still pass `--test '!...'` to
#    explicitly skip those scenarios.
#
# Image mapping:
#   quay.io/cilium/*           → quay.tencentcloudcr.com/cilium/* (internal mirror)
#   registry.k8s.io/coredns/*  → docker.io/k8smirror/coredns:*   (synced to dockerhub)
#   gcr.io/*/echo-advanced     → docker.io/k8smirror/echo-advanced:* (synced to dockerhub)

# is_china_region — Returns 0 if the given region SHORT code (e.g. "cd", "bj")
# represents a China-mainland region, 1 otherwise.
# The label `topology.kubernetes.io/region` on TKE nodes uses the SHORT form
# from the TKE region table (cd=Chengdu, bj=Beijing, hk=HongKong, ...).
# Source of truth: ~/.claude-internal/skills/tke-knowledge/regions.md
# Maintenance: when TKE adds a new China-mainland region, append its short code
# to CN_REGION_CODES below. Overseas regions and HK/MO/TW are excluded (HK/TW
# are not subject to GFW egress restrictions, default targets work fine there).
is_china_region() {
  local code="$1"
  [[ -z "$code" ]] && return 1
  # China-mainland short region codes (public + finance + EC):
  #   gz/sh/bj/cd/cq/nj/szx/qy/tsn  — public
  #   shjr/szjr/bjjr                 — finance
  #   jnec/hzec/fzec/whec/csec/sjwec/hfeec/sheec/xiyec/xbec/cgoec — EC
  #   zw                             — Zhongwei
  case "$code" in
  gz | sh | bj | cd | cq | nj | szx | qy | tsn) return 0 ;;
  shjr | szjr | bjjr) return 0 ;;
  jnec | hzec | fzec | whec | csec | sjwec | hfeec | sheec | xiyec | xbec | cgoec) return 0 ;;
  zw) return 0 ;;
  *) return 1 ;;
  esac
}

# detect_cluster_region — Inspects all non-super nodes' region labels and prints
# one of: "china" / "overseas" / "mixed" / "unknown".
#   - All nodes in China-mainland regions → "china"
#   - All nodes in overseas regions → "overseas"
#   - Mix of China + overseas → "mixed" (treat as overseas to be safe)
#   - No region labels found → "unknown" (treat as overseas to be safe)
# Reads `topology.kubernetes.io/region` first, falls back to
# `failure-domain.beta.kubernetes.io/region` (deprecated but still set on
# older clusters).
detect_cluster_region() {
  local lines
  lines=$(kubectl get node -o jsonpath='{range .items[*]}{.metadata.labels.node\.kubernetes\.io/instance-type}{"|"}{.metadata.labels.topology\.kubernetes\.io/region}{"|"}{.metadata.labels.failure-domain\.beta\.kubernetes\.io/region}{"\n"}{end}' 2>/dev/null)
  if [[ -z "$lines" ]]; then
    echo "unknown"
    return
  fi
  local saw_cn=0 saw_oversea=0
  while IFS='|' read -r itype region region_legacy; do
    [[ -z "$itype$region$region_legacy" ]] && continue
    # Skip super nodes (eklet) — they don't represent the cluster's underlying region
    [[ "$itype" == "eklet" ]] && continue
    local code="${region:-$region_legacy}"
    [[ -z "$code" ]] && continue
    if is_china_region "$code"; then
      saw_cn=1
    else
      saw_oversea=1
    fi
  done <<<"$lines"
  if ((saw_cn == 1 && saw_oversea == 0)); then
    echo "china"
  elif ((saw_cn == 0 && saw_oversea == 1)); then
    echo "overseas"
  elif ((saw_cn == 1 && saw_oversea == 1)); then
    echo "mixed"
  else
    echo "unknown"
  fi
}

# detect_cilium_routing_mode — Reads the cilium helm release values to determine
# whether this install is Native Routing or Overlay. Returns "native", "overlay",
# or "unknown" on stdout. Used by cmd_test to print mode-specific warnings.
detect_cilium_routing_mode() {
  local mode
  mode=$(helm -n kube-system get values cilium 2>/dev/null | awk '/^routingMode:/ {print $2}' | tr -d '"' | head -1)
  case "$mode" in
  native) echo "native" ;;
  tunnel) echo "overlay" ;; # cilium uses routingMode=tunnel for vxlan/geneve
  *) echo "unknown" ;;
  esac
}

# first_node_external_ip — Returns the first non-super node's ExternalIP, or
# empty if none. Used by probe_pod_to_node_eip to pick a target.
first_node_external_ip() {
  kubectl get node -o jsonpath='{range .items[*]}{.metadata.labels.node\.kubernetes\.io/instance-type}{"|"}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}' 2>/dev/null |
    awk -F'|' '$1 != "eklet" && $2 != "" {print $2; exit}'
}

# probe_pod_to_node_eip — Launches a temporary Pod and tries to ping <eip> with
# a 4s timeout. Returns 0 if reachable, non-zero otherwise.
# Used to decide whether the Native + EIP pod-to-host warning is actually
# applicable. If a NAT gateway is configured in the VPC, this ping succeeds
# (Pod IP -> NAT gateway -> public -> node EIP DNAT -> node), so the warning
# is suppressed; if no NAT gateway, the ping fails and we print the warning.
probe_pod_to_node_eip() {
  local eip="$1"
  local probe_name="cilium-eip-probe-$$"
  local rc
  kubectl run "$probe_name" \
    --image="$CILIUM_CURL_IMAGE" \
    --restart=Never \
    --attach \
    --rm \
    --quiet \
    --command -- \
    ping -c 1 -W 4 "$eip" >/dev/null 2>&1
  rc=$?
  kubectl delete pod "$probe_name" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  return "$rc"
}

# probe_pod_egress — Launches a temporary curl Pod and tries to reach `target`
# with a 5-second timeout. Returns 0 if reachable, non-zero otherwise.
# Used to warn users when nodes lack public-internet egress.
# Uses --attach instead of -i so it works in non-interactive environments.
# The probe pod has a unique name (PID-based) to avoid colliding with concurrent runs.
probe_pod_egress() {
  local target="$1"
  local probe_name="cilium-egress-probe-$$"
  local rc
  kubectl run "$probe_name" \
    --image="$CILIUM_CURL_IMAGE" \
    --restart=Never \
    --attach \
    --rm \
    --quiet \
    --command -- \
    curl -sS -o /dev/null --max-time 5 "$target" >/dev/null 2>&1
  rc=$?
  # Best-effort cleanup in case --rm didn't fire (e.g. timeout, signal)
  kubectl delete pod "$probe_name" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  return "$rc"
}

# resolve_cn_external_ips — Dynamically resolves CN_EXTERNAL_IP_DOMAIN inside the
# cluster and finds two distinct IPs in the same /16 that respond with HTTPS 2xx/3xx
# (with --insecure, since direct-IP HTTPS can't pass SAN validation for CN services).
#
# Outputs three space-separated values to stdout: "ip1 ip2 cidr"
# Returns 0 on success, non-zero if no working pair found (caller should fall back).
#
# Why dynamic: CN public services rarely sign certs for raw IPs, so the only working
# IP is the one currently backing npmmirror.com (an alibaba ECS public IP that rotates).
# We resolve it fresh on each run.
resolve_cn_external_ips() {
  local probe_name="cilium-cn-resolve-$$"
  local out
  out=$(kubectl run "$probe_name" \
    --image="$CILIUM_CURL_IMAGE" \
    --restart=Never \
    --attach \
    --rm \
    --quiet \
    --command -- /bin/sh -c "
set +e
ips=\$(dig +short +time=3 +tries=2 ${CN_EXTERNAL_IP_DOMAIN} A 2>/dev/null | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$' | head -1)
[ -z \"\$ips\" ] && exit 1
ip1=\$ips
# Verify ip1 actually responds with HTTPS 2xx/3xx (with --insecure)
code=\$(curl --silent --fail --show-error --insecure --connect-timeout 2 --max-time 5 -4 -o /dev/null -w '%{http_code}' \"https://\${ip1}:443\" 2>/dev/null)
case \"\$code\" in 2*|3*) ;; *) exit 2 ;; esac
prefix=\$(echo \"\$ip1\" | awk -F. '{printf \"%s.%s\", \$1, \$2}')
# Scan a few candidate IPs in the same /16 for a second working one
ip2=
for last3 in 233.61 232.62 234.62 232.61 234.61 233.63 230.10 240.10 250.10 100.10 150.10 170.10 200.10 220.20 130.30; do
  candidate=\"\${prefix}.\${last3}\"
  [ \"\$candidate\" = \"\$ip1\" ] && continue
  c=\$(curl --silent --fail --show-error --insecure --connect-timeout 1 --max-time 3 -4 -o /dev/null -w '%{http_code}' \"https://\${candidate}:443\" 2>/dev/null)
  case \"\$c\" in 2*|3*) ip2=\$candidate; break ;; esac
done
[ -z \"\$ip2\" ] && exit 3
echo \"\${ip1} \${ip2} \${prefix}.0.0/16\"
" 2>/dev/null)
  local rc=$?
  kubectl delete pod "$probe_name" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  if [[ $rc -ne 0 ]] || [[ -z "$out" ]]; then
    return 1
  fi
  echo "$out"
  return 0
}

cmd_test() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      Cilium Connectivity Test        ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  command -v cilium &>/dev/null || fatal "$(is_zh && echo "cilium CLI 未安装，请先安装: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli" || echo "cilium CLI not installed. Install: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli")"
  command -v kubectl &>/dev/null || fatal "$(msg NO_KUBECTL)"
  kubectl cluster-info &>/dev/null || fatal "$(msg NO_CLUSTER)"

  # cilium connectivity test itself includes cilium-health checks per-node as part
  # of its setup phase, so we don't run a separate cilium-health verification here.

  info "$(is_zh && echo "运行 cilium connectivity test..." || echo "Running cilium connectivity test...")"
  echo ""

  # ---- Region-aware external target selection ----
  local cluster_region
  cluster_region=$(detect_cluster_region)
  local -a external_args=()
  case "$cluster_region" in
  china)
    if is_zh; then
      info "检测到节点位于中国大陆地域，使用国内可达的外部目标 (域名: ${CN_EXTERNAL_TARGET} / ${CN_EXTERNAL_OTHER_TARGET})"
      info "动态解析 ${CN_EXTERNAL_IP_DOMAIN} 以确定 pod-to-cidr 用例的 external-ip..."
    else
      info "Cluster nodes are in China-mainland region, using China-reachable external targets (domains: ${CN_EXTERNAL_TARGET} / ${CN_EXTERNAL_OTHER_TARGET})"
      info "Resolving ${CN_EXTERNAL_IP_DOMAIN} dynamically to determine external-ip for pod-to-cidr scenarios..."
    fi

    external_args=(
      --external-target "$CN_EXTERNAL_TARGET"
      --external-other-target "$CN_EXTERNAL_OTHER_TARGET"
      # CN public services don't sign certs for raw IPs, so direct-IP HTTPS
      # in pod-to-cidr would fail SAN validation without --insecure.
      # cilium-cli internal HTTP tests use plain HTTP (no TLS), so this
      # only relaxes external-target HTTPS validation, which is safe here.
      --curl-insecure
    )

    local cn_ips
    if cn_ips=$(resolve_cn_external_ips); then
      # cn_ips format: "ip1 ip2 cidr"
      local cn_ip1 cn_ip2 cn_cidr
      read -r cn_ip1 cn_ip2 cn_cidr <<<"$cn_ips"
      if is_zh; then
        info "动态解析成功，将注入以下参数:"
      else
        info "Dynamic resolution succeeded, will inject:"
      fi
      echo "  --external-ip          ${cn_ip1}"
      echo "  --external-other-ip    ${cn_ip2}"
      echo "  --external-cidr        ${cn_cidr}"
      echo "  --external-target      ${CN_EXTERNAL_TARGET}"
      echo "  --external-other-target ${CN_EXTERNAL_OTHER_TARGET}"
      echo "  --curl-insecure"
      external_args+=(
        --external-ip "$cn_ip1"
        --external-other-ip "$cn_ip2"
        --external-cidr "$cn_cidr"
      )
    else
      # Couldn't find a working IP pair — only WARN; user decides whether to skip.
      if is_zh; then
        warn "未能动态解析到可用的国内 IP 对（CN 公网服务对裸 IP HTTPS 支持有限），以下依赖 IP 的 CIDR 用例预计会失败:"
        warn "  - pod-to-cidr / to-cidr-external / from-cidr-external / client-egress-to-cidrgroup-deny / 等"
        warn "  这是国内公网环境的客观限制（无稳定的 IP-only HTTPS 服务），与 cilium 能力无关。"
        warn "  CIDR 策略能力本身仍由其它用例间接覆盖（如 to-entities-world、from-cidr 等）。"
        warn "  如需跳过，可显式追加: --test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr' --test '!/client-egress-to-cidr'"
      else
        warn "Could not resolve a working CN IP pair (CN public services have limited IP-only HTTPS support). The following IP-dependent CIDR test cases will likely fail:"
        warn "  - pod-to-cidr / to-cidr-external / from-cidr-external / client-egress-to-cidrgroup-deny / etc."
        warn "  This is a CN public-internet limitation (no stable IP-only HTTPS service), not a cilium issue."
        warn "  CIDR policy capability is still indirectly covered by other tests (to-entities-world, from-cidr, etc.)."
        warn "  To skip explicitly, append: --test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr' --test '!/client-egress-to-cidr'"
      fi
    fi
    ;;
  overseas)
    if is_zh; then
      info "检测到节点位于海外地域，使用 cilium 默认外部目标 (1.1.1.1 / one.one.one.one. / k8s.io.)"
    else
      info "Cluster nodes are in overseas region, using cilium default external targets (1.1.1.1 / one.one.one.one. / k8s.io.)"
    fi
    ;;
  mixed)
    if is_zh; then
      warn "检测到节点跨地域分布（部分国内、部分海外），保守使用 cilium 默认外部目标"
      warn "如全部节点在国内，可手动追加: --external-target ${CN_EXTERNAL_TARGET} --external-other-target ${CN_EXTERNAL_OTHER_TARGET} --curl-insecure"
    else
      warn "Mixed-region cluster detected (some nodes in China, some overseas), falling back to cilium default external targets"
      warn "If all nodes are in China, append manually: --external-target ${CN_EXTERNAL_TARGET} --external-other-target ${CN_EXTERNAL_OTHER_TARGET} --curl-insecure"
    fi
    ;;
  unknown | *)
    if is_zh; then
      warn "未能识别节点地域（topology.kubernetes.io/region 标签缺失或值未知），使用 cilium 默认外部目标"
    else
      warn "Cannot detect cluster region (topology.kubernetes.io/region label missing or unknown), using cilium default external targets"
    fi
    ;;
  esac

  # ---- Pod public-internet egress probe ----
  # Pick a probe target based on region: CN domain for china, default cilium target for overseas/unknown.
  local probe_target probe_label
  if [[ "$cluster_region" == "china" ]]; then
    probe_target="https://${CN_EXTERNAL_TARGET%.}"
    probe_label="${CN_EXTERNAL_TARGET}"
  else
    probe_target="https://one.one.one.one"
    probe_label="one.one.one.one"
  fi
  if is_zh; then
    info "探测节点是否能从 Pod 出公网 (${probe_label})..."
  else
    info "Probing pod public-internet egress (${probe_label})..."
  fi
  if probe_pod_egress "$probe_target"; then
    if is_zh; then
      info "Pod 公网连通性正常"
    else
      info "Pod public-internet egress OK"
    fi
  else
    if is_zh; then
      warn "Pod 无法访问公网 (${probe_label})！以下用例预计会失败，属正常现象，与 cilium 无关:"
      warn "  - pod-to-world / pod-to-cidr"
      warn "  - to-fqdns / to-cidr-external / client-egress-l7* / tls-sni*"
      warn "解决办法: 为节点配置 NAT 网关 / Egress Gateway / 节点 EIP，使 Pod 能出公网"
      warn "或显式跳过这些用例: --test '!/pod-to-world' --test '!/pod-to-cidr'"
    else
      warn "Pod cannot reach public internet (${probe_label})! The following cases will fail — this is expected and unrelated to cilium:"
      warn "  - pod-to-world / pod-to-cidr"
      warn "  - to-fqdns / to-cidr-external / client-egress-l7* / tls-sni*"
      warn "Fix: configure NAT gateway / Egress Gateway / node EIP so pods can reach public internet"
      warn "Or explicitly skip these cases: --test '!/pod-to-world' --test '!/pod-to-cidr'"
    fi
  fi

  # ---- Native + node EIP warning ----
  # In Native Routing mode, cilium-cli's pod-to-host scenario contains a
  # ping-ipv4-external-ip sub-action that pings every node's ExternalIP from
  # a Pod. Whether this passes depends on whether the VPC has a public NAT
  # gateway:
  #
  #   - WITHOUT NAT gateway: fails. cilium tags node EIPs with identity=
  #     remote-node, BPF masquerade early-exits and skips SNAT, so the packet
  #     leaves with src=Pod-IP (no public-egress path) → dropped.
  #   - WITH NAT gateway: succeeds. cilium still doesn't SNAT, but the packet
  #     reaches the VPC route table which sends "dst=public" traffic to the
  #     NAT gateway; NAT gateway SNATs to its own public IP, the packet loops
  #     back to the node EIP via the public internet, and the cloud network
  #     DNATs EIP → node VPC IP. Higher latency than direct routing, but works.
  #
  # Pod -> a real public IP (e.g. 223.5.5.5) always works either way: that
  # destination is identity=world, doesn't hit the remote-node early-exit, so
  # cilium SNATs via ipMasqAgent and the packet egresses with the node primary
  # ENI IP. Only node EIPs hit the remote-node special case.
  #
  # Overlay mode is unaffected: Pod IPs come from an independent CIDR not in
  # the VPC, cilium always SNATs egress to the node primary-ENI IP, which has
  # public egress capability.
  #
  # Implementation: actually probe (Pod ping <some-node-EIP>) instead of
  # blindly warning whenever Native + EIP. If the probe succeeds (NAT gateway
  # configured), suppress the warning entirely.
  # See appendix/connectivity-test.md "Why Pod ping node EIP never works on
  # Native Routing" + "Why does the test environment need a NAT gateway".
  local routing_mode probe_eip
  routing_mode=$(detect_cilium_routing_mode)
  if [[ "$routing_mode" == "native" ]]; then
    probe_eip=$(first_node_external_ip)
    if [[ -n "$probe_eip" ]]; then
      if is_zh; then
        info "探测从 Pod 是否能 ping 通节点 EIP (${probe_eip})..."
      else
        info "Probing whether a Pod can ping a node EIP (${probe_eip})..."
      fi
      if probe_pod_to_node_eip "$probe_eip"; then
        if is_zh; then
          info "Pod ping 节点 EIP 通过（VPC 已配 NAT 网关或其它公网路径），pod-to-host 用例不会受影响"
        else
          info "Pod can reach node EIP (NAT gateway or other public route configured); pod-to-host won't be affected"
        fi
      else
        echo ""
        if is_zh; then
          warn "Pod 无法 ping 通节点 EIP (${probe_eip})"
          warn "  pod-to-host scenario 中的 ping-ipv4-external-ip 子动作会失败。原因（与安全组/ICMP 无关）:"
          warn "    - VPC-CNI Native 下 Pod IP 来自节点辅助 ENI 的 IP 池，辅助 ENI 不绑 EIP，"
          warn "      Pod IP 本身没有公网能力——访问任何公网目的都必须先 SNAT 成节点主 ENI IP"
          warn "    - cilium 把节点 EIP 视为 remote-node identity，BPF masquerade 对此早退出，"
          warn "      不做 SNAT（早退出先于 ipMasqAgent CIDR 判断，ip-masq-agent 也救不了）"
          warn "    - 结果包以 Pod IP 出节点，目的是公网 EIP，但 Pod IP 没公网出口路径"
          warn "  Pod 访问真公网 IP 仍然正常（identity=world 不触发早退出，会 SNAT）。"
          warn "  解决办法（任一即可）:"
          warn "    a) VPC 配置 NAT 网关 → 让 Pod 借 NAT 网关公网能力绕回节点 EIP"
          warn "    b) 跳过该 scenario: --test '!/pod-to-host\$'"
          warn "  详细分析与抓包证据: https://imroc.cc/tke/networking/cilium/appendix/connectivity-test"
        else
          warn "Pod cannot ping node EIP (${probe_eip})"
          warn "  pod-to-host's ping-ipv4-external-ip sub-action will fail. Why"
          warn "  (NOT a security-group / ICMP issue):"
          warn "    - VPC-CNI Native Pod IPs come from the secondary ENI's IP pool; the"
          warn "      secondary ENI has NO EIP, so Pod IPs have no public-internet egress."
          warn "      Reaching ANY public destination requires SNAT to the primary-ENI IP first."
          warn "    - cilium tags node EIPs as remote-node identity. BPF masquerade early-exits"
          warn "      for remote-node destinations (no SNAT). Early-exit fires BEFORE the"
          warn "      ipMasqAgent CIDR check, so ip-masq-agent cannot rescue this case."
          warn "    - Result: packet leaves with src=Pod-IP (no egress path), dst=node-EIP."
          warn "  Pod -> real public IPs still works fine (identity=world doesn't hit the"
          warn "  early-exit, cilium SNATs normally)."
          warn "  Fix (choose either):"
          warn "    a) Configure a NAT gateway in the VPC so Pod traffic loops back to node EIP"
          warn "    b) Skip the scenario: --test '!/pod-to-host\$'"
          warn "  Full analysis + tcpdump evidence: https://imroc.cc/tke/en/networking/cilium/appendix/connectivity-test"
        fi
      fi
    fi
  fi

  echo ""

  # Pre-clean leftover test namespaces from any previous run (cilium-cli
  # leaves them behind on failure; on TKE the gatekeeper webhook blocks ns
  # deletion while Pods exist, so cilium connectivity test's own setup can
  # also stumble on stale state).
  cleanup_cilium_test_namespaces

  local start_ts=$SECONDS
  local rc=0
  cilium connectivity test \
    --curl-image "$CILIUM_CURL_IMAGE" \
    --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
    --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
    --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1 \
    --test-conn-disrupt-image quay.tencentcloudcr.com/cilium/test-connection-disruption:v0.0.17 \
    ${external_args[@]+"${external_args[@]}"} \
    "$@" || rc=$?
  local elapsed=$((SECONDS - start_ts))
  local pretty
  pretty=$(format_duration "$elapsed")

  echo ""
  info "============================================"
  if ((rc == 0)); then
    if is_zh; then
      info "测试完成！耗时 ${pretty}"
    else
      info "Tests completed! Elapsed: ${pretty}"
    fi
  else
    if is_zh; then
      warn "测试结束（部分用例失败，cilium 退出码 ${rc}）。耗时 ${pretty}"
    else
      warn "Tests finished with failures (cilium exit code ${rc}). Elapsed: ${pretty}"
    fi
  fi
  if is_zh; then
    info "更多说明参考: https://imroc.cc/tke/networking/cilium/appendix/connectivity-test"
  else
    info "More details: https://imroc.cc/tke/en/networking/cilium/appendix/connectivity-test"
  fi
  info "============================================"
  echo ""
  return "$rc"
}

# ====== perf subcommand ======
# Runs cilium connectivity perf with TKE-compatible image overrides.
# `cilium connectivity perf` uses netperf to measure pod-to-pod throughput
# and latency across same-node and cross-node combinations. It needs at least 2
# nodes available (cilium-cli will fail otherwise).
#
# We override --performance-image to a TKE-internal mirror (quay.tencentcloudcr.com)
# so the netperf image pulls on TKE clusters without public internet access.

# cleanup_cilium_test_namespaces — Tear down lingering cilium-test-* namespaces
# left behind by a previous run.
#
# Why this exists:
#   When `cilium connectivity test` finishes with failures, cilium-cli leaves
#   the test namespaces / Deployments / Pods around so users can inspect them.
#   When `cilium connectivity perf` then starts, its first step is `kubectl
#   delete ns cilium-test-1` — but TKE clusters have a gatekeeper webhook
#   `baseline.gatekeeper.sh / block-namespace-deletion-rule` that REFUSES to
#   delete a namespace while it still contains Pods. So perf gets stuck on
#   "Waiting for namespace cilium-test-1 to disappear" indefinitely.
#
# Strategy: tear down workloads first (they hold the Pods), wait for Pods to
# go away, then delete the namespace. This satisfies the gatekeeper rule.
#
# Called by both cmd_test (pre-run, in case previous run left junk) and
# cmd_perf (pre-run, MUST happen before cilium connectivity perf starts).
cleanup_cilium_test_namespaces() {
  local namespaces=("cilium-test-1" "cilium-test-ccnp1" "cilium-test-ccnp2")
  local found=0
  for ns in "${namespaces[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    return 0
  fi

  info "$(is_zh && echo "检测到上次测试残留的 namespace，先清理..." || echo "Detected leftover test namespaces, cleaning up first...")"

  # Step 1: delete all workloads holding Pods. --wait=false to fan out quickly.
  for ns in "${namespaces[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      kubectl -n "$ns" delete deployment,daemonset,statefulset,replicaset,job,cronjob --all --wait=false --ignore-not-found >/dev/null 2>&1 || true
    fi
  done

  # Step 2: wait for Pods to actually disappear (gatekeeper blocks ns delete
  # while any pod exists). 60s should be plenty; if not, fall back to force.
  for ns in "${namespaces[@]}"; do
    if ! kubectl get ns "$ns" >/dev/null 2>&1; then
      continue
    fi
    local i pod_count
    for i in $(seq 1 30); do
      pod_count=$(kubectl -n "$ns" get pod --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$pod_count" -eq 0 ]]; then
        break
      fi
      sleep 2
    done
    # Force-delete any stragglers with grace period 0
    if [[ "$pod_count" -gt 0 ]]; then
      kubectl -n "$ns" delete pod --all --grace-period=0 --force --wait=false >/dev/null 2>&1 || true
      sleep 3
    fi
  done

  # Step 3: delete the namespaces themselves
  for ns in "${namespaces[@]}"; do
    kubectl delete ns "$ns" --wait=false --ignore-not-found >/dev/null 2>&1 || true
  done

  # Step 4: wait for namespaces to be gone (best-effort, ~30s)
  local i
  for i in $(seq 1 15); do
    local still_there=0
    for ns in "${namespaces[@]}"; do
      kubectl get ns "$ns" >/dev/null 2>&1 && still_there=1
    done
    if [[ "$still_there" -eq 0 ]]; then
      info "$(is_zh && echo "残留 namespace 已清理" || echo "Leftover namespaces cleaned up")"
      return 0
    fi
    sleep 2
  done
  warn "$(is_zh && echo "namespace 清理超时，可能导致后续测试卡住；可手动 kubectl delete ns cilium-test-{1,ccnp1,ccnp2}" || echo "Namespace cleanup timed out; may cause subsequent tests to hang. Manual: kubectl delete ns cilium-test-{1,ccnp1,ccnp2}")"
}

cmd_perf() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║      Cilium Performance Test         ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""

  command -v cilium &>/dev/null || fatal "$(is_zh && echo "cilium CLI 未安装，请先安装: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli" || echo "cilium CLI not installed. Install: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli")"
  command -v kubectl &>/dev/null || fatal "$(msg NO_KUBECTL)"
  kubectl cluster-info &>/dev/null || fatal "$(msg NO_CLUSTER)"

  info "$(is_zh && echo "运行 cilium connectivity perf..." || echo "Running cilium connectivity perf...")"
  echo ""

  # Pre-clean leftover test namespaces. cilium connectivity perf will try to
  # `kubectl delete ns cilium-test-1` as its first step; on TKE the gatekeeper
  # webhook block-namespace-deletion-rule rejects ns deletion while Pods still
  # exist, so without pre-cleanup perf hangs on "Waiting for namespace ... to
  # disappear" indefinitely.
  cleanup_cilium_test_namespaces

  local start_ts=$SECONDS
  local rc=0
  cilium connectivity perf \
    --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90 \
    "$@" || rc=$?
  local elapsed=$((SECONDS - start_ts))
  local pretty
  pretty=$(format_duration "$elapsed")

  echo ""
  info "============================================"
  if ((rc == 0)); then
    if is_zh; then
      info "性能测试完成！耗时 ${pretty}"
    else
      info "Performance test completed! Elapsed: ${pretty}"
    fi
  else
    if is_zh; then
      warn "性能测试结束（cilium 退出码 ${rc}）。耗时 ${pretty}"
    else
      warn "Performance test finished with errors (cilium exit code ${rc}). Elapsed: ${pretty}"
    fi
  fi
  if is_zh; then
    info "更多说明与各方案实测数据参考: https://imroc.cc/tke/networking/cilium/appendix/performance-test"
  else
    info "More details and benchmark data: https://imroc.cc/tke/en/networking/cilium/appendix/performance-test"
  fi
  info "============================================"
  echo ""
  return "$rc"
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

# ====== enable-hubble subcommand ======
# Standalone subcommand to enable Hubble Relay + Hubble UI on an existing cilium installation.
# Checks cilium is installed, then delegates to helm_enable_hubble().

cmd_enable_hubble() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║         Enable Cilium Hubble         ║${NC}"
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

  helm_enable_hubble

  echo ""
  info "============================================"
  info "$(msg HUBBLE_DONE)"
  info "  kubectl -n kube-system get pod -l app.kubernetes.io/part-of=cilium"
  info "  cilium status"
  info "  cilium hubble ui"
  info "============================================"
  echo ""
}

# ====== Main Entry Point ======
# Dispatches to the appropriate subcommand based on the first argument.

main() {
  local cmd="${1:-}"
  case "$cmd" in
  install) cmd_install_cilium ;;
  uninstall) cmd_uninstall_cilium ;;
  install-localdns) cmd_install_localdns ;;
  test)
    shift
    cmd_test "$@"
    ;;
  perf)
    shift
    cmd_perf "$@"
    ;;
  enable-egress-gateway) cmd_enable_egress_gateway ;;
  enable-hubble) cmd_enable_hubble ;;
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
