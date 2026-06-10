#!/usr/bin/env bash
# Note: intentionally NOT using `set -e`. A single iperf3/fortio exec
# failure should warn and continue with the next round, not abort the
# whole benchmark — we lose hours of work otherwise.
set -uo pipefail

###############################################################################
# TKE Network Benchmark
#
# A self-contained script for running network performance benchmarks across
# different TKE network solutions (Cilium Native, Cilium Overlay,
# kube-proxy iptables, kube-proxy IPVS).
#
# Prerequisite:
#   KUBECONFIG must point to a working kubeconfig (or current-context is set).
#   The script just runs `kubectl` directly — no wrappers, no extra flags.
#
# Usage:
#   bash network-benchmark.sh
#   KUBECONFIG=/path/to/cfg bash network-benchmark.sh
#   bash network-benchmark.sh --dir ./results-clusterA --ns nb
#
# Options:
#   -h, --help       Show help
#   --dir DIR        Output directory (default: ./benchmark-results-<context>)
#   --skip-cleanup   Skip cleanup after benchmark
#   --ns NS          Namespace for test workloads (default: network-benchmark)
#
# Environment Variables:
#   NETPERF_IMAGE      netperf image (default: networkstatic/netperf:latest)
#   IPERF_IMAGE        iperf3 image (default: networkstatic/iperf3:latest)
#   FORTIO_IMAGE       fortio image (default: fortio/fortio:latest)
#   IPERF_DURATION     iperf3 test duration in seconds (default: 30)
#   FORTIO_DURATION    fortio/netperf test duration in seconds (default: 60)
#   ROUNDS             repetitions per scenario (default: 1)
#   ROUND_SLEEP        seconds between rounds (default: 30)
#   KUBECTL_TIMEOUT    timeout for kubectl exec/cp calls (default: 180)
#
# Output:
#   Creates benchmark-results-<context>/ directory with structured results.
#
###############################################################################

# ─── Logging ─────────────────────────────────────────────────────────────────

red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
blue() { printf "\033[34m%s\033[0m\n" "$*"; }
log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*"; }
step() { blue "━━━ $* ━━━"; }
info() { log "INFO: $*"; }
warn() { yellow "WARN: $*"; }
err() { red "ERROR: $*"; }

# ─── Defaults ────────────────────────────────────────────────────────────────

OUTPUT_DIR=""
SKIP_CLEANUP=false
NS="network-benchmark"

NETPERF_IMAGE="${NETPERF_IMAGE:-networkstatic/netperf:latest}"
IPERF_IMAGE="${IPERF_IMAGE:-networkstatic/iperf3:latest}"
FORTIO_IMAGE="${FORTIO_IMAGE:-fortio/fortio:latest}"

WORKER_NODE_1=""
WORKER_NODE_2=""
CLUSTER_TYPE=""

# ─── Test Parameters ─────────────────────────────────────────────────────────
# Override via env to tune test intensity vs QoS budget.
#   IPERF_DURATION: seconds per iperf3 run (default 30). Shorter = less burst
#                   credit consumed, avoids QoS throttling on small instances.
#   FORTIO_DURATION: seconds per fortio/netperf run (default 60).
#   ROUNDS: repetitions per scenario (default 1). More rounds = better
#           statistical confidence but consumes more QoS burst budget.
#   ROUND_SLEEP: seconds to wait between rounds (default 30). Gives burst
#                credit time to recover between tests.
IPERF_DURATION="${IPERF_DURATION:-30}"
FORTIO_DURATION="${FORTIO_DURATION:-60}"
ROUNDS="${ROUNDS:-1}"
ROUND_SLEEP="${ROUND_SLEEP:-30}"

# Timeout wrapping kubectl exec/cp. Must be larger than the longest single
# test (IPERF_DURATION or FORTIO_DURATION) plus warmup + overhead.
KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-180}"

# Track every background monitor pid so trap can reap them on exit. Keeping a
# space-separated list rather than an array makes it easy to print in logs.
MONITOR_PIDS=""

_cleanup_on_exit() {
  # Reap background monitors before exit / interrupt so they don't become
  # orphans that keep appending to the resource CSVs forever.
  if [[ -n "$MONITOR_PIDS" ]]; then
    for pid in $MONITOR_PIDS; do
      kill "$pid" 2>/dev/null || true
    done
  fi
}
trap _cleanup_on_exit EXIT INT TERM

# ─── Parse Arguments ─────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      show_help
      exit 0
      ;;
    --dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --ns)
      NS="$2"
      shift 2
      ;;
    --skip-cleanup)
      SKIP_CLEANUP=true
      shift
      ;;
    *)
      err "Unknown option: $1"
      show_help
      exit 1
      ;;
    esac
  done
}

