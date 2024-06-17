#!/bin/bash
# Auth: happylife
# Desc: VLESS+WS+TLS+网站安装脚本 (Caddy版本)
# Plat: Debian 10+

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then 
  echo "请以root用户运行此脚本。"
  exit
fi

# 获取用户输入的域名、SSL证书路径、网站路径
read -p "请输入域名: " domainName
read -p "请输入SSL证书路径 (例如 /path/to/ssl.crt): " sslCertPath
read -p "请输入SSL证书密钥路径 (例如 /path/to/ssl.key): " sslKeyPath
read -p "请输入网站路径 (例如 /var/www/html): " websitePath

if [ -z "$domainName" ] || [ -z "$sslCertPath" ] || [ -z "$sslKeyPath" ] || [ -z "$websitePath" ]; then
    echo "所有输入项均不能为空。"
    exit
fi

# 配置系统时区为东八区
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 更新系统并安装必要的包
apt update
apt install curl ufw pwgen -y

# 安装Caddy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy

# 配置参数
port="$(shuf -i 20000-65000 -n 1)"
uuid="$(uuidgen)"
path="/$(pwgen -A0 6 8 | xargs | sed 's/ /\//g')"
v2rayConfig="/usr/local/etc/v2ray/config.json"

# 使用v2ray官方命令安装v2ray并设置开机启动
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
systemctl enable v2ray

# 修正官方5.1+版本安装脚本启动命令错误
grep -r 'v2ray -config' /etc/systemd/system/* | cut -d: -f1 | xargs -i sed -i 's/v2ray -config/v2ray run -config/' {}
systemctl daemon-reload

# 配置Caddy
cat <<EOF > /etc/caddy/Caddyfile
{
    email your-email@example.com
}

$domainName {
    encode zstd gzip
    root * $websitePath
    file_server

    @v2ray_ws {
        path $path*
    }
    reverse_proxy @v2ray_ws 127.0.0.1:$port
    tls $sslCertPath $sslKeyPath
}
EOF

# 配置v2ray
echo '
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "inbound": {
    "port": '$port',
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "'$uuid'",
          "level": 1
        }
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "'$path'"
      }
    }
  },
  "outbound": {
    "protocol": "freedom",
    "settings": {}
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "blocked"
      }
    ]
  }
}
' > $v2rayConfig

# 重启v2ray和Caddy
systemctl restart v2ray
systemctl status -l v2ray
caddy reload --config /etc/caddy/Caddyfile
systemctl restart caddy

# 输出配置信息
echo
echo "域名: $domainName"
echo "端口: 443"
echo "UUID: $uuid"
echo "协议: vless"
echo "安全: tls"
echo "传输: websocket"
echo "路径: $path"

# 生成V2Ray客户端配置
echo '
{
  "v": "2",
  "ps": "'$domainName'",
  "add": "'$domainName'",
  "port": "443",
  "id": "'$uuid'",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "'$domainName'",
  "path": "'$path'",
  "tls": "tls"
}
' > /root/v2ray_client_config.json

echo "V2Ray客户端配置已生成，路径为：/root/v2ray_client_config.json"

