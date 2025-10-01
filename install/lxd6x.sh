#!/bin/bash
# 安装 LXD（默认版本 6.5）
# 用法: ./install-lxd.sh [VERSION]

VERSION="${1:-6.5}"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/lxd.service"

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   FILE="bin.linux.lxc.x86_64" ;;
    aarch64)  FILE="bin.linux.lxc.aarch64" ;;
    *)        err "未知架构: $ARCH"; exit 1 ;;
esac

URL="https://github.com/canonical/lxd/releases/download/lxd-${VERSION}/${FILE}"
log "架构: $ARCH"
log "下载 LXD ${VERSION} from $URL"

# 下载
if ! curl -L -o lxd "$URL"; then
    err "下载失败 $URL"
else
    chmod +x lxd && mv -f lxd "${INSTALL_DIR}/lxd" || err "安装二进制失败"
fi

# 安装依赖
apt update -y || err "apt update 失败"
apt install -y uidmap dnsmasq-base rsync iptables || err "依赖安装失败"

# 添加 lxd group
if ! getent group lxd >/dev/null; then
    groupadd --system lxd || err "创建 lxd 组失败"
fi

# systemd service
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

systemctl daemon-reload || err "daemon-reload 失败"
systemctl enable --now lxd || err "启动 LXD 服务失败"

log "安装完成"
lxd --version || err "无法检查版本"

log "初始化请执行: sudo lxd init"
