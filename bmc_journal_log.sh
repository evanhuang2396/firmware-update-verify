#!/usr/bin/env bash
# =============================================================================
# BMC journalctl Log Monitor
# Called by hpm_upgrade_test.sh — do not run directly
# Args: <BMC_IP> <BMC_USER> <BMC_PASS_FILE> <LOG_FILE>
# =============================================================================

BMC_IP="$1"
BMC_USER="$2"
BMC_PASS_FILE="$3"
LOG_FILE="$4"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [[ -z "${BMC_IP}" || -z "${BMC_USER}" || -z "${BMC_PASS_FILE}" || -z "${LOG_FILE}" ]]; then
    echo "[ERROR] Missing arguments" >&2
    exit 1
fi

: > "${LOG_FILE}"
echo "=== journalctl log start: $(date) ===" | tee -a "${LOG_FILE}"
echo "BMC: ${BMC_USER}@${BMC_IP}" | tee -a "${LOG_FILE}"

sshpass -f "${BMC_PASS_FILE}" ssh ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" '
    journalctl -f -u xyz.openbmc_project.Software.BMC.Updater &
    journalctl -f -u xyz.openbmc_project.Software.Version &
    journalctl -f -u xyz.openbmc_project.Software.Download &
    journalctl -f | grep fwupd &
    wait
' 2>&1 | sed -u -e 's/\r$//' -e '/^[[:space:]]*$/d' | tee -a "${LOG_FILE}"
