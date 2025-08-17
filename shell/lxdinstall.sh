#!/bin/bash

# LXD自动安装脚本
# 支持Debian和Ubuntu系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        log_info "使用命令: sudo $0"
        exit 1
    fi
}

# 检查操作系统
check_os() {
    log_info "检查操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        log_error "无法确定操作系统版本"
        exit 1
    fi
    
    case $OS in
        "Ubuntu")
            log_success "检测到Ubuntu系统 - 版本: $VERSION"
            ;;
        "Debian GNU/Linux")
            log_success "检测到Debian系统 - 版本: $VERSION"
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            log_error "此脚本仅支持Debian和Ubuntu系统"
            exit 1
            ;;
    esac
}

# 检查系统架构
check_architecture() {
    log_info "检查系统架构..."
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            log_success "检测到x86_64架构"
            ;;
        aarch64|arm64)
            log_success "检测到ARM64架构"
            ;;
        armv7l)
            log_success "检测到ARMv7架构"
            ;;
        *)
            log_warning "检测到架构: $ARCH"
            log_warning "可能不被完全支持，但将尝试继续安装"
            ;;
    esac
}

# 更新软件包源
update_packages() {
    log_info "更新软件包源..."
    apt update
    log_success "软件包源更新完成"
}

# 安装snapd
install_snapd() {
    log_info "检查snapd安装状态..."
    
    if command -v snap >/dev/null 2>&1; then
        log_success "snapd已安装"
        snap version
        return 0
    fi
    
    log_info "安装snapd..."
    apt install -y snapd
    
    # 启动snapd服务
    systemctl enable snapd
    systemctl start snapd
    
    # 等待snapd初始化
    log_info "等待snapd服务初始化..."
    sleep 10
    
    # 创建snap软链接（对于某些系统可能需要）
    if [ ! -L /snap ]; then
        ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
    fi
    
    log_success "snapd安装完成"
    snap version
}

# 安装LXD
install_lxd() {
    log_info "检查LXD安装状态..."
    
    if snap list lxd >/dev/null 2>&1; then
        log_success "LXD已通过snap安装"
        return 0
    fi
    
    log_info "通过snap安装LXD..."
    snap install lxd
    
    log_success "LXD安装完成"
}

# 配置用户组
configure_lxd_group() {
    log_info "配置LXD用户组..."
    
    # 获取当前登录用户（不是root）
    REAL_USER=$(who am i | awk '{print $1}' | head -n1)
    if [ -z "$REAL_USER" ]; then
        REAL_USER=$SUDO_USER
    fi
    
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        usermod -aG lxd "$REAL_USER"
        log_success "用户 $REAL_USER 已添加到lxd组"
        log_warning "请注销并重新登录以使组权限生效，或使用 'newgrp lxd' 命令"
    else
        log_warning "无法确定当前用户，请手动将用户添加到lxd组: usermod -aG lxd [username]"
    fi
}

# 显示LXD版本信息
show_lxd_version() {
    log_info "LXD版本信息："
    lxd --version
    echo
    
    log_info "LXD详细信息："
    snap info lxd | grep -E "(installed|tracking|refresh-date)"
}

# 显示初始化命令和说明
show_init_instructions() {
    echo
    log_success "=== LXD安装完成! ==="
    echo
    log_info "下一步操作："
    echo
    echo -e "${YELLOW}1. 初始化LXD:${NC}"
    echo -e "   ${GREEN}lxd init${NC}"
    echo
    echo -e "${YELLOW}2. 或使用自动配置初始化:${NC}"
    echo -e "   ${GREEN}lxd init --auto${NC}"
    echo
    log_warning "注意: 如果您不是root用户，请确保已退出并重新登录以使lxd组权限生效"
}

# 主函数
main() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           LXD 自动安装脚本${NC}"
    echo -e "${BLUE}        支持 Debian 和 Ubuntu 系统${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
    
    check_root
    check_os
    check_architecture
    update_packages
    install_snapd
    install_lxd
    configure_lxd_group
    show_lxd_version
    show_init_instructions
    
    echo
    log_success "脚本执行完成!"
}

# 错误处理
trap 'log_error "脚本执行过程中发生错误，请检查上述输出信息"; exit 1' ERR

# 执行主函数
main
