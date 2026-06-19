#!/bin/bash
# ============================================================
#  1-audit-old.sh  — 在旧服务器上跑，只读，不动任何业务
#
#  作用:
#    - 读出当前 im-agent-hub 的关键信息 (域名/DB大小/uploads大小/secret)
#    - 生成 /tmp/im-hub-audit/site_XX.manifest (公开，可放心传输)
#    - 生成 /tmp/im-hub-audit/site_XX.secrets  (敏感，权限 600)
#
#  用法:
#    bash 1-audit-old.sh                   # 自动检测 site_id
#    bash 1-audit-old.sh --site-id 03      # 手动指定
# ============================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/im-agent-hub}"
CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"
UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"
OUT_DIR="/tmp/im-hub-audit"

SITE_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --site-id) SITE_ID="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"; UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

# ---------- 前置检查 ----------
[ -f "$CONFIG_FILE" ] || { echo "❌ config not found: $CONFIG_FILE"; exit 1; }
command -v psql >/dev/null || { echo "❌ psql not installed"; exit 1; }

# ---------- 从 nginx 推断域名 (如果存在) ----------
DETECTED_DOMAIN=""
if [ -d /etc/nginx/sites-enabled ]; then
    DETECTED_DOMAIN=$(grep -h "server_name" /etc/nginx/sites-enabled/* 2>/dev/null \
        | grep -v '^\s*#' \
        | sed -E 's/.*server_name\s+//;s/;.*//' \
        | tr ' ' '\n' \
        | grep -vE '^(www\.|_|localhost|$)' \
        | head -1 || true)
fi
SOURCE_DOMAIN="${DETECTED_DOMAIN:-unknown}"

# ---------- 让用户确认 site_id ----------
if [ -z "$SITE_ID" ]; then
    echo ""
    echo "==========================================="
    echo "  检测到域名: $SOURCE_DOMAIN"
    echo "==========================================="
    read -p "请输入这个站点的 site_id (两位数字, 例如 03): " SITE_ID
fi
if ! [[ "$SITE_ID" =~ ^[0-9]{2}$ ]]; then
    echo "❌ site_id 必须是两位数字 (例如 03)"
    exit 1
fi

# ---------- 解析配置 ----------
get_yaml() {
    # 简单 yaml 取值: 取 key 后面的字符串值 (不支持嵌套，平铺即可)
    local key="$1"
    grep -E "^\s*${key}\s*:" "$CONFIG_FILE" | head -1 | sed -E "s/^\s*${key}\s*:\s*//;s/^\"//;s/\"$//;s/\s*#.*$//"
}

DB_HOST=$(get_yaml host)
DB_PORT=$(get_yaml port | head -1)
DB_USER=$(get_yaml user)
DB_PASS=$(get_yaml password | head -1)
DB_NAME=$(get_yaml dbname)
JWT_SECRET=$(get_yaml jwt_secret)
VOICE_SECRET=$(get_yaml secret | tail -1)   # voice_relay.secret 在文件末尾
VOICE_URL=$(get_yaml relay_ws_url)

# 兼容 host: postgres (旧 docker 配置) → 改为 localhost 做 audit
if [ "$DB_HOST" = "postgres" ]; then
    DB_HOST="localhost"
fi
DB_PORT="${DB_PORT:-5432}"

[ -n "$DB_NAME" ] || { echo "❌ 无法从 config 解析 dbname"; exit 1; }
[ -n "$VOICE_SECRET" ] || echo "⚠️  voice_relay.secret 为空，语音通话可能未启用"

# ---------- 查询 PG ----------
export PGPASSWORD="$DB_PASS"
PSQL="psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -tA"

DB_SIZE_BYTES=$($PSQL -c "SELECT pg_database_size('$DB_NAME');" 2>/dev/null || echo "0")
DB_SIZE_HUMAN=$($PSQL -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null || echo "?")

# 表行数
TABLE_ROWS=$($PSQL -c "
SELECT relname || '=' || n_live_tup
FROM pg_stat_user_tables
ORDER BY relname;" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# message 表的最早/最新时间 (用于评估数据时间范围)
MSG_OLDEST=$($PSQL -c "SELECT to_timestamp(MIN(send_time)/1000) FROM messages;" 2>/dev/null | head -1 || echo "?")
MSG_NEWEST=$($PSQL -c "SELECT to_timestamp(MAX(send_time)/1000) FROM messages;" 2>/dev/null | head -1 || echo "?")

# ---------- uploads ----------
UPLOADS_BYTES=0
UPLOADS_HUMAN="0"
UPLOADS_COUNT=0
if [ -d "$UPLOADS_DIR" ]; then
    UPLOADS_BYTES=$(du -sb "$UPLOADS_DIR" 2>/dev/null | awk '{print $1}')
    UPLOADS_HUMAN=$(du -sh "$UPLOADS_DIR" 2>/dev/null | awk '{print $1}')
    UPLOADS_COUNT=$(find "$UPLOADS_DIR" -type f 2>/dev/null | wc -l)
fi

# ---------- secret 指纹 (只暴露 sha256，原文存在 .secrets 里) ----------
sha_short() { echo -n "$1" | sha256sum | awk '{print substr($1, 1, 16)}'; }
VOICE_SECRET_SHA=$(sha_short "$VOICE_SECRET")
JWT_SECRET_SHA=$(sha_short "$JWT_SECRET")

# ---------- 系统信息 ----------
HOSTNAME=$(hostname)
SOURCE_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
TIMESTAMP=$(date -Iseconds)

# ---------- 写文件 ----------
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

MANIFEST="$OUT_DIR/site_${SITE_ID}.manifest"
SECRETS="$OUT_DIR/site_${SITE_ID}.secrets"

cat > "$MANIFEST" <<EOF
# IM Agent Hub site audit manifest
site_id: ${SITE_ID}
source_domain: ${SOURCE_DOMAIN}
source_ip: ${SOURCE_IP}
source_hostname: ${HOSTNAME}
audited_at: ${TIMESTAMP}

# Database
db_name: ${DB_NAME}
db_size_bytes: ${DB_SIZE_BYTES}
db_size_human: ${DB_SIZE_HUMAN}
table_row_counts: ${TABLE_ROWS}
message_oldest: ${MSG_OLDEST}
message_newest: ${MSG_NEWEST}

# Uploads
uploads_path: ${UPLOADS_DIR}
uploads_total_bytes: ${UPLOADS_BYTES}
uploads_total_human: ${UPLOADS_HUMAN}
uploads_file_count: ${UPLOADS_COUNT}

# Secret fingerprints (sha256 first 16 chars)
# ★ 13 台旧服务器的 voice_relay_secret_sha256 必须完全相同！
voice_relay_secret_sha256: ${VOICE_SECRET_SHA}
voice_relay_url: ${VOICE_URL}
jwt_secret_sha256: ${JWT_SECRET_SHA}
EOF

cat > "$SECRETS" <<EOF
# SENSITIVE — do NOT commit, only transfer via scp to new server
site_id=${SITE_ID}
source_domain=${SOURCE_DOMAIN}
jwt_secret=${JWT_SECRET}
voice_relay_secret=${VOICE_SECRET}
voice_relay_url=${VOICE_URL}
EOF
chmod 600 "$SECRETS"

# ---------- 屏幕摘要 ----------
echo ""
echo "==========================================="
echo "  ✅ 审计完成 site_${SITE_ID}"
echo "==========================================="
echo "  域名:           $SOURCE_DOMAIN"
echo "  数据库:         $DB_NAME ($DB_SIZE_HUMAN)"
echo "  消息时间范围:   $MSG_OLDEST  →  $MSG_NEWEST"
echo "  uploads:        $UPLOADS_HUMAN ($UPLOADS_COUNT 个文件)"
echo "  voice secret 指纹: $VOICE_SECRET_SHA"
echo ""
echo "  输出文件:"
echo "    $MANIFEST  (公开)"
echo "    $SECRETS   (敏感，权限 600)"
echo ""
echo "  下一步:"
echo "    在本地拉取这两个文件:"
echo "      scp ${HOSTNAME}:${MANIFEST} ./audit/"
echo "      scp ${HOSTNAME}:${SECRETS}  ./audit/"
echo ""
echo "  ★ 13 台都跑完后，比对所有 manifest 的 voice_relay_secret_sha256:"
echo "      grep voice_relay_secret_sha256 audit/*.manifest"
echo "    必须完全相同！否则跨站语音会失败。"
echo ""
