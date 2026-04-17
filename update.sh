#!/bin/bash
# ============================================================
#  IM Agent Hub 服务器一键更新脚本
#  适用于已通过 deploy-bare.sh 部署的服务器
#
#  用法：
#    bash /opt/im-agent-hub/update.sh
#
#  或直接从 GitHub 拉取执行：
#    curl -fsSL https://raw.githubusercontent.com/tiger14779/im-agent-hub/feature/voice-call/update.sh | bash
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

INSTALL_DIR="/opt/im-agent-hub"
BRANCH="${1:-feature/voice-call}"

[ "$(id -u)" -ne 0 ] && error "请使用 root 用户运行"
[ -d "$INSTALL_DIR" ] || error "未找到安装目录 $INSTALL_DIR，请先运行 deploy-bare.sh"

info "=========================================="
info "  IM Agent Hub 更新部署"
info "  分支: $BRANCH"
info "=========================================="

# ---------- 拉取最新代码 ----------
info "拉取最新代码..."
cd "$INSTALL_DIR"
git fetch origin
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
git pull origin "$BRANCH"
info "代码已更新到: $(git log -1 --format='%h %s')"

# ---------- 确保 Go 在 PATH 中 ----------
export PATH=$PATH:/usr/local/go/bin
command -v go &>/dev/null || error "Go 未安装，请先运行完整的 deploy-bare.sh"
info "Go 版本: $(go version)"

# ---------- 重新编译后端 ----------
info "编译后端..."
cd "$INSTALL_DIR/server"
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.google.cn
go mod download -x 2>/dev/null | tail -3 || true
mkdir -p "$INSTALL_DIR/bin"
CGO_ENABLED=0 GOOS=linux go build -a -o "$INSTALL_DIR/bin/im-agent-hub" .
info "后端编译完成: $(ls -lh $INSTALL_DIR/bin/im-agent-hub | awk '{print $5, $9}')"

# ---------- 重新构建 H5 前端 ----------
if command -v node &>/dev/null && command -v npm &>/dev/null; then
    info "重新构建 H5 前端..."
    cd "$INSTALL_DIR/web/h5"
    npm install --silent
    npm run build
    rm -rf "$INSTALL_DIR/server/static/h5"
    mkdir -p "$INSTALL_DIR/server/static/h5"
    cp -r dist/. "$INSTALL_DIR/server/static/h5/"
    info "H5 前端构建完成"

    info "重新构建管理后台前端..."
    cd "$INSTALL_DIR/web/admin"
    npm install --silent
    npm run build
    rm -rf "$INSTALL_DIR/server/static/admin"
    mkdir -p "$INSTALL_DIR/server/static/admin"
    cp -r dist/. "$INSTALL_DIR/server/static/admin/"
    info "管理后台前端构建完成"
else
    warn "Node.js/npm 未安装，跳过前端构建（静态文件保持不变）"
fi

# ---------- 更新 Nginx 配置（如果已安装且站点配置存在）----------
if command -v nginx &>/dev/null; then
    # 检测已部署的域名（取 sites-enabled 里第一个非 default 的配置文件名）
    NGINX_SITE=$(ls /etc/nginx/sites-enabled/ 2>/dev/null | grep -v '^default$' | head -1)
    if [ -n "$NGINX_SITE" ]; then
        DOMAIN="$NGINX_SITE"
        PORT=$(grep -oP '(?<=proxy_pass http://127\.0\.0\.1:)\d+' "/etc/nginx/sites-available/${DOMAIN}" 2>/dev/null | head -1)
        PORT="${PORT:-8080}"
        info "检测到 Nginx 站点: ${DOMAIN}（后端端口 ${PORT}），更新配置..."

        # 判断是否已有 SSL 证书，直接写入对应配置，避免依赖 certbot --reinstall
        if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
            info "检测到 SSL 证书，写入 HTTP + HTTPS 完整配置..."
            cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

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
        else
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
        fi
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            info "Nginx 配置已更新并重载 ✓"
        else
            warn "Nginx 配置测试失败，跳过重载，请手动检查: nginx -t"
        fi
    else
        info "未检测到活跃的 Nginx 站点，跳过 Nginx 更新"
    fi
else
    info "Nginx 未安装，跳过"
fi

# ---------- 重启服务 ----------
info "重启服务..."
systemctl restart im-agent-hub
sleep 2

if systemctl is-active --quiet im-agent-hub; then
    info "服务已成功启动 ✓"
    systemctl status im-agent-hub --no-pager -l | tail -5
else
    error "服务启动失败，查看日志: journalctl -u im-agent-hub -n 30"
fi

info "=========================================="
info "  更新完成！"
info "=========================================="
