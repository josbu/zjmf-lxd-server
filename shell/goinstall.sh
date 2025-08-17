#!/bin/bash

# ZJMF LXD Server 一键安装脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
GITHUB_REPO="https://github.com/xkatld/zjmf-lxd-server"
VERSION="v0.0.2"  # 默认版本
SERVICE_NAME="zjmf-lxd-server"
INSTALL_DIR="/opt/zjmf-lxd-server"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
UPGRADE_MODE=false
FORCE_INSTALL=false

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

log_prompt() {
    echo -e "${CYAN}[INPUT]${NC} $1"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        log_info "使用命令: sudo $0"
        exit 1
    fi
}

# 显示使用帮助
show_usage() {
    echo -e "${BLUE}用法:${NC}"
    echo "  $0 [选项]"
    echo
    echo -e "${BLUE}选项:${NC}"
    echo "  -v, --version VERSION    指定安装版本 (如: v0.0.2, 0.0.3)"
    echo "  -f, --force             强制覆盖安装，不询问确认"
    echo "  -h, --help              显示此帮助信息"
    echo
    echo -e "${BLUE}示例:${NC}"
    echo "  $0                      # 使用默认版本安装"
    echo "  $0 -v v0.0.3           # 安装指定版本"
    echo "  $0 -v 0.0.2 -f         # 强制安装指定版本"
    echo "  $0 --version v0.0.4 --force  # 完整参数格式"
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                if [[ -z "$2" ]]; then
                    log_error "版本参数不能为空"
                    show_usage
                    exit 1
                fi
                # 自动添加v前缀（如果没有的话）
                if [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
                    VERSION="v$2"
                else
                    VERSION="$2"
                fi
                shift 2
                ;;
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "使用版本: $VERSION"
    if [ "$FORCE_INSTALL" = true ]; then
        log_info "强制安装模式已启用"
    fi
}
check_current_version() {
    # 强制安装模式直接跳过版本检查
    if [ "$FORCE_INSTALL" = true ]; then
        if [ -d "$INSTALL_DIR" ]; then
            log_info "强制安装模式：将覆盖现有安装"
            UPGRADE_MODE=true
        fi
        return 1
    fi
    
    if [ ! -f "$INSTALL_DIR/version" ]; then
        return 1
    fi
    
    local current_version=$(cat "$INSTALL_DIR/version")
    log_info "当前已安装版本: $current_version"
    
    if [ "$current_version" = "$VERSION" ]; then
        echo
        log_prompt "检测到相同版本已安装，是否要重新安装？(y/N): "
        read -r reinstall_choice
        case $reinstall_choice in
            [Yy]|[Yy][Ee][Ss])
                log_info "将重新安装当前版本"
                UPGRADE_MODE=true
                return 1
                ;;
            *)
                log_info "取消安装"
                exit 0
                ;;
        esac
    else
        log_info "将从 $current_version 升级到 $VERSION"
        UPGRADE_MODE=true
        return 1
    fi
    
    return 0
}
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            BINARY_NAME="lxdapi-amd64"
            DOWNLOAD_URL="$GITHUB_REPO/releases/download/$VERSION/lxdapi-amd64.zip"
            log_success "检测到AMD64架构"
            ;;
        aarch64|arm64)
            BINARY_NAME="lxdapi-arm64"
            DOWNLOAD_URL="$GITHUB_REPO/releases/download/$VERSION/lxdapi-arm64.zip"
            log_success "检测到ARM64架构"
            ;;
        *)
            log_error "不支持的架构: $arch"
            log_error "仅支持AMD64和ARM64架构"
            exit 1
            ;;
    esac
}

# 安装依赖
install_dependencies() {
    log_info "安装必要的依赖包..."
    
    # 更新包列表
    apt update
    
    # 安装必要的包
    apt install -y curl wget unzip systemd openssl xxd
    
    log_success "依赖包安装完成"
}

