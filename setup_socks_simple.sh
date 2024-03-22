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
            "port": 1080,  # Socks 通常使用的端口
            "protocol": "socks",
            "settings": {
                "auth": "noauth",
                "udp": false,
                "ip": "127.0.0.1",
                "userLevel": 0
            }
        }'
OUTBOUND_TEMPLATE='        {
            "tag": "out-TAG",
            "protocol": "socks",
            "settings": {
                "servers": [{
                    "address": "127.0.0.1",
                    "port": 1234,
                    "users": [
                        {
                            "user": "test user",
                            "pass": "test pass",
                            "level": 0
                        }
                    ]
                }]
            }
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
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//TAG/$TAG_NUM}

    CONFIG_JSON+="$OUTBOUND_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 添加 routing 部分的开始
CONFIG_JSON+="\n    ],\n    \"routing\": {\n        \"rules\": [\n"

# 为每个 IP 地址添加 routing 条目
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    ROUTE_ENTRY=${ROUTE_TEMPLATE//TAG/$TAG_NUM}

    CONFIG_JSON+="$ROUTE_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# 完成配置文件的内容
CONFIG_JSON+="\n        ]\n    }\n}"

# 确保 v2ray 目录存在
mkdir -p $(dirname "$CONFIG_FILE")

# 将新的配置写入文件
echo -e "$CONFIG_JSON" > "$CONFIG_FILE"

echo "Configuration file has been created at $CONFIG_FILE"


EOF

# 添加执行权限
chmod +x ./create_v2ray_config.sh

# 执行脚本生成配置文件
./create_v2ray_config.sh

# 停止并删除已存在的容器
if [ $(docker ps -a -q -f name=test) ]; then
    echo "Stopping and removing existing v2fly container..."
    docker stop test
    docker rm test
fi

# 使用 Docker 启动 V2Ray 服务
docker run --network host -d --name test -v /root/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json

echo "V2Ray Docker container has been started."
