# HPM Upgrade Test Script — 修改 Plan

## 目標
將測試指令抽象化，支援多組 test case，方便擴充與替換，debug 架構不變。

---

## 新增檔案

### `test_cases.yaml`
定義所有測試情境。

**欄位說明：**
- `name`：test case 唯一識別名稱
- `transport`：`lanplus` 或 `usb`
- `target_cmd`：spv_ipmi 的子指令部分（不含公共參數）
- `fw_var`：使用的 firmware 變數名稱（對應 USER CONFIG 的變數）
- `interactive`：是否需要 expect 處理互動 prompt

**內容：**
```yaml
- name: hpm_lanplus
  transport: lanplus
  target_cmd: "hpm upgrade {FW} force activate"
  fw_var: FW_FILE
  interactive: true

- name: isc_bmc_lanplus
  transport: lanplus
  target_cmd: "isc bmc update {HPM}"
  fw_var: HPM_FILE
  interactive: false

- name: isc_bios_lanplus
  transport: lanplus
  target_cmd: "isc bios update {HPM}"
  fw_var: HPM_FILE
  interactive: false

- name: isc_pld_lanplus
  transport: lanplus
  target_cmd: "isc pld update {HPM}"
  fw_var: HPM_FILE
  interactive: false
```

---

## 修改檔案

### 1. `hpm_upgrade_test.sh`

#### USER CONFIG 區塊
新增 `HPM_FILE` 變數，並新增 `TEST_CASE` 變數：
```bash
FW_FILE="/path/to/firmware.hpm"
HPM_FILE="/path/to/firmware_isc.hpm"
TEST_CASE="hpm_lanplus"   # 對應 test_cases.yaml 的 name 欄位
```

#### check_files()
新增檢查：
- `test_cases.yaml` 存在
- `yq` 指令可用（用於解析 yaml）
- 根據選定 test case 的 `fw_var` 欄位，檢查對應 fw 檔案存在

#### main()
在建立 tmux session 之前，新增 test case 解析邏輯：
1. 用 `yq` 從 `test_cases.yaml` 讀取選定 `TEST_CASE` 的各欄位
2. 根據 `transport` 欄位組出完整 spv_ipmi 指令：
   - `lanplus`：`spv_ipmi -U root -P 0penBmc -H ${BMC_IP} -I lanplus -C 17 -z 30000 -N 10 <target_cmd>`
   - `usb`：`spv_ipmi -U root -P 0penBmc -C 17 -N 10 <target_cmd>`
3. 將組好的完整指令、`interactive` 欄位，以參數形式傳給 `host_hpm_upgrade.sh`

#### Pane 2 的 tmux send-keys
```bash
tmux send-keys -t "${SESSION}:0.2" \
    "bash '${SCRIPT_DIR}/host_hpm_upgrade.sh' \
        '${FULL_CMD}' \
        '${INTERACTIVE}' \
        '${LOG_HOST}'" Enter
```

---

### 2. `host_hpm_upgrade.sh`

#### 參數調整
```bash
FULL_CMD="$1"    # 完整 spv_ipmi 指令
INTERACTIVE="$2" # true / false
LOG_FILE="$3"
```

#### 執行邏輯
根據 `INTERACTIVE` 欄位決定執行方式：