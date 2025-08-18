#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

REPO="https://github.com/xkatld/zjmf-lxd-server"
VERSION="v0.0.2"
NAME="zjmf-lxd-server"
DIR="/opt/$NAME"
CFG="$DIR/config.yaml"
SERVICE="/etc/systemd/system/$NAME.service"
DB_FILE="lxdapi.db"
FORCE=false

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "请使用 root 运行"

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="$2"; [[ $VERSION != v* ]] && VERSION="v$VERSION"; shift 2;;
    -f|--force) FORCE=true; shift;;
    -h|--help) echo "$0 [-v 版本] [-f]"; exit 0;;
    *) err "未知参数 $1";;
  esac
done

arch=$(uname -m)
case $arch in
  x86_64) BIN="lxdapi-amd64";;
  aarch64|arm64) BIN="lxdapi-arm64";;
  *) err "不支持架构 $arch";;
esac
DOWNLOAD_URL="$REPO/releases/download/$VERSION/$BIN.zip"

UPGRADE=false
if [[ -d "$DIR" ]] && [[ -f "$DIR/version" ]]; then
  CUR=$(cat "$DIR/version")
  if [[ $CUR != "$VERSION" || $FORCE == true ]]; then
    UPGRADE=true
    info "升级: $CUR -> $VERSION"
  else
    ok "已是最新版本 $VERSION"
    exit 0
  fi
fi

apt update -y
apt install -y curl wget unzip openssl xxd systemd || err "依赖安装失败"

systemctl stop $NAME 2>/dev/null || true

TMP_DB=$(mktemp -d)
if [[ $UPGRADE == true ]]; then
  [[ -f "$DIR/$DB_FILE" ]] && cp "$DIR/$DB_FILE" "$TMP_DB/" && ok "数据库已备份"
  rm -rf "$DIR"/*
fi
mkdir -p "$DIR"

TMP=$(mktemp -d)
wget -qO "$TMP/app.zip" "$DOWNLOAD_URL" || err "下载失败"
unzip -qo "$TMP/app.zip" -d "$DIR"
chmod +x "$DIR/$BIN"
echo "$VERSION" > "$DIR/version"
rm -rf "$TMP"

[[ -f "$TMP_DB/$DB_FILE" ]] && mv "$TMP_DB/$DB_FILE" "$DIR/"
rm -rf "$TMP_DB"

DEFAULT_IP=$(curl -s ifconfig.me || curl -s ip.sb || echo "127.0.0.1")

if [[ -f "$CFG" ]]; then
  CUR_IP=$(grep -E "^- \"([0-9]{1,3}\.){3}[0-9]{1,3}\"" "$CFG" | head -n1 | sed 's/.*"\([^"]*\)".*/\1/')
  CUR_HASH=$(grep "api_hash:" "$CFG" | sed 's/.*"\([^"]*\)".*/\1/')
else
  err "配置文件不存在，请先创建配置文件"
fi

read -p "外网IP [$CUR_IP]: " EXTERNAL_IP
EXTERNAL_IP=${EXTERNAL_IP:-$CUR_IP}
read -p "API Hash [$CUR_HASH]: " API_HASH
API_HASH=${API_HASH:-$CUR_HASH}

sed -i "s/^- \".*\"/- \"$EXTERNAL_IP\"/" "$CFG"
sed -i "s/\(api_hash:\s*\).*/\1\"$API_HASH\"/" "$CFG"

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
StandardOutput=append:$DIR/$NAME.log
StandardError=append:$DIR/$NAME.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $NAME

echo
ok "安装/升级完成"
echo "数据目录: $DIR"
systemctl is-active --quiet $NAME \
  && echo "服务状态: 已启动" \
  || echo "服务状态: 未运行"
