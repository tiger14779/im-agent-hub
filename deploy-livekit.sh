#!/bin/bash
# ============================================================
#  LiveKit 一键部署脚本 (二进制, Ubuntu 22)
#  适配：现有 Nginx + SSL 证书 + 聊天系统共存
#  使用：chmod +x deploy-livekit.sh && sudo ./deploy-livekit.sh
# ============================================================

set -e

# ── 配置区（按需修改） ────────────────────────────────────────
DOMAIN="livekit.mckao.xyz"            # LiveKit 子域名
API_KEY="livekit_key_$(openssl rand -hex 8)"       # 自动生成，也可手动填写
API_SECRET="$(openssl rand -base64 32 | tr -d '=+/' | head -c 48)"   # 自动生成

LIVEKIT_VERSION="1.10.1"              # LiveKit 版本，可改为最新
LIVEKIT_PORT=7880                      # 信令端口（内部，Nginx代理）
LIVEKIT_TCP=7881                       # RTC TCP备用
LIVEKIT_UDP=7882                       # 媒体 UDP（必须对外开放）

INSTALL_DIR="/opt/livekit"
CERT_DIR="/etc/letsencrypt/live"

# ── 颜色输出 ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

# ── 检查 root ────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "请使用 root 或 sudo 运行此脚本"

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   LiveKit 一键部署 (二进制)                   ${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# ── 1. 自动检测 SSL 证书路径 ─────────────────────────────────
info "检测 SSL 证书..."
# 支持 Let's Encrypt 泛域名证书
BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^[^.]*\.//')  # 去掉子域名前缀

CERT_FILE=""
KEY_FILE=""

# 优先级：精确域名 > 通配符 > 基础域名
for try_domain in "$DOMAIN" "*.$BASE_DOMAIN" "$BASE_DOMAIN"; do
    safe=$(echo "$try_domain" | tr '*' '_')
    if [ -f "${CERT_DIR}/${safe}/fullchain.pem" ]; then
        CERT_FILE="${CERT_DIR}/${safe}/fullchain.pem"
        KEY_FILE="${CERT_DIR}/${safe}/privkey.pem"
        success "找到证书: ${CERT_DIR}/${safe}/"
        break
    fi
done

# 如果 letsencrypt 目录找不到，尝试在 nginx 配置中提取
if [ -z "$CERT_FILE" ]; then
    warn "未在 /etc/letsencrypt 找到证书，尝试从 Nginx 配置提取..."
    CERT_FILE=$(grep -r "ssl_certificate " /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | grep -v "ssl_certificate_key" | head -1 | awk '{print $NF}' | tr -d ';')
    KEY_FILE=$(grep -r "ssl_certificate_key " /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -1 | awk '{print $NF}' | tr -d ';')
fi

if [ -z "$CERT_FILE" ] || [ ! -f "$CERT_FILE" ]; then
    error "无法找到 SSL 证书，请手动设置脚本中 CERT_FILE 和 KEY_FILE 变量"
fi

success "SSL 证书: $CERT_FILE"
success "SSL 私钥: $KEY_FILE"

# ── 2. 安装目录 ───────────────────────────────────────────────
info "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# ── 3. 下载 LiveKit 二进制 ────────────────────────────────────
LIVEKIT_BIN="$INSTALL_DIR/livekit-server"

if [ -f "$LIVEKIT_BIN" ]; then
    CURRENT_VER=$("$LIVEKIT_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
    warn "已检测到 LiveKit 二进制 (v${CURRENT_VER})，跳过下载"
else
    info "下载 LiveKit v${LIVEKIT_VERSION}..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_TAG="amd64" ;;
        aarch64) ARCH_TAG="arm64" ;;
        *)       error "不支持的架构: $ARCH" ;;
    esac

    DL_URL="https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_${LIVEKIT_VERSION}_linux_${ARCH_TAG}.tar.gz"
    TMP_TAR="/tmp/livekit.tar.gz"

    # 优先用 wget，再用 curl
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$TMP_TAR" "$DL_URL" || error "下载失败，请检查网络或版本号: $DL_URL"
    else
        curl -fL -o "$TMP_TAR" "$DL_URL" || error "下载失败，请检查网络或版本号: $DL_URL"
    fi

    tar -xzf "$TMP_TAR" -C "$INSTALL_DIR" livekit-server
    chmod +x "$LIVEKIT_BIN"
    rm -f "$TMP_TAR"
    success "LiveKit 二进制已安装: $LIVEKIT_BIN"
fi

# ── 4. 生成 livekit.yaml ──────────────────────────────────────
CONFIG_FILE="$INSTALL_DIR/livekit.yaml"

# 如果已有配置，备份
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    warn "已备份旧配置到 ${CONFIG_FILE}.bak.*"
fi

info "生成 livekit.yaml..."
cat > "$CONFIG_FILE" << EOF
port: ${LIVEKIT_PORT}
bind_addresses:
  - ""          # 监听所有接口（内网 + 外网）

