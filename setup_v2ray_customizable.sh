#!/bin/bash

# 更新系统并安装 Docker
sudo apt update && sudo apt upgrade -y
sudo apt install docker.io -y
# 如果你想使用 snap 安装 Docker，可以取消下面两行的注释
# sudo snap refresh snapd
# sudo snap install docker

# 拉取 v2fly 的 Docker 镜像
docker pull v2fly/v2fly-core

# 创建配置文件目录
mkdir -p /root/v2ray/

# 创建 create_v2ray_config.sh 脚本
cat << 'EOF' > /root/create_v2ray_config.sh
#!/bin/bash

# 用户输入
read -p "Enter port [12345]: " PORT
PORT=${PORT:-12345}

read -p "Enter ID [00000000-0000-0000-0000-000000000000]: " ID
ID=${ID:-00000000-0000-0000-0000-000000000000}

read -p "Enter encryption method (tcp or ws) [tcp]: " ENCRYPTION
ENCRYPTION=${ENCRYPTION:-tcp}

# 根据加密方式选择，初始化变量
V2RAY_PATH="/"
HOST=""

# 如果选择了ws加密方式，进一步获取path和host的配置
if [ "$ENCRYPTION" == "ws" ]; then
    read -p "Enter path [/path_test]: " V2RAY_PATH
    V2RAY_PATH=${V2RAY_PATH:-/path_test}

    read -p "Enter host [vmess_ws_test]: " HOST
    HOST=${HOST:-vmess_ws_test}
fi

# 定义配置文件的路径
CONFIG_FILE="/root/v2ray/config.json"

# 自动获取本机IP地址，排除本地回环地址和docker内部网络地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\."))

# 初始化配置文件的内容
CONFIG_JSON="{\n    \"inbounds\": [\n"

# 根据加密方式调整 INBOUND_TEMPLATE
if [ "$ENCRYPTION" == "ws" ]; then
    INBOUND_TEMPLATE='        {
                "tag": "in-TAG",
                "listen": "IP_ADDRESS",
                "port": PORT,
                "protocol": "vmess",
                "settings": {
                    "clients": [
                        {
                            "id": "ID"
                        }
                    ]
                },
                "streamSettings": {
                    "network": "ws",
                    "wsSettings": {
                        "path": "V2RAY_PATH_IN",
                        "headers": {
                            "Host": "HOST"
                        }
                    }
                }
            }'
elif [ "$ENCRYPTION" == "tcp" ]; then
    INBOUND_TEMPLATE='        {
                "tag": "in-TAG",
                "listen": "IP_ADDRESS",
                "port": PORT,
                "protocol": "vmess",
                "settings": {
                    "clients": [
                        {
                            "id": "ID"
                        }
                    ]
                }
            }'
else
    echo "Error: Invalid encryption method. Please choose 'tcp' or 'ws'."
    exit 1
fi

INBOUND_TEMPLATE=${INBOUND_TEMPLATE//PORT/$PORT}
INBOUND_TEMPLATE=${INBOUND_TEMPLATE//ID/$ID}
INBOUND_TEMPLATE=${INBOUND_TEMPLATE//V2RAY_PATH_IN/$V2RAY_PATH}
INBOUND_TEMPLATE=${INBOUND_TEMPLATE//HOST/$HOST}

# 为每个 IP 地址生成 inbounds 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    INBOUND_ENTRY=${INBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    INBOUND_ENTRY=${INBOUND_ENTRY//TAG/$TAG_NUM}

    # 添加当前条目到配置
    CONFIG_JSON+="$INBOUND_ENTRY"

    # 如果当前条目不是最后一个，则添加逗号和换行符
    if [ $((i+1)) -lt ${#IP_ADDRESSES[@]} ]; then
        CONFIG_JSON+=",\n"
    else
        CONFIG_JSON+="\n"
    fi
done

# 添加 outbounds 部分的开始
CONFIG_JSON+="    ],\n    \"outbounds\": [\n        {
            \"protocol\": \"freedom\",
            \"settings\": {}
        }\n    ]\n}"

# 将新的配置写入文件
echo -e "$CONFIG_JSON" > "$CONFIG_FILE"


echo "Configuration file has been created at $CONFIG_FILE"
EOF

# 添加执行权限
chmod +x /root/create_v2ray_config.sh

# 执行脚本生成配置文件
/root/create_v2ray_config.sh

# 停止并删除已存在的容器
if [ $(docker ps -a -q -f name=v2fly) ]; then
    echo "Stopping and removing existing v2fly container..."
    docker stop v2fly
    docker rm v2fly
fi

# 使用 Docker 启动 V2Ray 服务
docker run --network host -d --name v2fly -v /root/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json

echo "V2Ray Docker container has been started."
