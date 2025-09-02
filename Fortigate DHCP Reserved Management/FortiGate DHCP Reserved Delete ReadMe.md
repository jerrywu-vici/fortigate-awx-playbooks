本專案使用 **Ansible AWX 24.6.1** 版本自動化操作 **FortiGate v7.2** 設備，提供整合的 DHCP Reserved Address 和 Firewall Address 管理功能。

## 🚀 功能概述

### 整合刪除功能 (Preview Playbook 5.6、Execute Playbook v5.1)
此 Workflow 整合了兩種刪除功能：

#### 1. DHCP Reserved Address 刪除功能
- **目的**: 將指定的 MAC 地址配置還原為保留設定 (Reserved)
- **支援 DHCP Server ID**: 2 (vlan40_PC) 和 12 (vlan22_FIC_WAN)

#### 2. Firewall Address 刪除功能
- **目的**: 刪除指定的 MAC 型別 Firewall Address 物件
- **自動處理**: 先從 Address Group 移除成員，再刪除 Address 物件
- **支援 Groups**: Group_22_FIC_Allow-MAC、Group_40_PC-Allow-MAC

**執行流程**: Preview → 人工審核 → Execute

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

### 2.1 整合功能說明

此 Workflow 可處理兩種類型的刪除操作：

#### DHCP Reserved Address 還原規則
**MAC 還原規則:**
```
IP 第四碼: 192.168.250.103 → 取出 "103" (三位數字)
MAC 格式: ff:ff:ff:ff:fX:XX
分解規則:
  X = IP 第四碼的第一位數字 → "103" → "1"
  XX = IP 第四碼的後兩位數字 → "103" → "03"
最終 MAC: ff:ff:ff:ff:f1:03
```

**Description 還原:**
- Description 一律還原為 "Reserved"


### 2.2 Survey 設計
- **問題1**: 要刪除的 MAC 地址或物件名稱
- **問題2**: 選擇 DHCP Server ID (僅 DHCP 模式需要)
  - ID 2 = vlan40_PC
  - ID 12 = vlan22_FIC_WAN

### 2.3 執行流程
1. **搜尋驗證**: 根據選擇的操作類型，確認指定的 MAC 或物件是否存在
2. **預覽配置**: 顯示將被修改或刪除的配置詳情
3. **人工確認**: 等待使用者批准或拒絕
4. **執行操作**: 
   - DHCP 模式：將找到的物件還原為保留設定
   - Firewall 模式：先從 Address Group 移除，再刪除 Address 物件

## 📋 Job Templates 設定

### 3.1 整合 Job Templates

#### Preview Job Template (v5.6)
- **Name**: `FortiGate DHCP Reserved Delete - Preview`
- **Playbook**: `FortiGate DHCP Reserved Delete Preview For Workflow.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要
- **功能**: 整合 DHCP Reserved 和 Firewall Address 的預覽功能

#### Execute Job Template (v5.1)
- **Name**: `FortiGate DHCP Reserved Delete - Execute`
- **Playbook**: `FortiGate DHCP Reserved Delete Execute For Workflow.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要
- **功能**: 整合 DHCP Reserved 和 Firewall Address 的執行功能

## 🔗 Workflow Template

### 4.1 整合刪除 Workflow
- **Name**: `Workflow-FortiGate DHCP Reserved Delete with Approval`
- **Survey**: 操作類型 + MAC地址/物件名稱 + DHCP Server ID (條件性顯示)

**Workflow Nodes 流程:**
```
[START] → [Preview Job v5.6] → [Approval Node] → [Execute Job v5.1] → [END]
              ↓                      ↓
          [On Failure]        [On Denied/Timeout]
              ↓                      ↓
            [END]                  [END]
```

### 4.2 Survey 邏輯設計
```yaml
# Survey 問題設計
- question_name: "輸入要刪除的MAC地址"
  Description: "請輸入完整MAC地址 (格式: xx:xx:xx:xx:xx:xx)，例如：00:11:22:33:44:55"
  Answer variable name: "delete_mac_param"
  Answer type: Text
  Required: v
  Minimum length: 17
  Maximum length: 17
  
- question_name: "選擇DHCP Server ID (ID 2 = vlan40_PC,ID 12 = vlan22_FIC_WAN)"
  Description: "ID 2 = vlan40_PC,ID 12 = vlan22_FIC_WAN"
  Answer variable name: server_id
  Answer type: Multiple Choice(single select)
  Required: v
  choices:
    - "2"
    - "12"
```

## 🎯 使用流程

### 5.1 標準操作流程
1. **啟動 Workflow**: 選擇整合的 Workflow Template
2. **填入 Survey**: 
   - 選擇操作類型 (DHCP Reserved 或 Firewall Address)
   - 輸入 MAC 地址或物件名稱
   - (條件性) 選擇 DHCP Server ID
3. **查看 Preview**: 檢視要刪除/修改的配置詳情
4. **人工確認**: 在 Approval Node 中批准或拒絕操作
5. **自動執行**: 批准後自動執行對應的刪除/還原操作
6. **檢視結果**: 查看最終執行摘要和日誌

### 5.2 錯誤處理
- **配置不存在**: Preview 階段會停止執行並提示
- **API 連接失敗**: 自動重試機制（可設定重試次數和延遲）
- **人工拒絕**: Workflow 正常結束，不執行實際操作
- **物件仍在使用**: Firewall Address 刪除時會先檢查依賴關係

## 📁 檔案結構
```
├── Fortigate DHCP Reserved Management/
│   ├── FortiGate DHCP Reserved Delete Preview For Workflow.yml
│   ├── FortiGate DHCP Reserved Delete Execute For Workflow.yml
└── └── FortiGate DHCP Reserved Delete README.md
```

## ⚠️ 注意事項

1. **整合功能**: 單一 Workflow 支援兩種刪除模式，透過 Survey 選擇
2. **備份機制**: 預設啟用配置備份功能
3. **SSL 驗證**: 預設關閉 SSL 憑證驗證
4. **權限要求**: 需要 FortiGate API Token 具備相應的讀寫權限
5. **VDOM 支援**: 預設使用 root VDOM，可依需求調整
6. **物件命名**: Firewall Address 物件必須以 "MAC_" 開頭且類型為 mac
7. **依賴檢查**: Firewall Address 刪除前會自動處理 Address Group 依賴關係

## 🔧 版本資訊

- **Ansible AWX**: 24.6.1
- **FortiGate OS**: v7.2
- **Ansible Collection**: fortinet.fortios
- **Python**: 3.x
- **Preview Playbook**: v5.6
- **Execute Playbook**: v5.1


