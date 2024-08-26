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
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

# 安装 Docker
install_docker() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get update
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
V2RAY_SHARE_LINK_FILE="/root/v2ray/share_v2ray_base64.txt"
SOCKS_SHARE_LINK_FILE="/root/v2ray/share_socks_base64.txt"

# 获取 IP 地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\.|^10\."))

# 生成 UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 初始化 V2Ray 配置
V2RAY_CONFIG_JSON='{
  "inbounds": [],
  "outbounds": [],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": []
  },
  "dns": {
    "servers": ["8.8.8.8", "1.1.1.1"]
  }
}'

# 初始化 SOCKS 配置
SOCKS_CONFIG_JSON='{
  "inbounds": [],
  "outbounds": [],
  "routing": {
    "rules": []
  }
}'

# 清空分享链接文件
echo "" >"$V2RAY_SHARE_LINK_FILE"
echo "" >"$SOCKS_SHARE_LINK_FILE"

declare -A UUID_MAP

# 输入 Vmess 和 SOCKS 的端口
read -p "请输入 Vmess 的端口: " VMESS_PORT
read -p "请输入 SOCKS 的端口: " SOCKS_PORT

# 生成 UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 生成 Vmess 分享链接
generate_vmess_share_link() {
    local ip=$1
    local uuid=$2
    local port=$3
    local link_json=$(
        cat <<EOF
{
  "v": "2",
  "ps": "vmess_${ip}",
  "add": "${ip}",
  "port": "${port}",
  "id": "${uuid}",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF
    )
    echo "vmess://$(echo -n "$link_json" | base64 -w 0)" >>"$V2RAY_SHARE_LINK_FILE"
}

generate_socks_share_link_with_auth() {
    local ip=$1
    local port=$2
    local tag_num=$3
    local user="user-$tag_num"
    local pass="pass-$tag_num"
    local remark="IP$tag_num"

    # 对用户名:密码进行 Base64 编码
    local up_encoded
    up_encoded=$(echo -n "${user}:${pass}" | base64)

    # 对备注进行 URL 编码
    local remark_encoded
    remark_encoded=$(echo -n "${remark}" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')

    # 构建并写入 V2Ray Socks 分享链接
    local socks_link="socks://${up_encoded}@${ip}:${port}#${remark_encoded}"
    echo "$socks_link" >>"$SOCKS_SHARE_LINK_FILE"
}

for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i + 1)))
    UUID=$(generate_uuid)

    # 添加 V2Ray 入站规则
    V2RAY_CONFIG_JSON=$(echo "$V2RAY_CONFIG_JSON" | jq --arg ip "${IP_ADDRESSES[$i]}" --arg uuid "$UUID" --arg port "$VMESS_PORT" --arg tag "in-$TAG_NUM" '.inbounds += [{
      tag: $tag,
      listen: $ip,
      port: ($port | tonumber),
      protocol: "vmess",
      settings: { clients: [{ id: $uuid }] }
    }]')

    # 添加 V2Ray 出站规则
    V2RAY_CONFIG_JSON=$(echo "$V2RAY_CONFIG_JSON" | jq --arg ip "${IP_ADDRESSES[$i]}" --arg tag "out-$TAG_NUM" '.outbounds += [{
      tag: $tag,
      sendThrough: $ip,
      protocol: "freedom"
    }]')

    # 添加路由规则
    V2RAY_CONFIG_JSON=$(echo "$V2RAY_CONFIG_JSON" | jq --arg inTag "in-$TAG_NUM" --arg outTag "out-$TAG_NUM" '.routing.rules += [{
      type: "field",
      inboundTag: [$inTag],
      outboundTag: $outTag
    }]')

    # 添加 SOCKS 入站规则
    SOCKS_CONFIG_JSON=$(echo "$SOCKS_CONFIG_JSON" | jq --arg ip "${IP_ADDRESSES[$i]}" --arg port "$SOCKS_PORT" --arg tag "socks-in-$TAG_NUM" --arg user "user-$TAG_NUM" --arg pass "pass-$TAG_NUM" '.inbounds += [{
        tag: $tag,
        protocol: "socks",
        port: ($port | tonumber),
        listen: $ip,
        settings: {
            auth: "password",
            accounts: [{ user: $user, pass: $pass }],
            udp: true,
            ip: $ip
    }
    }]')

    # 添加 SOCKS 出站规则
    SOCKS_CONFIG_JSON=$(echo "$SOCKS_CONFIG_JSON" | jq --arg ip "${IP_ADDRESSES[$i]}" --arg uuid "$UUID" --arg port "$VMESS_PORT" --arg tag "vmess-out-$TAG_NUM" '.outbounds += [{
      tag: $tag,
      sendThrough: $ip,
      protocol: "vmess",
      settings: {
        vnext: [{
          address: $ip,
          port: ($port | tonumber),
          users: [{ id: $uuid, alterId: 0, security: "auto" }]
        }]
      }
    }]')

    # 添加路由规则
    SOCKS_CONFIG_JSON=$(echo "$SOCKS_CONFIG_JSON" | jq --arg inTag "socks-in-$TAG_NUM" --arg outTag "vmess-out-$TAG_NUM" '.routing.rules += [{
      type: "field",
      inboundTag: [$inTag],
      outboundTag: $outTag
    }]')

    # 生成 Vmess 分享链接
    generate_vmess_share_link "${IP_ADDRESSES[$i]}" "$UUID" "$VMESS_PORT"

    # 生成 SOCKS 分享链接
    generate_socks_share_link_with_auth "${IP_ADDRESSES[$i]}" "$SOCKS_PORT" "$TAG_NUM"
done

echo "$V2RAY_CONFIG_JSON" | jq '.' >"$V2RAY_CONFIG_FILE"
echo "V2Ray 配置文件已创建在 $V2RAY_CONFIG_FILE"

echo "$SOCKS_CONFIG_JSON" | jq '.' >"$SOCKS_CONFIG_FILE"
echo "SOCKS 配置文件已创建在 $SOCKS_CONFIG_FILE"

echo "V2Ray分享链接已创建在 $V2RAY_SHARE_LINK_FILE"

echo "SOCKS分享链接已创建在 $SOCKS_SHARE_LINK_FILE"

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
        (
            crontab -l 2>/dev/null
            echo "$cron_entry"
        ) | crontab -
        echo "脚本 $script_path 已添加到开机启动，将在启动后60秒执行。"
    fi
}

script_path="/root/setup_v2ray_socks.sh"
add_to_startup "$script_path"

rm /root/setup_v2ray_socks.sh
echo "Deleted current script."