show_help() {
  cat <<EOF
TKE Network Benchmark

Prerequisite:
  KUBECONFIG points to a working kubeconfig (current-context is used directly).

Usage:
  bash network-benchmark.sh
  KUBECONFIG=/path/to/cfg bash network-benchmark.sh
  bash network-benchmark.sh --dir ./results-clusterA --ns nb

Options:
  -h, --help           Show this help
  --dir DIR            Output directory (default: ./benchmark-results-<context>)
  --ns NS              Namespace for test workloads (default: network-benchmark)
  --skip-cleanup       Skip cleanup after benchmark

Environment Variables:
  NETPERF_IMAGE      netperf image (default: networkstatic/netperf:latest)
  IPERF_IMAGE        iperf3 image (default: networkstatic/iperf3:latest)
  FORTIO_IMAGE       fortio image (default: fortio/fortio:latest)
  IPERF_DURATION     iperf3 test duration in seconds (default: 30)
  FORTIO_DURATION    fortio/netperf test duration in seconds (default: 60)
  ROUNDS             repetitions per scenario (default: 1)
  ROUND_SLEEP        seconds between rounds (default: 30)
  KUBECTL_TIMEOUT    timeout for kubectl exec/cp calls (default: 180)

Examples:
  # Default: quick run (1 round × 30s iperf / 60s fortio), safe for small instances
  bash network-benchmark.sh --dir ./bench

  # Full run on large instances (no QoS worry): 3 rounds × 120s each
  ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench
EOF
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

check_prereqs() {
  local missing=0
  for cmd in kubectl python3 timeout; do
    if ! command -v "$cmd" &>/dev/null; then
      err "Prerequisite '$cmd' not found"
      [[ "$cmd" == "timeout" ]] && err "  on macOS install via: brew install coreutils && export PATH=\"\$(brew --prefix coreutils)/libexec/gnubin:\$PATH\""
      missing=1
    fi
  done
  if ! kubectl cluster-info &>/dev/null; then
    err "kubectl cannot reach the cluster. Check KUBECONFIG / current-context."
    missing=1
  fi
  return "$missing"
}

get_cluster_name() {
  kubectl config current-context 2>/dev/null || echo "unknown"
}

# ─── Cluster Detection ───────────────────────────────────────────────────────

detect_cluster_type() {
  info "Detecting cluster type..."

  local cilium_ready
  cilium_ready=$(kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
  if [[ "$cilium_ready" -gt 0 ]]; then
    local cilium_status
    cilium_status=$(kubectl -n kube-system exec ds/cilium -- cilium status 2>/dev/null || echo "")
    if echo "$cilium_status" | grep -qi "Tunnel.*vxlan\|Tunnel.*geneve"; then
      CLUSTER_TYPE="cilium-overlay"
      info "Detected: Cilium Overlay"
    else
      CLUSTER_TYPE="cilium-native"
      info "Detected: Cilium Native Routing"
    fi
    return 0
  fi

  local kube_proxy_running
  kube_proxy_running=$(kubectl -n kube-system get pod -l k8s-app=kube-proxy --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$kube_proxy_running" -gt 0 ]]; then
    local proxy_mode
    proxy_mode=$(kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config}' 2>/dev/null | grep -o 'mode: "[^"]*"' | cut -d'"' -f2 || echo "iptables")
    if [[ "$proxy_mode" == "ipvs" ]]; then
      CLUSTER_TYPE="kubeproxy-ipvs"
      info "Detected: kube-proxy IPVS"
    else
      CLUSTER_TYPE="kubeproxy-iptables"
      info "Detected: kube-proxy iptables"
    fi
    return 0
  fi

  if kubectl -n kube-system get configmap kube-proxy &>/dev/null; then
    local proxy_mode
    proxy_mode=$(kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config}' 2>/dev/null | grep -o 'mode: "[^"]*"' | cut -d'"' -f2 || echo "iptables")
    if [[ "$proxy_mode" == "ipvs" ]]; then
      CLUSTER_TYPE="kubeproxy-ipvs"
      info "Detected: kube-proxy IPVS (from config)"
    else
      CLUSTER_TYPE="kubeproxy-iptables"
      info "Detected: kube-proxy iptables (from config)"
    fi
    return 0
  fi

  err "Unable to detect cluster type"
  exit 1
}

collect_context_info() {
  step "Collecting cluster context info"
  mkdir -p "$OUTPUT_DIR"

  local cluster_name
  cluster_name=$(get_cluster_name)

  cat >"$OUTPUT_DIR/context.yaml" <<EOF
cluster_name: $cluster_name
cluster_type: $CLUSTER_TYPE
test_date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
k8s_version: $(kubectl version -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | head -1 | cut -d'"' -f4)
node_count: $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
node_os: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null)
kernel_version: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}' 2>/dev/null)
node_model: $(kubectl describe node 2>/dev/null | grep 'machine-size' | head -1 | awk '{print $NF}' || echo "unknown")
EOF

  info "Context info saved to $OUTPUT_DIR/context.yaml"
}

# ─── Select Worker Nodes ────────────────────────────────────────────────────

select_worker_nodes() {
  step "Selecting worker nodes for cross-node tests"

  local nodes
  nodes=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -3)

  WORKER_NODE_1=$(echo "$nodes" | sed -n '1p')
  WORKER_NODE_2=$(echo "$nodes" | sed -n '2p')

  if [[ -z "$WORKER_NODE_1" || -z "$WORKER_NODE_2" ]]; then
    err "Need at least 2 worker nodes, found: $(echo "$nodes" | wc -l)"
    exit 1
  fi

  info "Using nodes: $WORKER_NODE_1 (server) <-> $WORKER_NODE_2 (client)"
}

# ─── Deploy / Cleanup ───────────────────────────────────────────────────────

deploy_test_workloads() {
  step "Deploying test workloads"
  local N="$NS"

  kubectl create namespace "$N" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

  # Node Level (hostNetwork)
  kubectl apply -n "$N" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server-host
  labels:
    app: benchmark
    role: iperf-server-host
spec:
  hostNetwork: true
  nodeName: $WORKER_NODE_1
  containers:
  - name: iperf
    image: $IPERF_IMAGE
    command: ["iperf3", "-s", "-p", "5202"]
    ports:
    - containerPort: 5202
      hostPort: 5202
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client-host
  labels:
    app: benchmark
    role: iperf-client-host
spec:
  hostNetwork: true
  nodeName: $WORKER_NODE_2
  containers:
  - name: iperf
    image: $IPERF_IMAGE
    command: ["sleep", "infinity"]
  terminationGracePeriodSeconds: 0
EOF

  # Pod-to-Pod workloads (iperf + netperf + fortio)
  kubectl apply -n "$N" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  labels:
    app: benchmark
    role: iperf-server
spec:
  nodeName: $WORKER_NODE_1
  containers:
  - name: iperf
    image: $IPERF_IMAGE
    command: ["iperf3", "-s"]
    ports:
    - containerPort: 5201
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client
  labels:
    app: benchmark
    role: iperf-client
spec:
  nodeName: $WORKER_NODE_2
  containers:
  - name: iperf
    image: $IPERF_IMAGE
    command: ["sleep", "infinity"]
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: netperf-server
  labels:
    app: benchmark
    role: netperf-server
spec:
  nodeName: $WORKER_NODE_1
  containers:
  - name: netperf
    image: $NETPERF_IMAGE
    command: ["netserver", "-D"]
    ports:
    - containerPort: 12865
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: netperf-client
  labels:
    app: benchmark
    role: netperf-client
spec:
  nodeName: $WORKER_NODE_2
  containers:
  - name: netperf
    image: $NETPERF_IMAGE
    command: ["sleep", "infinity"]
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-server
  labels:
    app: benchmark
    role: fortio-server
spec:
  nodeName: $WORKER_NODE_1
  containers:
  - name: fortio
    image: $FORTIO_IMAGE
    command: ["fortio", "server"]
    ports:
    - containerPort: 8080
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-client
  labels:
    app: benchmark
    role: fortio-client
spec:
  nodeName: $WORKER_NODE_2
  containers:
  - name: fortio
    image: $FORTIO_IMAGE
    # Fortio distroless: keep pod alive with minimal server. We exec into
    # this container for load tests. Results are written to stdout and may
    # be lost on WebSocket errors — the script handles retries.
    command: ["fortio", "server", "-http-port", "9999", "-grpc-port", "disabled", "-tcp-port", "disabled", "-udp-port", "disabled", "-redirect-port", "disabled"]
  terminationGracePeriodSeconds: 0
EOF

  # Services
  kubectl apply -n "$N" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: iperf-service
spec:
  selector:
    app: benchmark
    role: iperf-server
  ports:
  - port: 5201
    targetPort: 5201
  type: ClusterIP
EOF

  info "Waiting for pods to be ready..."
  local pods="pod/iperf-server-host pod/iperf-client-host pod/iperf-server pod/iperf-client pod/netperf-server pod/netperf-client pod/fortio-server pod/fortio-client"
  if ! kubectl wait -n "$N" --for=condition=Ready $pods --timeout=300s; then
    err "Pods failed to become Ready within 300s — aborting"
    kubectl get pod -n "$N" -o wide || true
    exit 1
  fi
  info "All test workloads ready"
}

