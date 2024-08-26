#!/bin/bash

# 检测操作系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    ...
elif [ -f /etc/redhat-release ]; then
    ...
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

# 处理APT锁定问题的函数
handle_apt_lock() {
    echo "APT 被其他进程锁定。正在尝试修复..."
    sudo pkill -9 apt-get
    sudo pkill -9 dpkg
    echo "清理锁文件..."
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/dpkg/lock-frontend
    echo "重新配置软件包..."
    sudo dpkg --configure -a
    echo "重试更新和安装..."
}

# 封装更新和安装操作为一个函数
update_pkg() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get update
    elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Fedora" ]]; then
        sudo yum update -y
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 安装 Docker
install_docker() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get install docker.io -y
    elif [[ "$OS" == "CentOS Linux" ]]; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
    elif [[ "$OS" == "Fedora" ]]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        echo "不支持的操作系统安装 Docker"
        exit 1
    fi
}

# 尝试更新
update_pkg

# 安装 Docker
install_docker

# 拉取 v2fly 的 Docker 镜像
docker pull v2fly/v2fly-core

# 创建配置文件目录
mkdir -p /root/v2ray/
mkdir -p /root/socks/

# 配置文件路径
V2RAY_CONFIG_FILE="/root/v2ray/config.json"
SOCKS_CONFIG_FILE="/root/socks/config_s.json"

# 获取 IP 地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk '{print \$2}' | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\.|^10\."))

# 生成 UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 初始化 V2Ray 配置
V2RAY_CONFIG_JSON="{\n    \"inbounds\": [\n"
INBOUND_TEMPLATE='        {
            "tag": "in-TAG",
            "listen": "IP_ADDRESS",
            "port": 12345,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "UUID"
                    }
                ]
            }
        }'
OUTBOUND_TEMPLATE='        {
            "tag": "out-TAG",
            "sendThrough": "IP_ADDRESS",
            "protocol": "freedom"
        }'
ROUTE_TEMPLATE='            {
                "type": "field",
                "inboundTag": "in-TAG",
                "outboundTag": "out-TAG"
            }'

