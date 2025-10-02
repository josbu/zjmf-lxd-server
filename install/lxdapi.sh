#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

REPO="https://github.com/xkatld/zjmf-lxd-server"
VERSION=""
NAME="lxdapi"
DIR="/opt/$NAME"
CFG="$DIR/config.yaml"
SERVICE="/etc/systemd/system/$NAME.service"
DB_FILE="lxdapi.db"
FORCE=false
DELETE=false

log() { echo -e "$1"; }
ok() { log "${GREEN}[OK]${NC} $1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
err() { log "${RED}[ERR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "请使用 root 运行"

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="$2"; [[ $VERSION != v* ]] && VERSION="v$VERSION"; shift 2;;
    -f|--force) FORCE=true; shift;;
    -d|--delete) DELETE=true; shift;;
    -h|--help) echo "$0 -v 版本 [-f] [-d]"; exit 0;;
    *) err "未知参数 $1";;
  esac
done

if [[ $DELETE == true ]]; then
  echo "警告: 此操作将删除所有数据，包括数据库文件和备份！"
  
  if [[ -d "$DIR/backups" ]]; then
    backup_count=$(ls "$DIR/backups"/lxdapi_backup_*.zip 2>/dev/null | wc -l)
    if [[ $backup_count -gt 0 ]]; then
      echo "发现 $backup_count 个SQLite压缩备份文件将被删除"
      echo "备份文件位置: $DIR/backups/"
    fi
  fi
  
  read -p "确定要继续吗? (y/N): " CONFIRM
  if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    ok "取消删除操作"
    exit 0
  fi
  
  systemctl stop $NAME 2>/dev/null || true
  systemctl disable $NAME 2>/dev/null || true
  rm -f "$SERVICE"
  systemctl daemon-reload
  if [[ -d "$DIR" ]]; then
    rm -rf "$DIR"
    ok "已强制删除 $NAME 服务和目录（包括所有备份）"
  else
    ok "目录 $DIR 不存在，无需删除"
  fi
  exit 0
fi

if [[ -z "$VERSION" ]]; then
  err "必须提供版本号参数，使用 -v 或 --version 指定版本"
fi

arch=$(uname -m)
case $arch in
  x86_64) BIN="lxdapi-amd64";;
  aarch64|arm64) BIN="lxdapi-arm64";;
  *) err "不支持的架构: $arch，仅支持 amd64 和 arm64";;
esac

if ! command -v lxd &> /dev/null; then
  err "未检测到 LXD，请先安装 LXD"
fi

lxd_version=$(lxd --version 2>/dev/null | grep -oE '^[0-9]+')
if [[ -z "$lxd_version" || "$lxd_version" -lt 5 ]]; then
  err "LXD 版本必须 >= 5.0，当前版本: $(lxd --version)"
fi

DOWNLOAD_URL="$REPO/releases/download/$VERSION/$BIN.zip"

UPGRADE=false
if [[ -d "$DIR" ]] && [[ -f "$DIR/version" ]]; then
  CUR=$(cat "$DIR/version")
  if [[ $CUR != "$VERSION" || $FORCE == true ]]; then
    UPGRADE=true
    info "升级: $CUR -> $VERSION"
  else
    ok "已是最新版本 $VERSION"
    exit 0
  fi
fi

apt update -y
apt install -y curl wget unzip zip openssl xxd systemd iptables-persistent || err "依赖安装失败"

systemctl stop $NAME 2>/dev/null || true

