# firmware-update-verify

A test harness for verifying BMC firmware upgrades via IPMI HPM protocol. It opens a **tmux** session with three synchronized panes — ipmid debug log, journalctl log, and the HPM upgrade command — so you can observe the entire update process in real time.

---

## Overview

```
┌─────────────────────────────────────────┐
│         Pane 0: ipmid log (40%)         │
├──────────────────┬──────────────────────┤
│ Pane 1: journal  │  Pane 2: Host hpm    │
│      (30%)       │       (30%)          │
└──────────────────┴──────────────────────┘
```

| Pane | Script | Purpose |
|------|--------|---------|
| 0 | `bmc_ipmid_log.sh` | Streams BMC `ipmid` debug output filtered by IPMI command codes |
| 1 | `bmc_journal_log.sh` | Streams `journalctl` for firmware-related systemd services |
| 2 | `host_hpm_upgrade.sh` | Runs the `spv_ipmi` / ISC upgrade command |

---

## Prerequisites

| Tool | Required for |
|------|-------------|
| `tmux` | Multi-pane session |
| `sshpass` | Password-based SSH to BMC |
| `ssh` | Remote access to BMC |
| `spv_ipmi` | IPMI HPM upgrade command |
| `expect` | Interactive mode (`hpm upgrade` only) |

Install on Ubuntu/Debian:
```bash
sudo apt install tmux sshpass expect
# spv_ipmi must be installed separately per your platform SDK
```

---

## Quick Start

### 1. Create a project config file

```bash
mkdir -p conf/venice_2_18
cp hpm_upgrade_test.conf.example conf/venice_2_18/hpm_upgrade_test.conf
```

Edit `conf/venice_2_18/hpm_upgrade_test.conf`:

```bash
PROJECT_NAME="venice_2_18"
BMC_IP="192.168.10.252"
BMC_USER="root"
BMC_PASS_FILE="${SCRIPT_DIR}/bmc_pass"          # plain-text file containing the BMC password
FW_FILE="${SCRIPT_DIR}/image/image-update-ast2600.hpm"

# Pick one test case:
TEST_CASE='spv_ipmi -U root -P ${BMC_PASS} -H ${BMC_IP} -I lanplus -C 17 -z 30000 -N 10 hpm upgrade ${FW_FILE} force activate'
```

### 2. Create the password file

```bash
echo 'your_bmc_password' > bmc_pass
chmod 600 bmc_pass
```

### 3. Run

```bash
./hpm_upgrade_test.sh --project venice_2_18
```

`--project` has higher priority than `PROJECT_NAME` inside the config file.

Press **Ctrl+C** in the launching terminal to stop the test and clean up.

Backward-compatible mode is still supported:

```bash
cp hpm_upgrade_test.conf.example hpm_upgrade_test.conf
./hpm_upgrade_test.sh
```

---

## Configuration Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `BMC_IP` | ✅ | BMC IP address |
| `BMC_USER` | ✅ | BMC SSH/IPMI username |
| `PROJECT_NAME` | ❌ | Project/platform label used for log grouping |
| `BMC_PASS_FILE` | ✅ | Path to a file containing the BMC password |
| `TEST_CASE` | ✅ | The `spv_ipmi` command template to execute |
| `FW_FILE` | Depends on `TEST_CASE` | Path to `.hpm` firmware file for `hpm upgrade` |
| `HPM_FILE` | Depends on `TEST_CASE` | Path to `.hpm` firmware file for ISC commands |
| `LOG_SUFFIX` | ❌ | Optional suffix appended to log filenames (e.g. `_round1`) |

Relative paths for `BMC_PASS_FILE`, `FW_FILE`, and `HPM_FILE` are resolved relative to the script directory.

You can also override the config file path via the environment variable:
```bash
HPM_TEST_CONFIG=/path/to/custom.conf ./hpm_upgrade_test.sh
```

Or select a project directly:

```bash
./hpm_upgrade_test.sh --project venice_2_18
```

The project mode resolves the config file from:

```bash
conf/<project>/hpm_upgrade_test.conf
```

Priority order for project selection is:

```bash
--project > HPM_TEST_PROJECT > PROJECT_NAME > PLATFORM_NAME > conf/<project>/... path
```

---

## Supported Test Cases

```bash
# Full HPM firmware update (interactive — uses expect)
TEST_CASE='spv_ipmi -U root -P ${BMC_PASS} -H ${BMC_IP} -I lanplus -C 17 -z 30000 -N 10 hpm upgrade ${FW_FILE} force activate'

# ISC BMC update (non-interactive)
TEST_CASE='spv_ipmi -U root -P ${BMC_PASS} -H ${BMC_IP} -I lanplus -C 17 -N 10 isc bmc update ${HPM_FILE}'

# ISC BIOS update (non-interactive)
TEST_CASE='spv_ipmi -U root -P ${BMC_PASS} -H ${BMC_IP} -I lanplus -C 17 -N 10 isc bios update ${HPM_FILE}'

# ISC PLD update (non-interactive)
TEST_CASE='spv_ipmi -U root -P ${BMC_PASS} -H ${BMC_IP} -I lanplus -C 17 -N 10 isc pld update ${HPM_FILE}'
```

Commands containing `hpm upgrade` are automatically treated as **interactive** (handled by `expect`). All others run as plain bash subprocesses.

---

## Logs

When `PROJECT_NAME` or `--project` is used, logs are saved under a per-project run directory:

```bash
logs/<project>/<timestamp>/
```

Example:

```bash
logs/venice_2_18/20260513_103012/
```

The generated files are:

| File | Contents |
|------|----------|
| `host_hpm[SUFFIX].log` | Output of the HPM upgrade command |
| `bmc_ipmid[SUFFIX].log` | BMC ipmid debug output |
| `bmc_journal[SUFFIX].log` | BMC journalctl output |

Use `LOG_SUFFIX` in the config to distinguish multiple test runs.

If you run the legacy root config without `PROJECT_NAME`, logs continue to be written to `logs/` for compatibility.

---

## File Reference

| File | Description |
|------|-------------|
| `hpm_upgrade_test.sh` | Main entry point — validates config, builds tmux layout, orchestrates all panes |
| `host_hpm_upgrade.sh` | Waits for BMC ipmid filter to be ready, then runs the upgrade command |
| `bmc_ipmid_log.sh` | SSH into BMC, restarts ipmid with debug filters, streams output |
| `bmc_journal_log.sh` | SSH into BMC, follows journalctl for firmware update services |
| `hpm_upgrade_test.conf.example` | Template configuration file |

---

## License

See [LICENSE](LICENSE).
