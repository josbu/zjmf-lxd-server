#!/bin/bash
set -e

LXD_VERSION="6.5"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/lxd.service"

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        URL="https://github.com/canonical/lxd/releases/download/lxd-${LXD_VERSION}/bin.linux.lxd.x86_64"
        ;;
    aarch64)
        URL="https://github.com/canonical/lxd/releases/download/lxd-${LXD_VERSION}/bin.linux.lxd.aarch64"
        ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo "👉 检测到架构: $ARCH"
echo "👉 下载 LXD ${LXD_VERSION} from $URL"

# 下载二进制
wget -qO lxd "$URL"
chmod +x lxd
sudo mv lxd "${INSTALL_DIR}/lxd"

# 安装依赖
echo "👉 安装依赖包"
sudo apt update
sudo apt install -y uidmap dnsmasq-base rsync iptables

# 创建 lxd group（如果不存在）
if ! getent group lxd >/dev/null; then
    sudo groupadd --system lxd
    echo "👉 已创建 lxd 用户组"
fi

# 写入 systemd unit
echo "👉 配置 systemd 服务"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
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

# 重新加载 systemd
sudo systemctl daemon-reload
sudo systemctl enable --now lxd

echo "✅ LXD ${LXD_VERSION} 已安装完成"
lxd --version

echo "👉 你可以运行以下命令初始化 LXD:"
echo "    sudo lxd init"