backup_database() {
  local backup_dir="$DIR/backups"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local backup_name="lxdapi_backup_${timestamp}"
  
  if [[ -f "$DIR/$DB_FILE" ]]; then
    mkdir -p "$backup_dir"
    
    local temp_backup_dir=$(mktemp -d)
    
    cp "$DIR/$DB_FILE" "$temp_backup_dir/"
    [[ -f "$DIR/$DB_FILE-shm" ]] && cp "$DIR/$DB_FILE-shm" "$temp_backup_dir/"
    [[ -f "$DIR/$DB_FILE-wal" ]] && cp "$DIR/$DB_FILE-wal" "$temp_backup_dir/"
    
    cd "$temp_backup_dir" && zip -q "${backup_name}.zip" * && mv "${backup_name}.zip" "$backup_dir/"
    rm -rf "$temp_backup_dir"
    
    if [[ -f "$backup_dir/${backup_name}.zip" ]]; then
      ok "SQLite数据库已备份: ${backup_name}.zip"
      
      cd "$backup_dir" && ls -t lxdapi_backup_*.zip 2>/dev/null | tail -n +3 | while read old_backup; do
        rm -f "$old_backup" 2>/dev/null
        info "清理旧备份: $old_backup"
      done
      
      return 0
    fi
  fi
  return 1
}

check_mysql_backup_warning() {
  if [[ -f "$CFG" ]]; then
    local current_db_type=$(grep -E "^\s*type:" "$CFG" 2>/dev/null | sed 's/.*type:\s*["\x27]*\([^"\x27]*\)["\x27]*.*/\1/' | tr -d ' ')
    if [[ "$current_db_type" == "mysql" ]]; then
      echo
      echo "• MySQL数据库需要您自行备份，请注意数据安全"
      echo
      read -p "确认继续升级? (y/N): " MYSQL_UPGRADE_CONFIRM
      if [[ $MYSQL_UPGRADE_CONFIRM != "y" && $MYSQL_UPGRADE_CONFIRM != "Y" ]]; then
        echo "已取消升级，请先备份MySQL数据库"
        exit 0
      fi
    fi
  fi
}

TMP_DB=$(mktemp -d)
if [[ $UPGRADE == true ]]; then
  check_mysql_backup_warning
  backup_database
  
  if [[ -f "$DIR/$DB_FILE" ]]; then
    cp "$DIR/$DB_FILE" "$TMP_DB/" && info "临时备份已创建"
    [[ -f "$DIR/$DB_FILE-shm" ]] && cp "$DIR/$DB_FILE-shm" "$TMP_DB/" 
    [[ -f "$DIR/$DB_FILE-wal" ]] && cp "$DIR/$DB_FILE-wal" "$TMP_DB/"
  fi
  
  find "$DIR" -maxdepth 1 -type f -delete
  find "$DIR" -maxdepth 1 -type d ! -name "backups" -exec rm -rf {} + 2>/dev/null || true
elif [[ -d "$DIR" ]]; then
  backup_database
fi
mkdir -p "$DIR"
mkdir -p "$DIR/backups"

TMP=$(mktemp -d)
wget -qO "$TMP/app.zip" "$DOWNLOAD_URL" || err "下载失败"
unzip -qo "$TMP/app.zip" -d "$DIR"
chmod +x "$DIR/$BIN"
echo "$VERSION" > "$DIR/version"
rm -rf "$TMP"

if [[ -f "$TMP_DB/$DB_FILE" ]]; then
  mv "$TMP_DB/$DB_FILE" "$DIR/"
  [[ -f "$TMP_DB/$DB_FILE-shm" ]] && mv "$TMP_DB/$DB_FILE-shm" "$DIR/"
  [[ -f "$TMP_DB/$DB_FILE-wal" ]] && mv "$TMP_DB/$DB_FILE-wal" "$DIR/"
  ok "数据库已恢复"
