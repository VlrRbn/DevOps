#!/usr/bin/env bash
# Description: Quick final Linux health gate (system, resources, network, boot state).
# Usage: capstone-health-check.sh [--strict] [--json]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  capstone-health-check.sh [--strict] [--json]

Examples:
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --json
USAGE
}

STRICT=0
JSON_MODE=0

# Parse supported flags.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --strict)
      STRICT=1
      ;;
    --json)
      JSON_MODE=1
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate required tools.
for cmd in awk free df uptime nproc vmstat ip getent; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# curl is optional: without it, egress HTTPS check is reported as SKIPPED.
HAS_CURL=0
if command -v curl >/dev/null 2>&1; then
  HAS_CURL=1
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

parse_vmstat_metric() {
  local metric="$1"
  local snapshot="$2"

  awk -v key="$metric" '
    /^[[:space:]]*r[[:space:]]+b[[:space:]]+swpd[[:space:]]/ {
      for (i = 1; i <= NF; i++) idx[$i] = i
      next
    }
    idx[key] && $1 ~ /^[0-9]+$/ {
      val = $(idx[key])
    }
    END {
      if (val == "") {
        exit 1
      }
      print val
    }
  ' <<<"$snapshot"
}

warn=0
warn_msgs=()

add_warn() {
  local msg="$1"
  warn=1
  warn_msgs+=("$msg")
  if (( JSON_MODE == 0 )); then
    echo "[WARN] $msg"
  fi
}

# Baseline host load and capacity.
nproc_count="$(nproc)"
load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
load_per_core="$(awk -v l="$load1" -v c="$nproc_count" 'BEGIN{if(c>0) printf "%.2f", l/c; else print "0.00"}')"

# Memory pressure from MemAvailable.
mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
mem_avail_pct="$(awk -v a="$mem_avail_kb" -v t="$mem_total_kb" 'BEGIN{if(t>0) printf "%.1f", (a/t)*100; else print "0.0"}')"

# Disk usage of root filesystem (core lab check).
root_use_pct="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
root_use_pct="${root_use_pct:-0}"

vmstat_snapshot="$(vmstat 1 2)"
iowait="$(parse_vmstat_metric wa "$vmstat_snapshot" || echo "N/A")"

run_state="unknown"
failed_count="N/A"
if command -v systemctl >/dev/null 2>&1; then
  run_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ -n "$run_state" ]] || run_state="unknown"
  failed_count="$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk 'NF{c++} END{print c+0}' || true)"
  [[ -n "$failed_count" ]] || failed_count="N/A"
fi

default_route="$(ip route show default 2>/dev/null | head -n 1 || true)"
dns_ok=1
if ! getent ahosts example.com >/dev/null 2>&1; then
  dns_ok=0
fi

egress_state="skipped_no_curl"
egress_ok=2
# Run egress check only when curl is present.
if (( HAS_CURL )); then
  if curl -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
    egress_state="ok"
    egress_ok=1
  else
    egress_state="fail"
    egress_ok=0
  fi
fi

if [[ "$run_state" == "degraded" || "$run_state" == "maintenance" || "$run_state" == "offline" ]]; then
  add_warn "system run state is unhealthy: $run_state"
fi

if [[ "$failed_count" != "N/A" ]] && (( failed_count > 0 )); then
  add_warn "failed units detected: $failed_count"
fi

if awk -v x="$load_per_core" 'BEGIN{exit !(x >= 1.50)}'; then
  add_warn "high load per core: $load_per_core (threshold >=1.50)"
fi

if awk -v x="$mem_avail_pct" 'BEGIN{exit !(x < 10.0)}'; then
  add_warn "low MemAvailable: ${mem_avail_pct}% (threshold <10%)"
fi

if (( root_use_pct >= 90 )); then
  add_warn "high root filesystem usage: ${root_use_pct}% (threshold >=90%)"
fi

