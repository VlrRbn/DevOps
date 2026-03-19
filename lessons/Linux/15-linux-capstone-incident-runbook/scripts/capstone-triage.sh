#!/usr/bin/env bash
# Description: Extended Linux capstone triage report (system, resources, network, boot diagnostics).
# Usage: capstone-triage.sh [--seconds N] [--since STR] [--save-dir DIR] [--strict] [--json]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  capstone-triage.sh [--seconds N] [--since STR] [--save-dir DIR] [--strict] [--json]

Defaults:
  --seconds 5
  --since "-2h"

Examples:
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --json --save-dir /tmp/lesson15-reports
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --strict
USAGE
}

SECONDS_N="5"
SINCE="-2h"
SAVE_DIR=""
STRICT=0
JSON_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --seconds)
      [[ $# -ge 2 ]] || { echo "ERROR: --seconds requires value" >&2; exit 2; }
      SECONDS_N="$2"
      shift 2
      ;;
    --since)
      [[ $# -ge 2 ]] || { echo "ERROR: --since requires value" >&2; exit 2; }
      SINCE="$2"
      shift 2
      ;;
    --save-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --save-dir requires value" >&2; exit 2; }
      SAVE_DIR="$2"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ "$SECONDS_N" =~ ^[0-9]+$ ]] || { echo "ERROR: --seconds must be integer" >&2; exit 2; }
(( SECONDS_N >= 1 )) || { echo "ERROR: --seconds must be >= 1" >&2; exit 2; }

for cmd in awk date hostname uname uptime free df vmstat ps ip ss lsblk findmnt journalctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

HAS_IOSTAT=0
HAS_PIDSTAT=0
# curl is optional: without it, egress HTTPS check is reported as SKIPPED.
HAS_CURL=0
if command -v iostat >/dev/null 2>&1; then
  HAS_IOSTAT=1
fi
if command -v pidstat >/dev/null 2>&1; then
  HAS_PIDSTAT=1
fi
if command -v curl >/dev/null 2>&1; then
  HAS_CURL=1
fi

nproc_count="$(nproc)"
load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
load_per_core="$(awk -v l="$load1" -v c="$nproc_count" 'BEGIN{if(c>0) printf "%.2f", l/c; else print "0.00"}')"
mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
mem_avail_pct="$(awk -v a="$mem_avail_kb" -v t="$mem_total_kb" 'BEGIN{if(t>0) printf "%.1f", (a/t)*100; else print "0.0"}')"
swap_used_mb="$(free -m | awk '/^Swap:/ {print $3+0}')"

# Disk usage across real filesystems (not only /).
fs_usage_table="$(
  df -PT \
    -x tmpfs -x devtmpfs -x squashfs -x overlay -x aufs -x ramfs \
    -x proc -x sysfs -x cgroup -x cgroup2 -x efivarfs -x devpts \
    -x mqueue -x tracefs -x securityfs -x configfs -x debugfs -x pstore \
    -x bpf -x fusectl -x autofs -x binfmt_misc -x rpc_pipefs 2>/dev/null \
    | awk 'NR>1 {use=$6; gsub(/%/,"",use); if (use ~ /^[0-9]+$/) print use "\t" $7 "\t" $2 "\t" $1}' \
    | sort -nr || true
)"

fs_max_use_pct=0
fs_max_target="N/A"
fs_max_fstype="N/A"
fs_max_source="N/A"
root_use_pct="N/A"
fs_hotspots=()

if [[ -n "$fs_usage_table" ]]; then
  fs_max_use_pct="$(awk -F'\t' 'NR==1 {print $1+0}' <<<"$fs_usage_table")"
  fs_max_target="$(awk -F'\t' 'NR==1 {print $2}' <<<"$fs_usage_table")"
  fs_max_fstype="$(awk -F'\t' 'NR==1 {print $3}' <<<"$fs_usage_table")"
  fs_max_source="$(awk -F'\t' 'NR==1 {print $4}' <<<"$fs_usage_table")"

  root_candidate="$(awk -F'\t' '$2=="/" {print $1; exit}' <<<"$fs_usage_table")"
  if [[ -n "$root_candidate" ]]; then
    root_use_pct="$root_candidate"
  fi

  while IFS=$'\t' read -r use target fstype source; do
    [[ -n "${use:-}" ]] || continue
    if (( use >= 90 )); then
      fs_hotspots+=("${use}% ${target} (${fstype}, ${source})")
    fi
  done <<<"$fs_usage_table"
