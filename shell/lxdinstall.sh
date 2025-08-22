
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 错误处理
set -euo pipefail

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root权限运行此脚本"
    exit 1
fi

# 检查系统类型 - 只支持Ubuntu和Debian
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
        log_error "不支持的系统类型：$ID，仅支持Ubuntu和Debian系统"
        exit 1
    fi
else
    log_error "无法检测系统类型，仅支持Ubuntu和Debian系统"
    exit 1
fi

# 检查CPU架构 - 只支持amd64和arm64
arch=$(uname -m)
if [ "$arch" != "x86_64" ] && [ "$arch" != "aarch64" ] && [ "$arch" != "arm64" ]; then
    log_error "不支持的CPU架构：$arch，仅支持amd64和arm64架构"
    exit 1
fi

# 更新软件包
apt update -y

# 安装snapd
apt install -y snapd
systemctl enable --now snapd

# 安装LXD
snap install lxd

# 提示只能手动初始化
echo
log_info "LXD安装完成"
log_error "只能手动初始化，请运行以下命令："
echo -e "${YELLOW}lxd init${NC} 储存必须选择zfs"
echo