cleanup_test_workloads() {
  if [[ "$SKIP_CLEANUP" == "true" ]]; then
    warn "Skipping cleanup (--skip-cleanup)"
    return 0
  fi
  step "Cleaning up test workloads"
  kubectl delete namespace "$NS" --ignore-not-found --timeout=60s 2>/dev/null || {
    kubectl delete pod -n "$NS" --all --grace-period=0 --force --ignore-not-found 2>/dev/null || true
    sleep 5
    kubectl delete namespace "$NS" --ignore-not-found 2>/dev/null || true
  }
  kubectl delete namespace test-services --ignore-not-found --timeout=120s 2>/dev/null || true
  info "Cleanup complete"
}

# ─── exec helpers ───────────────────────────────────────────────────────────

_pod_exec() {
  local pod="$1"
  shift
  kubectl exec -n "$NS" "$pod" -- "$@"
}

# ─── Resource Monitoring ────────────────────────────────────────────────────

start_resource_monitor() {
  local csv_file="$1"
  local label="$2"
  local pid_file="$3"
  mkdir -p "$(dirname "$csv_file")"
  echo "timestamp,pod,cpu_millicores,memory_mib" >"$csv_file"
  # Capture parent (main script) pid so the subshell can self-terminate if the
  # main process dies unexpectedly. Without this, a stalled main script leaves
  # the monitor loop running under init(1) appending forever.
  local parent_pid=$$
  (
    while kill -0 "$parent_pid" 2>/dev/null; do
      kubectl top pod -n kube-system -l "$label" --no-headers 2>/dev/null | while read -r pod cpu mem rest; do
        echo "$(date +%H:%M:%S),$pod,${cpu%%m},${mem%%Mi}" >>"$csv_file"
      done
      sleep 5
    done
  ) &
  local mon_pid=$!
  echo "$mon_pid" >"$pid_file"
  MONITOR_PIDS="$MONITOR_PIDS $mon_pid"
}

stop_resource_monitor() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
    # Drop it from MONITOR_PIDS so the trap doesn't double-kill (harmless,
    # but keeps logs tidy if we ever decide to log kills).
    MONITOR_PIDS=$(echo "$MONITOR_PIDS" | tr ' ' '\n' | grep -vx "$pid" | tr '\n' ' ')
  fi
}

# ─── iperf3 Throughput Tests ────────────────────────────────────────────────

_run_iperf() {
  local label="$1" server_ip="$2" port="$3" parallel="$4" output_dir="$5" result_file="$6"
  local out="$output_dir/$result_file"
  mkdir -p "$output_dir"
  info "Running: $label (${IPERF_DURATION}s, P=$parallel)"

  # Write JSON to a file inside the pod then kubectl cp out, avoiding SPDY
  # channel stalls on large stdout payloads.
  local pod_file="/tmp/iperf_${result_file}"
  if ! timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" iperf-client -- \
      iperf3 -c "$server_ip" -p "$port" -t "$IPERF_DURATION" -P "$parallel" -J --logfile "$pod_file" >/dev/null 2>&1; then
    warn "  iperf3 timed out or returned non-zero, result may be incomplete"
  fi
  if ! timeout 60 kubectl cp -n "$NS" "iperf-client:${pod_file}" "$out" >/dev/null 2>&1; then
    warn "  kubectl cp failed for $result_file"
    return 0
  fi
  timeout 30 kubectl exec -n "$NS" iperf-client -- rm -f "$pod_file" >/dev/null 2>&1 || true

  local py_tmp="/tmp/nb_iperf_$$.py"
  cat >"$py_tmp" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
v = d["end"]["sum_received"]["bits_per_second"] / 1e9
print(f"{v:.2f}")
PYEOF
  local gbps
  gbps=$(python3 "$py_tmp" "$out" 2>/dev/null || echo "N/A")
  rm -f "$py_tmp"

  info "  → ${gbps} Gbps"
}

