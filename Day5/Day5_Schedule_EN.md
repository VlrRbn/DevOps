# Day5_Schedule_EN

# Day 5 — Processes & Services

**Date:** 25.08.2025

**Start:** 16:00

**Total duration:** ~6h

**Format:** theory → practice → mini-lab (service+timer) → logs/troubleshoot → (optional hard) → docs

---

## Warm-up

- `hostnamectl`
- `systemctl is-system-running`
- `systemctl list-units --type=service --state=running | head -20`

---

## Inspect a built-in service (cron)

- `systemctl status cron`
- `systemctl cat cron`
- `systemctl show -p FragmentPath,ActiveState,SubState,MainPID,ExecStart cron`
- Logs:
    - `journalctl -u cron --since "15 min ago" | tail -n 30`
    - `sudo systemctl restart cron && journalctl -u cron -n 10 --no-pager`

---

## Drop-in override (safe change)

Create `/etc/systemd/system/cron.service.d/override.conf`:

```
[Service]Environment=HELLO=world
```

Apply & verify:
- `sudo systemctl daemon-reload && sudo systemctl restart cron`
- `systemctl cat cron`
- `systemctl show -p Environment cron`

---

## Mini-lab: custom service + timer

Script:

```bash
sudo tee /usr/local/bin/hello.sh >/dev/null <<'SH'
#!/usr/bin/env 
bash echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
SH
sudo chmod +x /usr/local/bin/hello.sh
```

Service:

```
[Unit]
Description=Hello logger (oneshot)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/hello.sh
```

Timer:

```
[Unit]
Description=Run hello.service every 5 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=hello.service
[Install]
WantedBy=timers.target
```

Run & check:
- `sudo systemctl daemon-reload`
- `sudo systemctl start hello.service`
- `sudo systemctl enable --now hello.timer`
- `systemctl list-timers --all | grep hello`
- `journalctl -u hello.service -n 10 --no-pager`

---

## Journald deep-dive

- Filters: `-u`, `-p`, `-b`, `-f`, `-t`
- Examples:
    - `journalctl -t hello -n 5`
    - `journalctl -u hello.service -o short-precise -n 3`

---

## Troubleshoot playbook

- `systemctl status <unit>` → `journalctl -u <unit>` → `systemctl restart`
- If degraded: `systemctl --failed`, `systemd-analyze blame`

---

## Optional Hard

Auto-restart demo:

```
[Unit]
Description=Flaky demo (restarts on failure)
[Service]
Type=simple
ExecStart=/bin/bash -lc 'echo start; sleep 2; echo crash >&2; exit 1'
Restart=on-failure
RestartSec=3s
```

Then:
- `sudo systemctl daemon-reload && sudo systemctl start flaky`
- `systemctl show -p NRestarts,ExecMainStatus flaky`

Basic hardening (hello.service): `ProtectSystem=strict`, `PrivateTmp=yes`, `NoNewPrivileges=yes`.

---

## Docs & stash artifacts

Copy to repo:
- `tools/hello.sh`
- `labs/day5/hello.service`
- `labs/day5/hello.timer`
- `labs/day5/flaky.service`