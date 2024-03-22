#!/bin/bash

# 封装更新和安装操作为一个函数
update_pkg() {
    sudo apt-get update && sudo apt-get upgrade -y
}

# 处理APT锁定问题的函数
handle_apt_lock() {
    echo "APT is locked by another process. Attempting to fix..."

    # 查找并强制结束所有apt-get和dpkg进程
    sudo pkill -9 apt-get
    sudo pkill -9 dpkg

    echo "Cleaning up lock files..."
    # 尝试删除锁文件，但请小心使用
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/dpkg/lock-frontend

    echo "Reconfiguring packages..."
    sudo dpkg --configure -a

    echo "Retrying update and install..."
}

# 尝试更新和安装，如果失败，则处理APT锁定问题
if ! update_pkg; then
    handle_apt_lock
    update_pkg
fi

# 安装docker
sudo apt-get install docker.io -y

# 拉取 v2fly 的 Docker 镜像
docker pull v2fly/v2fly-core

# 创建配置文件目录
mkdir -p /root/socks/

# 创建 create_socks_config.sh 脚本
cat <<'EOF' >./create_socks_config.sh
#!/bin/bash

# 定义配置文件的路径
CONFIG_FILE="/root/socks/config_s.json"

# 自动获取本机IP地址，排除本地回环地址和docker内部网络地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\."))

# 定义vmess出站的目标服务器信息
VMESS_TARGET_PORT=12345
VMESS_USER_ID="00000000-0000-0000-0000-000000000000"
SOCKS_PORT=18200

# 初始化配置文件的内容
CONFIG_JSON="{\n    \"inbounds\": [\n"
INBOUND_TEMPLATE='        {
            "tag": "socks-in-TAG",
            "protocol": "socks",
            "port": PORT_NUM,
            "listen": "IP_ADDRESS",
            "settings": {
                "auth": "password",
                "accounts": [
                    {
                        "user": "user-TAG",
                        "pass": "pass-TAG"
                    }
                ],
                "udp": true,
                "ip": "IP_ADDRESS",
                "userLevel": 0
            }
        }'
OUTBOUND_TEMPLATE='        {
            "tag": "vmess-out-TAG",
            "sendThrough": "IP_ADDRESS",
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": "VMESS_TARGET_ADDRESS",
                        "port": VMESS_TARGET_PORT,
                        "users": [
                            {
                                "id": "VMESS_USER_ID",
                                "alterId": 0,
                                "security": "auto"
                            }
                        ]
                    }
                ]
            }
        }'
ROUTE_TEMPLATE='            {
                "type": "field",
                "inboundTag": "socks-in-TAG",
                "outboundTag": "vmess-out-TAG"
            }'

