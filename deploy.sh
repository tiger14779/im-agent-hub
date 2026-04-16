#!/bin/bash
# ============================================================
#  IM Agent Hub 一键部署脚本（Docker 版）
#  适用于全新的 Ubuntu 18.04 / 20.04 / 22.04 / 24.04 服务器
#  支持 SSL：可选配置域名 + Nginx + Let's Encrypt 自动 HTTPS
#
#  用法（在服务器上执行）：
#    # 不带域名（HTTP 模式）
#    curl -fsSL https://raw.githubusercontent.com/tiger14779/im-agent-hub/main/deploy.sh | bash
#
#    # 带域名（自动配置 HTTPS）
#    curl -fsSL https://raw.githubusercontent.com/tiger14779/im-agent-hub/main/deploy.sh | bash -s -- --domain aozhou5a.xyz
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
PORT=8080
DOMAIN=""
BRANCH="main"

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain|-d)
            DOMAIN="$2"; shift 2 ;;
        --branch|-b)
            BRANCH="$2"; shift 2 ;;
        *)
            shift ;;
    esac
done

# ---------- 检测系统 ----------
if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 用户运行，或在命令前加 sudo"
fi

info "=========================================="
info "  IM Agent Hub 一键部署"
info "=========================================="

# ---------- 安装 Docker ----------
if ! command -v docker &> /dev/null; then
    info "正在安装 Docker..."
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates gnupg lsb-release > /dev/null
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    info "Docker 安装完成"
else
    info "Docker 已安装: $(docker --version)"
fi

# ---------- 安装 Docker Compose ----------
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    info "正在安装 Docker Compose..."
    apt-get install -y -qq docker-compose-plugin > /dev/null 2>&1 || \
    apt-get install -y -qq docker-compose > /dev/null 2>&1 || \
    {
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
        curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    }
    info "Docker Compose 安装完成"
else
    info "Docker Compose 已安装"
fi

# 统一 compose 命令
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# ---------- 安装 Git ----------
if ! command -v git &> /dev/null; then
    info "正在安装 Git..."
    apt-get install -y -qq git > /dev/null
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

# ---------- 停止旧容器 ----------
if docker ps -a --format '{{.Names}}' | grep -q '^im-agent-hub$'; then
    info "停止旧容器..."
    $COMPOSE_CMD down 2>/dev/null || true
fi

# ---------- 构建并启动 ----------
info "正在构建镜像并启动容器（首次构建约 3-5 分钟）..."
$COMPOSE_CMD up -d --build

# ---------- 配置 Nginx + SSL（如果指定了域名）----------
if [ -n "$DOMAIN" ]; then
    info "检测到域名 ${DOMAIN}，开始配置 Nginx + SSL..."

    if ! command -v nginx &> /dev/null; then
        info "正在安装 Nginx..."
        apt-get update -qq
        apt-get install -y -qq nginx > /dev/null
        systemctl enable --now nginx
    fi

    if ! command -v certbot &> /dev/null; then
        info "正在安装 Certbot..."
        apt-get install -y -qq certbot python3-certbot-nginx > /dev/null
    fi

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

    location /api/call/audio {
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

    ln -sf "/etc/nginx/sites-available/${DOMAIN}" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t || error "Nginx 配置错误"
    systemctl reload nginx

    info "正在申请 Let's Encrypt SSL 证书..."
    certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --non-interactive --agree-tos --register-unsafely-without-email --redirect

    info "SSL 证书申请成功！"
    systemctl enable --now certbot.timer 2>/dev/null || true
fi

# ---------- 等待服务就绪 ----------
info "等待服务启动..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}" | grep -q "200\|301\|302"; then
        break
    fi
    sleep 2
done

# ---------- 获取服务器IP ----------
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

# ---------- 完成 ----------
echo ""
info "=========================================="
info "  部署完成！"
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
info "    查看日志:   cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f"
info "    重启服务:   cd ${INSTALL_DIR} && ${COMPOSE_CMD} restart"
info "    停止服务:   cd ${INSTALL_DIR} && ${COMPOSE_CMD} down"
info "    更新部署:   cd ${INSTALL_DIR} && git pull && ${COMPOSE_CMD} up -d --build"
if [ -n "$DOMAIN" ]; then
    info "    SSL 状态:   certbot certificates"
    info "    Nginx 日志: tail -f /var/log/nginx/access.log"
fi
echo ""
