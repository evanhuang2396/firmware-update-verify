#!/usr/bin/env bash
# =============================================================================
# HPM Upgrade Test - Main Script
# Usage: ./hpm_upgrade_test.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASENAME="hpm_upgrade_test.conf"
CONFIG_ROOT_DIR="${SCRIPT_DIR}/conf"
CONFIG_FILE_DEFAULT="${SCRIPT_DIR}/${CONFIG_BASENAME}"
CONFIG_FILE="${HPM_TEST_CONFIG:-}"
REQUESTED_PROJECT_NAME="${HPM_TEST_PROJECT:-}"
PATH_PROJECT_NAME=""
CONFIG_PROJECT_NAME=""
PROJECT_NAME=""

usage() {
    cat <<EOF
Usage: $0 [--project <name>] [--help]

Options:
  --project <name>  Load config from conf/<name>/hpm_upgrade_test.conf
  --help            Show this help message

Environment:
  HPM_TEST_PROJECT  Default project name when --project is not provided
  HPM_TEST_CONFIG   Explicit config path override
EOF
}

validate_project_name() {
    local project_name="$1"

    [[ -z "${project_name}" ]] && return 0

    if [[ ! "${project_name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "[ERROR] Invalid project name: ${project_name}" >&2
        echo "[INFO]  Allowed characters: letters, numbers, dot, underscore, hyphen" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            [[ $# -lt 2 ]] && {
                echo "[ERROR] Missing value for --project" >&2
                usage >&2
                exit 1
            }
            REQUESTED_PROJECT_NAME="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

validate_project_name "${REQUESTED_PROJECT_NAME}"

if [[ -z "${CONFIG_FILE}" ]]; then
    if [[ -n "${REQUESTED_PROJECT_NAME}" ]]; then
        CONFIG_FILE="${CONFIG_ROOT_DIR}/${REQUESTED_PROJECT_NAME}/${CONFIG_BASENAME}"
    else
        CONFIG_FILE="${CONFIG_FILE_DEFAULT}"
    fi
fi

CONFIG_DIR="$(cd "$(dirname "${CONFIG_FILE}")" 2>/dev/null && pwd)"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log_info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

# -----------------------------------------------------------------------------
# [USER CONFIG]
# -----------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "[ERROR] Config file not found: ${CONFIG_FILE}" >&2
    if [[ -n "${REQUESTED_PROJECT_NAME}" ]]; then
        echo "[INFO]  Create ${CONFIG_ROOT_DIR}/${REQUESTED_PROJECT_NAME}/${CONFIG_BASENAME} from ${SCRIPT_DIR}/hpm_upgrade_test.conf.example." >&2
    else
        echo "[INFO]  Copy ${SCRIPT_DIR}/hpm_upgrade_test.conf.example -> ${SCRIPT_DIR}/hpm_upgrade_test.conf and update values." >&2
    fi
    exit 1
fi

CONFIG_DIR="$(cd "$(dirname "${CONFIG_FILE}")" && pwd)"

if [[ "${CONFIG_FILE}" == "${CONFIG_ROOT_DIR}/"*"/${CONFIG_BASENAME}" ]]; then
    PATH_PROJECT_NAME="${CONFIG_FILE#${CONFIG_ROOT_DIR}/}"
    PATH_PROJECT_NAME="${PATH_PROJECT_NAME%/${CONFIG_BASENAME}}"
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

CONFIG_PROJECT_NAME="${PROJECT_NAME:-}"
CONFIG_PROJECT_NAME="${CONFIG_PROJECT_NAME:-${PROJECT:-}}"
CONFIG_PROJECT_NAME="${CONFIG_PROJECT_NAME:-${PLATFORM_NAME:-}}"
PROJECT_NAME="${REQUESTED_PROJECT_NAME:-${CONFIG_PROJECT_NAME:-${PATH_PROJECT_NAME}}}"
validate_project_name "${PROJECT_NAME}"

if [[ -z "${BMC_IP:-}" || -z "${BMC_USER:-}" || -z "${BMC_PASS_FILE:-}" || -z "${TEST_CASE:-}" ]]; then
    echo "[ERROR] Missing required config values in ${CONFIG_FILE}" >&2
    echo "[INFO]  Required: BMC_IP, BMC_USER, BMC_PASS_FILE, TEST_CASE" >&2
    exit 1
fi

BMC_SSH_PORT="${BMC_SSH_PORT:-22}"

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

if [[ "${TEST_CASE}" == *'${FW_FILE}'* && -z "${FW_FILE:-}" ]]; then
    log_error "TEST_CASE references \${FW_FILE} but FW_FILE is not set in ${CONFIG_FILE}"
    exit 1
fi
if [[ "${TEST_CASE}" == *'${HPM_FILE}'* && -z "${HPM_FILE:-}" ]]; then
    log_error "TEST_CASE references \${HPM_FILE} but HPM_FILE is not set in ${CONFIG_FILE}"
    exit 1
fi

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
if [[ -n "${PROJECT_NAME}" ]]; then
    LOG_DIR="${SCRIPT_DIR}/logs/${PROJECT_NAME}/${TIMESTAMP}"
else
    LOG_DIR="${SCRIPT_DIR}/logs"
fi
LOG_HOST="${LOG_DIR}/host_hpm${LOG_SUFFIX}.log"
LOG_IPMID="${LOG_DIR}/bmc_ipmid${LOG_SUFFIX}.log"
LOG_JOURNAL="${LOG_DIR}/bmc_journal${LOG_SUFFIX}.log"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p ${BMC_SSH_PORT}"
READY_FLAG="/tmp/hpm_test_ipmid_ready"
BMC_CLEANUP_PATTERNS=("dbgutil" "journalctl.*Updater" "journalctl.*Version" "journalctl.*Download" "journalctl.*fwupd")

check_dependencies() {
    local missing=()
    for cmd in tmux sshpass ssh; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ "${INTERACTIVE}" == "true" ]] && ! command -v uv &>/dev/null; then
        missing+=("uv")
    fi
    [[ ${#missing[@]} -gt 0 ]] && { log_error "Missing: ${missing[*]}"; exit 1; }
}

check_files() {
    [[ ! -f "${SCRIPT_DIR}/bmc_ipmid_log.sh" ]]     && { log_error "bmc_ipmid_log.sh not found"; exit 1; }
    [[ ! -f "${SCRIPT_DIR}/bmc_journal_log.sh" ]]    && { log_error "bmc_journal_log.sh not found"; exit 1; }
    [[ ! -f "${SCRIPT_DIR}/host_hpm_upgrade.sh" ]]   && { log_error "host_hpm_upgrade.sh not found"; exit 1; }
}

check_bmc_connection() {
    log_info "Checking BMC SSH connection to ${BMC_IP}:${BMC_SSH_PORT}..."
    if ! sshpass -f "${BMC_PASS_FILE}" ssh ${SSH_OPTS} "${BMC_USER}@${BMC_IP}" "echo ok" &>/dev/null; then
        log_error "Cannot connect to BMC at ${BMC_IP}:${BMC_SSH_PORT}"
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
    log_info " Project   : ${PROJECT_NAME:-default}"
    log_info " Config    : ${CONFIG_FILE}"
    log_info " BMC IP:Port : ${BMC_IP}:${BMC_SSH_PORT}"
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
        "bash '${SCRIPT_DIR}/bmc_ipmid_log.sh' '${BMC_IP}' '${BMC_USER}' '${BMC_PASS_FILE}' '${LOG_IPMID}' '${BMC_SSH_PORT}'" Enter

    sleep 0.5

    # Pane 1: journalctl log
    tmux send-keys -t "${SESSION}:0.1" \
        "bash '${SCRIPT_DIR}/bmc_journal_log.sh' '${BMC_IP}' '${BMC_USER}' '${BMC_PASS_FILE}' '${LOG_JOURNAL}' '${BMC_SSH_PORT}'" Enter

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