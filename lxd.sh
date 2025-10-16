#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

NAME="LXD"
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
      echo "  -d, --delete  卸载 LXD"
      echo "  -h, --help    显示帮助信息"
      exit 0;;
    *) err "未知参数 $1";;
  esac
done

if [[ $DELETE == true ]]; then
  echo "警告: 此操作将完全卸载 LXD 及其所有数据！"
  read -p "确定要继续吗? (y/N): " CONFIRM
  if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    ok "取消卸载操作"
    exit 0
  fi
  
  info "停止 LXD 服务..."
  systemctl stop lxd 2>/dev/null || true
  systemctl stop lxd.socket 2>/dev/null || true
  
  info "卸载 LXD..."
  snap remove lxd 2>/dev/null || true
  
  info "清理残留文件..."
  rm -rf /var/lib/lxd 2>/dev/null || true
  rm -rf /var/log/lxd 2>/dev/null || true
  
  ok "LXD 卸载完成"
  exit 0
fi

info "检测系统环境..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case $ID in
        ubuntu)
            info "系统: Ubuntu $VERSION_ID"
            ;;
        debian)
            info "系统: Debian $VERSION_ID"
            ;;
        *)
            err "不支持的系统: $ID (仅支持 Ubuntu/Debian)"
            ;;
    esac
else
    err "无法检测系统类型 (仅支持 Ubuntu/Debian)"
fi

arch=$(uname -m)
case $arch in
    x86_64)
        info "架构: amd64"
        ;;
    aarch64|arm64)
        info "架构: arm64"
        ;;
    *)
        err "不支持的架构: $arch (仅支持 amd64/arm64)"
        ;;
esac

if [[ $FORCE != true ]] && [[ -f /snap/bin/lxd || -f /snap/bin/lxc ]]; then
    ok "LXD 已安装"
    if [[ -f /snap/bin/lxd ]]; then
        echo "  LXD 版本: $(/snap/bin/lxd --version 2>/dev/null || echo '未知')"
    fi
    if [[ -f /snap/bin/lxc ]]; then
        echo "  LXC 版本: $(/snap/bin/lxc --version 2>/dev/null || echo '未知')"
    fi
    warn "使用 -f 参数可强制重新安装"
    exit 0
fi

info "开始安装 LXD"

info "更新软件包列表..."
apt update -y || err "软件包更新失败"

info "安装 snapd..."
apt install -y snapd || err "snapd 安装失败"

info "启用 snapd 服务..."
systemctl enable --now snapd || err "snapd 服务启用失败"

info "更新环境变量..."
export PATH="/snap/bin:$PATH"

info "等待 snapd 服务就绪..."
sleep 5

info "安装 LXD (Snap)..."
snap install lxd --channel=latest/stable || err "LXD 安装失败"

info "验证 LXD 安装..."
if [[ ! -f /snap/bin/lxd ]]; then
    err "lxd 命令不可用，安装失败"
fi

if [[ ! -f /snap/bin/lxc ]]; then
    err "lxc 命令不可用，安装失败"
fi

info "配置性能优化..."
snap set lxd daemon.debug=false 2>/dev/null || warn "性能优化配置失败"

info "重启 LXD 服务..."
snap restart lxd 2>/dev/null || warn "LXD 服务重启失败"

info "等待 LXD 服务就绪..."
sleep 3

echo
ok "LXD 安装完成！"
echo "  LXD 版本: $(/snap/bin/lxd --version 2>/dev/null || echo '未知')"
echo "  LXC 版本: $(/snap/bin/lxc --version 2>/dev/null || echo '未知')"
echo "  性能优化: 已关闭调试日志"
echo

warn "请手动初始化 LXD："
echo -e "${YELLOW}/snap/bin/lxd init${NC}"
echo
echo "初始化建议："
echo "  - 存储后端推荐: btrfs"
echo "  - 网络配置可使用默认值"
echo

ok "详细教程: https://github.com/xkatld/zjmf-lxd-server/wiki"