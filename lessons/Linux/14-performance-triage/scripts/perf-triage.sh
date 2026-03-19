#!/usr/bin/env bash
# Description: Build an extended performance triage report (CPU/RAM/IO/process view).
# Usage: perf-triage.sh [--seconds N] [--save-dir DIR] [--strict]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  perf-triage.sh [--seconds N] [--save-dir DIR] [--strict]

Defaults:
  --seconds 5

Examples:
  ./lessons/14-performance-triage/scripts/perf-triage.sh
  ./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
  ./lessons/14-performance-triage/scripts/perf-triage.sh --strict
USAGE
}

SECONDS_N="5"
SAVE_DIR=""
STRICT=0

# Parse supported options.
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
    --save-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --save-dir requires value" >&2; exit 2; }
      SAVE_DIR="$2"
      shift 2
      ;;
    --strict)
      STRICT=1
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

# Validate base commands.
for cmd in awk nproc free ps uptime vmstat date hostname uname; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# Detect optional tools once and report capability summary in output.
# iostat and pidstat from sysstat package are common, but not always installed by default.
HAS_IOSTAT=0
HAS_PIDSTAT=0
if command -v iostat >/dev/null 2>&1; then
  HAS_IOSTAT=1
fi
if command -v pidstat >/dev/null 2>&1; then
  HAS_PIDSTAT=1
fi

# Pre-calc strict heuristics before report rendering.
nproc_count="$(nproc)"
load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
load_per_core="$(awk -v l="$load1" -v c="$nproc_count" 'BEGIN{if(c>0) printf "%.2f", l/c; else print "0.00"}')"
mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
mem_avail_pct="$(awk -v a="$mem_avail_kb" -v t="$mem_total_kb" 'BEGIN{if(t>0) printf "%.1f", (a/t)*100; else print "0.0"}')"
swap_used_mb="$(free -m | awk '/^Swap:/ {print $3+0}')"

iowait="0"
if command -v vmstat >/dev/null 2>&1; then
  iowait="$(vmstat 1 2 | tail -n 1 | awk '{print $16+0}')"
fi

strict_fail=0
if awk -v x="$load_per_core" 'BEGIN{exit !(x >= 1.50)}'; then strict_fail=1; fi
if awk -v x="$mem_avail_pct" 'BEGIN{exit !(x < 10.0)}'; then strict_fail=1; fi
if (( swap_used_mb > 512 )); then strict_fail=1; fi
if (( iowait >= 25 )); then strict_fail=1; fi

render_report() {
  echo "[INFO] performance triage report"
  echo "[INFO] generated: $(date '+%F %T')"
  echo "[INFO] host: $(hostname)"
  echo "[INFO] kernel: $(uname -r)"
  echo "[INFO] sample_seconds: $SECONDS_N"
  echo "[INFO] optional tools:"
  if (( HAS_IOSTAT )); then
    echo "  - iostat: available"
  else
    echo "  - iostat: missing"
  fi
  if (( HAS_PIDSTAT )); then
    echo "  - pidstat: available"
  else
    echo "  - pidstat: missing"
  fi
  if (( ! HAS_IOSTAT || ! HAS_PIDSTAT )); then
    echo "  - tip: install sysstat for full disk/process sampling"
  fi
  echo

  echo "[CHECK] uptime + load"
  uptime
  echo "load1=$load1 nproc=$nproc_count load_per_core=$load_per_core"
  echo

  echo "[CHECK] memory and swap"
  free -h
  echo "mem_available_pct=${mem_avail_pct}%"
  echo "swap_used_mb=$swap_used_mb"
  echo

  echo "[CHECK] top CPU processes"
  ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%cpu | head -n 15
  echo

  echo "[CHECK] top MEM processes"
  ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%mem | head -n 15
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
    echo "[CHECK] pidstat CPU sample (1s x ${SECONDS_N})"
    pidstat 1 "$SECONDS_N"
    echo
  else
    echo "[INFO] skipped pidstat block (not installed)"
    echo
  fi

  echo "[CHECK] strict heuristics snapshot"
  echo "load_per_core=$load_per_core (warn >= 1.50)"
  echo "mem_available_pct=${mem_avail_pct}% (warn < 10%)"
  echo "swap_used_mb=$swap_used_mb (warn > 512)"
  echo "iowait=$iowait (warn >= 25)"
}

# Save to file if requested.
if [[ -n "$SAVE_DIR" ]]; then
  mkdir -p "$SAVE_DIR"
  REPORT="$SAVE_DIR/perf-triage_$(date +%Y%m%d_%H%M%S).txt"
  render_report | tee "$REPORT"
  echo "[INFO] saved report: $REPORT"
else
  render_report
fi

if (( STRICT && strict_fail )); then
  echo "[FAIL] strict mode detected performance pressure" >&2
  exit 1
fi

echo "[OK] performance triage completed"
