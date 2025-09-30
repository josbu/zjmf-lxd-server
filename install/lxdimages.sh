#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

REPO="https://github.com/xkatld/zjmf-lxd-server"
NAME="lxdimages"
INSTALL_DIR="/usr/local/bin"
FORCE=false
DELETE=false

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
warn() { log "${YELLOW}[WARN]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "请使用 root 运行"

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force) FORCE=true; shift;;
    -d|--delete) DELETE=true; shift;;
    -h|--help) 
      echo "用法: $0 [选项]"
      echo "选项:"
      echo "  -f, --force   强制重新安装"
      echo "  -d, --delete  删除已安装的程序"
      echo "  -h, --help    显示帮助信息"
      exit 0;;
    *) err "未知参数 $1";;
  esac
done

if [[ $DELETE == true ]]; then
  echo "警告: 此操作将删除已安装的 $NAME 程序！"
  read -p "确定要继续吗? (y/N): " CONFIRM
  if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    ok "取消删除操作"
    exit 0
  fi
  
  if [[ -f "$INSTALL_DIR/$NAME" ]]; then
    rm -f "$INSTALL_DIR/$NAME"
    ok "已删除 $NAME 程序"
  else
    warn "程序 $NAME 未安装，无需删除"
  fi
  exit 0
fi

info "开始安装 $NAME 程序"

info "检测系统架构..."
arch=$(uname -m)
case $arch in
  x86_64) 
    BIN="lxdimages-amd64"
    info "检测到架构: x86_64 (amd64)"
    ;;
  aarch64|arm64) 
    BIN="lxdimages-arm64"
    info "检测到架构: aarch64 (arm64)"
    ;;
  *) 
    err "不支持的架构: $arch，仅支持 amd64 和 arm64"
    ;;
esac

if [[ -f "$INSTALL_DIR/$NAME" ]] && [[ $FORCE != true ]]; then
  warn "$NAME 已安装，使用 -f 参数强制重新安装"
  exit 0
fi

info "检查系统依赖..."
apt update -y >/dev/null 2>&1
apt install -y curl wget || err "依赖安装失败"

DOWNLOAD_URL="$REPO/raw/refs/heads/main/lxdimages/$BIN"
info "下载程序: $DOWNLOAD_URL"

TMP=$(mktemp)
if ! wget -q --show-progress -O "$TMP" "$DOWNLOAD_URL"; then
  err "下载失败: $DOWNLOAD_URL"
fi

if [[ ! -s "$TMP" ]]; then
  rm -f "$TMP"
  err "下载的文件为空或无效"
fi

info "安装程序到 $INSTALL_DIR/$NAME"
mkdir -p "$INSTALL_DIR"
mv "$TMP" "$INSTALL_DIR/$NAME"
chmod +x "$INSTALL_DIR/$NAME"

if [[ ! -x "$INSTALL_DIR/$NAME" ]]; then
  err "安装失败: 程序不可执行"
fi

echo
ok "安装完成！"
echo "程序路径: $INSTALL_DIR/$NAME"
echo "系统架构: $arch"
echo "二进制文件: $BIN"

if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  warn "$INSTALL_DIR 不在 PATH 中，请手动添加或使用完整路径"
  echo "可以运行: export PATH=\"\$PATH:$INSTALL_DIR\""
fi

echo
info "程序信息:"
if "$INSTALL_DIR/$NAME" --version 2>/dev/null; then
  :
elif "$INSTALL_DIR/$NAME" -v 2>/dev/null; then
  :
elif "$INSTALL_DIR/$NAME" version 2>/dev/null; then
  :
else
  echo "程序已安装，可以使用 $NAME 命令运行，详细教程：https://github.com/xkatld/zjmf-lxd-server/wiki"
fi

echo
ok "$NAME 安装完成！"
