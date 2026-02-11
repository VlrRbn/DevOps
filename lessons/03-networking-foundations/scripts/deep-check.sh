#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage:
  deep-check.sh <output_dir>
  deep-check.sh [--hosts-test] <output_dir>

Description:
  Runs optional + advanced diagnostics from lesson 03:
  - resolvectl, curl -I, wget --spider
  - dig by record type and by specific resolvers
  - dig +trace
  - mtr snapshot

Flags:
  --hosts-test --- Temporarily add mytest.local to /etc/hosts and remove it.
USAGE
}

OUTPUT_DIR=""
HOSTS_TEST=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

for arg in "$@"; do
  case "$arg" in
    --hosts-test)
      HOSTS_TEST=1
      ;;
    -*)
    echo "ERROR: Unknown argument: $arg"
    usage
    exit 2
    ;;
    *)
      if [[ -z "$OUTPUT_DIR" ]]; then
         OUTPUT_DIR="$arg"
       else
         echo "ERROR: Multiple output directories specified: $OUTPUT_DIR and $arg"
         usage
         exit 2
       fi ;;
  esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "ERROR: <output_dir> is required"
  usage
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
timestamp="$(date +%Y%m%d_%H%M%S)"
run_dir="$OUTPUT_DIR/deep-check_$timestamp"
mkdir -p "$run_dir"

failures=0
skipped=0

has_cmd() {
  command -v "$1" >/dev/null 2>&1
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

if has_cmd resolvectl; then
  run_to_file "resolvectl_status" "$OUTPUT_DIR/dns_status.txt" resolvectl status
else
  printf "[SKIP] resolvectl is not installed\n"
  skipped=$((skipped + 1))
fi

if has_cmd curl; then
  run_cmd "curl_headers_google" curl -I https://google.com
else
  printf "[SKIP] curl is not installed\n"
  skipped=$((skipped + 1))
fi

if has_cmd wget; then
  run_cmd "wget_spider_example" wget --spider https://example.com
else
  printf "[SKIP] wget is not installed\n"
  skipped=$((skipped + 1))
fi

if has_cmd dig; then
  run_cmd "dig_a" dig google.com A
  run_cmd "dig_ns" dig google.com NS
  run_cmd "dig_mx" dig google.com MX
  run_cmd "dig_resolver_1_1_1_1" dig @1.1.1.1 google.com A
  run_cmd "dig_resolver_8_8_8_8" dig @8.8.8.8 google.com A
  run_cmd "dig_trace" dig +trace google.com
elif has_cmd nslookup; then
  run_cmd "nslookup_google_default" nslookup google.com
  run_cmd "nslookup_google_1_1_1_1" nslookup google.com 1.1.1.1
  run_cmd "nslookup_google_8_8_8_8" nslookup google.com 8.8.8.8
else
  printf "[SKIP] neither dig nor nslookup is installed\n"
  skipped=$((skipped + 1))
fi

if has_cmd mtr; then
  run_to_file "mtr_1_1_1_1" "$OUTPUT_DIR/mtr_1_1_1_1.txt" mtr -rw -c 10 1.1.1.1
else
  printf "[SKIP] mtr is not installed\n"
  skipped=$((skipped + 1))
fi

if [[ "$HOSTS_TEST" -eq 1 ]]; then
  if has_cmd sudo && has_cmd getent; then
    run_cmd "hosts_add" bash -lc "echo '1.2.3.4 mytest.local' | sudo tee -a /etc/hosts >/dev/null"
    run_cmd "hosts_check" getent hosts mytest.local
    run_cmd "hosts_remove" bash -lc "sudo sed -i -E '/(^|[[:space:]])mytest\\.local([[:space:]]|$)/d' /etc/hosts"
  else
    printf "[SKIP] hosts test needs sudo and getent\n"
    skipped=$((skipped + 1))
  fi
fi

echo
echo "Deep check completed."
echo "Output directory: $OUTPUT_DIR"
echo "Run logs: $run_dir"
echo "Failures: $failures"
echo "Skipped: $skipped"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

exit 0
