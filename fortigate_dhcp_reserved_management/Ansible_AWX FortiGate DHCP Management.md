本專案使用 **Ansible AWX 24.6.1** 版本自動化操作 **FortiGate v7.2** 設備，提供 DHCP Reserved Address 和 Firewall Address 的管理功能。

## 🚀 功能概述

### 1. DHCP Reserved Address 刪除功能
- **目的**: 將指定的 MAC 地址配置還原為保留設定 (Reserved)
- **支援 DHCP Server ID**: 2 (vlan40_PC) 和 12 (vlan22_FIC_WAN)
- **流程**: Preview → 人工審核 → Execute

### 2. Firewall Address 刪除功能
- **目的**: 刪除指定的 MAC 型別 Firewall Address 物件
- **自動處理**: 先從 Address Group 移除成員，再刪除 Address 物件
- **支援 Groups**: Group_22_FIC_Allow-MAC、Group_40_PC-Allow-MAC

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

### DHCP Reserved Address Delete Workflow

#### 2.1 還原規則說明

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

#### 2.2 Survey 設計
- **問題1**: 要刪除的 MAC 地址
- **問題2**: 選擇 DHCP Server ID
  - ID 2 = vlan40_PC
  - ID 12 = vlan22_FIC_WAN

#### 2.3 執行流程
1. **搜尋驗證**: 確認指定的 MAC 是否存在於設定中
2. **預覽配置**: 顯示將被修改的配置詳情
3. **人工確認**: 等待使用者批准或拒絕
4. **執行還原**: 將找到的物件還原為保留設定

### Firewall Address Delete Workflow

#### 2.4 Address Group 處理
目標環境中的 Address Groups:
```bash
config firewall addrgrp
    edit "Group_22_FIC_Allow-MAC"
        set member "MAC_Chiachi_NB_WLAN" "MAC_Barz_NB_WLAN" "MAC_Ian.su_NB_WLAN"
    next
    edit "Group_40_PC-Allow-MAC"
        set member "MAC_test_PC_WLAN" "MAC_other_device"
    next
end
```

#### 2.5 Address 物件格式
```bash
config firewall address
    edit "MAC_test_PC_WLAN"
        set type mac
        set comment "172.23.22.170"
        set macaddr "00:11:22:33:44:55"
    next
end
```

## 📋 Job Templates 設定

### 3.1 DHCP Reserved Delete Templates

#### Preview Job Template
- **Name**: `FortiGate DHCP Reserved Delete - Preview`
- **Playbook**: `fortigate_dhcp_reserved_delete_preview_for_workflow.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要

#### Execute Job Template  
- **Name**: `FortiGate DHCP Reserved Delete - Execute`
- **Playbook**: `fortigate_dhcp_reserved_delete_execute_for_workflow.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要

### 3.2 Firewall Address Delete Templates

#### Preview Job Template
- **Name**: `FortiGate Firewall Address Delete - Preview`
- **Playbook**: `fortigate_firewall_address_delete_preview.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要

#### Execute Job Template
- **Name**: `FortiGate Firewall Address Delete - Execute`  
- **Playbook**: `fortigate_firewall_address_delete_execute.yml`
- **Credentials**: FortiGate Production
- **Survey**: 不需要

## 🔗 Workflow Templates

### 4.1 DHCP Reserved Delete Workflow
- **Name**: `Workflow-FortiGate DHCP Reserved Delete with Approval`
- **Survey**: MAC地址 + DHCP Server ID 選擇

**Workflow Nodes 流程:**
```
[START] → [Preview Job] → [Approval Node] → [Execute Job] → [END]
            ↓                    ↓
        [On Failure]      [On Denied/Timeout]
            ↓                    ↓
          [END]                [END]
```

### 4.2 Firewall Address Delete Workflow
- **Name**: `Workflow-FortiGate Firewall Address Delete with Approval`
- **Survey**: MAC Address 物件名稱

**Workflow Nodes 流程:**
```
[START] → [Preview Job] → [Approval Node] → [Execute Job] → [END]
            ↓                    ↓
        [On Failure]      [On Denied/Timeout]
            ↓                    ↓
          [END]                [END]
```

## 🎯 使用流程

### 5.1 標準操作流程
1. **啟動 Workflow**: 選擇對應的 Workflow Template
2. **填入 Survey**: 輸入必要的參數（MAC地址、Server ID等）
3. **查看 Preview**: 檢視要刪除/修改的配置詳情
4. **人工確認**: 在 Approval Node 中批准或拒絕操作
5. **自動執行**: 批准後自動執行刪除/還原操作
6. **檢視結果**: 查看最終執行摘要和日誌

### 5.2 錯誤處理
- **配置不存在**: Preview 階段會停止執行並提示
- **API 連接失敗**: 自動重試機制（可設定重試次數和延遲）
- **人工拒絕**: Workflow 正常結束，不執行實際操作

## 📁 檔案結構
```
├── playbooks/
│   ├── dhcp_reserved/
│   │   ├── fortigate_dhcp_reserved_delete_preview_for_workflow.yml
│   │   └── fortigate_dhcp_reserved_delete_execute_for_workflow.yml
│   └── firewall_address/
│       ├── fortigate_firewall_address_delete_preview.yml
│       └── fortigate_firewall_address_delete_execute.yml
├── inventory/
│   └── fortigate_hosts.yml
└── README.md
```

## ⚠️ 注意事項

1. **備份機制**: 預設啟用配置備份功能
2. **SSL 驗證**: 預設關閉 SSL 憑證驗證
3. **權限要求**: 需要 FortiGate API Token 具備相應的讀寫權限
4. **VDOM 支援**: 預設使用 root VDOM，可依需求調整
5. **物件命名**: Firewall Address 物件必須以 "MAC_" 開頭且類型為 mac

## 🔧 版本資訊

- **Ansible AWX**: 24.6.1
- **FortiGate OS**: v7.2
- **Ansible Collection**: fortinet.fortios
- **Python**: 3.x


