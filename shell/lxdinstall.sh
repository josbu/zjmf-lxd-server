#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

trap 'log_error "执行出错，请检查日志"' ERR

check_root() {
    [ "$EUID" -ne 0 ] && log_error "请使用root权限运行此脚本"
    log_success "root权限检查通过"
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "无法检测系统"
    fi
    . /etc/os-release
    case $ID in
        ubuntu)
            [ "${VERSION_ID%%.*}" -lt 24 ] && log_error "检测到Ubuntu $VERSION_ID，仅支持Ubuntu 24及以上"
            ;;
        debian)
            [ "${VERSION_ID%%.*}" -lt 12 ] && log_error "检测到Debian $VERSION_ID，仅支持Debian 12及以上"
            ;;
        *)
            log_error "检测到不支持的系统: $NAME，仅支持Ubuntu 24+ 和 Debian 12+"
            ;;
    esac
    log_success "系统检测通过: $NAME $VERSION_ID"
}

check_architecture() {
    case $(uname -m) in
        x86_64) log_success "检测到amd64架构";;
        aarch64|arm64) log_success "检测到arm64架构";;
        *) log_error "检测到不支持的架构: $(uname -m)，仅支持amd64和arm64";;
    esac
}

update_packages() {
    log_info "更新软件包源..."
    apt update -y
    log_success "软件包源更新完成"
}

install_snapd() {
    if ! command -v snap >/dev/null 2>&1; then
        log_info "安装snapd..."
        apt install -y snapd
        systemctl enable --now snapd
        sleep 5
        [ ! -L /snap ] && ln -s /var/lib/snapd/snap /snap || true
    fi
    log_success "snapd已安装"
}

install_lxd() {
    if ! snap list lxd >/dev/null 2>&1; then
        log_info "安装LXD..."
        snap install lxd
    fi
    log_success "LXD已安装"
}

configure_lxd_group() {
    REAL_USER=${SUDO_USER:-$(logname 2>/dev/null || true)}
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        usermod -aG lxd "$REAL_USER"
        log_success "用户 $REAL_USER 已加入lxd组"
        log_warning "请重新登录或执行 'newgrp lxd' 生效"
    else
        log_info "无需修改用户组"
    fi
}

show_lxd_version() {
    log_info "LXD版本: $(lxd --version || echo '未安装')"
    snap info lxd | grep -E "(installed|tracking|refresh-date)" || true
}

show_init_instructions() {
    echo
    log_success "LXD安装完成!"
    echo -e "${YELLOW}运行初始化:${NC} ${GREEN}lxd init${NC} 或 ${GREEN}lxd init --auto${NC}"
}

main() {
    log_info "脚本开始执行..."
    check_root
    check_os
    check_architecture
    update_packages
    install_snapd
    install_lxd
    configure_lxd_group
    show_lxd_version
    show_init_instructions
    log_success "脚本执行完成!"
}

main
