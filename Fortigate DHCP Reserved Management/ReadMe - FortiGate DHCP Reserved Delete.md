本專案使用 **Ansible AWX 24.6.1** 版本自動化操作 **FortiGate v7.2** 設備，提供整合的 DHCP Reserved Address 和 Firewall Address 管理功能。

## 🚀 功能概述

### 整合刪除功能 (Preview Playbook v6.0、Execute Playbook v6.0)

此 Workflow 整合了兩種刪除功能，透過單一流程處理不同類型的配置管理：

#### 1. DHCP Reserved Address 管理功能
- **目的**: 將指定的 MAC 地址配置還原為保留設定 (Reserved)
- **支援 DHCP Server ID**: 
  - ID 2 = vlan40_PC
  - ID 12 = vlan22_FIC_WAN
- **還原規則**: 依據 IP 第四碼自動計算保留 MAC 格式

#### 2. Firewall Address 刪除功能
- **目的**: 刪除指定的 MAC 型別 Firewall Address 物件
- **智能處理**: 自動檢測並處理 Address Group 依賴關係
- **執行順序**: Address Group 移除 → Address Object 刪除
- **支援 Groups**: 
  - Group_22_FIC_Allow-MAC
  - Group_40_PC-Allow-MAC

**標準流程**: Preview → 人工審核 → Execute

## ⚙️ AWX 設定

### 1.1 Credential Type 設定

#### Input Configuration
```yaml
fields:
  - id: fortigate_host
    type: string
    label: FortiGate Host/IP
    help_text: FortiGate device IP address or FQDN
  - id: fortigate_api_token
    type: string
    label: API Access Token
    secret: true
    help_text: FortiGate REST API access token
  - id: vdom
    type: string
    label: VDOM
    default: root
    help_text: Virtual Domain name (default is root)
  - id: api_port
    type: string
    label: API Port
    default: '443'
    help_text: HTTPS port for API access (default 443)
  - id: validate_certs
    type: boolean
    label: Validate SSL Certificates
    default: false
    help_text: Whether to validate SSL certificates
  - id: timeout
    type: string
    label: Connection Timeout
    default: '30'
    help_text: Connection timeout in seconds
  - id: api_retries
    type: string
    label: API Retry Count
    default: '3'
    help_text: Number of API call retries on failure
  - id: api_delay
    type: string
    label: API Retry Delay
    default: '5'
    help_text: Delay between API retries in seconds
  - id: backup_enabled
    type: boolean
    label: Enable Configuration Backup
    default: true
    help_text: Create backup before making changes
required:
  - fortigate_host
  - fortigate_api_token
```

#### Injector Configuration
```yaml
extra_vars:
  fortigate_host: '{{ fortigate_host }}'
  fortigate_vdom: '{{ vdom }}'
  fortigate_timeout: '{{ timeout }}'
  fortigate_api_port: '{{ api_port }}'
  fortigate_api_delay: '{{ api_delay }}'
  fortigate_api_retries: '{{ api_retries }}'
  fortigate_access_token: '{{ fortigate_api_token }}'
  fortigate_backup_enabled: '{{ backup_enabled }}'
  fortigate_validate_certs: '{{ validate_certs }}'
```

### 1.2 Inventory Hosts 設定
```yaml
# FortiGate 連接參數
ansible_connection: httpapi
ansible_network_os: fortinet.fortios.fortios
ansible_httpapi_use_ssl: true
ansible_httpapi_port: "{{ fortigate_api_port | default('443') }}"
ansible_httpapi_timeout: "{{ fortigate_timeout | default('30') }}"

# 自動注入參數（由credential提供）
ansible_host: "{{ fortigate_host }}"
ansible_httpapi_validate_certs: "{{ fortigate_validate_certs | default(false) }}"

# 優化連線參數
ansible_python_interpreter: /usr/bin/python3
ansible_httpapi_session_timeout: 300
ansible_command_timeout: "{{ fortigate_timeout | default('30') }}"
```

## 🔄 Workflow 設計

### 2.1 整合功能架構

#### DHCP Reserved Address 還原邏輯
**MAC 地址計算規則:**
```
輸入 IP: 192.168.250.103
提取第四碼: 103
分解規則:
  - 第一位數字: 1
  - 後兩位數字: 03
生成保留 MAC: ff:ff:ff:ff:f1:03
描述還原: "Reserved"
```


### 2.2 Survey 設計邏輯

