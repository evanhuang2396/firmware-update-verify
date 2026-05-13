# Agent Reference — firmware-update-verify

This document provides context for AI coding agents working on this repository.

---

## Purpose

This repo is a **test harness** for verifying BMC firmware upgrades via IPMI HPM protocol.
It coordinates three concurrent tasks inside a `tmux` session:

1. **ipmid debug log** — captures BMC ipmid traffic during the upgrade
2. **journalctl log** — monitors firmware-related systemd services on the BMC
3. **HPM upgrade command** — executes the actual `spv_ipmi` command from the host

---

## Repository Layout

```
firmware-update-verify/
├── hpm_upgrade_test.sh          # Main entry point
├── host_hpm_upgrade.sh          # Runs spv_ipmi; waits for ipmid filter readiness
├── bmc_ipmid_log.sh             # SSH into BMC; sets up dbgutil filters; streams ipmid log
├── bmc_journal_log.sh           # SSH into BMC; follows journalctl for FW update services
├── hpm_upgrade_test.conf.example  # Config template (copy to .conf and edit)
└── logs/                        # Created at runtime; never committed
```

---

## Key Concepts

### Config file (`hpm_upgrade_test.conf`)
- Sourced by the main script at startup
- Not committed — derived from `hpm_upgrade_test.conf.example`
- Override path via `HPM_TEST_CONFIG` env variable

### Readiness synchronization
`bmc_ipmid_log.sh` touches `/tmp/hpm_test_ipmid_ready` after the BMC debug filters are applied.
`host_hpm_upgrade.sh` polls for this flag before launching the upgrade command.
This ensures ipmid output is captured from the very beginning of the upgrade.

### Interactive vs non-interactive mode
The main script inspects `TEST_CASE` for the substring `hpm upgrade`.
- If found → `INTERACTIVE=true` → `host_hpm_upgrade.sh` uses `expect` to auto-answer prompts
- Otherwise → plain `bash -lc` subprocess

### tmux session
Session name: `hpm_upgrade_test`
Layout (3 panes, single window):

```
┌─────────────────────────────────────────┐
│         Pane 0: ipmid log (40%)         │
├──────────────────┬──────────────────────┤
│ Pane 1: journal  │  Pane 2: Host hpm    │
│      (30%)       │       (30%)          │
└──────────────────┴──────────────────────┘
```

---

## Environment & Dependencies

| Tool | Purpose |
|------|---------|
| `tmux` | Multi-pane session |
| `sshpass` | Password SSH to BMC |
| `spv_ipmi` | IPMI HPM upgrade client (platform SDK tool) |
| `expect` | Interactive prompt handling for `hpm upgrade` |
| `dbgutil` | BMC-side tool for ipmid debug filter (runs on BMC via SSH) |

---

## Conventions

- All scripts use `#!/usr/bin/env bash` and `-o StrictHostKeyChecking=no -o ConnectTimeout=10` for SSH
- Logs are written to `logs/` and **never** committed (add to `.gitignore` if missing)
- `BMC_PASS_FILE` is a plain-text file — never hardcode credentials in scripts
- Relative paths in config are resolved against the script directory (`SCRIPT_DIR`)

---

## Common Modification Points

| Goal | Where to change |
|------|----------------|
| Add a new IPMI command filter | `bmc_ipmid_log.sh` — add `dbgutil filter add <N> <code> -s` |
| Follow additional systemd services | `bmc_journal_log.sh` — add `journalctl -f -u <service> &` |
| Add a new test case type | `hpm_upgrade_test.conf.example` — document new `TEST_CASE` pattern; update interactive detection in `hpm_upgrade_test.sh` if needed |
| Change log naming | `hpm_upgrade_test.sh` — `LOG_HOST`, `LOG_IPMID`, `LOG_JOURNAL` variables |
| Adjust expect timeout | `host_hpm_upgrade.sh` — `set timeout 300` |
| Add BMC process cleanup | `hpm_upgrade_test.sh` — `BMC_CLEANUP_PATTERNS` array |

---

## What NOT to do

- Do not run `host_hpm_upgrade.sh`, `bmc_ipmid_log.sh`, or `bmc_journal_log.sh` directly — they are called by `hpm_upgrade_test.sh` with specific arguments
- Do not commit `hpm_upgrade_test.conf` or `bmc_pass` (credentials)
- Do not commit the `logs/` directory
