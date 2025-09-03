# FortiGate DHCP Reserved Create&Update

本專案使用 **Ansible AWX 24.6.1** 自動化操作 **FortiGate v7.2** 設備，提供三階段整合的 DHCP Reserved Address、Firewall Address Object 和 Address Group 管理功能。

## 🚀 功能概述

### 三階段整合自動化 (v2.1)
此解決方案提供完整的網路配置自動化，透過單一 Workflow 執行三個相關聯的配置階段：

| 階段 | 功能 | 操作類型 |
|------|------|----------|
| **階段1** | DHCP Reserved Address | CREATE / UPDATE |
| **階段2** | Firewall Address Object | CREATE / UPDATE |
| **階段3** | Address Group Member | ADD_MEMBER |

### 關鍵特色
- ✅ **智能操作判斷**: 自動檢測每個階段是否需要執行
- ✅ **完整回滾機制**: 後續階段失敗自動回滾前面已完成的配置
- ✅ **衝突檢測**: MAC 地址衝突、IP 範圍驗證、重複配置檢查
- ✅ **人工審核**: Preview → Approval → Execute 的安全執行流程
- ✅ **統一命名**: 固定的 Template 和 Playbook 名稱，便於維護

## 📋 執行流程

### 工作流程圖
```
[Survey 輸入] → [Preview 分析] → [Approval Node] → [Execute 執行]
     ↓              ↓               ↓               ↓
  IP/MAC/描述    三階段預覽檢查    人工確認操作      依序執行配置
   Server ID      衝突檢測         安全審核         自動回滾
```

### 三階段操作邏輯

#### 輸入參數範例
```yaml
IP地址: 172.23.22.170
MAC地址: 00:11:22:33:44:55
描述: test_PC_WLAN
DHCP Server ID: 12 (vlan22_FIC_WAN)
```

#### 執行結果
```bash
# 階段1: DHCP Reserved Address
config system dhcp server
    edit 12
        config reserved-address
            edit [auto-generated-id]
                set ip 172.23.22.170
                set mac 00:11:22:33:44:55
                set description "test_PC_WLAN"
            next
        end
    next
end

# 階段2: Firewall Address Object  
config firewall address
    edit "MAC_test_PC_WLAN"
        set type mac
        set comment "172.23.22.170"
        set macaddr "00:11:22:33:44:55"
    next
end

# 階段3: Address Group Member
config firewall addrgrp
    edit "Group_22_FIC_Allow-MAC"
        set member [existing_members] "MAC_test_PC_WLAN"
    next
end
```

## 🔍 檢查點與執行規則

### Preview 階段檢查點規則

#### 1. 參數驗證規則

| 檢查項目 | 驗證規則 | 失敗條件 | 錯誤處理 |
|----------|----------|----------|----------|
| **FortiGate Credentials** | `fortigate_host` 和 `fortigate_access_token` 必須定義 | 任一參數未定義 | 立即終止，顯示缺少參數 |
| **Survey 參數** | `ip_param`, `mac_param`, `desc_param`, `server_id` 必須定義 | 任一參數未定義 | 立即終止，顯示缺少參數 |
| **Server ID** | 必須在 `["2", "12"]` 範圍內 | 不在支援清單 | 立即終止，顯示支援的 ID |

#### 2. 格式驗證規則

| 驗證項目 | 正則表達式/邏輯 | 通過條件 | 失敗處理 |
|----------|------------------|----------|----------|
| **IP 格式** | `ansible.utils.ipaddr` | 有效的 IPv4 地址 | 終止並提示正確格式 |
| **MAC 格式** | `^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$` | 符合 MAC 格式 | 終止並提示正確格式 |
| **MAC 正規化** | `replace('-', ':').lower()` | 統一為小寫冒號格式 | 自動轉換 |

#### 3. API 連接驗證規則

```yaml
檢查規則:
  - URL: "https://{{ fortigate_host }}/api/v2/cmdb/system/global"
  - Method: GET
  - 期望狀態碼: 200
  - 重試次數: 3 (可設定)
  - 重試間隔: 5 秒 (可設定)
  - 超時時間: 30 秒 (可設定)

通過條件: API 回應狀態碼 200
失敗條件: 連續重試失敗或非 200 狀態碼
```