run_throughput_tests() {
  step "Running Throughput Tests (iperf3, ${IPERF_DURATION}s × ${ROUNDS} rounds, ${ROUND_SLEEP}s interval)"
  local d="$OUTPUT_DIR/throughput"
  mkdir -p "$d"

  local N="$NS"
  local node1_ip
  node1_ip=$(kubectl get pod -n "$N" iperf-server-host -o jsonpath='{.status.hostIP}')
  local server_pod_ip
  server_pod_ip=$(kubectl get pod -n "$N" iperf-server -o jsonpath='{.status.podIP}')
  local svc_ip
  svc_ip=$(kubectl get svc -n "$N" iperf-service -o jsonpath='{.spec.clusterIP}')

  info "Node1 IP: $node1_ip | Server Pod IP: $server_pod_ip | Svc IP: $svc_ip"

  # Warmup: short 5s burst to prime TCP cwnd, route caches, and ENI token
  # bucket. Without this, the first test shows ~25% lower throughput due to
  # TCP slow-start from cold state.
  info "Warmup (5s)..."
  timeout 30 kubectl exec -n "$NS" iperf-client -- \
    iperf3 -c "$node1_ip" -p 5202 -t 5 -P 8 >/dev/null 2>&1 || true
  sleep 5

  local mon_pid=""
  if [[ "$CLUSTER_TYPE" == cilium-* ]]; then
    start_resource_monitor "$OUTPUT_DIR/resources/cilium_throughput.csv" "k8s-app=cilium" "/tmp/nb_cilium_mon.pid"
    mon_pid="/tmp/nb_cilium_mon.pid"
  elif [[ "$CLUSTER_TYPE" == kubeproxy-* ]]; then
    start_resource_monitor "$OUTPUT_DIR/resources/kubeproxy_throughput.csv" "k8s-app=kube-proxy" "/tmp/nb_kp_mon.pid"
    mon_pid="/tmp/nb_kp_mon.pid"
  fi

  for r in $(seq 1 "$ROUNDS"); do
    _run_iperf "Node Level 8stream r$r" "$node1_ip" "5202" "8" "$d" "node_throughput_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_iperf "Pod-to-Pod single r$r" "$server_pod_ip" "5201" "1" "$d" "pod2pod_single_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_iperf "Pod-to-Pod 8stream r$r" "$server_pod_ip" "5201" "8" "$d" "pod2pod_8stream_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_iperf "Pod-to-Pod 16stream r$r" "$server_pod_ip" "5201" "16" "$d" "pod2pod_16stream_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_iperf "Via Service 8stream r$r" "$svc_ip" "5201" "8" "$d" "via_service_8stream_r${r}.json"
    sleep "$ROUND_SLEEP"
  done

  [[ -n "$mon_pid" ]] && stop_resource_monitor "$mon_pid"
  sleep 10
  info "Throughput tests complete"
}

# ─── fortio RPS Tests ───────────────────────────────────────────────────────

_run_fortio() {
  local label="$1" url="$2" connections="$3" keepalive="$4"
  local output_dir="$5" result_file="$6"
  local out="$output_dir/$result_file"
  mkdir -p "$output_dir"
  info "Running: $label (c=$connections, keepalive=$keepalive)"

  if [[ "$keepalive" == "false" ]]; then
    # Short-connection mode: must use kubectl exec (REST API doesn't support
    # disabling keepalive). Short-conn tests have low QPS (~10K) and small
    # JSON output, so WebSocket close 1006 is rare. Retry if it does happen.
    local attempt max_attempts=3
    local duration="$FORTIO_DURATION"
    for attempt in $(seq 1 $max_attempts); do
      local rc=0
      timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" fortio-client -- \
        fortio load -qps 0 -c "$connections" -t "${duration}s" -keepalive=false -json - "$url" \
        >"$out" 2>"${out}.err" || rc=$?
      [[ ! -s "${out}.err" ]] && rm -f "${out}.err"
      if [[ -s "$out" ]] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$out" 2>/dev/null; then
        break
      fi
      if [[ $attempt -lt $max_attempts ]]; then
        warn "  attempt $attempt failed, retrying in 10s with shorter duration..."
        rm -f "$out" "${out}.err"
        sleep 10
        duration=30
      else
        warn "  fortio failed after $max_attempts attempts"
        [[ -s "${out}.err" ]] && warn "  stderr: $(tail -3 "${out}.err")"
      fi
    done
  else
    # Keepalive mode: use fortio REST API via port-forward. This bypasses
    # kubectl exec WebSocket entirely — high-throughput keepalive tests
    # (80K+ req/s) always triggered WebSocket close 1006 via exec.
    local pf_pid=""
    local local_port=$((19000 + RANDOM % 1000))
    kubectl port-forward -n "$NS" pod/fortio-client ${local_port}:9999 >/dev/null 2>&1 &
    pf_pid=$!
    sleep 2

    local api_url="http://localhost:${local_port}/fortio/rest/run"
    local params="url=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$url")"
    params="${params}&qps=-1&t=${FORTIO_DURATION}s&c=${connections}&json=on"

    local rc=0
    timeout "$KUBECTL_TIMEOUT" curl -sf "${api_url}?${params}" >"$out" 2>/dev/null || rc=$?

    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true

    # If REST API failed, fall back to kubectl exec with retry
    if ! { [[ -s "$out" ]] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$out" 2>/dev/null; }; then
      warn "  REST API failed (rc=$rc), falling back to kubectl exec..."
      rm -f "$out"
      local attempt max_attempts=3
      local duration="$FORTIO_DURATION"
      for attempt in $(seq 1 $max_attempts); do
        rc=0
        timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" fortio-client -- \
          fortio load -qps 0 -c "$connections" -t "${duration}s" -json - "$url" \
          >"$out" 2>"${out}.err" || rc=$?
        [[ ! -s "${out}.err" ]] && rm -f "${out}.err"
        if [[ -s "$out" ]] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$out" 2>/dev/null; then
          break
        fi
        if [[ $attempt -lt $max_attempts ]]; then
          warn "  attempt $attempt failed, retrying in 10s with shorter duration..."
          rm -f "$out" "${out}.err"
          sleep 10
          duration=30
        else
          warn "  fortio failed after $max_attempts attempts"
          [[ -s "${out}.err" ]] && warn "  stderr: $(tail -3 "${out}.err")"
        fi
      done
    fi
  fi
  [[ -f "${out}.err" && ! -s "${out}.err" ]] && rm -f "${out}.err"

  # Parse result if we got valid output
  if [[ ! -s "$out" ]]; then
    warn "  no output for $result_file"
    return 0
  fi

  local py_tmp="/tmp/nb_fortio_$$.py"
  cat >"$py_tmp" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(int(d["ActualQPS"]))
PYEOF
  local qps
  qps=$(python3 "$py_tmp" "$out" 2>/dev/null || echo "N/A")
  rm -f "$py_tmp"
  info "  → ${qps} req/s"
}