else
  backup_dir="$DIR/backups"
  if [[ -d "$backup_dir" ]]; then
    latest_backup=$(ls -t "$backup_dir"/lxdapi_backup_*.zip 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
      local temp_restore_dir=$(mktemp -d)
      
      if unzip -q "$latest_backup" -d "$temp_restore_dir"; then
        [[ -f "$temp_restore_dir/$DB_FILE" ]] && cp "$temp_restore_dir/$DB_FILE" "$DIR/"
        [[ -f "$temp_restore_dir/$DB_FILE-shm" ]] && cp "$temp_restore_dir/$DB_FILE-shm" "$DIR/"
        [[ -f "$temp_restore_dir/$DB_FILE-wal" ]] && cp "$temp_restore_dir/$DB_FILE-wal" "$DIR/"
        
        ok "从压缩备份恢复数据库: $(basename "$latest_backup")"
      else
        echo "${YELLOW}[WARNING]${NC} 解压备份文件失败: $(basename "$latest_backup")"
      fi
      
      rm -rf "$temp_restore_dir"
    fi
  fi
fi
rm -rf "$TMP_DB"


DEFAULT_IP=$(curl -s 4.ipw.cn || echo "127.0.0.1")
DEFAULT_HASH=$(openssl rand -hex 8 | tr 'a-f' 'A-F')
DEFAULT_PORT="8080"

get_default_interface() {
  ip route | grep default | head -1 | awk '{print $5}' || echo "eth0"
}

get_interface_ipv4() {
  local interface="$1"
  ip -4 addr show "$interface" 2>/dev/null | grep inet | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1 || echo ""
}

get_interface_ipv6() {
  local interface="$1"
  ip -6 addr show "$interface" 2>/dev/null | grep inet6 | grep -v "::1" | grep -v "fe80" | head -1 | awk '{print $2}' | cut -d/ -f1 || echo ""
}

DEFAULT_INTERFACE=$(get_default_interface)
DEFAULT_IPV4=$(get_interface_ipv4 "$DEFAULT_INTERFACE")
DEFAULT_IPV6=$(get_interface_ipv6 "$DEFAULT_INTERFACE")

[[ -z "$DEFAULT_IPV4" ]] && DEFAULT_IPV4="$DEFAULT_IP"
read -p "外网IP [$DEFAULT_IP]: " EXTERNAL_IP
EXTERNAL_IP=${EXTERNAL_IP:-$DEFAULT_IP}

read -p "API Hash [$DEFAULT_HASH]: " API_HASH
API_HASH=${API_HASH:-$DEFAULT_HASH}

read -p "API 端口 [$DEFAULT_PORT]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-$DEFAULT_PORT}

echo
echo "==== 数据库配置向导 ===="
echo "请选择数据库类型："
echo "1. SQLite (默认，轻量级，无需额外配置)"
echo "2. MySQL 5.7+ (企业级，需要预先准备MySQL服务)"
echo
read -p "请选择数据库类型 [1-2]: " DB_TYPE_CHOICE

while [[ ! $DB_TYPE_CHOICE =~ ^[1-2]$ ]]; do
    echo "无效选择，请输入 1-2 之间的数字"
    read -p "请选择数据库类型 [1-2]: " DB_TYPE_CHOICE
done

if [[ $DB_TYPE_CHOICE == "1" ]]; then
    DB_TYPE="sqlite"
    DB_SQLITE_PATH="lxdapi.db"
    info "已选择 SQLite 数据库，数据库文件: lxdapi.db"
else
    DB_TYPE="mysql"
    echo
    echo "==== MySQL 数据库配置 ===="
    echo "请确保 MySQL 服务已启动，并且已创建数据库和用户"
    echo
    echo "• MySQL数据库需要您自行备份，请注意数据安全"
    echo
    read -p "我已了解MySQL备份责任，确认继续? (y/N): " MYSQL_BACKUP_CONFIRM
    if [[ $MYSQL_BACKUP_CONFIRM != "y" && $MYSQL_BACKUP_CONFIRM != "Y" ]]; then
        echo "已取消MySQL配置，请先备份数据库后重新运行安装脚本"
        exit 0
    fi
    echo
    
    read -p "MySQL 服务器地址 [localhost]: " DB_MYSQL_HOST
    DB_MYSQL_HOST=${DB_MYSQL_HOST:-localhost}
    
    read -p "MySQL 端口 [3306]: " DB_MYSQL_PORT
    DB_MYSQL_PORT=${DB_MYSQL_PORT:-3306}
    
    read -p "MySQL 用户名 [lxdapi]: " DB_MYSQL_USER
    DB_MYSQL_USER=${DB_MYSQL_USER:-lxdapi}
    
    read -p "MySQL 密码: " DB_MYSQL_PASSWORD
    while [[ -z "$DB_MYSQL_PASSWORD" ]]; do
        echo "MySQL 密码不能为空"
        read -p "MySQL 密码: " DB_MYSQL_PASSWORD
    done
    
    read -p "MySQL 数据库名 [lxdapi]: " DB_MYSQL_DATABASE
    DB_MYSQL_DATABASE=${DB_MYSQL_DATABASE:-lxdapi}
    
    
    echo
    info "正在测试 MySQL 连接..."
    if command -v mysql >/dev/null 2>&1; then
        if mysql -h"$DB_MYSQL_HOST" -P"$DB_MYSQL_PORT" -u"$DB_MYSQL_USER" -p"$DB_MYSQL_PASSWORD" -e "USE $DB_MYSQL_DATABASE;" 2>/dev/null; then
            ok "MySQL 连接测试成功"
        else
            echo "[WARNING] MySQL 连接测试失败，请检查配置"
            echo "继续安装，但请确保 MySQL 配置正确"
        fi
    else
        echo "[WARNING] 未找到 mysql 客户端，跳过连接测试"
    fi
fi

echo
echo "==== 存储池配置向导 ===="
echo "请配置 LXD 存储池（按优先级顺序尝试创建容器）"
echo

DETECTED_POOLS_LIST=$(lxc storage list --format csv 2>/dev/null | cut -d, -f1 | grep -v "^NAME$" | head -10)
if [[ -n "$DETECTED_POOLS_LIST" ]]; then
    echo "检测到的存储池："
    echo "$DETECTED_POOLS_LIST" | sed 's/^/  - /'
else
    echo "未检测到存储池"
fi
echo
echo "请选择存储池配置方式："
echo "1. 自动使用所有检测到的存储池"
echo "2. 手动指定存储池列表"
echo
read -p "请选择配置方式 [1-2]: " STORAGE_MODE

while [[ ! $STORAGE_MODE =~ ^[1-2]$ ]]; do
    echo "无效选择，请输入 1-2 之间的数字"
    read -p "请选择配置方式 [1-2]: " STORAGE_MODE
done

case $STORAGE_MODE in
  1)
    DETECTED_POOLS=$(lxc storage list --format csv 2>/dev/null | cut -d, -f1 | grep -v "^NAME$" | head -10 | tr '\n' ' ')
    if [[ -n "$DETECTED_POOLS" ]]; then
      STORAGE_POOLS=""
      for pool in $DETECTED_POOLS; do
        if [[ -n "$STORAGE_POOLS" ]]; then
          STORAGE_POOLS="$STORAGE_POOLS, \"$pool\""
        else
          STORAGE_POOLS="\"$pool\""
        fi
      done
      echo "已自动配置存储池: $DETECTED_POOLS"
    else
      STORAGE_POOLS="\"default\""
      echo "未检测到存储池，使用默认配置: default"
    fi
    ;;
  2)
    echo "请输入存储池名称，多个存储池用空格分隔（按优先级顺序）"
    echo "示例: default zfs-pool btrfs-pool"
    read -p "存储池列表: " MANUAL_POOLS
    if [[ -n "$MANUAL_POOLS" ]]; then
      STORAGE_POOLS=""
      for pool in $MANUAL_POOLS; do
        if [[ -n "$STORAGE_POOLS" ]]; then
          STORAGE_POOLS="$STORAGE_POOLS, \"$pool\""
        else
          STORAGE_POOLS="\"$pool\""
        fi
      done
      echo "已手动配置存储池: $MANUAL_POOLS"
    else
      STORAGE_POOLS="\"default\""
      echo "输入为空，使用默认配置: default"
    fi
    ;;
