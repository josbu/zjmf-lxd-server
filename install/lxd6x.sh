#!/bin/bash

LXD_VERSION="6.5"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/lxd.service"

set -u

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        URL="https://github.com/canonical/lxd/releases/download/lxd-${LXD_VERSION}/bin.linux.lxd.x86_64"
        ;;
    aarch64)
        URL="https://github.com/canonical/lxd/releases/download/lxd-${LXD_VERSION}/bin.linux.lxd.aarch64"
        ;;
    *)
        error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

log "架构: $ARCH"
log "下载 LXD ${LXD_VERSION} from $URL"

wget -qO lxd "$URL" || error "下载失败"
chmod +x lxd 2>/dev/null || error "赋权失败"
mv -f lxd "${INSTALL_DIR}/lxd" 2>/dev/null || error "移动文件失败"

log "安装依赖包"
apt update -y || error "apt update 失败"
apt install -y uidmap dnsmasq-base rsync iptables || error "依赖安装失败"

if ! getent group lxd >/dev/null; then
    groupadd --system lxd || error "创建 lxd 组失败"
    log "已创建 lxd 用户组"
fi

log "配置 systemd 服务"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=LXD container hypervisor
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${INSTALL_DIR}/lxd --group lxd
Restart=on-failure
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || error "systemctl daemon-reload 失败"
systemctl enable --now lxd || error "启动 LXD 服务失败"

log "安装完成"
lxd --version || error "检查版本失败"

log "初始化请执行: sudo lxd init"
