#!/bin/bash

# 设置变量
V2RAY_CONFIG="/root/v2ray/config.json"
NGINX_CONF_DIR="/etc/nginx/conf.d/"
SHARE_FILE="/root/v2ray/share_v2ray_base64.txt"

# 安装必要的软件包
apt-get update -y
apt-get install -y curl jq socat nginx

# 安装并配置 V2Ray (假设你已经下载了v2fly-setup.sh脚本)
curl -o setup_v2ray_customizable.sh https://raw.githubusercontent.com/Quan111111/v2fly-setup/main/setup_v2ray_customizable.sh && chmod +x setup_v2ray_customizable.sh && ./setup_v2ray_customizable.sh

# 获取域名
read -p "domain: " DOMAIN || exit 1

# 获取 V2Ray 监听端口和路径
V2RAY_PORT=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG")
V2RAY_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$V2RAY_CONFIG")

# 检查获取的参数是否有效
if [[ -z "$V2RAY_PORT" || -z "$V2RAY_PATH" ]]; then
  echo "从 V2Ray 配置文件中获取端口、路径或ID失败！"
  exit 1
fi

# 修改 V2Ray 配置文件 (如果需要修改监听地址，请在此处添加)
jq --arg listen "127.0.0.1" '.inbounds[0].listen = $listen' "$V2RAY_CONFIG" > "$V2RAY_CONFIG.tmp" && mv "$V2RAY_CONFIG.tmp" "$V2RAY_CONFIG"

# 检查配置文件修改是否成功
if grep -q '"listen": "127.0.0.1"' "$V2RAY_CONFIG"; then
  echo "V2Ray 配置文件修改成功。"
  docker stop test_v
  docker rm test_v
  docker run --network host -d --name test_v -v /root/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json
else
  echo "V2RAY 配置文件修改失败！"
  exit 1
fi

curl https://get.acme.sh | sh -s email=support@mastersmade.org

systemctl stop nginx.service

# 获取 Let's Encrypt 证书 (假设你已经安装了acme.sh)
CERT_DIR="/root/.acme.sh/${DOMAIN}_ecc/"
if [ ! -f "${CERT_DIR}/fullchain.cer" ] || [ ! -f "${CERT_DIR}/${DOMAIN}.key" ]; then
  echo "获取证书中..."
  /root/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN"
  if [ ! -f "${CERT_DIR}/fullchain.cer" ] || [ ! -f "${CERT_DIR}/${DOMAIN}.key" ]; then
    echo "获取证书失败！"
    exit 1
  fi
  echo "证书获取成功。"
fi