# 备份现有配置
backup_current_config() {
    if [ "$UPGRADE_MODE" = true ] && [ -f "$CONFIG_FILE" ]; then
        log_info "备份当前配置文件..."
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "配置文件已备份"
        return 0
    fi
    return 1
}

# 恢复配置文件
restore_config() {
    local backup_file="$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 查找最新的备份文件
    local latest_backup=$(ls -t "$CONFIG_FILE.backup."* 2>/dev/null | head -n1)
    
    if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
        log_info "发现配置文件备份，是否恢复现有配置？"
        echo
        log_prompt "选择配置方式："
        echo "1) 保留现有配置 (推荐升级时选择)"
        echo "2) 重新配置IP和Hash"
        echo -n "请选择 (1-2): "
        read -r config_choice
        
        case $config_choice in
            1)
                cp "$latest_backup" "$CONFIG_FILE"
                log_success "已恢复现有配置"
                return 0
                ;;
            2)
                log_info "将进行重新配置"
                return 1
                ;;
            *)
                log_warning "无效选择，将进行重新配置"
                return 1
                ;;
        esac
    fi
    
    return 1
}

# 停止现有服务
stop_existing_service() {
    if [ "$UPGRADE_MODE" = true ]; then
        log_info "停止现有服务..."
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            systemctl stop "$SERVICE_NAME"
            log_success "服务已停止"
        else
            log_info "服务未在运行"
        fi
    fi
}
create_install_dir() {
    log_info "准备安装目录..."
    
    # 如果是升级模式，只备份旧的二进制文件
    if [ "$UPGRADE_MODE" = true ] && [ -d "$INSTALL_DIR" ]; then
        log_info "升级模式：备份当前程序文件..."
        if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
            cp "$INSTALL_DIR/$BINARY_NAME" "$INSTALL_DIR/${BINARY_NAME}.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    elif [ -d "$INSTALL_DIR" ]; then
        # 全新安装时备份整个目录
        log_warning "检测到已存在的安装目录，创建完整备份..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$INSTALL_DIR"
    else
        mkdir -p "$INSTALL_DIR"
    fi
    
    log_success "安装目录准备完成: $INSTALL_DIR"
}

# 下载并解压程序
download_and_extract() {
    log_info "下载ZJMF LXD Server $VERSION..."
    
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/lxdapi.zip"
    
    # 下载文件
    if ! wget -O "$zip_file" "$DOWNLOAD_URL"; then
        log_error "下载失败，请检查网络连接或URL是否正确"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_success "下载完成"
    log_info "解压文件..."
    
    # 解压到安装目录
    if ! unzip -q "$zip_file" -d "$INSTALL_DIR"; then
        log_error "解压失败"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # 记录版本信息
    echo "$VERSION" > "$INSTALL_DIR/version"
    
    log_success "程序文件解压完成，版本: $VERSION"
}

