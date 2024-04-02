#!/bin/bash

# get_architecture
arch=$(uname -m)
# 设置 ARCHITECTURE 变量
if [[ $arch == "aarch64" ]]; then
    ARCHITECTURE="aarch64"
elif [[ $arch == "x86_64" ]]; then
    ARCHITECTURE="x86_64"
else
    ARCHITECTURE="unknown"
fi
 
github_project="zdz/ServerStatus-Rust"
tag=$(curl -m 10 -sL "https://api.github.com/repos/$github_project/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
echo "最新版本号为：${tag}"
echo "机器架构为：${ARCHITECTURE}"

mkdir -p /root/server_status_rust/status_client/ && cd /root/server_status_rust/status_client/

curl -L -O https://github.com/zdz/ServerStatus-Rust/releases/download/${tag}/client-${ARCHITECTURE}-unknown-linux-musl.zip && \
unzip -o "client-${ARCHITECTURE}-unknown-linux-musl.zip" && \
rm "client-${ARCHITECTURE}-unknown-linux-musl.zip"

read -p "输入本机名称:" name
name=${name:-"默认机器名称"}

read -p "输入注册组[默认hostease]:" group
group=${group:-"hostease"}

read -p "输入密码[默认pppp]:" password
password=${password:-"pppp"}

# /root/server_status_rust/status_client/stat_client -a "http://status.quan.zone:18888/report" --gid ${group} -p ${password} --alias ${name}

nohup /root/server_status_rust/status_client/stat_client -a "http://status.quan.zone:18888/report" --gid ${group} -p ${password} --alias ${name} > /root/server_status_rust/status_client/log.txt 2>&1 &

# 添加脚本到开机启动
add_to_startup() {
    local script_path="$1"
    # 在脚本路径前加上 sleep 30 && 来实现开机后延时60秒执行
    local cron_entry="@reboot sleep 30 && /bin/bash $script_path"

    # 检查 crontab 是否已经包含了这一行
    if crontab -l | grep -Fq "/bin/bash $script_path"; then
        echo "脚本 $script_path 已经在开机启动中了，不会重复添加。"
    else
        # 使用 crontab 将脚本添加到开机启动
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "脚本 $script_path 已添加到开机启动，将在启动后30秒执行。"
    fi
}

# 脚本路径
script1="/root/set_server_status.sh"

# 添加脚本到开机启动
add_to_startup "$script1"