#### 4. DHCP Server 配置驗證

```yaml
步驟1 - 取得 Server 配置:
  URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}"
  驗證: Server 存在且有 ip-range 設定

步驟2 - IP 範圍檢查:
  取得範圍: server['ip-range'][0]['start-ip'] ~ server['ip-range'][0]['end-ip']
  檢查邏輯: target_ip >= start_ip AND target_ip <= end_ip
  
通過條件: IP 在允許範圍內
失敗條件: IP 超出範圍，顯示允許範圍並終止
```

### 三階段操作判斷規則

#### 階段1: DHCP Reserved Address 判斷

**取得現有配置規則**
```yaml
API 呼叫:
  URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address"
  Method: GET
  
搜尋邏輯:
  - 遍歷所有 reserved-address
  - 比對條件: existing_mac.lower() == target_mac.lower()
```

**MAC 衝突檢測規則**
```yaml
衝突條件:
  - 找到相同 MAC 地址 
  - 但 IP 地址不同 (existing_ip != target_ip)
  
衝突處理:
  - 顯示衝突詳情 (既有IP、ID、描述)
  - 提供解決方案
  - 立即終止 Workflow
  
無衝突條件:
  - 未找到相同 MAC，或
  - 找到相同 MAC 且 IP 也相同
```

**操作類型判斷**
```yaml
CREATE 條件:
  - 目標 IP 在 DHCP 中不存在

UPDATE 條件:
  - 目標 IP 在 DHCP 中已存在
  
需要執行判斷:
  CREATE: 總是需要執行
  UPDATE: 當 MAC 或描述與現有配置不同時才執行
```

#### 階段2: Firewall Address Object 判斷

**Address Object 檢查規則**
```yaml
API 呼叫:
  URL: "/api/v2/cmdb/firewall/address/{{ target_address_name }}"
  Method: GET
  期望狀態: [200, 404]
  
Address 命名規則:
  格式: "MAC_{{ description }}"
  範例: "MAC_test_PC_WLAN"
```

**操作類型判斷**
```yaml
CREATE 條件:
  - API 回應 404 (Address 不存在)

UPDATE 條件:
  - API 回應 200 (Address 已存在)
  
需要執行判斷:
  CREATE: 總是需要執行
  UPDATE: 當 comment 或 macaddr 與目標不同時執行
    - comment != target_ip
    - macaddr[0].macaddr.lower() != target_mac.lower()
```

#### 階段3: Address Group 判斷

**Group 成員檢查規則**
```yaml
API 呼叫:
  URL: "/api/v2/cmdb/firewall/addrgrp/{{ target_address_group }}"
  Method: GET
  
Group 對應規則:
  Server ID 2  → "Group_40_PC-Allow-MAC"
  Server ID 12 → "Group_22_FIC_Allow-MAC"

成員檢查邏輯:
  1. 取得現有 members 列表
  2. 提取所有 member.name
  3. 檢查 target_address_name 是否在列表中
```

**需要執行判斷**
```yaml
ADD_MEMBER 條件:
  - target_address_name 不在現有 Group members 中
  
跳過條件:
  - target_address_name 已在 Group members 中
  
執行內容:
  - 將 target_address_name 加入 members 列表
  - 保持其他 members 不變
```

### Execute 階段執行規則

#### 執行前置條件檢查

```yaml
必要條件:
  1. 通過 Preview 階段所有檢查
  2. 人工 Approval 通過
  3. Workflow 變數正確傳遞
  
Workflow 變數驗證:
  - wf_target_ip, wf_target_mac, wf_address_name, wf_group_name 必須存在
  - wf_three_stage_operations = true
  - wf_preview_version 兼容 (v2.1)
```

#### 執行順序與條件

**階段1: DHCP 執行條件**
```yaml
執行條件:
  - dhcp_needs_operation = true

CREATE 執行:
  - URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address"
  - Method: POST
  - Body: {ip, mac, description}
  
UPDATE 執行:
  - URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address/{{ id }}"
  - Method: PUT
  - Body: {ip, mac, description}

成功條件: HTTP 狀態碼 200
失敗處理: 顯示錯誤並終止 (無需回滾)
```

