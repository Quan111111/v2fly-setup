#!/bin/bash

# 检测操作系统类型
if [ -f /etc/os-release ]; then
    # 使用 freedesktop.org 和 systemd 的方式
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # 使用 linuxbase.org 的方式
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # 用于一些没有 lsb_release 命令的 Debian/Ubuntu 版本
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # 旧版 Debian/Ubuntu 等
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # 旧版 SuSE 等
    ...
elif [ -f /etc/redhat-release ]; then
    # 旧版 Red Hat, CentOS 等
    ...
else
    # 使用 uname 作为后备，比如 "Linux <版本>"，也适用于 BSD 等
    OS=$(uname -s)
    VER=$(uname -r)
fi

# 处理 Ubuntu 和 Debian 中 APT 锁定问题的函数
handle_apt_lock() {
    echo "APT 被另一个进程锁定。尝试修复中..."
    
    # 查找并强制结束所有 apt-get 和 dpkg 进程
    sudo pkill -9 apt-get
    sudo pkill -9 dpkg
    
    echo "清理锁文件中..."
    # 尝试删除锁文件，但请小心使用
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/dpkg/lock-frontend

    echo "重新配置软件包中..."
    sudo dpkg --configure -a

    echo "重试更新和安装操作中..."
}

# 将更新和安装操作封装为一个函数
update_pkg() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        # sudo apt-get update && sudo apt-get upgrade -y
        sudo apt-get update
    elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Fedora" ]]; then
        sudo yum update -y
        # CentOS 8 及以上版本可能需要使用 dnf
        # sudo dnf update -y
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
        echo "不支持安装 Docker 的操作系统"
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
mkdir -p /root/socks/

# 创建配置文件脚本
cat << 'EOF' >./create_socks_config.sh
#!/bin/bash

# 用户定义的配置文件路径
CONFIG_FILE="/root/socks/config_s.json"

# 自动获取本机 IP 地址，排除本地回环地址、docker 内部网络地址和以10开头的私有IP地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\.|^10\.")) 

# 定义 vmess 出站的目标服务器信息
VMESS_TARGET_PORT=12345
VMESS_USER_ID="00000000-0000-0000-0000-000000000000"
SOCKS_PORT=18200

# 初始化配置文件内容
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

# 为每个 IP 地址生成入站条目
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

# 添加出站部分的开始
CONFIG_JSON+="\n    ],\n    \"outbounds\": [\n"

# 为每个 IP 地址生成出站条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//TAG/$TAG_NUM}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_TARGET_ADDRESS/${IP_ADDRESSES[$i]}} # 使用相同的 IP 作为目标地址
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_TARGET_PORT/$VMESS_TARGET_PORT}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//VMESS_USER_ID/$VMESS_USER_ID}

    CONFIG_JSON+="$OUTBOUND_ENTRY"
    # 如果当前条目不是最后一个，则添加逗号和换行符
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 添加路由部分的开始
CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"rules\": [\n"

# 为每个 IP 地址添加路由条目
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

echo "配置文件已创建在 $CONFIG_FILE"

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
    SOCKS_INFO="$IP_ADDRESS\t$PORT_NUM\t$USER\t$PASS"
    echo -e "$SOCKS_INFO" >> "$SHARE_SOCKS_INFO_FILE"
done

echo "V2Ray Socks 信息已保存到 $SHARE_SOCKS_INFO_FILE"


# 初始化 V2Ray Socks 加密分享链接文件
SHARE_SOCKS_BASE64_FILE="/root/socks/share_socks_base64.txt"
echo "" > "$SHARE_SOCKS_BASE64_FILE"  # 清空旧的分享链接文件内容

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    PORT_NUM=$((${SOCKS_PORT} + i)) # 假设端口号基于此规则生成
    USER="user-$TAG_NUM"
    PASS="pass-$TAG_NUM"
    IP_ADDRESS=${IP_ADDRESSES[$i]}
    REMARK="IP$i" # 备注信息

    # 对用户名:密码进行 Base64 编码
    UP_ENCODED=$(echo -n "${USER}:${PASS}" | base64)
    
    # 对备注进行 URL 编码
    REMARK_ENCODED=$(echo -n "${REMARK}" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
    
    # 构建并写入 V2Ray Socks 分享链接
    SOCKS_LINK="socks://${UP_ENCODED}@${IP_ADDRESS}:${PORT_NUM}#${REMARK_ENCODED}"
    echo "$SOCKS_LINK" >> "$SHARE_SOCKS_BASE64_FILE"
done


echo "V2Ray Socks 分享链接（Base64 编码）已保存到 $SHARE_SOCKS_BASE64_FILE"


EOF

# 添加执行权限
chmod +x ./create_socks_config.sh

# 执行脚本生成配置文件
./create_socks_config.sh

# 停止并删除已存在的容器
if [ $(docker ps -a -q -f name=test_s) ]; then
    echo "停止并删除现有的 'test_s' v2fly 容器中..."
    docker stop test_s
    docker rm test_s
fi

# 使用 Docker 启动 socks 服务
docker run --network host -d --name test_s -v /root/socks/config_s.json:/etc/socks/config_s.json v2fly/v2fly-core run -c /etc/socks/config_s.json

echo "socks Docker 容器已启动。"

# 添加脚本到开机启动
add_to_startup() {
    local script_path="$1"
    # 在脚本路径前加上 sleep 60 && 来实现开机后延时60秒执行
    local cron_entry="@reboot sleep 60 && /bin/bash $script_path"

    # 检查 crontab 是否已经包含了这一行
    if crontab -l | grep -Fq "/bin/bash $script_path"; then
        echo "脚本 $script_path 已经在开机启动中了，不会重复添加。"
    else
        # 使用 crontab 将脚本添加到开机启动
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "脚本 $script_path 已添加到开机启动，将在启动后60秒执行。"
    fi
}

# 脚本路径
script1="/root/setup_socks_simple.sh"

# 添加脚本到开机启动
add_to_startup "$script1"
