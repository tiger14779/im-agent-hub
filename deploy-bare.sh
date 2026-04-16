#!/bin/bash
# ============================================================
#  IM Agent Hub 裸机一键部署脚本
#  适用于全新的 Ubuntu 20.04 / 22.04 / 24.04 服务器
#  省资源：不依赖 Docker，直接安装 PostgreSQL + Go 编译运行
#  支持 SSL：可选配置域名 + Nginx + Let's Encrypt 自动 HTTPS
#
#  用法（在服务器上执行）：
#    # 不带域名（HTTP 模式）
#    curl -fsSL https://raw.githubusercontent.com/tiger14779/im-agent-hub/main/deploy-bare.sh | bash
#
#    # 带域名（自动配置 HTTPS）
#    curl -fsSL https://raw.githubusercontent.com/tiger14779/im-agent-hub/main/deploy-bare.sh | bash -s -- --domain aozhou5a.xyz
#
#  部署完成后：
#    无域名:  http://服务器IP:8080
#    有域名:  https://你的域名
#    管理后台: /admin/
#    管理员账号: admin / admin123
# ============================================================

set -e

# ---------- 颜色输出 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- 配置 ----------
REPO_URL="https://github.com/tiger14779/im-agent-hub.git"
INSTALL_DIR="/opt/im-agent-hub"
GO_VERSION="1.21.13"
NODE_VERSION="18"
PORT=8080
DOMAIN=""
BRANCH="main"

DB_USER="imhub"
DB_PASS="imhub2024"
DB_NAME="imhub"

LIVEKIT_URL=""
LIVEKIT_KEY=""
LIVEKIT_SECRET=""

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain|-d)
            DOMAIN="$2"; shift 2 ;;
        --branch|-b)
            BRANCH="$2"; shift 2 ;;
        --livekit-url)
            LIVEKIT_URL="$2"; shift 2 ;;
        --livekit-key)
            LIVEKIT_KEY="$2"; shift 2 ;;
        --livekit-secret)
            LIVEKIT_SECRET="$2"; shift 2 ;;
        *)
            shift ;;
    esac
done

# ---------- 检测系统 ----------
if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 用户运行，或在命令前加 sudo"
fi

if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
    warn "此脚本为 Ubuntu 设计，其他发行版可能不兼容"
fi

info "=========================================="
info "  IM Agent Hub 裸机一键部署"
info "=========================================="

# ---------- 抑制交互式提示（needrestart / debconf）----------
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ---------- apt 包装函数：自动等待锁 + 重试 ----------
# -o DPkg::Lock::Timeout=300 让 apt 自己等锁最多 5 分钟，无需外部轮询
APT="apt-get -y -qq -o DPkg::Lock::Timeout=300"

apt_install() {
    $APT install "$@" > /dev/null
}

# 首次启动时 unattended-upgrades 可能占用锁，先等它自然结束
wait_apt_initial() {
    local waited=0
    info "检查 apt 锁状态..."
    while fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; do
        if [ $waited -eq 0 ]; then
            info "系统后台更新进行中，等待完成（最多 5 分钟）..."
        fi
        sleep 5; waited=$((waited+5))
        if [ $waited -ge 300 ]; then
            warn "等待超时，强制清除 apt 锁..."
            kill -9 $(fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null) 2>/dev/null || true
            rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock
            dpkg --configure -a 2>/dev/null || true
            break
        fi
    done
    info "apt 锁已释放，继续安装..."
}

# ---------- 系统更新 ----------
info "更新系统软件包..."
wait_apt_initial
$APT update
apt_install curl wget git build-essential

# ---------- 安装 PostgreSQL ----------
if ! command -v psql &> /dev/null; then
    info "正在安装 PostgreSQL 16..."
    apt_install gnupg lsb-release
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    $APT update
    apt_install postgresql-16
    systemctl enable --now postgresql
    info "PostgreSQL 16 安装完成"
else
    info "PostgreSQL 已安装: $(psql --version)"
fi

# ---------- 配置数据库 ----------
info "配置数据库..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" 2>/dev/null || true
info "数据库 ${DB_NAME} 就绪"

# ---------- 安装 Go ----------
if ! command -v go &> /dev/null || ! go version | grep -q "go${GO_VERSION}"; then
    info "正在安装 Go ${GO_VERSION}..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin
    info "Go $(go version | awk '{print $3}') 安装完成"
else
    info "Go 已安装: $(go version)"
fi

# ---------- 安装 Node.js ----------
if ! command -v node &> /dev/null; then
    info "正在安装 Node.js ${NODE_VERSION}..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - > /dev/null 2>&1
    apt_install nodejs
    info "Node.js $(node -v) 安装完成"
else
    info "Node.js 已安装: $(node -v)"
fi

# ---------- 拉取代码 ----------
if [ -d "$INSTALL_DIR" ]; then
    info "检测到已有安装，正在更新代码..."
    cd "$INSTALL_DIR"
    git fetch origin
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
    git pull origin "$BRANCH"
else
    info "正在克隆项目..."
    git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# ---------- 写入配置（database.host = localhost）----------
info "写入生产配置..."

# 构建可选的 livekit 配置段
LIVEKIT_YAML_BLOCK=""
if [ -n "$LIVEKIT_URL" ] && [ -n "$LIVEKIT_KEY" ] && [ -n "$LIVEKIT_SECRET" ]; then
    LIVEKIT_YAML_BLOCK="