#### Survey 問題配置
```yaml
# 問題1: MAC 地址輸入
question_name: "輸入要處理的MAC地址"
description: "請輸入完整MAC地址 (格式: xx:xx:xx:xx:xx:xx)，例如：00:11:22:33:44:55"
variable_name: delete_mac_param
type: text
required: true
validation: MAC地址格式驗證

# 問題2: DHCP Server ID 選擇  
question_name: "選擇DHCP Server ID"
description: "ID 2 = vlan40_PC, ID 12 = vlan22_FIC_WAN"
variable_name: server_id
type: multiplechoice
choices:
  - "2"
  - "12"
required: true
```

### 2.3 執行流程架構

#### 階段1: 預覽階段 (Preview v6.0)
1. **參數驗證**: 驗證 Credentials、Survey 參數、Server ID
2. **連接測試**: 測試 FortiGate API 連接
3. **DHCP 配置搜尋**: 
   - 獲取現有 DHCP Reserved Addresses
   - 搜尋目標 MAC 地址
   - 計算還原後的配置
4. **Firewall 配置搜尋**:
   - 獲取所有 MAC 類型 Address Objects
   - 搜尋 MAC_ 開頭的目標物件
   - 分析 Address Group 成員關係
5. **預覽總結**: 顯示將要執行的操作
6. **Workflow 變數設定**: 傳遞配置資訊給執行階段

#### 階段2: 執行階段 (Execute v6.0)
1. **變數接收**: 接收 Preview 階段的 Workflow 變數
2. **執行前驗證**: 確認配置未在審核期間被修改
3. **DHCP 操作執行**: 
   - 執行 MAC 地址還原
   - 更新描述為 "Reserved"
4. **Firewall 操作執行**:
   - Step 1: 從 Address Group 移除成員
   - Step 2: 刪除 Address Object
5. **操作後驗證**: 驗證所有變更已正確執行
6. **結果摘要**: 顯示最終執行結果

## 📋 Job Templates 設定

### 3.1 整合 Job Templates v6.0

#### Preview Job Template
```yaml
Name: FortiGate Multi-Function Delete - Preview v6.0
Playbook: FortiGate DHCP Reserved Delete Preview For Workflow v6.0.yml
Credentials: FortiGate Production
Survey: 不需要 (由 Workflow 提供)
功能: 
  - 整合 DHCP Reserved 和 Firewall Address 預覽
  - 自動偵測可用的配置
  - 設定 Workflow 變數供執行階段使用
```

#### Execute Job Template
```yaml
Name: FortiGate Multi-Function Delete - Execute v6.0  
Playbook: FortiGate DHCP Reserved Delete Execute For Workflow v6.0.yml
Credentials: FortiGate Production
Survey: 不需要 (接收 Workflow 變數)
功能:
  - 執行 DHCP Reserved Address 還原
  - 執行 Firewall Address 和 Group 管理
  - 提供完整的操作驗證和摘要
```

## 🔗 Workflow Template

### 4.1 整合管理 Workflow v6.0

#### Workflow 基本設定
```yaml
Name: "Workflow-FortiGate Integrated Delete Management v6.0"
Description: "整合的 DHCP Reserved 和 Firewall Address 刪除管理流程"
Survey: MAC地址輸入 + DHCP Server ID 選擇
```

#### Workflow Nodes 流程圖
```
[START] 
   ↓
[Preview Job v6.0] ←── 獲取配置、分析依賴關係、設定變數
   ↓ (Success)
[Approval Node] ←── 人工審核預覽結果
   ↓ (Approved)        ↓ (Denied/Timeout)
[Execute Job v6.0]     [END]
   ↓ (Success)
[END]
   ↑
[On Failure] ←── 任何階段失敗都會到此結束
```

#### Workflow Survey 完整設計
```yaml
# Survey 配置
survey_spec:
  name: "FortiGate 整合刪除管理"
  description: "處理 DHCP Reserved Address 還原和 Firewall Address 刪除"
  spec:
    - question_name: "輸入要處理的MAC地址"
      question_description: |
        請輸入完整的MAC地址，支援格式：
        - xx:xx:xx:xx:xx:xx (冒號分隔)
        - xx-xx-xx-xx-xx-xx (連字號分隔)
        範例: 00:11:22:33:44:55
      required: true
      type: "text"
      variable: "delete_mac_param"
      min: 17
      max: 17
      
    - question_name: "選擇DHCP Server ID"
      question_description: |
        選擇對應的DHCP Server:
        - ID 2: vlan40_PC (用戶PC網段)
        - ID 12: vlan22_FIC_WAN (FIC WAN網段)  
      required: true
      type: "multiplechoice"
      variable: "server_id"
      choices:
        - "2"
        - "12"
```

