#!/bin/bash

# ZJMF LXD Server 一键安装脚本

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
REPO="https://github.com/xkatld/zjmf-lxd-server"
VERSION="v0.0.2"
NAME="zjmf-lxd-server"
DIR="/opt/$NAME"
CFG="$DIR/config.yaml"
SERVICE="/etc/systemd/system/$NAME.service"
FORCE=false
UPGRADE=false

# 日志函数
log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; }

# root 检查
[[ $EUID -ne 0 ]] && { err "请用 root 运行"; exit 1; }

# 参数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="${2/v/}"; VERSION="v$VERSION"; shift 2;;
    -f|--force) FORCE=true; shift;;
    -h|--help)
      echo "$0 [-v 版本] [-f]"; exit 0;;
    *) err "未知参数 $1"; exit 1;;
  esac
done

# 检查版本
if [[ -f "$DIR/version" ]]; then
  CUR=$(cat "$DIR/version")
  if [[ $CUR == "$VERSION" && $FORCE != true ]]; then
    info "已安装 $CUR，无需更新"
    exit 0
  fi
  UPGRADE=true
  info "升级: $CUR -> $VERSION"
fi

# 架构
arch=$(uname -m)
case $arch in
  x86_64) BIN="lxdapi-amd64";;
  aarch64|arm64) BIN="lxdapi-arm64";;
  *) err "不支持架构 $arch"; exit 1;;
esac
URL="$REPO/releases/download/$VERSION/$BIN.zip"

# 依赖
info "安装依赖..."
apt update -y && apt install -y curl wget unzip openssl xxd systemd || exit 1
ok "依赖安装完成"

# 停止旧服务
systemctl stop $NAME 2>/dev/null || true

# 目录
mkdir -p "$DIR"

# 下载
TMP=$(mktemp -d)
info "下载 $URL"
wget -qO "$TMP/app.zip" "$URL" || { err "下载失败"; exit 1; }
unzip -qo "$TMP/app.zip" -d "$DIR"
chmod +x "$DIR/$BIN"
echo "$VERSION" > "$DIR/version"
rm -rf "$TMP"
ok "下载完成"

# 配置
if [[ ! -f "$CFG" || $FORCE == true ]]; then
  IP=$(curl -s ifconfig.me || echo "127.0.0.1")
  HASH=$(openssl rand -hex 32)
  cat > "$CFG" <<EOF
server:
  port: 8080
  mode: release
  tls:
    enabled: true
    cert_file: "server.crt"
    key_file: "server.key"
    auto_gen: true
    server_ips:
      - "$IP"
      - "127.0.0.1"
security:
  enable_auth: true
  api_hash: "$HASH"
  hash_expire_hours: 24
EOF
  ok "配置文件已生成"
else
  info "保留原有配置"
fi

# systemd
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

# 信息
echo
ok "安装完成！"
info "目录: $DIR"
info "配置: $CFG"
info "访问: https://$IP:8080"
