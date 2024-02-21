#!/bin/bash

# ����ϵͳ����װ Docker
sudo apt update && sudo apt upgrade -y
sudo apt install docker.io -y
# �������ʹ�� snap ��װ Docker������ȡ���������е�ע��
# sudo snap refresh snapd
# sudo snap install docker

# ��ȡ v2fly �� Docker ����
docker pull v2fly/v2fly-core

# ���������ļ�Ŀ¼
mkdir -p ./v2ray/

# ���� create_v2ray_config.sh �ű�
cat << 'EOF' > ./create_v2ray_config.sh
#!/bin/bash

# ���������ļ���·��
CONFIG_FILE="./v2ray/config.json"

# �Զ���ȡ����IP��ַ���ų����ػػ���ַ��docker�ڲ������ַ
IP_ADDRESSES=($(ip addr show | grep "inet\b" | awk "{print \$2}" | cut -d/ -f1 | grep -v -E "^127\.|^172\.17\."))

# ��ʼ�������ļ�������
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

# Ϊÿ�� IP ��ַ���� inbounds �� outbounds ��Ŀ
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    INBOUND_ENTRY=${INBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    INBOUND_ENTRY=${INBOUND_ENTRY//TAG/$TAG_NUM}

    CONFIG_JSON+="$INBOUND_ENTRY,\n"
done

# ��� outbounds ���ֵĿ�ʼ
CONFIG_JSON+="    ],\n    \"outbounds\": [\n"

# Ϊÿ�� IP ��ַ��� outbounds ��Ŀ
for i in "${!IP_ADDRESSES[@]}"; do
    TAG_NUM=$(printf "%02d" $((i+1)))
    OUTBOUND_ENTRY=${OUTBOUND_TEMPLATE//IP_ADDRESS/${IP_ADDRESSES[$i]}}
    OUTBOUND_ENTRY=${OUTBOUND_ENTRY//TAG/$TAG_NUM}

    CONFIG_JSON+="$OUTBOUND_ENTRY"
    if [ $i -lt $((${#IP_ADDRESSES[@]} - 1)) ]; then
        CONFIG_JSON+=",\n"
    fi
done

# ��������ļ�������
CONFIG_JSON+="\n    ]\n}"

# ȷ�� v2ray Ŀ¼����
mkdir -p $(dirname "$CONFIG_FILE")

# ���µ�����д���ļ�
echo -e "$CONFIG_JSON" > "$CONFIG_FILE"

echo "Configuration file has been created at $CONFIG_FILE"
EOF

# ���ִ��Ȩ��
chmod +x ./create_v2ray_config.sh

# ִ�нű����������ļ�
./create_v2ray_config.sh

# ֹͣ��ɾ���Ѵ��ڵ�����
if [ $(docker ps -a -q -f name=v2fly) ]; then
    echo "Stopping and removing existing v2fly container..."
    docker stop v2fly
    docker rm v2fly
fi

# ʹ�� Docker ���� V2Ray ����
docker run --network host -d --name v2fly -v $(pwd)/v2ray/config.json:/etc/v2ray/config.json v2fly/v2fly-core run -c /etc/v2ray/config.json

echo "V2Ray Docker container has been started."
