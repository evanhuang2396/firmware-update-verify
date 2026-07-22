#!/usr/bin/env bash
# =============================================================================
# BMC ipmid Log Monitor
# Called by hpm_upgrade_test.sh — do not run directly
# Args: <BMC_IP> <BMC_USER> <BMC_PASS_FILE> <LOG_FILE> <BMC_SSH_PORT>
# =============================================================================

BMC_IP="$1"
BMC_USER="$2"
BMC_PASS_FILE="$3"
LOG_FILE="$4"
BMC_SSH_PORT="${5:-22}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p ${BMC_SSH_PORT}"

if [[ -z "${BMC_IP}" || -z "${BMC_USER}" || -z "${BMC_PASS_FILE}" || -z "${LOG_FILE}" ]]; then
    echo "[ERROR] Missing arguments" >&2
    exit 1
fi

: > "${LOG_FILE}"
echo "=== ipmid log start: $(date) ===" | tee -a "${LOG_FILE}"
echo "BMC: ${BMC_USER}@${BMC_IP}" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

READY_FLAG="/tmp/hpm_test_ipmid_ready"
rm -f "${READY_FLAG}"

# Single SSH session: restart + filter add + filter start
# Run in background so we can touch ready flag after filters are set
sshpass -f "${BMC_PASS_FILE}" ssh -t ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" '
    TTY_PATH=$(tty)
    dbgutil restart -p $TTY_PATH -l 1 -k 1
    dbgutil filter add 1 64 -s
    dbgutil filter add 2 1 -s
    dbgutil filter add 3 123 -s
    dbgutil filter add 4 82 -s
    dbgutil filter start -t 0x1 -f 8
    sleep infinity
' 2>&1 | tee -a "${LOG_FILE}" &

SSH_PID=$!

# Give filters time to apply, then signal HPM upgrade to proceed
sleep 3
touch "${READY_FLAG}"
echo "=== ipmid filter ready, HPM upgrade may proceed ===" | tee -a "${LOG_FILE}"

wait "${SSH_PID}"