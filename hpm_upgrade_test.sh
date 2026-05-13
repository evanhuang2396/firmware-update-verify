#!/usr/bin/env bash
# =============================================================================
# HPM Upgrade Test - Main Script
# Usage: ./hpm_upgrade_test.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE_DEFAULT="${SCRIPT_DIR}/hpm_upgrade_test.conf"
CONFIG_FILE="${HPM_TEST_CONFIG:-${CONFIG_FILE_DEFAULT}}"

# -----------------------------------------------------------------------------
# [USER CONFIG]
# -----------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "[ERROR] Config file not found: ${CONFIG_FILE}" >&2
    echo "[INFO]  Copy ${SCRIPT_DIR}/hpm_upgrade_test.conf.example -> ${SCRIPT_DIR}/hpm_upgrade_test.conf and update values." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

if [[ -z "${BMC_IP:-}" || -z "${BMC_USER:-}" || -z "${BMC_PASS_FILE:-}" || -z "${TEST_CASE:-}" ]]; then
    echo "[ERROR] Missing required config values in ${CONFIG_FILE}" >&2
    echo "[INFO]  Required: BMC_IP, BMC_USER, BMC_PASS_FILE, TEST_CASE" >&2
    exit 1
fi

if [[ "${BMC_PASS_FILE}" != /* ]]; then
    BMC_PASS_FILE="${SCRIPT_DIR}/${BMC_PASS_FILE#./}"
fi
if [[ -n "${FW_FILE:-}" && "${FW_FILE}" != /* ]]; then
    FW_FILE="${SCRIPT_DIR}/${FW_FILE#./}"
fi
if [[ -n "${HPM_FILE:-}" && "${HPM_FILE}" != /* ]]; then
    HPM_FILE="${SCRIPT_DIR}/${HPM_FILE#./}"
fi

if [[ ! -f "${BMC_PASS_FILE}" ]]; then
    echo "[ERROR] BMC password file not found: ${BMC_PASS_FILE}" >&2
    exit 1
fi
BMC_PASS="$(< "${BMC_PASS_FILE}")"

eval "FULL_CMD=\"${TEST_CASE}\""

if [[ "${FULL_CMD}" == *"hpm upgrade"* ]]; then
    INTERACTIVE="true"
else
    INTERACTIVE="false"
fi

# -----------------------------------------------------------------------------
# [CONSTANTS]
# -----------------------------------------------------------------------------
SESSION="hpm_upgrade_test"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_HOST="${LOG_DIR}/host_hpm${LOG_SUFFIX}.log"
LOG_IPMID="${LOG_DIR}/bmc_ipmid${LOG_SUFFIX}.log"
LOG_JOURNAL="${LOG_DIR}/bmc_journal${LOG_SUFFIX}.log"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
READY_FLAG="/tmp/hpm_test_ipmid_ready"
BMC_CLEANUP_PATTERNS=("dbgutil" "journalctl.*Updater" "journalctl.*Version" "journalctl.*Download" "journalctl.*fwupd")

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log_info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

check_dependencies() {
    local missing=()
    for cmd in tmux sshpass ssh spv_ipmi; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ "${INTERACTIVE}" == "true" ]] && ! command -v expect &>/dev/null; then
        missing+=("expect")
    fi
    [[ ${#missing[@]} -gt 0 ]] && { log_error "Missing: ${missing[*]}"; exit 1; }
}

check_files() {
    [[ ! -f "${SCRIPT_DIR}/bmc_ipmid_log.sh" ]]     && { log_error "bmc_ipmid_log.sh not found"; exit 1; }
    [[ ! -f "${SCRIPT_DIR}/bmc_journal_log.sh" ]]    && { log_error "bmc_journal_log.sh not found"; exit 1; }
    [[ ! -f "${SCRIPT_DIR}/host_hpm_upgrade.sh" ]]   && { log_error "host_hpm_upgrade.sh not found"; exit 1; }
}

check_bmc_connection() {
    log_info "Checking BMC SSH connection to ${BMC_IP}..."
    if ! sshpass -f "${BMC_PASS_FILE}" ssh ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" "echo ok" &>/dev/null; then
        log_error "Cannot connect to BMC at ${BMC_IP}"
        exit 1
    fi
    log_info "BMC connection OK"
}

cleanup_bmc_processes() {
    log_info "Cleaning up residual BMC processes..."
    local cmds=""
    for p in "${BMC_CLEANUP_PATTERNS[@]}"; do
        cmds+="pkill -f '${p}' 2>/dev/null; "
    done
    sshpass -f "${BMC_PASS_FILE}" ssh ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" "${cmds} true" || true
    sleep 1
    log_info "BMC cleanup done"
}

cleanup_and_exit() {
    echo ""
    log_warn "Stopping test..."

    if tmux has-session -t "${SESSION}" 2>/dev/null; then
        tmux kill-session -t "${SESSION}"
        log_info "tmux session '${SESSION}' killed"
    fi

    cleanup_bmc_processes
    rm -f "${READY_FLAG}"

    echo ""
    log_info "Logs saved:"
    log_info "  Host    → ${LOG_HOST}"
    log_info "  ipmid   → ${LOG_IPMID}"
    log_info "  journal → ${LOG_JOURNAL}"
    exit 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    trap cleanup_and_exit INT TERM

    echo ""
    log_info "==============================="
    log_info " HPM Upgrade Test"
    log_info " Timestamp : ${TIMESTAMP}"
    log_info " BMC IP      : ${BMC_IP}"
    log_info " Interactive : ${INTERACTIVE}"
    log_info " Command     : ${FULL_CMD}"
    log_info "==============================="
    echo ""

    check_dependencies
    check_files
    check_bmc_connection
    mkdir -p "${LOG_DIR}"

    # Kill old session if exists
    if tmux has-session -t "${SESSION}" 2>/dev/null; then
        log_warn "Existing tmux session '${SESSION}' found, killing..."
        tmux kill-session -t "${SESSION}"
        sleep 1
    fi

    # Clean leftover BMC processes and ready flag from previous run
    cleanup_bmc_processes
    rm -f "${READY_FLAG}"

    # ---------------------------------------------------------------------------
    # Build tmux layout
    #
    #   ┌─────────────────────────────────────────┐
    #   │         Pane 0: ipmid log (40%)         │
    #   ├──────────────────┬──────────────────────┤
    #   │ Pane 1: journal  │  Pane 2: Host hpm    │
    #   │      (30%)       │       (30%)          │
    #   └──────────────────┴──────────────────────┘
    # ---------------------------------------------------------------------------
    tmux new-session  -d -s "${SESSION}" -x "$(tput cols)" -y "$(tput lines)"
    tmux split-window -v -p 60 -t "${SESSION}:0.0"
    tmux split-window -h -p 50 -t "${SESSION}:0.1"

    # Pane titles (tmux >= 3.0)
    tmux select-pane -t "${SESSION}:0.0" -T "ipmid log"
    tmux select-pane -t "${SESSION}:0.1" -T "journalctl log"
    tmux select-pane -t "${SESSION}:0.2" -T "Host: hpm upgrade"

    # Pane 0: ipmid log
    tmux send-keys -t "${SESSION}:0.0" \
        "bash '${SCRIPT_DIR}/bmc_ipmid_log.sh' '${BMC_IP}' '${BMC_USER}' '${BMC_PASS_FILE}' '${LOG_IPMID}'" Enter

    sleep 0.5

    # Pane 1: journalctl log
    tmux send-keys -t "${SESSION}:0.1" \
        "bash '${SCRIPT_DIR}/bmc_journal_log.sh' '${BMC_IP}' '${BMC_USER}' '${BMC_PASS_FILE}' '${LOG_JOURNAL}'" Enter

    sleep 0.5

    # Pane 2: host command runner (interactive mode auto-detected from command)
    tmux send-keys -t "${SESSION}:0.2" \
        "bash '${SCRIPT_DIR}/host_hpm_upgrade.sh' \"${FULL_CMD}\" '${INTERACTIVE}' '${LOG_HOST}'" Enter

    # Focus host pane
    tmux select-pane -t "${SESSION}:0.2"

    log_info "Attaching to tmux session '${SESSION}'..."
    log_info "Press Ctrl+C in THIS terminal to stop and clean up."
    sleep 1

    tmux attach-session -t "${SESSION}"

    # Reached only if all panes exit naturally
    cleanup_and_exit
}

main "$@"