**階段2: Address Object 執行條件**
```yaml
執行前提:
  - 階段1 成功 OR 階段1 跳過
  - address_needs_operation = true

CREATE 執行:
  - URL: "/api/v2/cmdb/firewall/address"
  - Method: POST
  - Body: {name, type: "mac", comment: IP, macaddr: [macaddr: MAC]}
  
UPDATE 執行:
  - URL: "/api/v2/cmdb/firewall/address/{{ address_name }}"
  - Method: PUT
  - Body: {name, type: "mac", comment: IP, macaddr: [macaddr: MAC]}

成功條件: HTTP 狀態碼 200
失敗處理: 回滾階段1 + 顯示錯誤並終止
```

**階段3: Group 執行條件**
```yaml
執行前提:
  - 階段1 成功 OR 階段1 跳過
  - 階段2 成功 OR 階段2 跳過  
  - group_needs_operation = true

執行內容:
  - URL: "/api/v2/cmdb/firewall/addrgrp/{{ group_name }}"
  - Method: PUT
  - Body: {member: updated_group_members}

成功條件: HTTP 狀態碼 200
失敗處理: 完整回滾階段2 + 階段1 + 顯示錯誤並終止
```

### 回滾機制規則

#### 回滾觸發條件

| 失敗階段 | 回滾範圍 | 回滾動作 |
|----------|----------|----------|
| **階段1失敗** | 無 | 直接終止，無需回滾 |
| **階段2失敗** | 階段1 | 執行階段1回滾動作 |
| **階段3失敗** | 階段2 + 階段1 | 依序回滾階段2、階段1 |

#### 回滾執行規則

**階段1 DHCP 回滾**
```yaml
CREATE 回滾:
  - URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address/{{ created_id }}"
  - Method: DELETE
  - 忽略錯誤: 是 (404 視為成功)

UPDATE 回滾:
  - URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address/{{ id }}"
  - Method: PUT
  - Body: {{ original_dhcp_object }}
  - 忽略錯誤: 是
```

**階段2 Address Object 回滾**
```yaml
CREATE 回滾:
  - URL: "/api/v2/cmdb/firewall/address/{{ address_name }}"
  - Method: DELETE
  - 忽略錯誤: 是 (404 視為成功)

UPDATE 回滾:
  - URL: "/api/v2/cmdb/firewall/address/{{ address_name }}"
  - Method: PUT  
  - Body: {{ original_address_object }}
  - 忽略錯誤: 是
```

#### 回滾成功判定
```yaml
成功條件:
  - HTTP 狀態碼 200 (操作成功)
  - HTTP 狀態碼 404 (物件已不存在，視為回滾成功)

失敗顯示:
  - 回滾狀態會在最終錯誤訊息中顯示
  - ✅成功 / ❌失敗
  - 不會因為回滾失敗再次終止
```

### 操作後驗證規則

#### 驗證執行條件
```yaml
觸發條件:
  - 至少有一個階段成功執行 (stage1_completed OR stage2_completed OR stage3_completed)

驗證內容:
  1. DHCP 配置驗證 (當 stage1_completed = true)
  2. Address Object 驗證 (當 stage2_completed = true)  
  3. Address Group 驗證 (當 stage3_completed = true)
```

#### 各階段驗證規則

**DHCP 配置驗證**
```yaml
API 呼叫:
  - URL: "/api/v2/cmdb/system.dhcp/server/{{ server_id }}/reserved-address?filter=ip=={{ target_ip }}"
  - Method: GET
  
驗證邏輯:
  - 找到配置數量 >= 1
  - MAC 地址匹配
  - 描述匹配

結果顯示: "找到配置: X 筆"
```

**Address Object 驗證**
```yaml
API 呼叫:
  - URL: "/api/v2/cmdb/firewall/address/{{ address_name }}"
  - Method: GET
  - 期望狀態: [200, 404]

驗證結果:
  - 200: ✅驗證通過
  - 404: ⚠️未找到配置
```

**Address Group 驗證**
```yaml
API 呼叫:
  - URL: "/api/v2/cmdb/firewall/addrgrp/{{ group_name }}"  
  - Method: GET

驗證邏輯:
  - 檢查 members 總數
  - 確認 address_name 在 members 列表中

結果顯示:
  - "Members數: X"
  - "Address已加入: true/false"
```

