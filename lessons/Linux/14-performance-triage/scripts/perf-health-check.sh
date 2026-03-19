#!/usr/bin/env bash
# Description: Quick CPU/RAM/IO pressure check with optional strict exit behavior.
# Usage: perf-health-check.sh [--strict]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  perf-health-check.sh [--strict]

Examples:
  ./lessons/14-performance-triage/scripts/perf-health-check.sh
  ./lessons/14-performance-triage/scripts/perf-health-check.sh --strict
USAGE
}

STRICT=0

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
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate required tools.
for cmd in awk nproc free ps uptime vmstat; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

warn=0

# Baseline host load and capacity.
nproc_count="$(nproc)"
load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
load_per_core="$(awk -v l="$load1" -v c="$nproc_count" 'BEGIN{if(c>0) printf "%.2f", l/c; else print "0.00"}')"

# Memory pressure from MemAvailable, not just "free" column.
mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
mem_avail_pct="$(awk -v a="$mem_avail_kb" -v t="$mem_total_kb" 'BEGIN{if(t>0) printf "%.1f", (a/t)*100; else print "0.0"}')"
mem_avail_mb="$(awk -v a="$mem_avail_kb" 'BEGIN{printf "%.1f", a/1024}')"

# Swap usage can indicate sustained memory pressure.
swap_total_mb="$(free -m | awk '/^Swap:/ {print $2+0}')"
swap_used_mb="$(free -m | awk '/^Swap:/ {print $3+0}')"
swap_used_pct="$(awk -v u="$swap_used_mb" -v t="$swap_total_mb" 'BEGIN{if(t>0) printf "%.1f", (u/t)*100; else print "0.0"}')"

# Parse vmstat by column name (safer than hardcoding field index like $16).
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

vmstat_snapshot="$(vmstat 1 2)"
iowait="$(parse_vmstat_metric wa "$vmstat_snapshot" || echo "N/A")"

echo "[CHECK] uptime/load"
uptime
echo "load1=$load1 nproc=$nproc_count load_per_core=$load_per_core"
echo

echo "[CHECK] memory/swap"
free -h
echo "mem_available_mb=${mem_avail_mb} mem_available_pct=${mem_avail_pct}%"
echo "swap_used_mb=$swap_used_mb swap_total_mb=$swap_total_mb swap_used_pct=${swap_used_pct}%"
echo

echo "[CHECK] top processes"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 8
ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 8
echo

echo "[CHECK] iowait"
echo "iowait=$iowait"

# Heuristics: practical defaults for early warning, not hard SLA limits.
if awk -v x="$load_per_core" 'BEGIN{exit !(x >= 1.50)}'; then
  echo "[WARN] high load per core: load_per_core=$load_per_core (threshold >=1.50)"
  warn=1
fi

if awk -v x="$mem_avail_pct" 'BEGIN{exit !(x < 10.0)}'; then
  echo "[WARN] low MemAvailable: mem_available_pct=${mem_avail_pct}% mem_available_mb=${mem_avail_mb} (threshold <10%)"
  warn=1
fi

if (( swap_used_mb > 512 )); then
  echo "[WARN] elevated swap usage: used=${swap_used_mb}MB (${swap_used_pct}%) (threshold >512MB)"
  warn=1
fi

if [[ "$iowait" != "N/A" ]] && awk -v x="$iowait" 'BEGIN{exit !(x >= 25)}'; then
  echo "[WARN] high iowait: wa=${iowait}% (threshold >=25%)"
  warn=1
fi

# Strict mode is useful for CI/cron alert hooks.
if (( STRICT && warn )); then
  echo "[FAIL] strict mode found performance pressure indicators" >&2
  exit 1
fi

echo "[OK] performance health check completed"
