#!/usr/bin/env bash
set -Eeuo pipefail

usage(){ echo "Usage: $0 {save|restore|validate|flush|flush-nat|show|diff} [-y]"; exit 1; }

cmd="${1:-}"; shift || true
assume_yes="${1:-}"

case "$cmd" in
  save)
    ts="$(date +%F_%H%M%S)"
    sudo cp -a /etc/nftables.conf "/etc/nftables.conf.bak.$ts" 2>/dev/null || true
    sudo nft list ruleset | sudo tee /etc/nftables.conf >/dev/null
    sudo nft -c -f /etc/nftables.conf     # Checking the configuration for syntax
    sudo systemctl enable --now nftables
    echo "Saved live ruleset to /etc/nftables.conf (+enabled nftables). Backup: /etc/nftables.conf.bak.$ts"
    ;;

  restore)
    sudo nft -c -f /etc/nftables.conf
    sudo nft -f /etc/nftables.conf        # Apply what is in /etc/nftables.conf
    echo "Restored ruleset from /etc/nftables.conf"
    ;;

  validate)
    sudo nft -c -f /etc/nftables.conf
    echo "Config is syntactically valid."
    ;;

  flush)
    if [[ "$assume_yes" != "-y" ]]; then
      read -r -p "This will FLUSH ALL nftables rules (firewall off). Continue? [y/N] " a
      [[ "$a" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
    fi
    sudo nft flush ruleset
    echo "Flushed entire ruleset."
    ;;

  flush-nat)
  # Safer: only remove the NAT table without touching filter/raw
    sudo nft delete table ip nat 2>/dev/null || true
    echo "Deleted table ip nat (filter/raw untouched)."
    ;;

  show)
    sudo nft list ruleset
    ;;

  diff)
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    sudo nft list ruleset > "$tmp"
  # Show the difference between the live ruleset and the one in /etc/nftables.conf
    sudo diff -u "$tmp" /etc/nftables.conf || true
    ;;

  *) usage ;;
esac