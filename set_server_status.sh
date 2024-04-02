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

read -p "输入本机名称：" name
name=${name:-"默认机器名称"}

/root/server_status_rust/status_client/stat_client -a "http://status.quan.zone:18888/report" -g hostease1 -p pppp -alias ${name}