esac

echo
echo "==== 网络配置向导 ===="
echo "请选择网络模式:"
echo "1. IPv4 NAT (基础模式)"
echo "2. IPv4 NAT + IPv6 NAT (双栈 NAT)"
echo "3. IPv4 NAT + IPv6 NAT + IPv6 独立绑定 (全功能模式)"
echo "4. IPv4 NAT + IPv6 独立绑定 (混合模式)"
echo "5. IPv6 独立绑定 (纯 IPv6 模式)"
echo
read -p "请选择网络模式 [1-5]: " NETWORK_MODE

while [[ ! $NETWORK_MODE =~ ^[1-5]$ ]]; do
  echo "无效选择，请输入 1-5 之间的数字"
  read -p "请选择网络模式 [1-5]: " NETWORK_MODE
done

case $NETWORK_MODE in
  1)
    NAT_SUPPORT="true"
    IPV6_NAT_SUPPORT="false"
    IPV6_BINDING_ENABLED="false"
    echo "已选择: IPv4 NAT (基础模式)"
    ;;
  2)
    NAT_SUPPORT="true"
    IPV6_NAT_SUPPORT="true"
    IPV6_BINDING_ENABLED="false"
    echo "已选择: IPv4 NAT + IPv6 NAT (双栈 NAT)"
    ;;
  3)
    NAT_SUPPORT="true"
    IPV6_NAT_SUPPORT="true"
    IPV6_BINDING_ENABLED="true"
    echo "已选择: IPv4 NAT + IPv6 NAT + IPv6 独立绑定 (全功能模式)"
    ;;
  4)
    NAT_SUPPORT="true"
    IPV6_NAT_SUPPORT="false"
    IPV6_BINDING_ENABLED="true"
    echo "已选择: IPv4 NAT + IPv6 独立绑定 (混合模式)"
    ;;
  5)
    NAT_SUPPORT="false"
    IPV6_NAT_SUPPORT="false"
    IPV6_BINDING_ENABLED="true"
    echo "已选择: IPv6 独立绑定 (纯 IPv6 模式)"
    ;;