# 获取用户输入的外网IP
get_external_ip() {
    # 在升级模式下，尝试从现有配置读取IP
    if [ "$UPGRADE_MODE" = true ] && [ -f "$CONFIG_FILE" ]; then
        local current_ip=$(grep -A 10 "server_ips:" "$CONFIG_FILE" | grep -v "localhost\|127.0.0.1" | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 | sed 's/.*"\([^"]*\)".*/\1/')
        if [ -n "$current_ip" ]; then
            log_info "检测到当前配置的外网IP: $current_ip"
            echo
            log_prompt "是否使用当前IP地址？(Y/n): "
            read -r use_current_ip
            case $use_current_ip in
                [Nn]|[Nn][Oo])
                    # 继续输入新IP
                    ;;
                *)
                    EXTERNAL_IP="$current_ip"
                    log_success "使用当前外网IP: $EXTERNAL_IP"
                    return
                    ;;
            esac
        fi
    fi
    
    log_prompt "请输入您的外网IP地址："
    echo -n "外网IP: "
    read EXTERNAL_IP
    
    # 简单验证IP格式
    if [[ ! $EXTERNAL_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "IP地址格式不正确，请重新输入"
        get_external_ip
        return
    fi
    
    log_success "外网IP设置为: $EXTERNAL_IP"
}

# 生成随机API Hash
generate_api_hash() {
    # 使用openssl生成64位十六进制字符串
    if command -v openssl >/dev/null 2>&1; then
        API_HASH=$(openssl rand -hex 32)
    else
        # 备用方法：使用/dev/urandom
        API_HASH=$(head -c 32 /dev/urandom | xxd -p -c 32)
    fi
    log_success "自动生成API Hash: $API_HASH"
}

# 获取用户输入的API Hash
get_api_hash() {
    # 在升级模式下，尝试从现有配置读取Hash
    if [ "$UPGRADE_MODE" = true ] && [ -f "$CONFIG_FILE" ]; then
        local current_hash=$(grep "api_hash:" "$CONFIG_FILE" | sed 's/.*"\([^"]*\)".*/\1/')
        if [ -n "$current_hash" ] && [[ $current_hash =~ ^[a-fA-F0-9]{64}$ ]]; then
            log_info "检测到当前配置的API Hash"
            echo
            log_prompt "是否使用当前API Hash？(Y/n): "
            read -r use_current_hash
            case $use_current_hash in
                [Nn]|[Nn][Oo])
                    # 继续重新设置Hash
                    ;;
                *)
                    API_HASH="$current_hash"
                    log_success "使用当前API Hash"
                    return
                    ;;
            esac
        fi
    fi
    
    echo
    log_prompt "请选择API Hash配置方式："
    echo "1) 自动生成64位API Hash (推荐)"
    echo "2) 手动输入API Hash"
    echo -n "请选择 (1-2): "
    read hash_choice
    
    case $hash_choice in
        1)
            generate_api_hash
            ;;
        2)
            log_prompt "请输入API Hash (64位十六进制字符串)："
            echo -n "API Hash: "
            read API_HASH
            
            # 验证Hash格式 (64位十六进制)
            if [[ ! $API_HASH =~ ^[a-fA-F0-9]{64}$ ]]; then
                log_error "API Hash格式不正确，必须是64位十六进制字符串"
                get_api_hash
                return
            fi
            log_success "API Hash设置完成"
            ;;
        *)
            log_error "无效选择，请输入1或2"
            get_api_hash
            return
            ;;
    esac
}

# 创建配置文件
create_config() {
    log_info "创建配置文件..."
    
    cat > "$CONFIG_FILE" << EOF
# LXD API 配置文件
server:
  # API服务端口
  port: 8080
  # 服务模式 (debug/release)
  mode: release
  # TLS配置 (启用HTTPS/WSS)
  tls:
    enabled: true                    # 启用TLS
    cert_file: "server.crt"         # SSL证书文件路径
    key_file: "server.key"          # SSL私钥文件路径
    auto_gen: true                   # 自动生成自签证书
    server_ips:                      # 服务器IP列表(用于证书SAN)
      - "$EXTERNAL_IP"               # 外网IP
      - "localhost"                  # 本地访问
      - "127.0.0.1"                 # 本地IP

# 安全配置
security:
  # 是否启用hash验证
  enable_auth: true
  # API访问hash (用于验证请求)
  api_hash: "$API_HASH"
  # hash过期时间(小时)
  hash_expire_hours: 24
EOF
    
    log_success "配置文件创建完成: $CONFIG_FILE"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ZJMF LXD Server API Service
After=network.target lxd.service
Wants=lxd.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# 环境变量
Environment=GIN_MODE=release

# 安全设置
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "systemd服务文件创建完成"
}

