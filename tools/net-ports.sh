#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 [--listen] [--established] [--port N] [--process NAME]"; }

listen=0; estab=0; port=""; proc=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --listen)      listen=1; shift;;
    --established) estab=1;  shift;;
    --port)        port="${2:?port number required}"; shift 2;;
    --process)     proc="${2:?process name required}"; shift 2;;
    *) usage; exit 1;;
  esac
done

# Команда как массив, а не одна строка
cmd=(sudo ss -tulpn)

# Фильтры для ss
args=(-H) # no header

# Если пользователь запросил оба состояния — убираем фильтр по state, чтобы показать всё
if (( listen && ! estab )); then
  args+=('state' 'listening')
elif (( estab && ! listen )); then
  args+=('state' 'established')
fi

# Фильтр по порту (sport/dport)
if [[ -n "$port" ]]; then
  args+=('( sport = :'"$port"' or dport = :'"$port"' )')
fi

# Если только -H — убираем его вовсе (по умолчанию показываем заголовок)
if [[ ${#args[@]} -eq 1 ]]; then
  args=()
fi

# Запуск и фильтр по процессу (без падения, если совпадений нет)
"${cmd[@]}" "${args[@]}" | {
  if [[ -n "$proc" ]]; then
    grep -i -- "$proc" || true
  else
    cat
  fi
}