declare -A UUID_MAP

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    UUID=$(generate_uuid)
    UUID_MAP[${IP_ADDRESSES[$i]}]=$UUID
    INBOUND_ENTRY=${INBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    INBOUND_ENTRY=${INBOUND_ENTRY//TAG/$TAG_NUM}
    INBOUND_ENTRY=${INBOUND_ENTRY//UUID/$UUID}
    V2RAY_CONFIG_JSON+="$INBOUND_ENTRY"
    if [ $((i+1)) -lt ${#IP_ADDRESSES[@]} ]; then
        V2RAY_CONFIG_JSON+=",\n"
    else
        V2RAY_CONFIG_JSON+="\n"
    fi
done

V2RAY_CONFIG_JSON+="    ],\n    \"outbounds\": [\n"

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//TAG/$TAG_NUM}
    V2RAY_CONFIG_JSON+="$OUTBOUND_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        V2RAY_CONFIG_JSON+=",\n"
    fi
done

V2RAY_CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"domainStrategy\": \"IPOnDemand\",\n        \"rules\": [\n"

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    ROUTE_ENTRY=${ROUTE_TEMPLATE//TAG/$TAG_NUM}
    V2RAY_CONFIG_JSON+="$ROUTE_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        V2RAY_CONFIG_JSON+=",\n"
    fi
done

V2RAY_CONFIG_JSON+="\n        ]\n    },\n    \"dns\": {\n        \"servers\": [\n            \"8.8.8.8\",\n            \"1.1.1.1\"\n        ]\n    }\n}"
V2RAY_CONFIG_JSON+="\n}"

echo -e "$V2RAY_CONFIG_JSON" > "$V2RAY_CONFIG_FILE"
echo "V2Ray 配置文件已创建在 $V2RAY_CONFIG_FILE"

# 初始化 SOCKS 配置
SOCKS_CONFIG_JSON="{\n    \"inbounds\": [\n"
SOCKS_PORT=18200
SOCKS_INBOUND_TEMPLATE='        {
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
SOCKS_OUTBOUND_TEMPLATE='        {
            "tag": "vmess-out-TAG",
            "sendThrough": "IP_ADDRESS",
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": "IP_ADDRESS",
                        "port": 12345,
                        "users": [
                            {
                                "id": "UUID",
                                "alterId": 0,
                                "security": "auto"
                            }
                        ]
                    }
                ]
            }
        }'
SOCKS_ROUTE_TEMPLATE='            {
                "type": "field",
                "inboundTag": "socks-in-TAG",
                "outboundTag": "vmess-out-TAG"
            }'

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    PORT_NUM=$((${SOCKS_PORT} + i))
    UUID=${UUID_MAP[${IP_ADDRESSES[$i]}]}
    SOCKS_INBOUND_ENTRY=${SOCKS_INBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    SOCKS_INBOUND_ENTRY=${SOCKS_INBOUND_ENTRY//TAG/$TAG_NUM}
    SOCKS_INBOUND_ENTRY=${SOCKS_INBOUND_ENTRY//PORT_NUM/$PORT_NUM}
    SOCKS_CONFIG_JSON+="$SOCKS_INBOUND_ENTRY"
    if [ $((i+1)) -lt ${#IP_ADDRESSES[@]} ]; then
        SOCKS_CONFIG_JSON+=",\n"
    else
        SOCKS_CONFIG_JSON+="\n"
    fi
done

SOCKS_CONFIG_JSON+="    ],\n    \"outbounds\": [\n"

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    UUID=${UUID_MAP[${IP_ADDRESSES[$i]}]}
    SOCKS_OUTBOUND_ENTRY=${SOCKS_OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    SOCKS_OUTBOUND_ENTRY=${SOCKS_OUTBOUND_ENTRY//TAG/$TAG_NUM}
    SOCKS_OUTBOUND_ENTRY=${SOCKS_OUTBOUND_ENTRY//UUID/$UUID}
    SOCKS_CONFIG_JSON+="$SOCKS_OUTBOUND_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        SOCKS_CONFIG_JSON+=",\n"
    fi
done

SOCKS_CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"rules\": [\n"

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    SOCKS_ROUTE_ENTRY=${SOCKS_ROUTE_TEMPLATE//TAG/$TAG_NUM}
    SOCKS_CONFIG_JSON+="$SOCKS_ROUTE_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        SOCKS_CONFIG_JSON+=",\n"
    fi
done

SOCKS_CONFIG_JSON+="\n        ]\n    }\n}"

echo -e "$SOCKS_CONFIG_JSON" > "$SOCKS_CONFIG_FILE"
echo "SOCKS 配置文件已创建在 $SOCKS_CONFIG_FILE"

# 启动 V2Ray 容器
if [ $(docker ps -a -q -f name=test_v) ]; then
    echo "停止并删除现有的 v2fly 容器..."
    docker stop test_v
    docker rm test_v
fi

docker run --network host -d --name test_v -v /root/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json

echo "V2Ray Docker 容器已启动."

# 启动 SOCKS 容器
if [ $(docker ps -a -q -f name=test_s) ]; then
    echo "停止并删除现有的 socks 容器..."
    docker stop test_s
    docker rm test_s
fi

docker run --network host -d --name test_s -v /root/socks/config_s.json:/etc/socks/config_s.json v2fly/v2fly-core run -c /etc/socks/config_s.json

echo "SOCKS Docker 容器已启动."

# 添加脚本到开机启动
add_to_startup() {
    local script_path="\$1"
    local cron_entry="@reboot sleep 60 && /bin/bash $script_path"
    if crontab -l | grep -Fq "/bin/bash $script_path"; then
        echo "脚本 $script_path 已经在开机启动中了，不会重复添加。"
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "脚本 $script_path 已添加到开机启动，将在启动后60秒执行。"
    fi
}

script_path="/root/setup_v2ray_socks.sh"
add_to_startup "$script_path"

rm /root/setup_v2ray_socks.sh
echo "Deleted current script."
