#!/bin/bash
# ZJMF LXD Server 一键安装脚本（完整配置保留IP和Hash）

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

DIR="/opt/zjmf-lxd-server"
CFG="$DIR/config.yaml"

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; }

[[ $EUID -ne 0 ]] && { err "请用 root 运行"; exit 1; }

mkdir -p "$DIR"

# 默认值
DEFAULT_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
DEFAULT_HASH=$(openssl rand -hex 32)

# 如果已有配置，读取现有值
if [[ -f "$CFG" ]]; then
  CUR_IP=$(grep -A 10 "server_ips:" "$CFG" | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | sed 's/.*"\([^"]*\)".*/\1/')
  CUR_HASH=$(grep "api_hash:" "$CFG" | sed 's/.*"\([^"]*\)".*/\1/')
else
  CUR_IP="$DEFAULT_IP"
  CUR_HASH="$DEFAULT_HASH"
fi

# 交互设置IP
read -p "外网IP [$CUR_IP]: " EXTERNAL_IP
EXTERNAL_IP=${EXTERNAL_IP:-$CUR_IP}

# 交互设置API Hash
read -p "API Hash [$CUR_HASH]: " API_HASH
API_HASH=${API_HASH:-$CUR_HASH}

ok "使用外网IP: $EXTERNAL_IP"
ok "使用API Hash: $API_HASH"

# 如果配置文件不存在，生成完整模板
if [[ ! -f "$CFG" ]]; then
cat > "$CFG" <<EOF
# LXD API 配置文件
server:
  port: 8080
  mode: release
  tls:
    enabled: true
    cert_file: "server.crt"
    key_file: "server.key"
    auto_gen: true
    server_ips:
      - "$EXTERNAL_IP"
      - "localhost"
      - "127.0.0.1"

security:
  enable_auth: true
  api_hash: "$API_HASH"
  hash_expire_hours: 24

database:
  path: "lxdapi.db"
  enable_log: false

lxc:
  timeout: 60
  verbose: false

task:
  max_concurrent: 10
  history_days: 30
  enable_log: true

traffic:
  interval: 5
  enable_log: false

container:
  enable_log: false

nat:
  enable_log: false

console:
  enabled: true
  session_timeout: 1800
  enable_log: false

traffic_limit:
  enabled: true
  check_interval_seconds: 5
  enable_log: false
  auto_suspend: true

database_cleanup:
  enabled: true
  check_interval_hours: 1
  enable_log: false
  auto_cleanup: true

cors:
  enabled: true
  allow_origins:
    - "*"
  allow_methods:
    - "GET"
    - "POST"
    - "PUT"
    - "DELETE"
    - "OPTIONS"
    - "PATCH"
  allow_headers:
    - "Origin"
    - "Content-Type"
    - "Accept"
    - "Authorization"
    - "X-API-Hash"
    - "X-Requested-With"
    - "apikey"
  expose_headers:
    - "Content-Length"
    - "X-Total-Count"
  allow_credentials: true
  max_age: 86400
EOF
ok "配置文件已生成"
else
  # 替换现有配置中的IP和Hash
  sed -i "s/\([ ]*-\s*\).*/\1\"$EXTERNAL_IP\"/1" "$CFG"
  sed -i "s/\(api_hash:\s*\).*/\1\"$API_HASH\"/" "$CFG"
  ok "配置文件已更新外网IP和API Hash"
fi

echo
ok "配置完成: $CFG"