esac

echo
echo "==== 网络接口配置 ===="
read -p "外网网卡接口 [$DEFAULT_INTERFACE]: " NETWORK_INTERFACE
NETWORK_INTERFACE=${NETWORK_INTERFACE:-$DEFAULT_INTERFACE}

if [[ $NAT_SUPPORT == "true" ]]; then
  read -p "外网IPv4地址 [$DEFAULT_IPV4]: " NETWORK_IPV4
  NETWORK_IPV4=${NETWORK_IPV4:-$DEFAULT_IPV4}
else
  NETWORK_IPV4=""
fi

if [[ $IPV6_NAT_SUPPORT == "true" ]]; then
  read -p "外网IPv6地址 [$DEFAULT_IPV6]: " NETWORK_IPV6
  NETWORK_IPV6=${NETWORK_IPV6:-$DEFAULT_IPV6}
else
  NETWORK_IPV6=""
fi

if [[ $IPV6_BINDING_ENABLED == "true" ]]; then
  echo
  echo "==== IPv6 独立绑定配置 ===="
  read -p "IPv6绑定网卡接口 [$DEFAULT_INTERFACE]: " IPV6_BINDING_INTERFACE
  IPV6_BINDING_INTERFACE=${IPV6_BINDING_INTERFACE:-$DEFAULT_INTERFACE}
  
  while [[ -z "$IPV6_POOL_START" ]]; do
    read -p "IPv6地址池起始地址 (如: 2001:db8::1000): " IPV6_POOL_START
    if [[ -z "$IPV6_POOL_START" ]]; then
      echo "IPv6地址池起始地址不能为空，请重新输入"
    fi
  done
else
  IPV6_BINDING_INTERFACE=""
  IPV6_POOL_START=""
fi

replace_config_var() {
  local placeholder="$1"
  local value="$2"
  escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')
  sed -i "s/\${$placeholder}/$escaped_value/g" "$CFG"
}

