#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage:
  core-check.sh <output_dir>

Description:
  Runs the minimal networking diagnostics flow from lesson 03:
  - ip -br addr
  - ip route
  - ping to 1.1.1.1
  - ping to google.com
  - traceroute to 1.1.1.1
  - DNS lookup (dig +short or nslookup fallback)

Examples:
  ./lessons/03-networking-foundations/scripts/core-check.sh /tmp/net-lab
  ./lessons/03-networking-foundations/scripts/core-check.sh "$HOME/net-lab"
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "ERROR: <output_dir> is required"
  usage
  exit 2
fi

OUTPUT_DIR="$1"

mkdir -p "$OUTPUT_DIR"
timestamp="$(date +%Y%m%d_%H%M%S)"
run_dir="$OUTPUT_DIR/core-check_$timestamp"
mkdir -p "$run_dir"

failures=0
skipped=0

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

mark_missing() {
  local cmd="$1"
  printf "[MISS] %s is not installed\n" "$cmd"
  failures=$((failures + 1))
}

run_cmd() {
  local name="$1"
  shift
  local out="$run_dir/${name}.out"
  local err="$run_dir/${name}.err"

  printf "[RUN ] %s\n" "$name"
  if "$@" >"$out" 2>"$err"; then
    printf "[ OK ] %s\n" "$name"
  else
    local code=$?
    printf "[FAIL] %s (exit %s)\n" "$name" "$code"
    failures=$((failures + 1))
  fi
}

run_to_file() {
  local name="$1"
  local file="$2"
  shift 2
  local out="$run_dir/${name}.out"
  local err="$run_dir/${name}.err"

  printf "[RUN ] %s -> %s\n" "$name" "$file"
  if "$@" >"$out" 2>"$err"; then
    cp "$out" "$file"
    printf "[ OK ] %s\n" "$name"
  else
    local code=$?
    printf "[FAIL] %s (exit %s)\n" "$name" "$code"
    failures=$((failures + 1))
  fi
}

if has_cmd ip; then
  run_to_file "ip_addr" "$OUTPUT_DIR/ip_addr.txt" ip -br addr
  run_to_file "ip_route" "$OUTPUT_DIR/ip_route.txt" ip route
else
  mark_missing "ip"
fi

if has_cmd ping; then
  run_cmd "ping_1_1_1_1" ping -c 4 1.1.1.1
  run_cmd "ping_google_com" ping -c 4 google.com
else
  mark_missing "ping"
fi

if has_cmd traceroute; then
  run_cmd "traceroute_1_1_1_1" traceroute -n 1.1.1.1
else
  mark_missing "traceroute"
fi

if has_cmd dig; then
  run_to_file "dns_lookup" "$OUTPUT_DIR/dns_lookup.txt" dig +short google.com
elif has_cmd nslookup; then
  run_to_file "dns_lookup" "$OUTPUT_DIR/dns_lookup.txt" nslookup google.com
else
  printf "[SKIP] neither dig nor nslookup is installed\n"
  skipped=$((skipped + 1))
fi

echo
echo "Core check completed."
echo "Output directory: $OUTPUT_DIR"
echo "Run logs: $run_dir"
echo "Failures: $failures"
echo "Skipped: $skipped"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

exit 0
