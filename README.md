# v2fly-setup
一个简单的一键配置v2fly的脚本

## 使用以下命令执行vmess+ws+tls版本
```
curl -o setup_v2ray_ws_tls.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_v2ray_ws_tls.sh && chmod +x setup_v2ray_ws_tls.sh && ./setup_v2ray_ws_tls.sh

```

## 使用以下命令执行vmess+ws+tls的前置socks版本
```
curl -o setup_socks_v2ray_ws_tls.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_socks_v2ray_ws_tls.sh && chmod +x setup_socks_v2ray_ws_tls.sh && ./setup_socks_v2ray_ws_tls.sh

```

## 使用以下命令执行自定义融合版本
```
sudo apt-get update && sudo apt-get install -y curl && sudo apt-get install -y jq && curl -o setup_mix_v2ray_and_socks.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_mix_v2ray_and_socks.sh && chmod +x setup_mix_v2ray_and_socks.sh && ./setup_mix_v2ray_and_socks.sh

```

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