replace_config_var "DB_TYPE" "$DB_TYPE"
if [[ $DB_TYPE == "mysql" ]]; then
    replace_config_var "DB_MYSQL_HOST" "$DB_MYSQL_HOST"
    replace_config_var "DB_MYSQL_PORT" "$DB_MYSQL_PORT"
    replace_config_var "DB_MYSQL_USER" "$DB_MYSQL_USER"
    replace_config_var "DB_MYSQL_PASSWORD" "$DB_MYSQL_PASSWORD"
    replace_config_var "DB_MYSQL_DATABASE" "$DB_MYSQL_DATABASE"
else
    replace_config_var "DB_MYSQL_HOST" "localhost"
    replace_config_var "DB_MYSQL_PORT" "3306"
    replace_config_var "DB_MYSQL_USER" "lxdapi"
    replace_config_var "DB_MYSQL_PASSWORD" "your_password"
    replace_config_var "DB_MYSQL_DATABASE" "lxdapi"
fi

replace_config_var "STORAGE_POOLS" "$STORAGE_POOLS"
replace_config_var "NAT_SUPPORT" "$NAT_SUPPORT"
replace_config_var "SERVER_PORT" "$SERVER_PORT"
replace_config_var "PUBLIC_NETWORK_IP_ADDRESS" "$EXTERNAL_IP"
replace_config_var "API_ACCESS_HASH" "$API_HASH"
replace_config_var "IPV6_NAT_SUPPORT" "$IPV6_NAT_SUPPORT"
replace_config_var "NETWORK_EXTERNAL_INTERFACE" "$NETWORK_INTERFACE"
replace_config_var "NETWORK_EXTERNAL_IPV4" "$NETWORK_IPV4"
replace_config_var "NETWORK_EXTERNAL_IPV6" "$NETWORK_IPV6"
replace_config_var "IPV6_BINDING_ENABLED" "$IPV6_BINDING_ENABLED"
replace_config_var "IPV6_BINDING_INTERFACE" "$IPV6_BINDING_INTERFACE"
replace_config_var "IPV6_POOL_START" "$IPV6_POOL_START"

cat > "$SERVICE" <<EOF
[Unit]
Description=lxdapi-xkatld
After=network.target

[Service]
WorkingDirectory=$DIR
ExecStart=$DIR/$BIN
Restart=always
RestartSec=5
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now $NAME

echo
ok "安装/升级完成"
echo "数据目录: $DIR"
echo "外网IP: $EXTERNAL_IP"
echo "API端口: $SERVER_PORT"
echo "API Hash: $API_HASH"
if [[ $DB_TYPE == "sqlite" ]]; then
    echo "数据库: SQLite ($DB_SQLITE_PATH)"
else
    echo "数据库: MySQL ($DB_MYSQL_HOST:$DB_MYSQL_PORT/$DB_MYSQL_DATABASE)"
fi
echo "存储池配置: [$STORAGE_POOLS]"
echo "网络模式: $(case $NETWORK_MODE in 1) echo "IPv4 NAT";; 2) echo "IPv4+IPv6 NAT";; 3) echo "全功能模式";; 4) echo "混合模式";; 5) echo "纯IPv6模式";; esac)"

if [[ -d "$DIR/backups" ]]; then
    backup_count=$(ls "$DIR/backups"/lxdapi_backup_*.zip 2>/dev/null | wc -l)
    if [[ $backup_count -gt 0 ]]; then
        latest_backup=$(ls -t "$DIR/backups"/lxdapi_backup_*.zip 2>/dev/null | head -1)
        backup_size=$(du -h "$latest_backup" 2>/dev/null | cut -f1)
        echo "SQLite备份: $backup_count 个压缩备份 (最新: $(basename "$latest_backup"), 大小: $backup_size)"
    fi
fi

echo "服务状态信息:"
systemctl status $NAME --no-pager