## ⚙️ AWX 設定

### Credential Type 配置

<details>
<summary>點擊展開 Credential Type 設定</summary>

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
  fortigate_api_retries: '{{ api_retries }}'
  fortigate_access_token: '{{ fortigate_api_token }}'
  fortigate_validate_certs: '{{ validate_certs }}'
```

</details>

### Job Templates 設定

| Template | 名稱 | Playbook |
|----------|------|----------|
| **Preview** | `FortiGate DHCP Reserved Create&Update - Preview` | `FortiGate DHCP Reserved Create&Update Preview For Workflow.yml` |
| **Execute** | `FortiGate DHCP Reserved Create&Update - Execute` | `FortiGate DHCP Reserved Create&Update Execute For Workflow.yml` |

### Workflow Template 設定

**固定名稱**: `Workflow-FortiGate DHCP Reserved Create&Update`

**Workflow Nodes**:
```
[START] → [Preview Job] → [Approval Node] → [Execute Job] → [END]
            ↓               ↓                ↓
        [On Failure]    [On Denied]     [On Failure]
            ↓               ↓                ↓
          [END]           [END]            [END]
```

### Survey 配置

| 參數 | 說明 | 範例 | 驗證規則 |
|------|------|------|----------|
| **IP地址** | 目標IP，必須在DHCP範圍內 | `172.23.22.170` | IPv4 格式 + 範圍檢查 |
| **MAC地址** | 支援 `:` 或 `-` 分隔 | `00:11:22:33:44:55` | 正則表達式驗證 |
| **描述** | Address Object名稱的一部分 | `test_PC_WLAN` | 1-64 字元 |
| **DHCP Server ID** | 2(vlan40_PC) 或 12(vlan22_FIC_WAN) | `12` | 必須在 ["2", "12"] |

## 🔧 Server ID 對應關係

| Server ID | 描述 | Address Group | IP 範圍檢查 |
|-----------|------|---------------|-------------|
| **2** | vlan40_PC | Group_40_PC-Allow-MAC | 自動從 DHCP Server 取得 |
| **12** | vlan22_FIC_WAN | Group_22_FIC_Allow-MAC | 自動從 DHCP Server 取得 |

## 🎯 使用流程

### 1. 啟動 Workflow
- 在 AWX 中選擇 `Workflow-FortiGate DHCP Reserved Create&Update`
- 填寫 Survey 參數

### 2. Preview 階段 (自動)
- 🔍 **參數驗證**: IP格式、MAC格式、Server ID
- 🔍 **API連接測試**: 驗證FortiGate連通性
- 🔍 **IP範圍檢查**: 確認IP在DHCP Server範圍內
- 🔍 **衝突檢測**: MAC地址衝突、Address Object重複
- 📊 **三階段預覽**: 顯示所有將要執行的變更

### 3. 人工審核
**審核要點**:
- [ ] 確認三階段操作類型正確 (CREATE/UPDATE/ADD_MEMBER)
- [ ] 檢查目標配置參數 (IP/MAC/描述)
- [ ] 確認無衝突警告
- [ ] 理解回滾機制
- [ ] 驗證 Address Group 對應關係

### 4. Execute 階段 (自動)
```yaml
執行順序:
  階段1: DHCP Reserved Address
    ↓ (成功)
  階段2: Firewall Address Object  
    ↓ (成功)
  階段3: Address Group Member
    ↓
  完成 ✅

錯誤處理:
  階段1失敗 → 終止 (無需回滾)
  階段2失敗 → 回滾階段1
  階段3失敗 → 回滾階段2 + 階段1
```

### 5. 驗證結果
- 📊 **配置驗證**: 自動檢查所有配置是否生效
- 📋 **執行摘要**: 顯示各階段執行狀態
- ⏱️ **時間統計**: 記錄執行時間

## 🛠️ 錯誤處理

### 重試機制規則
```yaml
API 重試設定:
  - 預設重試次數: 3
  - 重試間隔: 5 秒
  - 超時時間: 30 秒
  - 適用範圍: 所有 FortiGate API 呼叫

