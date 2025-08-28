Ansible AWX FortiGate DHCP Reserved Delete 配置文檔
我使用 Ansible AWX 24.6.1 版本來操作 FortiGate v7.2 的設備。

1. AWX 設定參數
1.1 Credential Type
Input Configuration
yaml
複製程式碼
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
Injector Configuration
yaml
複製程式碼
extra_vars:
  fortigate_host: '{{ fortigate_host }}'
  fortigate_vdom: '{{ vdom }}'
  fortigate_timeout: '{{ timeout }}'
  fortigate_api_port: '{{ api_port }}'
  fortigate_access_token: '{{ fortigate_api_token }}'
  fortigate_validate_certs: '{{ validate_certs }}'
1.2 Inventory Hosts
FortiGate 連接設定
yaml
複製程式碼
ansible_connection: httpapi
ansible_network_os: fortinet.fortios.fortios
ansible_httpapi_use_ssl: true
ansible_httpapi_port: 443
這些值會由 credential 自動注入
yaml
複製程式碼
ansible_host: "{{ fortigate_host }}"
ansible_httpapi_validate_certs: "{{ fortigate_validate_certs }}"
1.3 GitHub Playbook
如附件

2. Workflow 設計說明
Workflow playbook 是 MAC 刪除功能，刪除的意思實際上只是將物件還原為保留設定 Reserved。

Survey 設計
要刪除的 MAC 是什麼
選擇 DHCP Server ID，既有設定上只會針對 server_id:2 跟 12 做選擇，需要說明：
ID 2 = vlan40_PC
ID 12 = vlan22_FIC_WAN
讓使用者能看到對應關係。

3. 刪除功能的設計
3.1 搜尋驗證
先搜尋既有設定是否有找到使用者貼的 MAC，如果沒有找到則停止執行並輸出說明目前並沒有這個 MAC 設定。

3.2 確認流程
如果搜尋既有設定有找到使用者貼的 MAC，則先列出目前的設定並讓使用者手動確認是否繼續執行將找到的物件還原為保留設定。

3.3 設定範例
假設下面是既有設定：

vbnet
複製程式碼
config system dhcp server
    edit 2
        config reserved-address
            edit 1
                set ip 192.168.250.100
                set mac 00:25:90:f4:10:62
                set description "Super-Win10"
            next
            edit 2
                set ip 192.168.250.101
                set mac ff:ff:ff:ff:f1:01
                set description "Reserved"
            next
            edit 3
                set ip 192.168.250.103
                set mac 00:25:bb:bb:01:03
                set description "test103_PC_updated"
            next
        end
    next
end
使用者貼的 MAC 是 00:25:bb:bb:01:03，會找到物件 ID 3 有這個 MAC，然後將設定還原為保留。

還原設定的範例如下：

python
執行程式碼
複製程式碼
edit 3
    set ip 192.168.250.103
    set mac ff:ff:ff:ff:f1:03
    set description "Reserved"
next
3.4 還原規則說明
逐步說明每個設定還原的規則：

(1) MAC 位址還原規則
先根據找到的物件 ID 3 裡面 IP 是 192.168.250.103
必須將 MAC 還原為 ff:ff:ff:ff:f1:03
規則就是根據 IP 第四碼 103，103 總共 3 個字會套用到 MAC 位址最後三個字
還原為 ff:ff:ff:ff:f1:03，剩下前面 9 碼都是 f
注意： 原則上 MAC 位址前 9 個字都會是 f，除非 IP 第四碼數字是 "0到99"，不過不用擔心因為既有設定的 IP 第四碼都會是 "100到250"。

正確的 MAC 還原規則說明：
IP 第四碼： 192.168.250.103 → 取出 "103" (三位數字)
MAC 格式： ff:ff:ff:ff:fX:XX
分解規則：
X = IP 第四碼的第一位數字 → "103" → "1"
XX = IP 第四碼的後兩位數字 → "103" → "03"
最終 MAC： ff:ff:ff:ff:f1:03
(2) Description 還原
Description 一律還原為 "Reserved"

4. 建立 Job Templates
4.1 Preview Job Template
Name: FortiGate DHCP Reserved Delete - Preview
Playbook: fortigate_dhcp_reserved_delete_preview_for_workflow.yml
Credentials: FortiGate Production
Survey: 不需要
4.2 Execute Job Template
Name: FortiGate DHCP Reserved Delete - Execute
Playbook: fortigate_dhcp_reserved_delete_execute_for_workflow.yml
Credentials: FortiGate Production
Survey: 不需要
4.3 建立 Workflow Template
Name: Workflow-FortiGate DHCP Reserved Delete with Approval
Survey:
問題1: 要刪除的MAC地址
問題2: 選擇DHCP Server ID
4.4 設定 Workflow Nodes
css
複製程式碼
[START] → [Preview Job] → [Approval Node] → [Execute Job] → [END]
            ↓                    ↓
        [On Failure]      [On Denied/Timeout]
            ↓                    ↓
          [END]                [END]
5. 使用流程
啟動 Workflow
填入 Survey: MAC地址 + 選擇DHCP Server ID
查看 Preview: 檢視要刪除的配置詳情
人工確認: 在 Approval Node 中批准或拒絕
自動執行: 批准後自動執行刪除操作
檢視結果: 查看最終執行摘要