# 启动并启用服务
start_service() {
    log_info "重新加载systemd配置..."
    systemctl daemon-reload
    
    log_info "启用服务开机自启..."
    systemctl enable "$SERVICE_NAME"
    
    log_info "启动ZJMF LXD Server服务..."
    if systemctl start "$SERVICE_NAME"; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败，请检查日志"
        log_info "查看日志命令: journalctl -u $SERVICE_NAME -f"
        return 1
    fi
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "服务运行正常"
    else
        log_warning "服务可能未正常启动，请检查状态"
    fi
}

# 显示服务信息
show_service_info() {
    echo
    log_success "=== ZJMF LXD Server 安装完成! ==="
    echo
    log_info "安装信息:"
    echo -e "  安装目录: ${GREEN}$INSTALL_DIR${NC}"
    echo -e "  配置文件: ${GREEN}$CONFIG_FILE${NC}"
    echo -e "  服务名称: ${GREEN}$SERVICE_NAME${NC}"
    echo -e "  服务端口: ${GREEN}8080${NC}"
    echo -e "  外网IP:   ${GREEN}$EXTERNAL_IP${NC}"
    echo -e "  API Hash: ${GREEN}$API_HASH${NC}"
    echo -e "  安装模式: ${GREEN}$([ "$UPGRADE_MODE" = true ] && echo "升级安装" || echo "全新安装")${NC}"
    echo
    log_info "常用命令:"
    echo -e "  查看服务状态: ${CYAN}systemctl status $SERVICE_NAME${NC}"
    echo -e "  查看服务日志: ${CYAN}journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "  重启服务:     ${CYAN}systemctl restart $SERVICE_NAME${NC}"
    echo -e "  停止服务:     ${CYAN}systemctl stop $SERVICE_NAME${NC}"
    echo -e "  禁用自启:     ${CYAN}systemctl disable $SERVICE_NAME${NC}"
    echo -e "  升级版本:     ${CYAN}sudo $0${NC} (重新运行此脚本)"
    echo
    log_info "访问地址:"
    echo -e "  本地访问: ${GREEN}https://localhost:8080${NC}"
    echo -e "  外网访问: ${GREEN}https://$EXTERNAL_IP:8080${NC}"
    echo
    echo
    log_warning "注意: 服务使用自签SSL证书，浏览器可能显示安全警告"
    
    # 显示当前服务状态
    echo
    log_info "当前服务状态:"
    systemctl status "$SERVICE_NAME" --no-pager -l
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    # 这里可以添加清理逻辑
}

# 主函数
main() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}      ZJMF LXD Server 安装/升级脚本${NC}"
    echo -e "${BLUE}              版本: $VERSION${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
    
    # 检查权限
    check_root
    
    # 检查当前版本（如果已安装）
    if check_current_version; then
        log_success "无需更新"
        exit 0
    fi
    
    # 检测架构
    detect_architecture
    
    # 安装依赖
    install_dependencies
    
    # 备份配置（升级模式）
    backup_current_config
    
    # 停止现有服务（升级模式）
    stop_existing_service
    
    # 创建安装目录
    create_install_dir
    
    # 下载和解压
    download_and_extract
    
    # 尝试恢复配置或重新配置
    if ! restore_config; then
        # 强制模式下跳过交互配置
        if [ "$FORCE_INSTALL" = true ]; then
            log_warning "强制安装模式：使用默认配置"
            EXTERNAL_IP="127.0.0.1"
            generate_api_hash
            create_config
        else
            # 获取用户输入
            get_external_ip
            get_api_hash
            # 创建配置文件
            create_config
        fi
    fi
    
    # 创建systemd服务
    create_systemd_service
    
    # 启动服务
    start_service
    
    # 显示安装信息
    show_service_info
    
    echo
    log_success "$([ "$UPGRADE_MODE" = true ] && echo "升级" || echo "安装")脚本执行完成!"
}

# 错误处理
trap 'log_error "安装过程中发生错误，正在清理..."; cleanup; exit 1' ERR

# 执行主函数
main "$@"