run_rps_tests() {
  step "Running RPS Tests (fortio, ${FORTIO_DURATION}s × ${ROUNDS} rounds, ${ROUND_SLEEP}s interval)"
  local d="$OUTPUT_DIR/rps"
  mkdir -p "$d"
  local N="$NS"

  local server_pod_ip
  server_pod_ip=$(kubectl get pod -n "$N" fortio-server -o jsonpath='{.status.podIP}')

  kubectl apply -n "$N" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: fortio-service
spec:
  selector:
    app: benchmark
    role: fortio-server
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
  sleep 3
  local fortio_svc_ip
  fortio_svc_ip=$(kubectl get svc -n "$N" fortio-service -o jsonpath='{.spec.clusterIP}')

  local mon_pid=""
  if [[ "$CLUSTER_TYPE" == cilium-* ]]; then
    start_resource_monitor "$OUTPUT_DIR/resources/cilium_rps.csv" "k8s-app=cilium" "/tmp/nb_cilium_mon.pid"
    mon_pid="/tmp/nb_cilium_mon.pid"
  elif [[ "$CLUSTER_TYPE" == kubeproxy-* ]]; then
    start_resource_monitor "$OUTPUT_DIR/resources/kubeproxy_rps.csv" "k8s-app=kube-proxy" "/tmp/nb_kp_mon.pid"
    mon_pid="/tmp/nb_kp_mon.pid"
  fi

  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Pod-to-Pod 64c r$r" "http://${server_pod_ip}:8080/echo?size=512" 64 true "$d" "pod2pod_c64_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Via Svc 64c (ka) r$r" "http://${fortio_svc_ip}:8080/echo?size=512" 64 true "$d" "svc_c64_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Via Svc 256c (ka) r$r" "http://${fortio_svc_ip}:8080/echo?size=512" 256 true "$d" "svc_c256_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Via Svc 64c (short) r$r" "http://${fortio_svc_ip}:8080/echo?size=512" 64 false "$d" "svc_short_c64_r${r}.json"
    sleep "$ROUND_SLEEP"
  done

  [[ -n "$mon_pid" ]] && stop_resource_monitor "$mon_pid"
  sleep 10
  info "RPS tests complete"
}

# ─── netperf Latency Tests ──────────────────────────────────────────────────

run_latency_tests() {
  step "Running Latency Tests (netperf TCP_RR/TCP_CRR + fortio HTTP, ${FORTIO_DURATION}s × ${ROUNDS} rounds)"
  local d="$OUTPUT_DIR/latency"
  mkdir -p "$d"
  local N="$NS"

  local np_ip
  np_ip=$(kubectl get pod -n "$N" netperf-server -o jsonpath='{.status.podIP}')
  local fs_ip
  fs_ip=$(kubectl get svc -n "$N" fortio-service -o jsonpath='{.spec.clusterIP}')

  for r in $(seq 1 "$ROUNDS"); do
    info "TCP_RR round $r"
    timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" netperf-client -- \
      netperf -H "$np_ip" -t TCP_RR -l "$FORTIO_DURATION" -- -r 1,1 \
      -o MIN_LATENCY,MEAN_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MAX_LATENCY,THROUGHPUT \
      >"$d/tcp_rr_r${r}.txt" 2>/dev/null || warn "  TCP_RR round $r failed"
    sleep "$ROUND_SLEEP"
  done

  for r in $(seq 1 "$ROUNDS"); do
    info "TCP_CRR round $r"
    timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" netperf-client -- \
      netperf -H "$np_ip" -t TCP_CRR -l "$FORTIO_DURATION" -- -r 1,1 \
      -o MIN_LATENCY,MEAN_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MAX_LATENCY,THROUGHPUT \
      >"$d/tcp_crr_r${r}.txt" 2>/dev/null || warn "  TCP_CRR round $r failed"
    sleep "$ROUND_SLEEP"
  done

  # fortio HTTP p99 — stdout mode (low load, 1000 QPS, no WebSocket issues).
  info "HTTP p99 @ 1000 QPS"
  timeout "$KUBECTL_TIMEOUT" kubectl exec -n "$NS" fortio-client -- \
    fortio load -qps 1000 -c 16 -t "${FORTIO_DURATION}s" -json - \
    "http://${fs_ip}:8080/echo?size=512" >"$d/http_1k_qps.json" 2>/dev/null || warn "  HTTP latency test may have errors"

  info "Latency tests complete"
}

# ─── Service Scale Test ─────────────────────────────────────────────────────

run_service_scale_test() {
  step "Running Service Scale Test (1000 dummy Services)"
  local d="$OUTPUT_DIR/service-scale"
  mkdir -p "$d"

  info "Creating 1000 dummy Services in batches..."
  kubectl create namespace test-services --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

  local batch_size=100
  for ((start = 1; start <= 1000; start += batch_size)); do
    local end=$((start + batch_size - 1))
    [[ $end -gt 1000 ]] && end=1000

    info "  Creating services $start-$end..."
    local batch_file=$(mktemp)
    local first=true
    for i in $(seq $start $end); do
      local o3=$(((i - 1) / 254))
      local o4=$(((i - 1) % 254 + 1))
      # YAML document separator between resources (not before the very first)
      if [[ "$first" == "true" ]]; then
        first=false
      else
        echo "---" >>"$batch_file"
      fi
      cat <<EOF >>"$batch_file"
apiVersion: v1
kind: Service
metadata:
  name: dummy-svc-${i}
  namespace: test-services
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: dummy-svc-${i}
  namespace: test-services
subsets:
- addresses:
  - ip: 10.99.${o3}.${o4}
  ports:
  - port: 80
    protocol: TCP
EOF
    done
    kubectl apply -f "$batch_file" 2>/dev/null
    rm -f "$batch_file"
  done

  info "Waiting 30s for sync..."
  sleep 30
  echo "1000" >"$d/dummy_services_count.txt"

  local fs_ip
  fs_ip=$(kubectl get svc -n "$NS" fortio-service -o jsonpath='{.spec.clusterIP}')

  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Via Svc 64c keepalive (1000svc) r$r" \
      "http://${fs_ip}:8080/echo?size=512" 64 true "$d" "svc_1k_svc_r${r}.json"
    sleep "$ROUND_SLEEP"
  done
  for r in $(seq 1 "$ROUNDS"); do
    _run_fortio "Via Svc 64c short (1000svc) r$r" \
      "http://${fs_ip}:8080/echo?size=512" 64 false "$d" "short_conn_1k_svc_r${r}.json"
    sleep "$ROUND_SLEEP"
  done

  info "Service scale tests complete"
}