# 为每个 IP 地址生成 inbounds 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    PORT_NUM=$((${SOCKS_PORT} + i)) # 定义每个入站端口
    INBOUND_ENTRY=${INBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    INBOUND_ENTRY=${INBOUND_ENTRY//TAG/$TAG_NUM}
    INBOUND_ENTRY=${INBOUND_ENTRY//PORT_NUM/$PORT_NUM}

    # 添加当前条目到配置
    CONFIG_JSON+="$INBOUND_ENTRY"

    # 如果当前条目不是最后一个，则添加逗号和换行符
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 添加 outbounds 部分的开始
CONFIG_JSON+="\n    ],\n    \"outbounds\": [\n"

# 为每个 IP 地址生成 outbounds 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//TAG/$TAG_NUM}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_TARGET_ADDRESS/${IP_ADDRESSES[$i]}} # 使用相同的IP作为目标地址
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_TARGET_PORT/$VMESS_TARGET_PORT}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_USER_ID/$VMESS_USER_ID}

    CONFIG_JSON+="$OUTBOUND_ENTRY"
    # 如果当前条目不是最后一个，则添加逗号和换行符
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 添加 routing 部分的开始
CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"rules\": [\n"

# 为每个 IP 地址添加 routing 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    ROUTE_ENTRY=${ROUTE_TEMPLATE//TAG/$TAG_NUM}
    CONFIG_JSON+="$ROUTE_ENTRY"

    # 如果当前条目不是最后一个，则添加逗号和换行符
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 完成配置文件的内容
CONFIG_JSON+="\n        ]\n    }\n}"

# 确保 socks 目录存在
mkdir -p $(dirname "$CONFIG_FILE")

# 将新的配置写入文件
echo -e "$CONFIG_JSON" >"$CONFIG_FILE"

echo "Configuration file has been created at $CONFIG_FILE"




# 初始化V2Ray加密分享链接文件
SHARE_V2RAY_BASE64_FILE="/root/socks/share_v2ray_base64.txt"
echo "" > "$SHARE_V2RAY_BASE64_FILE"  # 清空旧的分享链接文件内容

# 生成并追加每个IP地址的V2Ray分享链接到文件
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    IP_ADDRESS=${IP_ADDRESSES[$i]}
    
    # 构造VMess链接的JSON部分
    VMESS_JSON=$(cat <<EOF_IN
{
  "v": "2",
  "ps": "vmess_${IP_ADDRESS}",
  "add": "${IP_ADDRESS}",
  "port": "${VMESS_TARGET_PORT}",
  "id": "${VMESS_USER_ID}",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF_IN
)

    # 使用Base64编码VMess JSON配置
    BASE64_VMESS=$(echo -n "$VMESS_JSON" | base64 | tr -d '\n')
    
    # 构建并写入V2Ray VMess链接
    VMESS_LINK="vmess://${BASE64_VMESS}"
    echo "$VMESS_LINK" >> "$SHARE_V2RAY_BASE64_FILE"
done

echo "V2Ray VMess share links(base64 encode) have been saved to $SHARE_V2RAY_BASE64_FILE"




# 初始化V2Ray Socks信息文件
SHARE_SOCKS_INFO_FILE="/root/socks/share_socks_info.txt"
echo "" > "$SHARE_SOCKS_INFO_FILE"  # 清空旧的分享链接文件内容

# 生成并追加每个IP地址的V2Ray Socks分享信息到文件
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    PORT_NUM=$((${SOCKS_PORT} + i)) # 与Socks代理端口保持一致
    USER="user-$TAG_NUM"
    PASS="pass-$TAG_NUM"
    IP_ADDRESS=${IP_ADDRESSES[$i]}
    
    # 构建并写入分享信息
    SOCKS_INFO="$IP_ADDRESS\t$PORT_NUM\t$USER\t$PASS\n"
    echo -e "$SOCKS_INFO" >> "$SHARE_SOCKS_INFO_FILE"
done

echo "V2Ray Socks share information has been saved to $SHARE_SOCKS_INFO_FILE"




# 初始化V2Ray Socks加密分享链接文件
SHARE_SOCKS_BASE64_FILE="/root/socks/share_socks_base64.txt"
echo "" > "$SHARE_SOCKS_BASE64_FILE"  # 清空旧的分享链接文件内容

# 生成并追加每个IP地址的V2Ray Socks分享链接到文件
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    PORT_NUM=$((${SOCKS_PORT} + i)) # 假设端口号基于此规则生成
    USER="user-$TAG_NUM"
    PASS="pass-$TAG_NUM"
    IP_ADDRESS=${IP_ADDRESSES[$i]}
    REMARK=("IP"+i) # 备注信息

    # 对用户名:密码进行Base64编码
    UP_ENCODED=$(echo -n "${USER}:${PASS}" | base64)
    
    # 对备注进行URL编码
    REMARK_ENCODED=$(echo -n "${REMARK}" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
    
    # 构建并写入V2Ray Socks分享链接
    SOCKS_LINK="socks://${UP_ENCODED}@${IP_ADDRESS}:${PORT_NUM}#${REMARK_ENCODED}"
    echo "$SOCKS_LINK" >> "$SHARE_SOCKS_BASE64_FILE"
done

echo "V2Ray Socks share links(base64 encode) have been saved to $SHARE_SOCKS_BASE64_FILE"



EOF

# 添加执行权限
chmod +x ./create_socks_config.sh

# 执行脚本生成配置文件
./create_socks_config.sh

# 停止并删除已存在的容器
if [ $(docker ps -a -q -f name=test_s) ]; then
    echo "Stopping and removing existing 'test_s' v2fly container..."
    docker stop test_s
    docker rm test_s
fi

# 使用 Docker 启动 socks 服务
docker run --network host -d --name test_s -v /root/socks/config_s.json:/etc/socks/config_s.json v2fly/v2fly-core run -c /etc/socks/config_s.json

echo "socks Docker container has been started."
