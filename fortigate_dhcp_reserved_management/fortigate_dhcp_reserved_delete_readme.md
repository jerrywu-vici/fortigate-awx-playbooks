我使用Ansible AWX 24.6.1版本來操作Fortigate v7.2的設備。
1. AWX設定參數
1.1 Credential Type
# Input Configuration
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

# Injector Configuration
extra_vars:
  fortigate_host: '{{ fortigate_host }}'
  fortigate_vdom: '{{ vdom }}'
  fortigate_timeout: '{{ timeout }}'
  fortigate_api_port: '{{ api_port }}'
  fortigate_access_token: '{{ fortigate_api_token }}'
  fortigate_validate_certs: '{{ validate_certs }}'

1.2
Inventory hosts
# FortiGate連接設定
ansible_connection: httpapi
ansible_network_os: fortinet.fortios.fortios
ansible_httpapi_use_ssl: true
ansible_httpapi_port: 443

# 這些值會由credential自動注入
ansible_host: "{{ fortigate_host }}"
ansible_httpapi_validate_certs: "{{ fortigate_validate_certs }}"

1.3 github playbook如附件

2. Workflow playbook是MAC刪除功能，刪除的意思實際上只是將物件還原為保留設定Reserved。
survey設計(1)要刪除的mac是什麼。(2)選擇DHCP Server ID，既有設定上只會針對server_id:2跟12做選擇，需要說明id 2=vlan40_PC，id 12=vlan22_FIC_WAN讓使用者能看到
接下來說明刪除功能的設計
1.1 先搜尋既有設定是否有找到使用者貼的mac，如果沒有找到則停止執行並輸出說明目前並沒有這個mac設定
2.2 如果搜尋既有設定有找到使用者貼的mac，則先列出目前的設定並讓使用者手動確認是否繼續執行將找到的物件還原為保留設定
2.3 假設下面是既有設定
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
使用者貼的mac是00:25:bb:bb:01:03，會找到物件id 3有這個mac，然後將設定還原為保留。
還原設定的範例如下:
            edit 3
                set ip 192.168.250.103
                set mac ff:ff:ff:ff:f1:03
                set description "Reserved"
            next
這邊逐步說明每個設定還原的規則。
(1)先根據找到的物件id 3裡面IP是192.168.250.103，所以必須將mac還原為ff:ff:ff:ff:f1:03，規則就是根據IP第四碼103，103總共3個字會套用到mac位址最後三個字還原為ff:ff:ff:ff:f1:03，剩下前面9碼都是f 原則上mac位址前9個字都會是f，除非IP第四碼數字是"0到99"，不過不用擔心因為既有設定的IP第四碼都會是"100到250" 。
正確的MAC還原規則說明
IP第四碼: 192.168.250.103 → 取出 "103" (三位數字)
MAC格式: ff:ff:ff:ff:fX:XX
分解規則:
X = IP第四碼的第一位數字 → "103" → "1"
XX = IP第四碼的後兩位數字 → "103" → "03"
最終MAC: ff:ff:ff:ff:f1:03
(2)description 一律還原為"Reserved"

3. 建立Job Templates
3.1 Preview Job Template
Name: FortiGate DHCP Reserved Delete - Preview
Playbook: fortigate_dhcp_reserved_delete_preview_for_workflow.yml
Credentials: FortiGate Production
Survey: 不需要
3.2 Execute Job Template
Name: FortiGate DHCP Reserved Delete - Execute
Playbook: fortigate_dhcp_reserved_delete_execute_for_workflow.yml
Credentials: FortiGate Production
Survey: 不需要
3.3建立Workflow Template
Name: Workflow-FortiGate DHCP Reserved Delete with Approval
Survey:
問題1: 要刪除的MAC地址
問題2: 選擇DHCP Server ID
3.4 設定Workflow Nodes
[START] → [Preview Job] → [Approval Node] → [Execute Job] → [END]
                ↓              ↓              
           [On Failure]   [On Denied/Timeout]
                ↓              ↓
              [END]          [END]

4. 使用流程
啟動Workflow
填入Survey: MAC地址 + 選擇DHCP Server ID
查看Preview: 檢視要刪除的配置詳情
人工確認: 在Approval Node中批准或拒絕
自動執行: 批准後自動執行刪除操作
檢視結果: 查看最終執行摘要
