#!/usr/bin/env bash
# =============================================================================
# BMC journalctl Log Monitor
# Called by hpm_upgrade_test.sh — do not run directly
# Args: <BMC_IP> <BMC_USER> <BMC_PASS_FILE> <LOG_FILE> <BMC_SSH_PORT>
# =============================================================================

BMC_IP="$1"
BMC_USER="$2"
BMC_PASS_FILE="$3"
LOG_FILE="$4"
BMC_SSH_PORT="${5:-22}"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p ${BMC_SSH_PORT}"

if [[ -z "${BMC_IP}" || -z "${BMC_USER}" || -z "${BMC_PASS_FILE}" || -z "${LOG_FILE}" ]]; then
    echo "[ERROR] Missing arguments" >&2
    exit 1
fi

: > "${LOG_FILE}"
echo "=== journalctl log start: $(date) ===" | tee -a "${LOG_FILE}"
echo "BMC: ${BMC_USER}@${BMC_IP}" | tee -a "${LOG_FILE}"

sshpass -f "${BMC_PASS_FILE}" ssh ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" '
    START_TIME="$(date "+%Y-%m-%d %H:%M:%S")"
    echo "=== journalctl since: ${START_TIME} ==="
    journalctl --since "${START_TIME}" -f -u xyz.openbmc_project.Software.BMC.Updater &
    journalctl --since "${START_TIME}" -f -u xyz.openbmc_project.Software.Version &
    journalctl --since "${START_TIME}" -f -u xyz.openbmc_project.Software.Download &
    journalctl --since "${START_TIME}" -f -t fwupd &
    journalctl --since "${START_TIME}" -f -t sh &
    wait
' 2>&1 | tee -a "${LOG_FILE}"
