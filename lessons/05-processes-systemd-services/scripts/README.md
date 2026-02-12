# Systemd Practice Scripts (Lesson 05)

This folder contains helper artifacts to reproduce the practical parts of lesson 05.

## Files

- `hello.sh`
  - payload script for journald logging with tag `hello`
- `units/hello.service`
- `units/hello.timer`
- `units/flaky.service`
- `setup-hello-timer.sh`
  - installs `hello.sh`, `hello.service`, `hello.timer`; reloads systemd; starts/enables timer
- `setup-flaky-service.sh`
  - installs and starts `flaky.service`; prints restart counters/logs
- `enable-persistent-journal.sh`
  - writes `/etc/systemd/journald.conf.d/persistent.conf` and restarts journald
- `cleanup-lab.sh`
  - removes lab artifacts and resets failed state

## Requirements

- `bash`
- `sudo`
- `systemd` tools: `systemctl`, `journalctl`
- `install` (coreutils)

## Usage

From repo root:

```bash
lessons/05-processes-systemd-services/scripts/setup-hello-timer.sh
lessons/05-processes-systemd-services/scripts/setup-flaky-service.sh
lessons/05-processes-systemd-services/scripts/enable-persistent-journal.sh
```

Cleanup:

```bash
lessons/05-processes-systemd-services/scripts/cleanup-lab.sh
# optional: also remove cron drop-in from the lesson
lessons/05-processes-systemd-services/scripts/cleanup-lab.sh --remove-cron-override
```

## Safety Notes

- These scripts write files to `/usr/local/bin` and `/etc/systemd/system`.
- Run them only on lab hosts where such changes are expected.
- Review script content before execution.
