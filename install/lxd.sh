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

info "开始安装 $NAME"

info "检测系统环境..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case $ID in
        ubuntu)
            info "检测到系统: Ubuntu $VERSION_ID"
            RECOMMENDED_STORAGE="zfs"
            ;;
        debian)
            info "检测到系统: Debian $VERSION_ID"
            RECOMMENDED_STORAGE="btrfs"
            ;;
        *)
            err "不支持的系统类型: $ID，仅支持 Ubuntu 和 Debian"
            ;;
    esac
else
    err "无法检测系统类型，仅支持 Ubuntu 和 Debian 系统"
fi

arch=$(uname -m)
case $arch in
    x86_64)
        info "检测到架构: x86_64 (amd64)"
        ;;
    aarch64|arm64)
        info "检测到架构: aarch64 (arm64)"
        ;;
    *)
        err "不支持的CPU架构: $arch，仅支持 amd64 和 arm64"
        ;;
esac

if command -v lxd &> /dev/null && [[ $FORCE != true ]]; then
    warn "LXD 已安装，使用 -f 参数强制重新安装"
    lxd --version 2>/dev/null || echo "版本信息获取失败"
    exit 0
fi

info "更新软件包列表..."
apt update -y || err "软件包更新失败"

info "安装系统依赖..."
apt install -y snapd || err "snapd 安装失败"

info "启用 snapd 服务..."
systemctl enable --now snapd || err "snapd 服务启用失败"

info "等待 snapd 服务就绪..."
sleep 3

info "安装 LXD..."
if [[ $FORCE == true ]]; then
    snap install lxd --force-dangerous 2>/dev/null || snap install lxd || err "LXD 安装失败"
else
    snap install lxd || err "LXD 安装失败"
fi

if ! command -v lxd &> /dev/null; then
    err "LXD 安装失败: 命令不可用"
fi

echo
ok "LXD 安装完成！"
echo "LXD 版本: $(lxd --version 2>/dev/null || echo '版本获取失败')"
echo "推荐存储后端: $RECOMMENDED_STORAGE"
echo "系统类型: $ID $VERSION_ID"
echo "CPU架构: $arch"
echo

warn "需要手动初始化 LXD，请运行以下命令："
echo -e "${YELLOW}lxd init${NC}"
echo
info "初始化建议:"
echo "- 系统推荐选择 btrfs 存储后端"
echo "- 存储池大小根据实际需求设置"
echo "- 网络配置可以使用默认设置"
echo
info "性能优化建议:"
echo "- 关闭调试日志以提升性能并减少日志占用："
echo -e "  ${YELLOW}sudo snap set lxd daemon.debug=false${NC}"
echo -e "  ${YELLOW}sudo snap restart lxd${NC}"
echo

ok "安装完成！请按照提示进行初始化，详细教程：https://github.com/xkatld/zjmf-lxd-server/wiki"