if [[ "$iowait" != "N/A" ]] && awk -v x="$iowait" 'BEGIN{exit !(x >= 25)}'; then
  add_warn "high iowait: ${iowait}% (threshold >=25%)"
fi

if [[ -z "$default_route" ]]; then
  add_warn "missing default route"
fi

if (( dns_ok == 0 )); then
  add_warn "DNS resolution test failed (getent ahosts example.com)"
fi

if (( HAS_CURL )) && (( egress_ok == 0 )); then
  add_warn "egress HTTPS check failed (curl https://example.com)"
fi

strict_failed=0
if (( STRICT && warn )); then
  strict_failed=1
fi

# Output results in JSON format for automation, otherwise human-readable.
if (( JSON_MODE )); then
  failed_units_json="null"
  if [[ "$failed_count" =~ ^[0-9]+$ ]]; then
    failed_units_json="$failed_count"
  fi

  iowait_json="null"
  if [[ "$iowait" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    iowait_json="$iowait"
  fi

  printf '{\n'
  printf '  "script": "capstone-health-check",\n'
  printf '  "strict": %s,\n' "$([[ $STRICT -eq 1 ]] && echo true || echo false)"
  printf '  "run_state": "%s",\n' "$(json_escape "$run_state")"
  printf '  "failed_units": %s,\n' "$failed_units_json"
  printf '  "load1": %s,\n' "$load1"
  printf '  "load_per_core": %s,\n' "$load_per_core"
  printf '  "mem_available_pct": %s,\n' "$mem_avail_pct"
  printf '  "root_use_pct": %s,\n' "$root_use_pct"
  printf '  "iowait": %s,\n' "$iowait_json"
  printf '  "default_route_present": %s,\n' "$([[ -n "$default_route" ]] && echo true || echo false)"
  printf '  "dns_ok": %s,\n' "$([[ $dns_ok -eq 1 ]] && echo true || echo false)"
  if (( egress_ok == 1 )); then
    printf '  "egress_ok": true,\n'
  elif (( egress_ok == 0 )); then
    printf '  "egress_ok": false,\n'
  else
    printf '  "egress_ok": null,\n'
  fi
  printf '  "egress_check": "%s",\n' "$egress_state"
  printf '  "warnings": ['
  for i in "${!warn_msgs[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "$(json_escape "${warn_msgs[$i]}")"
  done
  printf '],\n'
  printf '  "status": "%s",\n' "$([[ $warn -eq 1 ]] && echo warn || echo ok)"
  printf '  "strict_failed": %s\n' "$([[ $strict_failed -eq 1 ]] && echo true || echo false)"
  printf '}\n'
else
  echo "[CHECK] system state"
  echo "run_state=$run_state failed_units=$failed_count"
  echo

  echo "[CHECK] load/memory/disk"
  uptime
  echo "load1=$load1 nproc=$nproc_count load_per_core=$load_per_core"
  free -h
  echo "mem_available_pct=${mem_avail_pct}%"
  echo "root_use_pct=${root_use_pct}%"
  echo "iowait=$iowait"
  echo

  echo "[CHECK] network basics"
  if [[ -n "$default_route" ]]; then
    echo "default_route=$default_route"
  else
    echo "default_route=MISSING"
  fi
  echo "dns_resolution=$([[ $dns_ok -eq 1 ]] && echo OK || echo FAIL)"
  if (( egress_ok == 1 )); then
    echo "egress_https=OK"
  elif (( egress_ok == 0 )); then
    echo "egress_https=FAIL"
  else
    echo "egress_https=SKIPPED (curl not installed)"
  fi

  if (( warn == 0 )); then
    echo "[INFO] no warnings detected"
  fi
fi

if (( strict_failed )); then
  if (( JSON_MODE == 0 )); then
    echo "[FAIL] strict mode found Linux health issues" >&2
  fi
  exit 1
fi

if (( JSON_MODE == 0 )); then
  echo "[OK] capstone health check completed"
fi
