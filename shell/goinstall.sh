#!/bin/bash
# ZJMF LXD Server 安装/升级脚本（保留数据库、交互配置）

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------------- 配置 ----------------
REPO="https://github.com/xkatld/zjmf-lxd-server"
VERSION="v0.0.2"
NAME="zjmf-lxd-server"
DIR="/opt/$NAME"
CFG="$DIR/config.yaml"
SERVICE="/etc/systemd/system/$NAME.service"
DB_FILE="lxdapi.db"
FORCE=false

# ---------------- 日志函数 ----------------
log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; }

# ---------------- 检查 root ----------------
[[ $EUID -ne 0 ]] && { err "请使用 root 运行"; exit 1; }

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="${2/v/}"; VERSION="v$VERSION"; shift 2;;
    -f|--force) FORCE=true; shift;;
    -h|--help) echo "$0 [-v 版本] [-f]"; exit 0;;
    *) err "未知参数 $1"; exit 1;;
  esac
done

# ---------------- 架构检测 ----------------
arch=$(uname -m)
case $arch in
  x86_64) BIN="lxdapi-amd64";;
  aarch64|arm64) BIN="lxdapi-arm64";;
  *) err "不支持架构 $arch"; exit 1;;
esac
DOWNLOAD_URL="$REPO/releases/download/$VERSION/$BIN.zip"

# ---------------- 检测升级模式 ----------------
UPGRADE=false
if [[ -d "$DIR" ]] && [[ -f "$DIR/version" ]]; then
  CUR=$(cat "$DIR/version")
  if [[ $CUR != "$VERSION" || $FORCE == true ]]; then
    UPGRADE=true
    info "升级模式: $CUR -> $VERSION"
  else
    ok "已安装最新版本 $VERSION"
    exit 0
  fi
fi

# ---------------- 安装依赖 ----------------
info "安装依赖..."
apt update -y
apt install -y curl wget unzip openssl xxd systemd || { err "依赖安装失败"; exit 1; }
ok "依赖安装完成"

# ---------------- 停止服务 ----------------
systemctl stop $NAME 2>/dev/null || true

# ---------------- 升级逻辑 ----------------
TMP_DB=$(mktemp -d)
if [[ $UPGRADE == true ]]; then
  info "备份数据库并清理旧文件..."
  if [[ -f "$DIR/$DB_FILE" ]]; then
    cp "$DIR/$DB_FILE" "$TMP_DB/"
    ok "数据库已备份"
  fi
  rm -rf "$DIR"/*
  ok "旧文件已清除"
fi

mkdir -p "$DIR"

# ---------------- 下载 & 安装 ----------------
info "下载程序..."
TMP=$(mktemp -d)
wget -qO "$TMP/app.zip" "$DOWNLOAD_URL" || { err "下载失败"; exit 1; }
unzip -qo "$TMP/app.zip" -d "$DIR"
chmod +x "$DIR/$BIN"
echo "$VERSION" > "$DIR/version"
rm -rf "$TMP"
ok "程序安装完成"

# ---------------- 恢复数据库 ----------------
if [[ -f "$TMP_DB/$DB_FILE" ]]; then
  mv "$TMP_DB/$DB_FILE" "$DIR/"
  ok "数据库已恢复"
fi
rm -rf "$TMP_DB"

# ---------------- 配置文件 ----------------
DEFAULT_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
DEFAULT_HASH=$(openssl rand -hex 32)
if [[ -f "$CFG" ]]; then
  CUR_IP=$(grep -A 10 "server_ips:" "$CFG" | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | sed 's/.*"\([^"]*\)".*/\1/')
  CUR_HASH=$(grep "api_hash:" "$CFG" | sed 's/.*"\([^"]*\)".*/\1/')
else
  CUR_IP="$DEFAULT_IP"
  CUR_HASH="$DEFAULT_HASH"
fi

# 交互设置
read -p "外网IP [$CUR_IP]: " EXTERNAL_IP
EXTERNAL_IP=${EXTERNAL_IP:-$CUR_IP}
read -p "API Hash [$CUR_HASH]: " API_HASH
API_HASH=${API_HASH:-$CUR_HASH}
ok "使用外网IP: $EXTERNAL_IP"
ok "使用API Hash: $API_HASH"

# 生成完整配置文件（新安装）或更新 IP/Hash（升级）
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
  path: "$DB_FILE"
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
ok "配置文件生成完成"
else
  sed -i "s/\([ ]*-\s*\).*/\1\"$EXTERNAL_IP\"/1" "$CFG"
  sed -i "s/\(api_hash:\s*\).*/\1\"$API_HASH\"/" "$CFG"
  ok "配置文件更新完成"
fi

# ---------------- systemd ----------------
cat > "$SERVICE" <<EOF
[Unit]
Description=ZJMF LXD Server
After=network.target

[Service]
WorkingDirectory=$DIR
ExecStart=$DIR/$BIN
Restart=always
RestartSec=5
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $NAME
ok "服务已启动"

# ---------------- 完成 ----------------
echo
ok "安装/升级完成！"
info "目录: $DIR"
info "配置: $CFG"
info "访问: https://$EXTERNAL_IP:8080"