# ─── Hubble Overhead Test ────────────────────────────────────────────────────

run_hubble_overhead_test() {
  if [[ "$CLUSTER_TYPE" != cilium-* ]]; then
    info "Skipping Hubble overhead test (not a Cilium cluster)"
    return 0
  fi
  step "Running Hubble Overhead Test"
  local d="$OUTPUT_DIR/hubble"
  mkdir -p "$d"

  local fs_ip
  fs_ip=$(kubectl get svc -n "$NS" fortio-service -o jsonpath='{.spec.clusterIP}')

  # Phase 1: with Hubble (default state)
  info "Testing with Hubble enabled (default)..."
  _run_fortio "Hubble ON (keepalive)" "http://${fs_ip}:8080/echo?size=512" 64 true "$d" "hubble_on.json"

  # Phase 2: disable Hubble
  info "Disabling Hubble..."
  kubectl -n kube-system exec ds/cilium -- cilium config set hubble-disable true >/dev/null 2>&1 || true
  sleep 15  # wait for config to propagate

  _run_fortio "Hubble OFF (keepalive)" "http://${fs_ip}:8080/echo?size=512" 64 true "$d" "hubble_off.json"

  # Restore Hubble
  info "Re-enabling Hubble..."
  kubectl -n kube-system exec ds/cilium -- cilium config set hubble-disable false >/dev/null 2>&1 || true
  sleep 10

  info "Hubble overhead test complete"
}

# ─── NetworkPolicy Overhead Test ─────────────────────────────────────────────

run_networkpolicy_test() {
  if [[ "$CLUSTER_TYPE" != cilium-* ]]; then
    info "Skipping NetworkPolicy test (not a Cilium cluster)"
    return 0
  fi
  step "Running NetworkPolicy L3/L4 Overhead Test"
  local d="$OUTPUT_DIR/networkpolicy"
  mkdir -p "$d"

  local fs_ip
  fs_ip=$(kubectl get svc -n "$NS" fortio-service -o jsonpath='{.spec.clusterIP}')

  # Phase 1: baseline (no policy)
  info "Testing without NetworkPolicy (baseline)..."
  _run_fortio "No policy (keepalive)" "http://${fs_ip}:8080/echo?size=512" 64 true "$d" "no_policy.json"

  # Phase 2: apply L3/L4 CiliumNetworkPolicy
  info "Applying L3/L4 CiliumNetworkPolicy..."
  kubectl apply -n "$NS" -f - <<'CNPEOF'
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-fortio-benchmark
spec:
  endpointSelector:
    matchLabels:
      app: benchmark
      role: fortio-server
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: benchmark
        role: fortio-client
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
CNPEOF
  sleep 10  # wait for policy to take effect

  _run_fortio "L3/L4 policy (keepalive)" "http://${fs_ip}:8080/echo?size=512" 64 true "$d" "l3l4_policy.json"

  # Cleanup policy
  info "Removing CiliumNetworkPolicy..."
  kubectl delete -n "$NS" ciliumnetworkpolicy allow-fortio-benchmark --ignore-not-found >/dev/null 2>&1
  sleep 5

  info "NetworkPolicy overhead test complete"
}

# ─── Component-Specific Metrics ─────────────────────────────────────────────

collect_component_metrics() {
  step "Collecting component-specific metrics"
  local rd="$OUTPUT_DIR/resources"
  mkdir -p "$rd"

  if [[ "$CLUSTER_TYPE" == cilium-* ]]; then
    info "Collecting Cilium metrics..."

    local cilium_csv="$rd/cilium_agent_cpu_mem.csv"
    echo "timestamp,pod,cpu_millicores,memory_mib" >"$cilium_csv"
    for _ in 1 2 3; do
      kubectl top pod -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | while read -r pod cpu mem rest; do
        echo "$(date +%H:%M:%S),$pod,${cpu%%m},${mem%%Mi}" >>"$cilium_csv"
      done
      sleep 5
    done

    info "Collecting BPF map info..."
    kubectl exec -n kube-system ds/cilium -- bpftool map list -j 2>/dev/null >"$rd/bpf_map_info.json" || true
    kubectl exec -n kube-system ds/cilium -- cilium bpf metrics 2>/dev/null >"$rd/bpf_metrics.txt" || true

    kubectl exec -n kube-system ds/cilium -- cilium bpf lb list 2>/dev/null | wc -l >"$rd/lb_entries_count.txt" || true
    kubectl exec -n kube-system ds/cilium -- cilium bpf ct list global 2>/dev/null | wc -l >"$rd/ct_entries_count.txt" || true
    kubectl exec -n kube-system ds/cilium -- cilium identity list 2>/dev/null | wc -l >"$rd/identity_count.txt" || true

  elif [[ "$CLUSTER_TYPE" == kubeproxy-* ]]; then
    info "Collecting kube-proxy metrics..."

    local kp_csv="$rd/kubeproxy_cpu_mem.csv"
    echo "timestamp,pod,cpu_millicores,memory_mib" >"$kp_csv"
    for _ in 1 2 3; do
      kubectl top pod -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | while read -r pod cpu mem rest; do
        echo "$(date +%H:%M:%S),$pod,${cpu%%m},${mem%%Mi}" >>"$kp_csv"
      done
      sleep 5
    done

    local kp_pod
    kp_pod=$(kubectl get pod -n kube-system -l k8s-app=kube-proxy -o name 2>/dev/null | head -1)
    kp_pod="${kp_pod#pod/}"

    if [[ "$CLUSTER_TYPE" == "kubeproxy-iptables" && -n "$kp_pod" ]]; then
      kubectl exec -n kube-system "$kp_pod" -- iptables-save 2>/dev/null | wc -l >"$rd/iptables_rules_count.txt" || true
    fi

    if [[ "$CLUSTER_TYPE" == "kubeproxy-ipvs" && -n "$kp_pod" ]]; then
      kubectl exec -n kube-system "$kp_pod" -- ipvsadm -ln 2>/dev/null | wc -l >"$rd/ipvs_rules_count.txt" || true
    fi
  fi

  info "Component metrics collected"
}

