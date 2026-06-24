#!/bin/bash
# ============================================================
#  2-setup-new.sh  — 在新服务器上跑一次，一次性初始化环境
#
#  做的事:
#    1. 装 Go 1.21 / PostgreSQL 16 / Nginx / Certbot
#    2. 克隆代码 + 编译二进制到 /opt/im-hub/bin/im-agent-hub
#    3. 写 systemd 模板服务 im-hub@.service
#    4. 限制 journald 大小 (防 13 个服务日志爆盘)
#    5. 调优 PG 配置 (shared_buffers 1GB 适合 8GB 机器)
#    6. 装每日自动备份 cron
#    7. 写 nginx 默认 server (拒绝未配置的域名)
#    8. 创建 /opt/im-hub/sites/ 和 /opt/im-hub/secrets/ 目录
#
#  用法 (在新服务器作为 root):
#    bash 2-setup-new.sh [--branch main]
# ============================================================
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/tiger14779/im-agent-hub.git}"
BRANCH="${BRANCH:-main}"
GO_VERSION="${GO_VERSION:-1.21.13}"
NODE_VERSION="${NODE_VERSION:-18}"

BASE_DIR="/opt/im-hub"
SRC_DIR="${BASE_DIR}/src"
BIN_DIR="${BASE_DIR}/bin"
SITES_DIR="${BASE_DIR}/sites"
SECRETS_DIR="${BASE_DIR}/secrets"
BACKUP_DIR="${BASE_DIR}/backups"

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch) BRANCH="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        *) echo "unknown: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || error "请用 root 跑 (或 sudo)"

# ---------- 0. 创建基础目录 ----------
info "创建基础目录..."
mkdir -p "$BIN_DIR" "$SITES_DIR" "$SECRETS_DIR" "$BACKUP_DIR"
chmod 700 "$SECRETS_DIR"

# ---------- 1. 装系统依赖 ----------
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -qq -o DPkg::Lock::Timeout=300"

info "更新 apt..."
$APT update
$APT install curl wget git build-essential gnupg lsb-release rsync >/dev/null

# ---------- 2. 装 PostgreSQL 16 ----------
if ! command -v psql >/dev/null; then
    info "装 PostgreSQL 16..."
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list
    $APT update
    $APT install postgresql-16 >/dev/null
    systemctl enable --now postgresql
else
    info "PostgreSQL 已装: $(psql --version)"
fi

# ---------- 3. 调优 PG 配置 ----------
PG_CONF="/etc/postgresql/16/main/postgresql.conf"
if [ -f "$PG_CONF" ] && ! grep -q "# im-hub tuning" "$PG_CONF"; then
    info "调优 PostgreSQL 配置 (适合 8GB 机器, 13 库)..."
    cat >> "$PG_CONF" <<EOF

# im-hub tuning (added by 2-setup-new.sh)
shared_buffers = 1GB
effective_cache_size = 4GB
work_mem = 16MB
maintenance_work_mem = 256MB
max_connections = 200
autovacuum = on
log_min_duration_statement = 1000
EOF
    systemctl restart postgresql
fi

# ---------- 4. 装 Go ----------
if ! command -v go >/dev/null || ! go version | grep -q "go${GO_VERSION}"; then
    info "装 Go ${GO_VERSION}..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
fi
export PATH=$PATH:/usr/local/go/bin
info "Go: $(go version)"

# ---------- 5. 装 Node (前端构建用) ----------
if ! command -v node >/dev/null; then
    info "装 Node ${NODE_VERSION}..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - >/dev/null 2>&1
    $APT install nodejs >/dev/null
fi
info "Node: $(node -v)"

# ---------- 6. 拉代码 ----------
if [ -d "$SRC_DIR" ]; then
    info "更新代码..."
    cd "$SRC_DIR"
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    info "克隆代码..."
    git clone -b "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi

# ---------- 6b. 把 migration 脚本复制到使用位置 ----------
info "复制 migration 脚本到 ${BASE_DIR}/migration/ ..."
mkdir -p "${BASE_DIR}/migration"
cp "${SRC_DIR}/migration/"*.sh "${BASE_DIR}/migration/"
chmod +x "${BASE_DIR}/migration/"*.sh

# ---------- 7. 构建前端 (一份共享) ----------
info "构建 H5 前端..."
cd "${SRC_DIR}/web/h5"
npm install --silent 2>/dev/null
npm run build
rm -rf "${SRC_DIR}/server/static/h5"
mkdir -p "${SRC_DIR}/server/static/h5"
cp -r dist/. "${SRC_DIR}/server/static/h5/"

info "构建管理后台..."
cd "${SRC_DIR}/web/admin"
npm install --silent 2>/dev/null
npm run build
rm -rf "${SRC_DIR}/server/static/admin"
mkdir -p "${SRC_DIR}/server/static/admin"
cp -r dist/. "${SRC_DIR}/server/static/admin/"

