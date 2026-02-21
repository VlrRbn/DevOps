#!/usr/bin/env bash
# Description: Collect focused boot diagnostics (journal/failed-units/dmesg/findmnt verify).
# Usage: boot-triage.sh [--boot N] [--since STR] [--save-dir DIR] [--strict]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  boot-triage.sh [--boot N] [--since STR] [--save-dir DIR] [--strict]

Defaults:
  --boot 0 (current boot)

Examples:
  ./lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh
  ./lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot -1 --strict
  ./lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --since "-2h" --save-dir /tmp/lesson13-reports
USAGE
}

BOOT_ID="0"
SINCE=""
SAVE_DIR=""
STRICT=0

# Parse supported flags.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --boot)
      [[ $# -ge 2 ]] || { echo "ERROR: --boot requires value" >&2; exit 2; }
      BOOT_ID="$2"
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
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate baseline tooling once.
for cmd in journalctl systemctl findmnt df hostname uname date; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

SUDO_CMD=()
# Use passwordless sudo when available; fallback to non-sudo path otherwise.
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  SUDO_CMD=(sudo -n)
fi

# Gather baseline health signals.
run_state="$(systemctl is-system-running 2>/dev/null || echo unknown)"
failed_count="$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk 'NF{c++} END{print c+0}')"

findmnt_rc=0
findmnt_out=""
if ! findmnt_out="$(findmnt --verify 2>&1)"; then
  findmnt_rc=$?
fi

journal_args=(-b "$BOOT_ID" -p err..alert --no-pager)
# Optional time window helps focus incidents with noisy journals.
if [[ -n "$SINCE" ]]; then
  journal_args+=(--since "$SINCE")
fi

journal_rc=0
journal_out=""
if ! journal_out="$(journalctl "${journal_args[@]}" 2>&1 | sed -n '1,120p')"; then
  journal_rc=$?
fi

# dmesg may require elevated privileges on hardened hosts.
dmesg_rc=0
dmesg_out=""
if ((${#SUDO_CMD[@]} > 0)); then
  if ! dmesg_out="$("${SUDO_CMD[@]}" dmesg --level=err,warn 2>&1 | tail -n 80)"; then
    dmesg_rc=$?
  fi
else
  if ! dmesg_out="$(dmesg --level=err,warn 2>&1 | tail -n 80)"; then
    dmesg_rc=$?
  fi
fi

strict_fail=0
# Strict mode fails on degraded system state, failed units, or broken fstab/mount metadata.
if [[ "$run_state" == "degraded" || "$run_state" == "maintenance" || "$run_state" == "offline" ]]; then
  strict_fail=1
fi
if (( failed_count > 0 )); then
  strict_fail=1
fi
if (( findmnt_rc != 0 )); then
  strict_fail=1
fi

# Render one consolidated report block for terminal and file output.
render_report() {
  echo "[INFO] boot triage report"
  echo "[INFO] generated: $(date '+%F %T')"
  echo "[INFO] host: $(hostname)"
  echo "[INFO] kernel: $(uname -r)"
  echo "[INFO] boot: $BOOT_ID"
  [[ -n "$SINCE" ]] && echo "[INFO] since: $SINCE"
  echo

  echo "[CHECK] system run state"
  echo "state=$run_state"
  echo

  echo "[CHECK] failed units count"
  echo "failed_units=$failed_count"
  systemctl list-units --failed --no-pager --plain || true
  echo

  echo "[CHECK] findmnt --verify"
  echo "rc=$findmnt_rc"
  printf '%s\n' "$findmnt_out"
  echo

  echo "[CHECK] journalctl err..alert (first 120 lines)"
  echo "rc=$journal_rc"
  printf '%s\n' "$journal_out"
  echo

  echo "[CHECK] dmesg err,warn (last 80 lines)"
  echo "rc=$dmesg_rc"
  printf '%s\n' "$dmesg_out"
  echo

  echo "[CHECK] rootfs usage"
  df -h /
}

# Save report to file when requested, otherwise print only to stdout.
if [[ -n "$SAVE_DIR" ]]; then
  mkdir -p "$SAVE_DIR"
  REPORT="$SAVE_DIR/boot-triage_$(date +%Y%m%d_%H%M%S).txt"
  render_report | tee "$REPORT"
  echo "[INFO] saved report: $REPORT"
else
  render_report
fi

if (( STRICT && strict_fail )); then
  echo "[FAIL] strict mode detected boot-health issues" >&2
  exit 1
fi

echo "[OK] boot triage completed"