# ─── Generate Summary ───────────────────────────────────────────────────────

generate_summary() {
  step "Generating benchmark summary"
  local pyfile="/tmp/nb_summary_$$.py"
  cat >"$pyfile" <<'PYEOF'
import json, glob, os, csv, sys

basedir = os.environ.get('NB_OUTPUT_DIR', '.')
if not os.path.isdir(basedir):
    sys.exit(0)

summary = {"cluster": {}, "throughput": {}, "rps": {}, "latency": {}, "service_scale": {}, "resources": {}}

# Context
ctx = os.path.join(basedir, "context.yaml")
if os.path.exists(ctx):
    with open(ctx) as f:
        for line in f:
            if ':' in line:
                k, v = line.strip().split(':', 1)
                summary["cluster"][k.strip()] = v.strip()

# Throughput
def parse_iperf(p):
    fs = sorted(glob.glob(os.path.join(basedir, p)))
    if not fs:
        return None
    vals = []
    for f in fs:
        try:
            with open(f) as fh:
                d = json.load(fh)
                vals.append(round(d['end']['sum_received']['bits_per_second'] / 1e9, 2))
        except: pass
    if not vals:
        return None
    return {"gbps": vals, "avg": round(sum(vals)/len(vals), 2)}

for key, pat in [
    ("node_level_8stream", "throughput/node_throughput_r*.json"),
    ("pod2pod_single", "throughput/pod2pod_single_r*.json"),
    ("pod2pod_8stream", "throughput/pod2pod_8stream_r*.json"),
    ("pod2pod_16stream", "throughput/pod2pod_16stream_r*.json"),
    ("via_service_8stream", "throughput/via_service_8stream_r*.json"),
]:
    r = parse_iperf(pat)
    if r: summary["throughput"][key] = r

# RPS
def parse_fortio(p):
    fs = sorted(glob.glob(os.path.join(basedir, p)))
    if not fs:
        return None
    vals = []
    for f in fs:
        try:
            with open(f) as fh:
                d = json.load(fh)
                vals.append(int(d['ActualQPS']))
        except: pass
    if not vals:
        return None
    return {"qps": vals, "avg_qps": int(sum(vals)/len(vals))}

for key, pat in [
    ("pod2pod_c64", "rps/pod2pod_c64_r*.json"),
    ("svc_c64", "rps/svc_c64_r*.json"),
    ("svc_c256", "rps/svc_c256_r*.json"),
    ("svc_short_c64", "rps/svc_short_c64_r*.json"),
]:
    r = parse_fortio(pat)
    if r: summary["rps"][key] = r

# Latency
def parse_netperf_latency(p, fname):
    fs = sorted(glob.glob(os.path.join(basedir, p)))
    if not fs:
        return None
    vals = []
    idx = {"p50": 2, "p99": 4, "mean": 1}.get(fname, 2)
    for f in fs:
        try:
            with open(f) as fh:
                lines = [l.strip() for l in fh.readlines() if l.strip()]
            if not lines: continue
            parts = lines[-1].split(',')
            if len(parts) > idx: vals.append(float(parts[idx]))
        except: pass
    if not vals:
        return None
    return int(sum(vals)/len(vals))

p50 = parse_netperf_latency("latency/tcp_rr_r*.txt", "p50")
p99 = parse_netperf_latency("latency/tcp_rr_r*.txt", "p99")
crr99 = parse_netperf_latency("latency/tcp_crr_r*.txt", "p99")
if p50: summary["latency"]["tcp_rr_p50_us"] = p50
if p99: summary["latency"]["tcp_rr_p99_us"] = p99
if crr99: summary["latency"]["tcp_crr_p99_us"] = crr99

# HTTP p99
hfs = glob.glob(os.path.join(basedir, "latency/http_1k_qps.json"))
if hfs:
    try:
        with open(hfs[0]) as f: d = json.load(f)
        for p in d.get('DurationHistogram', {}).get('Percentiles', []):
            if p.get('Percentile') == 99:
                summary["latency"]["http_p99_1k_qps_ms"] = round(p['Value'] * 1000, 2)
                break
    except: pass

# Service scale — compare keepalive and short-connection with their baselines
summary["service_scale"] = {}
# Keepalive
scale_ka = parse_fortio("service-scale/svc_1k_svc_r*.json")
baseline_ka = summary.get("rps", {}).get("svc_c64", {}).get("avg_qps")
if scale_ka and baseline_ka and baseline_ka > 0:
    summary["service_scale"]["keepalive_baseline_qps"] = baseline_ka
    summary["service_scale"]["keepalive_1k_svc_qps"] = scale_ka["avg_qps"]
    summary["service_scale"]["keepalive_degradation_pct"] = round((scale_ka["avg_qps"] - baseline_ka) / baseline_ka * 100, 1)
# Short-connection
scale_short = parse_fortio("service-scale/short_conn_1k_svc_r*.json")
baseline_short = summary.get("rps", {}).get("svc_short_c64", {}).get("avg_qps")
if scale_short and baseline_short and baseline_short > 0:
    summary["service_scale"]["short_conn_baseline_qps"] = baseline_short
    summary["service_scale"]["short_conn_1k_svc_qps"] = scale_short["avg_qps"]
    summary["service_scale"]["short_conn_degradation_pct"] = round((scale_short["avg_qps"] - baseline_short) / baseline_short * 100, 1)

# Rules count
for cf_key in ["iptables_rules_count.txt", "ipvs_rules_count.txt"]:
    cf = os.path.join(basedir, "resources", cf_key)
    if os.path.exists(cf):
        with open(cf) as f:
            summary["service_scale"][cf_key.replace("_count.txt", "_rules")] = int(f.read().strip())

# Resources
def parse_csv(pattern):
    fs = sorted(glob.glob(os.path.join(basedir, pattern)))
    if not fs:
        return {}, {}
    cpu_vals, mem_vals = [], []
    for f in fs:
        try:
            with open(f) as fh:
                for row in csv.DictReader(fh):
                    try:
                        cpu_vals.append(float(row['cpu_millicores']))
                        mem_vals.append(float(row['memory_mib']))
                    except: pass
        except: pass
    if not cpu_vals:
        return {}, {}
    return {"avg_cpu_m": round(sum(cpu_vals)/len(cpu_vals), 1)}, \
           {"avg_mem_mb": round(sum(mem_vals)/len(mem_vals), 1)}

for res_key, csv_pat in [
    ("cilium_agent", "resources/cilium_*.csv"),
    ("kubeproxy", "resources/kubeproxy_*.csv"),
]:
    cpu_d, mem_d = parse_csv(csv_pat)
    if cpu_d: summary["resources"][res_key] = {**cpu_d, **mem_d}

# Hubble overhead
def parse_single_fortio(path):
    fp = os.path.join(basedir, path)
    if not os.path.exists(fp):
        return None
    try:
        with open(fp) as fh:
            d = json.load(fh)
            return int(d['ActualQPS'])
    except:
        return None

hubble_on = parse_single_fortio("hubble/hubble_on.json")
hubble_off = parse_single_fortio("hubble/hubble_off.json")
if hubble_on and hubble_off and hubble_off > 0:
    summary["hubble"] = {
        "with_hubble_qps": hubble_on,
        "without_hubble_qps": hubble_off,
        "overhead_pct": round((hubble_on - hubble_off) / hubble_off * 100, 1)
    }

# NetworkPolicy overhead
np_baseline = parse_single_fortio("networkpolicy/no_policy.json")
np_l3l4 = parse_single_fortio("networkpolicy/l3l4_policy.json")
if np_baseline and np_l3l4 and np_baseline > 0:
    summary["networkpolicy"] = {
        "baseline_qps": np_baseline,
        "l3l4_qps": np_l3l4,
        "l3l4_overhead_pct": round((np_l3l4 - np_baseline) / np_baseline * 100, 1)
    }

# Write
out = os.path.join(basedir, "benchmark-summary.json")
with open(out, 'w') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print(f"Summary written to {out}")
PYEOF
  NB_OUTPUT_DIR="$OUTPUT_DIR" python3 "$pyfile" 2>/dev/null || warn "Python3 not available for summary generation"
  rm -f "$pyfile"
}

