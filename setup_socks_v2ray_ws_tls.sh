#!/bin/bash

# Detect operating system type and get OS name and version
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
elif [ -f /etc/SuSe-release ]; then
    OS=SuSE
    VER=$(grep VERSION /etc/SuSe-release | awk '{print $3}')
elif [ -f /etc/redhat-release ]; then
    OS=$(grep "NAME" /etc/redhat-release | awk '{print $3}')
    VER=$(grep "VERSION_ID" /etc/redhat-release | awk '{print $3}')
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Function to handle APT lock issues in Ubuntu and Debian
handle_apt_lock() {
    echo "APT is locked by another process. Attempting to fix..."
    sudo pkill -9 apt-get
    sudo pkill -9 dpkg
    echo "Cleaning up lock files..."
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/dpkg/lock-frontend
    echo "Reconfiguring packages..."
    sudo dpkg --configure -a
    echo "Retrying update and install operations..."
}

# Function to update system packages
update_pkg() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get update || handle_apt_lock && sudo apt-get update && sudo apt-get upgrade -y
    elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Fedora" ]] || [[ "$OS" == "Red Hat Enterprise Linux" ]]; then
        sudo yum update -y
    else
        echo "Unsupported operating system"
        exit 1
    fi
}

# Function to install Docker
install_docker() {
    if [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "Debian" ]]; then
        sudo apt-get install docker.io -y || handle_apt_lock && sudo apt-get install docker.io -y
    elif [[ "$OS" == "CentOS Linux" ]] || [[ "$OS" == "Red Hat Enterprise Linux" ]]; then
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
        echo "Unsupported operating system for Docker installation"
        exit 1
    fi
}

# Update system packages
update_pkg

# Install Docker
install_docker

# Pull the v2fly Docker image
docker pull v2fly/v2fly-core

# Create configuration directory
mkdir -p /root/socks/

# Create configuration file script
cat << 'EOFF' >./create_socks_config.sh
#!/bin/bash

# Configuration file path
CONFIG_FILE="/root/v2ray/config.json"
OUTPUT_DIR="/root/socks/"
mkdir -p "$OUTPUT_DIR"

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file '$CONFIG_FILE' not found!"
  exit 1
fi

# Use jq to parse the configuration file and get necessary information
VMESS_SERVER_PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE" 2>/dev/null || echo "")
VMESS_USER_ID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE" 2>/dev/null || echo "")

# Get the server's public IP address (replace with your actual method of obtaining the public IP)
SERVER_PUBLIC_IP=$(curl -s ifconfig.me) # Using ifconfig.me to get the public IP, replace as needed

# Check if the public IP was obtained
if [ -z "$SERVER_PUBLIC_IP" ]; then
  echo "Error: Unable to get the server's public IP address!"
  exit 1
fi

# Get streamSettings
STREAM_SETTINGS=$(jq -r '.inbounds[0].streamSettings' "$CONFIG_FILE" 2>/dev/null || echo '{"network": "tcp", "tcpSettings": {"header": {"type": "none"}}}')

# Get user input
read -p "Enter SOCKS port number: " SOCKS_PORT
read -p "Enter username: " USERNAME
read -p "Enter password: " PASSWORD

# Check for required fields
if [ -z "$VMESS_SERVER_PORT" ] || [ -z "$VMESS_USER_ID" ]; then
  echo "Error: Configuration file is missing required fields!"
  exit 1
fi

# Generate the socks5 configuration file, including user input
cat > "$OUTPUT_DIR/config_s.json" << EOF
{
  "inbounds": [
    {
      "tag": "in-01",
      "listen": "$SERVER_PUBLIC_IP",
      "port": $SOCKS_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USERNAME",
            "pass": "$PASSWORD"
          }
        ],
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "out-01",
      "protocol": "vmess",
      "streamSettings": $STREAM_SETTINGS,
      "settings": {
        "vnext": [
          {
            "address": "127.0.0.1",
            "port": $VMESS_SERVER_PORT,
            "users": [
              {
                "id": "$VMESS_USER_ID",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": "in-01",
        "outboundTag": "out-01"
      }
    ]
  }
}
EOF

echo "V2Ray socks5 configuration file created at $OUTPUT_DIR/config_s.json"

# Generate sharing link information compatible with v2rayN
SHARE_SOCKS_INFO_FILE="$OUTPUT_DIR/share_socks_info.txt"
> "$SHARE_SOCKS_INFO_FILE"
echo "$SERVER_PUBLIC_IP\t$SOCKS_PORT\t$USERNAME\t$PASSWORD" > "$SHARE_SOCKS_INFO_FILE"
echo "V2Ray Socks information saved to $SHARE_SOCKS_INFO_FILE"

# Encode username and password using base64
encoded_credentials=$(echo -n "$USERNAME:$PASSWORD" | base64)

# Generate V2RayN compatible sharing link
v2rayn_link="socks://$encoded_credentials@$SERVER_PUBLIC_IP:$SOCKS_PORT"
echo "$v2rayn_link" > "$OUTPUT_DIR/share_socks_base64.txt"
echo "V2RayN compatible Socks sharing link saved to $OUTPUT_DIR/share_socks_base64.txt"


EOFF

chmod +x ./create_socks_config.sh

# Stop and remove existing container
stop_and_remove_container() {
    container_name="test_s"
    if docker ps -a -q -f name="$container_name" &> /dev/null; then
        echo "Stopping and removing existing '$container_name' v2fly container..."
        docker stop "$container_name"
        docker rm "$container_name"
    fi
}

# Execute the script to generate the configuration file
./create_socks_config.sh

# Stop and remove existing container
stop_and_remove_container

# Start the socks service using Docker
docker run --network host -d --name test_s -v /root/socks:/etc/socks v2fly/v2fly-core run -c /etc/socks/config_s.json

echo "Socks Docker container started."

# Add script to startup
add_to_startup() {
    local script_path="$1"
    local cron_entry="@reboot sleep 60 && /bin/bash $script_path"
    if crontab -l | grep -Fq "/bin/bash $script_path"; then
        echo "Script $script_path is already in startup, will not add again."
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "Script $script_path added to startup, will execute 60 seconds after boot."
    fi
}

# Add script to startup (commented out to avoid accidental addition)
# add_to_startup "$0"
rm /root/setup_socks_v2ray_ws_tls.sh /root/create_socks_config.sh

echo "Script completed. Please manually add to startup (e.g., using systemd)"
