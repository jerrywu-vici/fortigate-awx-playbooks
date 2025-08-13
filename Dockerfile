# 使用 AWX 預設的 EE 作為基礎映像檔，確保包含 AWX 執行所需的工具。
FROM ghcr.io/ansible/awx-ee:latest

# 切換到 AWX 的工作目錄
WORKDIR /usr/bin/

# 安裝 Ansible Collections
# 這個指令會自動讀取 requirements.yml 檔案並安裝裡面的 Collections
COPY requirements.yml .
RUN ansible-galaxy collection install -r requirements.yml --collections-path /usr/share/ansible/collections

# 你也可以在這裡安裝其他的 Python Library
# RUN pip3 install <your_python_library>