rtc:
  tcp_port: ${LIVEKIT_TCP}
  udp_port: ${LIVEKIT_UDP}
  use_external_ip: true   # 搬瓦工/VPS 必须开启，自动获取公网IP

keys:
  ${API_KEY}: ${API_SECRET}

logging:
  level: info
  pion_level: error    # 减少 WebRTC 底层噪音日志
EOF

success "配置文件已生成: $CONFIG_FILE"

# ── 5. 创建 systemd 服务 ──────────────────────────────────────
SERVICE_FILE="/etc/systemd/system/livekit.service"
info "创建 systemd 服务..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=LiveKit Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LIVEKIT_BIN} --config ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=65536
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable livekit
systemctl restart livekit
sleep 2

if systemctl is-active --quiet livekit; then
    success "LiveKit 服务已启动"
else
    error "LiveKit 服务启动失败，请查看: journalctl -u livekit -n 50"
fi

# ── 6. 开放防火墙端口（不影响其他端口）───────────────────────
info "配置防火墙..."

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow ${LIVEKIT_TCP}/tcp comment "LiveKit RTC TCP" 2>/dev/null || true
    ufw allow ${LIVEKIT_UDP}/udp comment "LiveKit RTC UDP" 2>/dev/null || true
    # 7880 不对外暴露，Nginx 代理即可
    success "ufw 规则已添加 (TCP ${LIVEKIT_TCP}, UDP ${LIVEKIT_UDP})"
fi

if command -v iptables &>/dev/null; then
    iptables -C INPUT -p tcp --dport ${LIVEKIT_TCP} -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport ${LIVEKIT_TCP} -j ACCEPT
    iptables -C INPUT -p udp --dport ${LIVEKIT_UDP} -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport ${LIVEKIT_UDP} -j ACCEPT
    # 持久化（如果有 netfilter-persistent）
    command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true
    success "iptables 规则已添加"
fi

# ── 7. 添加 Nginx 配置（不修改现有配置）─────────────────────
NGINX_CONF="/etc/nginx/sites-available/livekit"
NGINX_ENABLED="/etc/nginx/sites-enabled/livekit"
info "配置 Nginx 反向代理..."

cat > "$NGINX_CONF" << EOF
# LiveKit 信令代理 —— 独立 server 块，不影响已有配置
server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # WebSocket 代理到 LiveKit 信令端口
    # livekit-client@2 发送的 join_request= 参数较大，需要足够的头部缓冲
    large_client_header_buffers 8 64k;

    location / {
        proxy_pass         http://127.0.0.1:${LIVEKIT_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffer_size  64k;
    }
}
EOF

# 如果已启用则跳过，避免重复软链接报错
if [ ! -L "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_CONF" "$NGINX_ENABLED"
fi

# 测试 Nginx 配置是否有语法错误
nginx -t && systemctl reload nginx
success "Nginx 配置已添加并重载"

# ── 8. 输出部署结果 ───────────────────────────────────────────
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   LiveKit 部署完成！                          ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "  ${YELLOW}WSS 地址${NC}  : wss://${DOMAIN}"
echo -e "  ${YELLOW}API Key${NC}   : ${API_KEY}"
echo -e "  ${YELLOW}API Secret${NC}: ${API_SECRET}"
echo -e "  ${YELLOW}UDP 端口${NC}  : ${LIVEKIT_UDP}  ← 搬瓦工控制面板也要放行此端口"
echo ""
echo -e "  ${BLUE}配置文件${NC}: ${CONFIG_FILE}"
echo -e "  ${BLUE}Nginx配置${NC}: ${NGINX_CONF}"
echo ""
echo -e "  查看日志  : ${YELLOW}journalctl -u livekit -f${NC}"
echo -e "  重启服务  : ${YELLOW}systemctl restart livekit${NC}"
echo ""

# ── 9. 生成项目配置片段 ───────────────────────────────────────
PROJECT_CONFIG="$INSTALL_DIR/config-for-project.yaml"
cat > "$PROJECT_CONFIG" << EOF
# 将以下内容填入 h5/server/config/config.yaml 的 livekit 节
livekit:
  ws_url: "wss://${DOMAIN}"
  api_key: "${API_KEY}"
  api_secret: "${API_SECRET}"
EOF

echo -e "  ${GREEN}项目配置片段已保存到: ${PROJECT_CONFIG}${NC}"
echo ""

# ── 10. 本地/异地测试命令 ────────────────────────────────────
echo -e "${BLUE}── 测试命令（在本机或另一台服务器执行）────────${NC}"
echo ""
echo -e "  # 测试 HTTPS/WSS 是否通"
echo -e "  ${YELLOW}curl -I https://${DOMAIN}${NC}"
echo ""
echo -e "  # 测试 UDP 7882 是否通（需安装 netcat）"
echo -e "  ${YELLOW}nc -u -z -w3 $(curl -s ifconfig.me 2>/dev/null || echo '212.50.246.152') ${LIVEKIT_UDP} && echo OK${NC}"
echo ""
echo -e "  # 查看 LiveKit 状态"
echo -e "  ${YELLOW}curl https://${DOMAIN}/rtc/validate${NC}"
echo ""