# ─── Print Summary Table ────────────────────────────────────────────────────

print_summary_table() {
  step "Benchmark Results Summary"
  local f="$OUTPUT_DIR/benchmark-summary.json"
  if [[ ! -f "$f" ]]; then
    warn "No summary file found at $f"
    return
  fi
  local pyfile="/tmp/nb_print_$$.py"
  cat >"$pyfile" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print()
print(f"  Cluster:       {d.get('cluster', {}).get('cluster_name', '?')}")
print(f"  Type:          {d.get('cluster', {}).get('cluster_type', '?')}")
print(f"  K8s Version:   {d.get('cluster', {}).get('k8s_version', '?')}")
print()
t = d.get('throughput', {})
if t:
    print("  ── Throughput ──")
    for k, v in t.items():
        print(f"    {k}: {v.get('avg', '?')} Gbps (rounds: {v.get('gbps', [])})")
    print()
r = d.get('rps', {})
if r:
    print("  ── RPS ──")
    for k, v in r.items():
        print(f"    {k}: {v.get('avg_qps', '?')} req/s")
    print()
l = d.get('latency', {})
if l:
    print("  ── Latency ──")
    for k, v in l.items():
        print(f"    {k}: {v}")
    print()
ss = d.get('service_scale', {})
if ss:
    print("  ── Service Scale (1000 Services) ──")
    if 'keepalive_baseline_qps' in ss:
        print(f"    keepalive baseline: {ss['keepalive_baseline_qps']} req/s")
        print(f"    keepalive 1k svc:   {ss['keepalive_1k_svc_qps']} req/s")
        print(f"    keepalive degrade:  {ss['keepalive_degradation_pct']}%")
    if 'short_conn_baseline_qps' in ss:
        print(f"    short-conn baseline: {ss['short_conn_baseline_qps']} req/s")
        print(f"    short-conn 1k svc:   {ss['short_conn_1k_svc_qps']} req/s")
        print(f"    short-conn degrade:  {ss['short_conn_degradation_pct']}%")
    print()
hb = d.get('hubble', {})
if hb:
    print("  ── Hubble Overhead ──")
    print(f"    with Hubble:    {hb.get('with_hubble_qps', '?')} req/s")
    print(f"    without Hubble: {hb.get('without_hubble_qps', '?')} req/s")
    print(f"    overhead:       {hb.get('overhead_pct', '?')}%")
    print()
np = d.get('networkpolicy', {})
if np:
    print("  ── NetworkPolicy L3/L4 Overhead ──")
    print(f"    no policy:  {np.get('baseline_qps', '?')} req/s")
    print(f"    L3/L4 CNP:  {np.get('l3l4_qps', '?')} req/s")
    print(f"    overhead:   {np.get('l3l4_overhead_pct', '?')}%")
    print()
PYEOF
  python3 "$pyfile" "$f" 2>/dev/null || true
  rm -f "$pyfile"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "╔═══════════════════════════════════════╗"
  echo "║         TKE Network Benchmark         ║"
  echo "╚═══════════════════════════════════════╝"
  echo ""

  parse_args "$@"

  check_prereqs || {
    err "Prerequisite check failed"
    exit 1
  }

  info "Current context: $(get_cluster_name)"

  detect_cluster_type

  local cname
  cname=$(get_cluster_name)
  OUTPUT_DIR="${OUTPUT_DIR:-./benchmark-results-${cname}}"
  info "Output directory: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR/resources"

  collect_context_info
  select_worker_nodes

  deploy_test_workloads
  run_throughput_tests
  run_rps_tests
  run_latency_tests
  run_hubble_overhead_test
  run_networkpolicy_test
  run_service_scale_test
  collect_component_metrics

  generate_summary
  print_summary_table

  cleanup_test_workloads

  green ""
  green "╔══════════════════════════════════════════════════════════╗"
  green "║          Benchmark Complete!                            ║"
  green "╚══════════════════════════════════════════════════════════╝"
  green ""
  green "Results saved to: $OUTPUT_DIR"
  green "Summary file:     $OUTPUT_DIR/benchmark-summary.json"
  echo ""
}

main "$@"