## 🎯 使用流程

### 5.1 標準操作流程

#### Step 1: 啟動 Workflow
- 在 AWX 中選擇 "Workflow-FortiGate Integrated Delete Management v6.0"
- 點擊 "Launch" 開始執行

#### Step 2: 填寫 Survey 資訊
```yaml
MAC地址輸入: "00:11:22:33:44:55"
DHCP Server ID: "2" (選擇對應的網段)
```

#### Step 3: Preview 階段自動執行
- ✅ 驗證 API 連接和參數
- 🔍 搜尋 DHCP 中的目標 MAC
- 🔍 搜尋 Firewall Address Objects
- 📊 分析 Address Group 依賴關係  
- 📋 顯示完整的變更預覽

#### Step 4: 人工審核確認
**預覽資訊範例:**
```
📊 操作總覽:
- DHCP操作: YES (192.168.40.123 → ff:ff:ff:ff:f1:23)
- Firewall操作: YES (MAC_test_PC_WLAN)
- Address Group: Group_40_PC-Allow-MAC (從8個成員減少為7個)

⚠️ 警告: 此操作將永久修改FortiGate配置！
```

#### Step 5: Execute 階段自動執行
- 🔧 執行 DHCP MAC 還原操作
- 🔧 從 Address Group 移除成員  
- 🔧 刪除 Firewall Address Object
- ✅ 驗證所有變更結果
- 📊 顯示最終執行摘要

#### Step 6: 檢視執行結果
**最終摘要範例:**
```
📊 整合操作結果:
- MAC: 00:11:22:33:44:55
- DHCP: ✅成功 (ID: 123, Reserved)
- Firewall: ✅成功 (MAC_test_PC_WLAN 已刪除)
- 完成時間: 2024-01-01T10:30:00Z
```

### 5.2 錯誤處理機制

#### 常見錯誤情境
```yaml
配置不存在:
  - DHCP: "⚠️ DHCP中未找到目標MAC"
  - Firewall: "⚠️ Firewall中未找到目標Address"
  - 處理: Preview階段停止，不進入Execute

API連接問題:
  - 錯誤: 連接超時、認證失敗
  - 處理: 自動重試機制 (預設3次，間隔5秒)
  
配置變更衝突:
  - 錯誤: Preview後配置被其他人修改
  - 處理: Execute階段驗證失敗，要求重新Preview

人工拒絕操作:
  - 處理: Workflow正常結束，不執行實際變更
  
依賴關係問題:
  - 錯誤: Address仍被其他Policy使用
  - 處理: 先處理依賴關係再刪除Object
```

## 📁 檔案結構

```
fortigate-awx-playbooks/
├── playbooks/
│   ├── FortiGate DHCP Reserved Delete Preview For Workflow v6.0.yml
│   ├── FortiGate DHCP Reserved Delete Execute For Workflow v6.0.yml
│   └── README.md
├── inventory/
│   └── fortigate_hosts.yml
├── credentials/
│   └── fortigate_credential_type.yml
└── workflows/
    └── integrated_delete_workflow.yml
```

## ⚠️ 重要注意事項

### 安全性考量
1. **備份機制**: 預設啟用配置備份，所有變更前都會記錄原始配置
2. **人工審核**: 強制要求人工確認，防止誤操作
3. **權限控制**: 需要對應的 FortiGate API Token 權限
4. **SSL驗證**: 可選擇啟用/關閉 SSL 憑證驗證

### 功能限制
1. **物件命名**: Firewall Address 必須以 "MAC_" 開頭且類型為 mac
2. **VDOM支援**: 預設使用 root VDOM，企業環境需調整
3. **Server ID**: 僅支援預定義的 Server ID (2, 12)
4. **依賴檢查**: 自動處理 Address Group，但無法處理 Policy 依賴

### 最佳實踐
1. **測試環境**: 建議先在測試環境驗證流程
2. **權限管理**: 使用最小權限原則設定 API Token
3. **監控告警**: 設定 AWX 執行結果通知
4. **文檔維護**: 定期更新 Server ID 對應關係

## 🔧 版本資訊

- **Ansible AWX**: 24.6.1
- **FortiGate OS**: v7.2.x
- **Ansible Collection**: fortinet.fortios (最新版)
- **Python**: 3.8+
- **Playbook 版本**: v6.0

---

**注意**: 本文檔與 Playbook v6.0 同步更新，請確保版本一致性。
