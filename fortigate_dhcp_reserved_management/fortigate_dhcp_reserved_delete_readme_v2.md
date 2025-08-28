# FortiGate DHCP Reserved Address Management - Ansible AWX Implementation

## 系統環境
- **AWX版本**: 24.6.1
- **目標設備**: FortiGate v7.2
- **功能**: DHCP Reserved Address MAC刪除（還原為Reserved狀態）

## 1. AWX 設定配置

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
  fortigate_access_token: '{{ fortigate_api_token }}'
  fortigate_validate_certs: '{{ validate_certs }}'
```

### 1.2 Inventory Hosts 設定

```yaml
# FortiGate 連接參數
ansible_connection: httpapi
ansible_network_os: fortinet.fortios.fortios
ansible_httpapi_use_ssl: true
ansible_httpapi_port: 443

# 自動注入參數（由credential提供）
ansible_host: "{{ fortigate_host }}"
ansible_httpapi_validate_certs: "{{ fortigate_validate_certs }}"
```

### 1.3 Playbook 評估

#### Preview Playbook 優化建議
- ✅ **功能完整**: 參數驗證、搜尋邏輯、錯誤處理完善
- ✅ **輸出清晰**: 使用emoji和結構化輸出，易於閱讀
- ⚠️ **可優化項目**:
  - 可加入API連線測試
  - 可增加更詳細的MAC格式驗證
  - 建議加入執行時間估算

#### Execute Playbook 優化建議
- ✅ **安全性**: 充分的參數驗證和確認步驟
- ✅ **容錯性**: 包含成功/失敗處理邏輯
- ⚠️ **可優化項目**:
  - 可加入執行前的API連線測試
  - 可增加回滾機制（記錄原始配置）
  - 建議加入操作後的驗證步驟

## 2. 功能設計說明

### 2.1 核心功能
- **目的**: 將指定MAC的DHCP Reserved Address還原為Reserved狀態
- **方式**: 修改MAC為計算值，描述改為"Reserved"
- **安全**: 雙重確認機制（預覽 + 人工批准）

### 2.2 MAC還原規則
```
IP範例: 192.168.250.103
第四碼: 103
分解: 第一位數字(1) + 後兩位數字(03)
還原MAC: ff:ff:ff:ff:f1:03
描述: "Reserved"
```

### 2.3 DHCP Server對應關係
- **Server ID 2**: vlan40_PC
- **Server ID 12**: vlan22_FIC_WAN

## 3. Workflow Template 設定

### 3.1 Survey 配置
```yaml
問題1: 
  - 名稱: delete_mac_param
  - 類型: Text
  - 標籤: "要刪除的MAC地址"
  - 說明: "請輸入完整MAC地址 (格式: xx:xx:xx:xx:xx:xx)"

問題2:
  - 名稱: server_id
  - 類型: Multiple Choice
  - 標籤: "選擇DHCP Server"
  - 選項:
    - 2 (vlan40_PC)
    - 12 (vlan22_FIC_WAN)
```

### 3.2 Job Templates

#### Preview Job Template
- **名稱**: FortiGate DHCP Reserved Delete - Preview
- **Playbook**: fortigate_dhcp_reserved_delete_preview_for_workflow.yml
- **Credentials**: FortiGate Production
- **用途**: 預覽配置變更，設定workflow變數

#### Execute Job Template
- **名稱**: FortiGate DHCP Reserved Delete - Execute  
- **Playbook**: fortigate_dhcp_reserved_delete_execute_for_workflow.yml
- **Credentials**: FortiGate Production
- **用途**: 執行實際的配置變更

### 3.3 Workflow 設計

```
[START] 
   ↓
[Preview Job] ──(失敗)──→ [END]
   ↓(成功)
[Approval Node] ──(拒絕/逾時)──→ [END] 
   ↓(批准)
[Execute Job] ──(失敗/成功)──→ [END]
```

## 4. 使用流程

### 4.1 操作步驟
1. **啟動Workflow**: 選擇 "Workflow-FortiGate DHCP Reserved Delete with Approval"
2. **填寫Survey**: 
   - 輸入要刪除的MAC地址
   - 選擇對應的DHCP Server ID
3. **檢視預覽**: 查看Preview Job的輸出結果
4. **人工確認**: 在Approval Node中批准或拒絕操作
5. **自動執行**: 批准後自動執行刪除操作
6. **檢視結果**: 查看Execute Job的執行摘要

### 4.2 安全機制
- ✅ 搜尋驗證：確認MAC存在才執行
- ✅ 預覽機制：顯示變更前後對比
- ✅ 人工批准：Approval Node手動確認
- ✅ 詳細日誌：完整的操作記錄

### 4.3 錯誤處理
- **MAC不存在**: 顯示可用MAC清單，停止執行
- **API連線失敗**: 顯示錯誤訊息，停止執行  
- **參數錯誤**: 參數驗證失敗，停止執行
- **執行失敗**: 顯示詳細錯誤資訊

## 5. 技術要點

### 5.1 Workflow變數傳遞
- Preview Job透過`set_stats`設定workflow變數
- Execute Job接收並驗證workflow變數
- 確保資料一致性和完整性

### 5.2 API整合
- 使用FortiGate REST API v2
- Bearer Token認證方式
- 支援VDOM多租戶環境

### 5.3 監控與日誌
- 結構化輸出便於監控
- 詳細的步驟記錄
- 成功/失敗狀態清晰標示

---
**注意事項**: 此操作將永久修改FortiGate配置，請在預覽步驟仔細確認後再批准執行。