# 创建 Nginx 配置文件
NGINX_CONF="${NGINX_CONF_DIR}${DOMAIN}.conf"
cat << EOF > "$NGINX_CONF"
server {
  listen 443 ssl;
  listen [::]:443 ssl;

  ssl_certificate       ${CERT_DIR}/fullchain.cer;
  ssl_certificate_key   ${CERT_DIR}/${DOMAIN}.key;
  ssl_session_timeout 1d;
  ssl_session_cache shared:MozSSL:10m;
  ssl_session_tickets off;

  ssl_protocols         TLSv1.2 TLSv1.3;
  ssl_ciphers           ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
  ssl_prefer_server_ciphers off;

  server_name           ${DOMAIN};

  location ${V2RAY_PATH} {
    if (\$http_upgrade != "websocket") {
        return 404;
    }
    proxy_redirect off;
    proxy_pass http://127.0.0.1:${V2RAY_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF


# 测试 Nginx 配置并重启
nginx -t && systemctl restart nginx || { echo "Nginx配置测试或重启失败！"; exit 1; }

# 获取 IP 地址
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk '{print $2}' | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\.|^10\."))
IP_ADDRESS=${IP_ADDRESSES[0]} # 获取第一个非本地IP地址

# 获取 V2Ray host
V2RAY_HOST=$(jq -r '.inbounds[0].streamSettings.wsSettings.headers.Host' "$V2RAY_CONFIG" || jq -r '.inbounds[0].streamSettings.wsSettings.host' "$V2RAY_CONFIG" )

# 检查获取的参数是否有效
if [[ -z "$V2RAY_HOST" ]]; then
    echo "从 V2Ray 配置文件中获取host失败！"
    exit 1
fi

V2RAY_ID=$(jq -r '.inbounds[0].settings.clients[0].id' "$V2RAY_CONFIG") # Extract ID from config.json

# 检查获取的参数是否有效
if [[ -z "$V2RAY_ID" ]]; then
    echo "从 V2Ray 配置文件中获取id失败！"
    exit 1
fi


echo "$NGINX_CONF"
NGINX_PORT=$(grep -oP 'listen\s+\K\d+' "$NGINX_CONF" | head -n 1)
if [[ -z "$NGINX_PORT" ]]; then
  echo "从 Nginx 配置文件中获取端口失败！"
  exit 1
fi
echo "$NGINX_PORT"

SUBDOMAIN=$(echo "$DOMAIN" | sed 's/\(.*\)\.\(.*\)\..*/\1/')

echo "SUBDOMAIN: $SUBDOMAIN"
echo "DOMAIN: $DOMAIN"
echo "IP_ADDRESS: $IP_ADDRESS"
echo "NGINX_PORT: $NGINX_PORT"
echo "V2RAY_ID: $V2RAY_ID"
echo "V2RAY_HOST: $V2RAY_HOST"
echo "V2RAY_PATH: $V2RAY_PATH"
echo "V2RAY_CONFIG: $V2RAY_CONFIG"  # 添加这个，检查配置文件路径是否正确
echo "SHARE_FILE: $SHARE_FILE"     # 添加这个，检查输出文件路径是否正确

# 生成 VMESS 链接
echo "start generate vmess_link"

vmess_data=$(jq -n \
    --arg v2ray_ps '"'"${SUBDOMAIN}"'"' \
    --arg v2ray_add '"'"${IP_ADDRESS}"'"' \
    --arg v2ray_port '"'"${NGINX_PORT}"'"' \
    --arg v2ray_id '"'"${V2RAY_ID}"'"' \
    --arg v2ray_host '"'"${V2RAY_HOST}"'"' \
    --arg v2ray_path '"'"${V2RAY_PATH}"'"' \
    --arg v2ray_sni '"'"${DOMAIN}"'"' \
    ' {
      "v": 2,
      "ps": ($v2ray_ps | fromjson),
      "add": ($v2ray_add | fromjson),
      "port": ($v2ray_port | fromjson),
      "id": ($v2ray_id | fromjson),
      "aid": 0,
      "scy": "auto",
      "net": "ws",
      "type": "none",
      "host": ($v2ray_host | fromjson),
      "path": ($v2ray_path | fromjson),
      "tls": "tls",
      "sni": ($v2ray_sni | fromjson),
      "alpn": "",
      "fp": ""
    }'
) || { echo "生成VMESS链接失败！ jq error: $?" ; exit 1; }

echo "jq return code: $?" # 检查jq的返回值

vmess_link="vmess://$(echo -n "$vmess_data" | base64)"

# 将 VMESS 链接写入文件
echo "$vmess_link" > "$SHARE_FILE"

# 删除SHARE_FILE中的换行符，并进行错误处理
tmpfile=$(mktemp)
if sed ':a;N;$!ba;s/\n//g' "$SHARE_FILE" > "$tmpfile"; then
  mv "$tmpfile" "$SHARE_FILE"
  echo "换行符已成功删除。"
else
  echo "删除换行符失败！ sed error: $?"
  rm "$tmpfile"  # 删除临时文件
  exit 1
fi

echo "VMESS 链接已生成到 $SHARE_FILE"
echo "脚本执行完毕。"