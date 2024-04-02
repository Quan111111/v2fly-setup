# v2fly-setup
一个简单的一键配置v2fly的脚本

## 使用以下命令执行简单vmess版本
```
sudo apt-get update && sudo apt-get install -y curl && curl -o setup_v2ray_simple.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_v2ray_simple.sh && chmod +x setup_v2ray_simple.sh && ./setup_v2ray_simple.sh

```

## 使用以下命令执行自定义vmess+ws版本
```
sudo apt-get update && sudo apt-get install -y curl && curl -o setup_v2ray_customizable.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_v2ray_customizable.sh && chmod +x setup_v2ray_customizable.sh && ./setup_v2ray_customizable.sh

```

## 使用以下命令执行简单vmess前置socks脚本
```
sudo apt-get update && sudo apt-get install -y curl && curl -o setup_socks_simple.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_socks_simple.sh && chmod +x setup_socks_simple.sh && ./setup_socks_simple.sh

```

## 使用以下命令部署status监控
```
sudo apt-get update && sudo apt install -y curl unzip && curl -o set_server_status.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/set_server_status.sh && chmod +x set_server_status.sh && ./set_server_status.sh
```

### 使用以下命令停止status监控
```
ps ax | grep 'stat_client' | grep -v grep | awk '{print $1}' | xargs -r kill -9
```