livekit:
  ws_url: \"${LIVEKIT_URL}\"
  api_key: \"${LIVEKIT_KEY}\"
  api_secret: \"${LIVEKIT_SECRET}\""
    info "LiveKit 语音通话已配置: ${LIVEKIT_URL}"
else
    warn "未提供 LiveKit 配置（--livekit-url/key/secret），语音通话功能将不可用"
fi

cat > "${INSTALL_DIR}/server/config/config.yaml" <<EOF
server:
  port: ${PORT}
  jwt_secret: "$(openssl rand -hex 32)"

database:
  host: localhost
  port: 5432
  user: ${DB_USER}
  password: ${DB_PASS}
  dbname: ${DB_NAME}

admin:
  username: "admin"
  password: "admin123"

cleanup:
  enabled: true
  retention_days: 45
  cron: "0 3 * * *"
${LIVEKIT_YAML_BLOCK}
EOF

# ---------- 构建前端 ----------
info "构建 H5 前端..."
cd "${INSTALL_DIR}/web/h5"
npm install --silent 2>/dev/null
npm run build
rm -rf "${INSTALL_DIR}/server/static/h5"
mkdir -p "${INSTALL_DIR}/server/static/h5"
cp -r dist/. "${INSTALL_DIR}/server/static/h5/"

info "构建管理后台..."
cd "${INSTALL_DIR}/web/admin"
npm install --silent 2>/dev/null
npm run build
rm -rf "${INSTALL_DIR}/server/static/admin"
mkdir -p "${INSTALL_DIR}/server/static/admin"
cp -r dist/. "${INSTALL_DIR}/server/static/admin/"

# ---------- 构建后端 ----------
info "构建 Go 后端..."
cd "${INSTALL_DIR}/server"
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.google.cn
go mod download
CGO_ENABLED=0 GOOS=linux go build -a -o "${INSTALL_DIR}/bin/im-agent-hub" .
info "后端编译完成"

# ---------- 创建数据目录 ----------
mkdir -p "${INSTALL_DIR}/server/data/uploads"

# ---------- 创建 systemd 服务 ----------
info "创建 systemd 服务..."
cat > /etc/systemd/system/im-agent-hub.service <<EOF
[Unit]
Description=IM Agent Hub Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/server
ExecStart=${INSTALL_DIR}/bin/im-agent-hub
Restart=always
RestartSec=5
Environment=TZ=Asia/Shanghai

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable im-agent-hub

# ---------- 停止旧进程，启动新服务 ----------
systemctl restart im-agent-hub

# ---------- 配置 Nginx + SSL（如果指定了域名）----------
if [ -n "$DOMAIN" ]; then
    info "检测到域名 ${DOMAIN}，开始配置 Nginx + SSL..."

    # 安装 Nginx 和 Certbot
    if ! command -v nginx &> /dev/null; then
        info "正在安装 Nginx..."
        apt_install nginx
        systemctl enable --now nginx
    fi

    if ! command -v certbot &> /dev/null; then
        info "正在安装 Certbot..."
        apt_install certbot python3-certbot-nginx
    fi

    # 生成 Nginx 配置
    info "写入 Nginx 配置..."
    cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ws {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;
    }

    location /api/service/ws {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;
    }
}
NGINXEOF

    # 启用站点
    ln -sf "/etc/nginx/sites-available/${DOMAIN}" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # 测试并重载 Nginx
    nginx -t || error "Nginx 配置错误"
    systemctl reload nginx

    # 申请 SSL 证书
    info "正在申请 Let's Encrypt SSL 证书..."
    certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --non-interactive --agree-tos --register-unsafely-without-email --redirect

    info "SSL 证书申请成功！"
    info "自动续期已启用（certbot.timer）"

    # 验证续期定时器
    systemctl enable --now certbot.timer 2>/dev/null || true
fi

# ---------- 等待服务就绪 ----------
info "等待服务启动..."
for i in $(seq 1 15); do
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}" 2>/dev/null | grep -q "200\|301\|302"; then
        break
    fi
    sleep 2
done

# ---------- 获取服务器IP ----------
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

# ---------- 完成 ----------
echo ""
info "=========================================="
info "  裸机部署完成！"
info "=========================================="
echo ""
if [ -n "$DOMAIN" ]; then
    info "  H5 客服端:   https://${DOMAIN}"
    info "  管理后台:     https://${DOMAIN}/admin/"
    info "  SSL 证书:     Let's Encrypt（自动续期）"
else
    info "  H5 客服端:   http://${SERVER_IP}:${PORT}"
    info "  管理后台:     http://${SERVER_IP}:${PORT}/admin/"
fi
echo ""
info "  管理员账号:   admin"
info "  管理员密码:   admin123"
echo ""
info "  常用命令："
info "    查看状态:   systemctl status im-agent-hub"
info "    查看日志:   journalctl -u im-agent-hub -f"
info "    重启服务:   systemctl restart im-agent-hub"
info "    停止服务:   systemctl stop im-agent-hub"
info "    更新部署:   cd ${INSTALL_DIR} && git pull && bash deploy-bare.sh${DOMAIN:+ --domain $DOMAIN}"
if [ -n "$DOMAIN" ]; then
    info "    SSL 状态:   certbot certificates"
    info "    Nginx 日志: tail -f /var/log/nginx/access.log"
fi
echo ""
info "  资源占用（比 Docker 方式省约 200-300MB 内存）"
echo ""
