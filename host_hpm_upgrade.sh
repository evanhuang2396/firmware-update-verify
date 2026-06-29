#!/usr/bin/env bash
# =============================================================================
# Host HPM Upgrade
# Called by hpm_upgrade_test.sh — do not run directly
# Args: <FULL_CMD> <INTERACTIVE> <LOG_FILE>
# =============================================================================

FULL_CMD="$1"
INTERACTIVE="$2"
LOG_FILE="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${FULL_CMD}" || -z "${INTERACTIVE}" || -z "${LOG_FILE}" ]]; then
    echo "[ERROR] Missing arguments" >&2
    exit 1
fi

READY_FLAG="/tmp/hpm_test_ipmid_ready"

: > "${LOG_FILE}"
echo "=== HPM Upgrade Start: $(date) ===" | tee -a "${LOG_FILE}"
echo "Interactive : ${INTERACTIVE}" | tee -a "${LOG_FILE}"
echo "Command     : ${FULL_CMD}" | tee -a "${LOG_FILE}"

# Wait for ipmid filter to be ready before starting upgrade
echo "=== Waiting for ipmid filter to be ready... ===" | tee -a "${LOG_FILE}"
while [[ ! -f "${READY_FLAG}" ]]; do
    sleep 1
done
echo "=== ipmid filter ready, starting HPM upgrade ===" | tee -a "${LOG_FILE}"

if [[ "${INTERACTIVE}" == "true" ]]; then
    uv run --with pexpect "${SCRIPT_DIR}/hpm_interact.py" "${FULL_CMD}" "${LOG_FILE}"
else
    bash -lc "${FULL_CMD}" 2>&1 | tee -a "${LOG_FILE}"
    cmd_rc=${PIPESTATUS[0]}
    if [[ ${cmd_rc} -ne 0 ]]; then
        echo "[ERROR] Command exited with rc=${cmd_rc}" | tee -a "${LOG_FILE}"
        exit ${cmd_rc}
    fi
fi

echo "=== HPM Upgrade End: $(date) ===" | tee -a "${LOG_FILE}"
echo ""
echo "=== HPM command finished. Review logs, then press Ctrl+C in outer terminal to stop. ==="