fi

run_state="unknown"
failed_count="N/A"
failed_units_raw=""
failed_unit_names=()
failed_units_preview="none"
if command -v systemctl >/dev/null 2>&1; then
  run_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ -n "$run_state" ]] || run_state="unknown"
  failed_units_raw="$(systemctl list-units --failed --no-legend --plain 2>/dev/null || true)"
  failed_count="$(awk 'NF{c++} END{print c+0}' <<<"$failed_units_raw" || true)"
  [[ -n "$failed_count" ]] || failed_count="N/A"

  while read -r unit _rest; do
    [[ -n "${unit:-}" ]] || continue
    failed_unit_names+=("$unit")
  done <<<"$failed_units_raw"
fi

if (( ${#failed_unit_names[@]} > 0 )); then
  failed_units_preview=""
  for unit in "${failed_unit_names[@]:0:3}"; do
    if [[ -n "$failed_units_preview" ]]; then
      failed_units_preview+=", "
    fi
    failed_units_preview+="$unit"
  done
  if (( ${#failed_unit_names[@]} > 3 )); then
    failed_units_preview+=", ..."
  fi
fi

default_route="$(ip route show default 2>/dev/null | head -n 1 || true)"
egress_state="skipped_no_curl"
egress_ok=2
# egress_ok: 1=OK, 0=FAIL, 2=SKIPPED(no curl). egress_state is JSON-friendly text.
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

iowait="N/A"
if command -v vmstat >/dev/null 2>&1; then
  iowait="$(vmstat 1 2 | tail -n 1 | awk '{print $16+0}')"
fi

dmesg_out="[INFO] dmesg unavailable"
dmesg_mode="unavailable"
if command -v dmesg >/dev/null 2>&1; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    dmesg_out="$(dmesg --level=err,warn 2>&1 | tail -n 80 || true)"
    dmesg_mode="captured_as_root"
  else
    if dmesg_out="$(dmesg --level=err,warn 2>&1 | tail -n 80)"; then
      dmesg_mode="captured_as_user"
    else
      dmesg_out=$'[INFO] skipped dmesg capture: insufficient privileges\n[INFO] run capstone-triage with sudo to include kernel warnings/errors'
      dmesg_mode="skipped_insufficient_privileges"
    fi
  fi
else
  dmesg_out=$'[INFO] skipped dmesg capture: dmesg command not found'
  dmesg_mode="skipped_missing_command"
fi

strict_fail=0
warn_msgs=()

add_warn() {
  strict_fail=1
  warn_msgs+=("$1")
}

if [[ "$run_state" == "degraded" || "$run_state" == "maintenance" || "$run_state" == "offline" ]]; then
  add_warn "system run state is unhealthy: $run_state"
fi
if [[ "$failed_count" != "N/A" ]] && (( failed_count > 0 )); then
  add_warn "failed units detected: $failed_count ($failed_units_preview)"
fi
if (( fs_max_use_pct >= 90 )); then
  add_warn "high filesystem usage: ${fs_max_use_pct}% on ${fs_max_target} (${fs_max_fstype}, ${fs_max_source}) (threshold >=90%)"
fi
if awk -v x="$mem_avail_pct" 'BEGIN{exit !(x < 10.0)}'; then
  add_warn "low MemAvailable: ${mem_avail_pct}% (threshold <10%)"
fi
if awk -v x="$load_per_core" 'BEGIN{exit !(x >= 1.50)}'; then
  add_warn "high load per core: $load_per_core (threshold >=1.50)"
fi
if [[ -z "$default_route" ]]; then
  add_warn "missing default route"
fi
if (( HAS_CURL )) && (( egress_ok == 0 )); then
  add_warn "egress HTTPS check failed (curl https://example.com)"
fi

strict_failed=0
if (( STRICT && strict_fail )); then
  strict_failed=1
fi

render_report() {
  echo "[INFO] linux capstone triage report"
  echo "[INFO] generated: $(date '+%F %T')"
  echo "[INFO] host: $(hostname)"
  echo "[INFO] kernel: $(uname -r)"
  echo "[INFO] sample_seconds: $SECONDS_N"
  echo "[INFO] journal_since: $SINCE"
  echo "[INFO] optional tools: iostat=$HAS_IOSTAT pidstat=$HAS_PIDSTAT"
  echo

  echo "[CHECK] system state"
  echo "run_state=$run_state failed_units=$failed_count"
  echo "failed_unit_names=$failed_units_preview"
  if command -v systemctl >/dev/null 2>&1; then
    if [[ -n "$failed_units_raw" ]]; then
      printf '%s\n' "$failed_units_raw"
    else
      echo "[INFO] no failed systemd units"
    fi
  fi
  echo

  echo "[CHECK] load/memory/disk"
  uptime
  echo "load1=$load1 nproc=$nproc_count load_per_core=$load_per_core"
  free -h
  echo "mem_available_pct=${mem_avail_pct}% swap_used_mb=$swap_used_mb filesystem_max_use_pct=${fs_max_use_pct}%"
  echo "filesystem_max_target=${fs_max_target} filesystem_max_fstype=${fs_max_fstype} filesystem_max_source=${fs_max_source}"
  echo "root_use_pct=${root_use_pct}"
  if (( ${#fs_hotspots[@]} > 0 )); then
    echo "filesystem_hotspots(>=90%):"
    for hotspot in "${fs_hotspots[@]}"; do
      echo "  - $hotspot"
    done
  fi
  echo "iowait=$iowait"
  df -hT
  echo

  echo "[CHECK] top processes"
  ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%cpu | head -n 15
  ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%mem | head -n 15
  echo

  echo "[CHECK] vmstat sample (1s x ${SECONDS_N})"
  vmstat 1 "$SECONDS_N"
  echo

  if (( HAS_IOSTAT )); then
    echo "[CHECK] iostat -xz sample (1s x ${SECONDS_N})"
    iostat -xz 1 "$SECONDS_N"
    echo
  else
    echo "[INFO] skipped iostat block (not installed)"
    echo
  fi

  if (( HAS_PIDSTAT )); then
    echo "[CHECK] pidstat sample (1s x ${SECONDS_N})"
    pidstat 1 "$SECONDS_N"
    echo
  else
    echo "[INFO] skipped pidstat block (not installed)"
    echo
  fi

  echo "[CHECK] network snapshot"
  echo "default_route=${default_route:-MISSING}"
  if (( egress_ok == 1 )); then
    echo "egress_https=OK"
  elif (( egress_ok == 0 )); then
    echo "egress_https=FAIL"
  else
    echo "egress_https=SKIPPED (curl not installed)"
  fi
  ip -brief addr
  ip route
  ss -tulpen | sed -n '1,80p'
  echo

  echo "[CHECK] storage snapshot"
  lsblk -f
  findmnt -A
  echo

  echo "[CHECK] journal warning..alert"
  journalctl --since "$SINCE" -p warning..alert --no-pager | sed -n '1,200p'
  echo

  echo "[CHECK] dmesg err,warn"
  printf '%s\n' "$dmesg_out"

  if (( ${#warn_msgs[@]} > 0 )); then
    echo
    echo "[CHECK] strict warning summary"
    for msg in "${warn_msgs[@]}"; do
      echo "[WARN] $msg"
    done
  fi
}

render_json() {
  local report_path="${1:-}"
  local failed_units_json="null"
  local iowait_json="null"
  local root_use_json="null"

  if [[ "$failed_count" =~ ^[0-9]+$ ]]; then
    failed_units_json="$failed_count"
  fi
  if [[ "$iowait" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    iowait_json="$iowait"
  fi
  if [[ "$root_use_pct" =~ ^[0-9]+$ ]]; then
    root_use_json="$root_use_pct"
  fi

  printf '{\n'
  printf '  "script": "capstone-triage",\n'
  printf '  "generated_at": "%s",\n' "$(date '+%F %T')"
  printf '  "host": "%s",\n' "$(json_escape "$(hostname)")"
  printf '  "kernel": "%s",\n' "$(json_escape "$(uname -r)")"
  printf '  "strict": %s,\n' "$([[ $STRICT -eq 1 ]] && echo true || echo false)"
  printf '  "seconds": %s,\n' "$SECONDS_N"
  printf '  "since": "%s",\n' "$(json_escape "$SINCE")"
  printf '  "run_state": "%s",\n' "$(json_escape "$run_state")"
  printf '  "failed_units": %s,\n' "$failed_units_json"
  printf '  "failed_unit_names": ['
  for i in "${!failed_unit_names[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "$(json_escape "${failed_unit_names[$i]}")"
  done
  printf '],\n'
  printf '  "metrics": {\n'
  printf '    "load1": %s,\n' "$load1"
  printf '    "load_per_core": %s,\n' "$load_per_core"
  printf '    "mem_available_pct": %s,\n' "$mem_avail_pct"
  printf '    "swap_used_mb": %s,\n' "$swap_used_mb"
  printf '    "filesystem_max_use_pct": %s,\n' "$fs_max_use_pct"
  printf '    "filesystem_max_target": "%s",\n' "$(json_escape "$fs_max_target")"
  printf '    "filesystem_max_fstype": "%s",\n' "$(json_escape "$fs_max_fstype")"
  printf '    "filesystem_max_source": "%s",\n' "$(json_escape "$fs_max_source")"
  printf '    "root_use_pct": %s,\n' "$root_use_json"
  printf '    "iowait": %s\n' "$iowait_json"
  printf '  },\n'
  printf '  "network": {\n'
  printf '    "default_route_present": %s,\n' "$([[ -n "$default_route" ]] && echo true || echo false)"
  printf '    "default_route": "%s",\n' "$(json_escape "${default_route:-}")"
  if (( egress_ok == 1 )); then
    printf '    "egress_ok": true,\n'
  elif (( egress_ok == 0 )); then
    printf '    "egress_ok": false,\n'
  else
    printf '    "egress_ok": null,\n'
  fi
  printf '    "egress_check": "%s"\n' "$egress_state"
  printf '  },\n'
  printf '  "optional_tools": {\n'
  printf '    "iostat": %s,\n' "$([[ $HAS_IOSTAT -eq 1 ]] && echo true || echo false)"
  printf '    "pidstat": %s\n' "$([[ $HAS_PIDSTAT -eq 1 ]] && echo true || echo false)"
  printf '  },\n'
  printf '  "dmesg_mode": "%s",\n' "$(json_escape "$dmesg_mode")"
  printf '  "filesystem_hotspots": ['
  for i in "${!fs_hotspots[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "$(json_escape "${fs_hotspots[$i]}")"
  done
  printf '],\n'
  printf '  "warnings": ['
  for i in "${!warn_msgs[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "$(json_escape "${warn_msgs[$i]}")"
  done
  printf '],\n'
  printf '  "status": "%s",\n' "$([[ ${#warn_msgs[@]} -gt 0 ]] && echo warn || echo ok)"
  printf '  "strict_failed": %s,\n' "$([[ $strict_failed -eq 1 ]] && echo true || echo false)"
  if [[ -n "$report_path" ]]; then
    printf '  "report_path": "%s"\n' "$(json_escape "$report_path")"
  else
    printf '  "report_path": null\n'
  fi
  printf '}\n'
}

if [[ -n "$SAVE_DIR" ]]; then
  mkdir -p "$SAVE_DIR"
  if (( JSON_MODE )); then
    REPORT="$SAVE_DIR/capstone-triage_$(date +%Y%m%d_%H%M%S).json"
    render_json "$REPORT" | tee "$REPORT"
    echo "[INFO] saved report: $REPORT" >&2
  else
    REPORT="$SAVE_DIR/capstone-triage_$(date +%Y%m%d_%H%M%S).txt"
    render_report | tee "$REPORT"
    echo "[INFO] saved report: $REPORT"
  fi
else
  if (( JSON_MODE )); then
    render_json
  else
    render_report
  fi
fi

if (( strict_failed )); then
  if (( JSON_MODE == 0 )); then
    echo "[FAIL] strict mode detected capstone triage issues" >&2
  fi
  exit 1
fi

if (( JSON_MODE == 0 )); then
  echo "[OK] capstone triage completed"
fi
