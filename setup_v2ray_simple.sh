#!/bin/bash

# 检测操作系统类型
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    ...
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    ...
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Ubuntu和Debian中处理APT锁定问题的函数
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

# 封装更新和安装操作为一个函数
update_pkg() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get update && sudo apt-get upgrade -y
    elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Fedora" ]]; then
        sudo yum update -y
        # CentOS 8及以上版本可能需要使用dnf
        # sudo dnf update -y
    else
        echo "Unsupported OS"
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
        # 启动 Docker 服务
        sudo systemctl start docker
        sudo systemctl enable docker
    elif [[ "$OS" == "Fedora" ]]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
        # 启动 Docker 服务
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        echo "Unsupported OS for Docker installation"
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

# 创建 create_v2ray_config.sh 脚本
cat << 'EOF' > ./create_v2ray_config.sh
#!/bin/bash

# 定义配置文件的路径
CONFIG_FILE="/root/v2ray/config.json"

# 自动获取本机IP地址，排除本地回环地址和docker内部网络地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\."))

# 初始化配置文件的内容
CONFIG_JSON="{\n    \"inbounds\": [\n"
INBOUND_TEMPLATE='        {
            "tag": "in-TAG",
            "listen": "IP_ADDRESS",
            "port": 12345,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "00000000-0000-0000-0000-000000000000"
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
CONFIG_JSON+="    ],\n    \"outbounds\": [\n"

# 为每个 IP 地址添加 outbounds 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//TAG/$TAG_NUM}

    CONFIG_JSON+="$OUTBOUND_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 添加 routing 部分的开始，包括 domainStrategy 的配置
CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"domainStrategy\": \"IPOnDemand\",\n        \"rules\": [\n"

# 为每个 IP 地址添加 routing 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    ROUTE_ENTRY=${ROUTE_TEMPLATE//TAG/$TAG_NUM}

    CONFIG_JSON+="$ROUTE_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 完成 routing 配置并添加 dns 配置项
CONFIG_JSON+="\n        ]\n    },\n    \"dns\": {\n        \"servers\": [\n            \"8.8.8.8\",\n            \"1.1.1.1\"\n        ]\n    }\n}"

# 完成配置文件的内容
CONFIG_JSON+="\n}"


# 确保 v2ray 目录存在
mkdir -p $(dirname "$CONFIG_FILE")

# 将新的配置写入文件
echo -e "$CONFIG_JSON" > "$CONFIG_FILE"

echo "Configuration file has been created at $CONFIG_FILE"

# 定义vmess出站的目标服务器信息
VMESS_TARGET_PORT=12345
VMESS_USER_ID="00000000-0000-0000-0000-000000000000"
SOCKS_PORT=18200

# 初始化V2Ray加密分享链接文件
SHARE_V2RAY_BASE64_FILE="/root/v2ray/share_v2ray_base64.txt"
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

EOF

# 添加执行权限
chmod +x ./create_v2ray_config.sh

# 执行脚本生成配置文件
./create_v2ray_config.sh

# 停止并删除已存在的容器
if [ $(docker ps -a -q -f name=test_v) ]; then
    echo "Stopping and removing existing v2fly container..."
    docker stop test_v
    docker rm test_v
fi

# 使用 Docker 启动 V2Ray 服务
docker run --network host -d --name test_v -v /root/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json

echo "V2Ray Docker container has been started."

# 添加脚本到开机启动
add_to_startup() {
    local script_path="$1"
    # 使用 crontab 将脚本添加到开机启动
    (crontab -l ; echo "@reboot /bin/bash $script_path") | crontab -
    echo "脚本 $script_path 已添加到开机启动"
}

# 脚本路径
script1="/root/setup_v2ray_simple.sh"

# 添加脚本到开机启动
add_to_startup "$script1"