重試條件:
  - 網路連接錯誤
  - 超時錯誤
  - 50x 伺服器錯誤

不重試條件:
  - 40x 客戶端錯誤 (除了 404)
  - 認證失敗
  - 參數驗證錯誤
```

### 終止條件彙總
| 階段 | 終止條件 | 影響範圍 |
|------|----------|----------|
| **參數驗證** | 格式錯誤、缺少參數 | 整個 Workflow |
| **API 連接** | 連接失敗、認證錯誤 | 整個 Workflow |
| **IP 範圍** | IP 超出 DHCP 範圍 | 整個 Workflow |
| **MAC 衝突** | MAC 已分配給其他 IP | 整個 Workflow |
| **階段1執行** | DHCP 操作失敗 | 後續階段不執行 |
| **階段2執行** | Address 操作失敗 | 階段3不執行，回滾階段1 |
| **階段3執行** | Group 操作失敗 | 回滾階段2和階段1 |

### 常見錯誤及解決方案

<details>
<summary>📋 點擊查看錯誤處理指南</summary>

#### MAC衝突
```
❌ 錯誤: MAC衝突檢測失敗！MAC已被分配給其他IP
✅ 解決: 使用不同MAC或確認是否要更新既有配置
```

#### IP超出範圍
```
❌ 錯誤: IP地址超出DHCP Server範圍
✅ 解決: 選擇正確範圍內的IP或更換Server ID
```

#### Address Object重複
```
❌ 錯誤: Address Object已存在但配置不同
✅ 解決: 確認是否要更新既有配置
```

#### API連接失敗
```
❌ 錯誤: FortiGate API連接失敗
✅ 解決: 檢查網路連通性、API Token有效性
```

</details>

## 📁 檔案結構

```
fortigate-awx-playbooks-v2.1/
├── dhcp-reserved-create-update/
│   ├── FortiGate DHCP Reserved Create&Update Preview For Workflow.yml
│   ├── FortiGate DHCP Reserved Create&Update Execute For Workflow.yml
│   └── README-CreateUpdate-v2.1.md
├── workflows/
│   └── dhcp-create-update-workflow.yml
├── inventory/
│   └── fortigate_hosts.yml
├── credentials/
│   └── fortigate_credential_type.yml
└── README.md
```

## 📊 版本資訊

### v2.1 更新內容
- ✅ **修正輸出格式**: 解決所有斷行顯示問題
- ✅ **統一命名規範**: 固定Template和Playbook名稱
- ✅ **優化用戶體驗**: 清晰的錯誤訊息和成功提示
- ✅ **增強穩定性**: 改善回滾機制的可靠性

### 技術規格
| 項目 | 版本/要求 |
|------|-----------|
| **Ansible AWX** | 24.6.1+ |
| **FortiGate OS** | v7.2+ |
| **Python** | 3.8+ |
| **Ansible Collection** | fortinet.fortios |

### 功能矩陣

| 功能 | 狀態 | 說明 |
|------|------|------|
| DHCP Reserved CREATE | ✅ | 創建新的DHCP保留地址 |
| DHCP Reserved UPDATE | ✅ | 更新既有DHCP配置 |
| Firewall Address CREATE | ✅ | 創建MAC類型Address Object |
| Firewall Address UPDATE | ✅ | 更新既有Address Object |
| Address Group Management | ✅ | 自動加入Address Group |
| 衝突檢測 | ✅ | MAC/IP/配置衝突檢測 |
| 自動回滾 | ✅ | 失敗時自動恢復配置 |
| 人工審核 | ✅ | Preview → Approval → Execute |

## 🏆 最佳實踐

### 操作建議
1. **測試環境驗證**: 建議先在測試環境執行
2. **分批處理**: 大量配置建議分批執行
3. **備份確認**: 執行前確保有完整備份
4. **權限管理**: 使用最小權限原則

### 監控建議
1. **執行日誌**: 定期檢查Workflow執行狀態
2. **錯誤分析**: 建立錯誤統計和分析機制
3. **性能監控**: 監控API響應時間和成功率


### 開發規範
- 遵循現有的命名規範
- 保持向下相容性
- 提供完整的測試案例
- 更新相關文檔

---

**版本**: v2.1  