# ---------- 8. 编译后端 (一份共享二进制) ----------
info "编译 Go 后端..."
cd "${SRC_DIR}/server"
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.google.cn
go mod download
CGO_ENABLED=0 GOOS=linux go build -a -o "${BIN_DIR}/im-agent-hub" .

# ---------- 9. systemd 模板服务 ----------
info "创建 systemd 模板服务 im-hub@.service ..."
cat > /etc/systemd/system/im-hub@.service <<EOF
[Unit]
Description=IM Agent Hub site %i
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${SITES_DIR}/%i
ExecStart=${BIN_DIR}/im-agent-hub
Environment=IM_AGENT_HUB_CONFIG=${SITES_DIR}/%i/config.yaml
Environment=TZ=Asia/Shanghai
Restart=always
RestartSec=5
# 资源限制 (单实例)
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# ---------- 10. 限制 journald 大小 ----------
info "限制 journald 大小 (防 13 服务日志爆盘)..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/im-hub.conf <<EOF
[Journal]
SystemMaxUse=2G
SystemMaxFileSize=200M
SystemKeepFree=2G
EOF
systemctl restart systemd-journald

# ---------- 11. 装 Nginx + Certbot ----------
if ! command -v nginx >/dev/null; then
    info "装 Nginx + Certbot..."
    $APT install nginx certbot python3-certbot-nginx >/dev/null
    systemctl enable --now nginx
fi

# ---------- 12. Nginx 全局兜底: 未配置的域名直接拒绝 ----------
info "写 nginx 默认 server (拒绝未知域名)..."
cat > /etc/nginx/sites-available/00-default-deny <<'EOF'
# 兜底: 任何没匹配到具体 server_name 的请求都返回 444 (关闭连接)
# 防止 DNS 错配 / Host 头篡改导致请求被错误路由
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
EOF
ln -sf /etc/nginx/sites-available/00-default-deny /etc/nginx/sites-enabled/00-default-deny
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# ---------- 13. 每日自动备份 cron ----------
info "装每日自动备份 cron (凌晨 4 点, 保留 7 天)..."
cat > /etc/cron.d/im-hub-backup <<EOF
# Backup all im-hub PG databases nightly
0 4 * * * root /opt/im-hub/backup-all.sh >> /var/log/im-hub-backup.log 2>&1
EOF

cat > "${BASE_DIR}/backup-all.sh" <<'EOF'
#!/bin/bash
# Dump all imhub_* databases to /opt/im-hub/backups/YYYY-MM-DD/
set -e
DATE=$(date +%Y-%m-%d)
DEST="/opt/im-hub/backups/$DATE"
mkdir -p "$DEST"

# Dump every database named imhub_*
for DB in $(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname LIKE 'imhub_%';"); do
    sudo -u postgres pg_dump -Fc "$DB" > "${DEST}/${DB}.dump"
    echo "[$(date -Iseconds)] backed up $DB → ${DEST}/${DB}.dump ($(du -h ${DEST}/${DB}.dump | cut -f1))"
done

# Cleanup older than 7 days
find /opt/im-hub/backups -maxdepth 1 -type d -name '20*' -mtime +7 -exec rm -rf {} +
echo "[$(date -Iseconds)] backup done, kept latest 7 days"
EOF
chmod +x "${BASE_DIR}/backup-all.sh"

# ---------- 14. uploads 清理 cron (只清自动产生的无用 .docx, 保留头像/图片/语音) ----------
info "装 uploads 清理 cron (每天清 7 天前的 .docx, 图片/头像不动)..."
cat > /etc/cron.d/im-hub-uploads-cleanup <<'EOF'
# 业务每 5 分钟自动产生一个 .docx (无用), 不清会撑爆磁盘
# 其他类型文件 (图片/头像/语音/视频) 保留不删 (是用户真实数据)
30 3 * * * root find /opt/im-hub/sites/*/data/uploads -type f -name "*.docx" -mtime +7 -delete 2>/dev/null
EOF

# ---------- 15. 完成 ----------
echo ""
info "==========================================="
info "  ✅ 新服务器初始化完成"
info "==========================================="
echo ""
echo "  二进制:     ${BIN_DIR}/im-agent-hub"
echo "  Sites:      ${SITES_DIR}/ (空, 等 3-init-site.sh 创建)"
echo "  Secrets:    ${SECRETS_DIR}/ (上传 *.secrets 到这里)"
echo "  Backups:    ${BACKUP_DIR}/ (每日 04:00 自动备份)"
echo ""
echo "  下一步:"
echo "    1. 上传旧服务器的 secrets 文件:"
echo "       scp ./audit/*.secrets new-server:${SECRETS_DIR}/"
echo "    2. 上传 sites.csv:"
echo "       scp sites.csv new-server:${BASE_DIR}/"
echo "    3. 对每个 site 跑初始化:"
echo "       bash 3-init-site.sh 01"
echo "       bash 3-init-site.sh 02"
echo "       ..."
echo ""
