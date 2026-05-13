#!/usr/bin/env bash
# =============================================================================
# Host HPM Upgrade
# Called by hpm_upgrade_test.sh — do not run directly
# Args: <FULL_CMD> <INTERACTIVE> <LOG_FILE>
# =============================================================================

FULL_CMD="$1"
INTERACTIVE="$2"
LOG_FILE="$3"

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
    export FULL_CMD LOG_FILE
    expect <<'EOF'
set timeout 300
log_file -a $env(LOG_FILE)
set cmd $env(FULL_CMD)

spawn bash -lc $cmd

expect {
    "Continue ignoring*" {
        send "y\r"
        exp_continue
    }
    "Services may be affected*" {
        send "y\r"
        exp_continue
    }
    timeout {
        puts "\n\[ERROR\] Timed out waiting for prompt or completion"
        exit 1
    }
    eof {
        catch wait result
        set rc [lindex $result 3]
        if {$rc != 0} {
            puts "\n\[ERROR\] Command exited with rc=$rc"
            exit $rc
        }
        puts "\n=== spv_ipmi process ended ==="
    }
}
EOF
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