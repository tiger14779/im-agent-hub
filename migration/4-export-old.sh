#!/bin/bash
# ============================================================
#  4-export-old.sh  — 在旧服务器上跑，导出数据
#
#  做的事:
#    1. pg_dump 数据库 (custom format, 支持并行 restore)
#    2. tar uploads/ 目录
#    3. 计算 sha256 (传输完整性)
#    4. 写 export_manifest (含 source_domain + 表行数, restore 时强制校验)
#    5. pg_restore --list 自检 dump 完整性
#
#  注意:
#    - 默认不停业务！dump 期间业务继续跑
#    - dump 是一致性快照 (PG MVCC)，dump 期间的新数据不会进 dump
#    - dump 完后业务继续写入的数据需要在停机切换时单独处理
#
#  用法:
#    bash 4-export-old.sh                   # 自动检测
#    bash 4-export-old.sh --site-id 03 --domain site03.com
# ============================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/im-agent-hub}"
CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"
UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"
OUT_DIR="/tmp/im-hub-export"

SITE_ID=""
DOMAIN=""
SKIP_UPLOADS_AGE=0   # 默认全部 uploads, 设为 30 则只导出最近 30 天的

while [[ $# -gt 0 ]]; do
    case $1 in
        --site-id) SITE_ID="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --uploads-days) SKIP_UPLOADS_AGE="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"; UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"; shift 2 ;;
        *) echo "unknown: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- 1. 自动检测 ----------
if [ -z "$DOMAIN" ] && [ -d /etc/nginx/sites-enabled ]; then
    DOMAIN=$(grep -h "server_name" /etc/nginx/sites-enabled/* 2>/dev/null \
        | grep -v '^\s*#' \
        | sed -E 's/.*server_name\s+//;s/;.*//' \
        | tr ' ' '\n' \
        | grep -vE '^(www\.|_|localhost|$)' \
        | head -1 || true)
fi

if [ -z "$SITE_ID" ] && [ -f /tmp/im-hub-audit/site_*.manifest ]; then
    SITE_ID=$(ls /tmp/im-hub-audit/site_*.manifest 2>/dev/null | head -1 | sed -E 's|.*/site_([0-9]+)\.manifest|\1|')
fi

if [ -z "$SITE_ID" ] || [ -z "$DOMAIN" ]; then
    echo ""
    echo "无法自动检测，请手动指定:"
    echo "  bash 4-export-old.sh --site-id 03 --domain site03.com"
    exit 1
fi

[[ "$SITE_ID" =~ ^[0-9]{2}$ ]] || error "site_id 必须是两位数字"

# ---------- 2. 读 DB 配置 ----------
[ -f "$CONFIG_FILE" ] || error "找不到 $CONFIG_FILE"

get_yaml() {
    grep -E "^\s*$1\s*:" "$CONFIG_FILE" | head -1 | sed -E "s/^\s*$1\s*:\s*//;s/^\"//;s/\"$//;s/\s*#.*$//"
}
DB_HOST=$(get_yaml host); [ "$DB_HOST" = "postgres" ] && DB_HOST="localhost"
DB_PORT=$(get_yaml port | head -1); DB_PORT="${DB_PORT:-5432}"
DB_USER=$(get_yaml user)
DB_PASS=$(get_yaml password | head -1)
DB_NAME=$(get_yaml dbname)

export PGPASSWORD="$DB_PASS"

# ---------- 3. 准备输出目录 ----------
TS=$(date +%Y%m%d-%H%M%S)
SITE_OUT="${OUT_DIR}/site_${SITE_ID}"
mkdir -p "$SITE_OUT"

DUMP_FILE="${SITE_OUT}/${DOMAIN}__site${SITE_ID}__${TS}.dump"
UPLOADS_TAR="${SITE_OUT}/${DOMAIN}__site${SITE_ID}__${TS}.uploads.tar.gz"
MANIFEST="${SITE_OUT}/export_manifest.yaml"

info "==========================================="
info "  导出 site ${SITE_ID} (${DOMAIN})"
info "==========================================="
info "  数据库: $DB_NAME"
info "  输出: $SITE_OUT"
info ""

# ---------- 4. dump 前记录行数 (供 restore 后比对) ----------
info "记录 dump 前表行数..."
PRE_ROWS_FILE="${SITE_OUT}/pre_dump_row_counts.txt"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tA <<'EOF' > "$PRE_ROWS_FILE"
SELECT relname || '=' || n_live_tup
FROM pg_stat_user_tables
ORDER BY relname;
EOF
cat "$PRE_ROWS_FILE" | sed 's/^/  /'

# ---------- 5. pg_dump ----------
info "执行 pg_dump (custom format)..."
START=$(date +%s)
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -Fc --no-owner --no-acl \
    -f "$DUMP_FILE"
DUMP_ELAPSED=$(($(date +%s) - START))
DUMP_SIZE=$(stat -c%s "$DUMP_FILE")
info "dump 完成: $(du -h "$DUMP_FILE" | cut -f1) (耗时 ${DUMP_ELAPSED}s)"

# ---------- 6. dump 自检 (能 list 出来说明文件没坏) ----------
info "校验 dump 完整性 (pg_restore --list)..."
ENTRY_COUNT=$(pg_restore --list "$DUMP_FILE" 2>/dev/null | grep -cE '^[0-9]' || true)
[ "$ENTRY_COUNT" -gt 0 ] || error "dump 文件解析失败 (0 entries)，可能损坏"
info "dump 含 $ENTRY_COUNT 个条目，校验通过"

# ---------- 7. sha256 ----------
info "计算 sha256..."
sha256sum "$DUMP_FILE" | awk '{print $1}' > "${DUMP_FILE}.sha256"
DUMP_SHA=$(cat "${DUMP_FILE}.sha256")

# ---------- 8. tar uploads ----------
if [ -d "$UPLOADS_DIR" ] && [ "$(ls -A "$UPLOADS_DIR" 2>/dev/null)" ]; then
    info "打包 uploads/ ..."
    START=$(date +%s)
    if [ "$SKIP_UPLOADS_AGE" -gt 0 ]; then
        info "  只打包最近 ${SKIP_UPLOADS_AGE} 天的文件..."
        find "$UPLOADS_DIR" -type f -mtime -"$SKIP_UPLOADS_AGE" -printf '%P\n' \
            | tar czf "$UPLOADS_TAR" -C "$UPLOADS_DIR" -T -
    else
        tar czf "$UPLOADS_TAR" -C "$UPLOADS_DIR" .
    fi
    TAR_ELAPSED=$(($(date +%s) - START))
    TAR_SIZE=$(stat -c%s "$UPLOADS_TAR")
    UPLOADS_FILE_COUNT=$(tar tzf "$UPLOADS_TAR" 2>/dev/null | grep -v '/$' | wc -l)
    sha256sum "$UPLOADS_TAR" | awk '{print $1}' > "${UPLOADS_TAR}.sha256"
    UPLOADS_SHA=$(cat "${UPLOADS_TAR}.sha256")
    info "uploads 打包: $(du -h "$UPLOADS_TAR" | cut -f1) ($UPLOADS_FILE_COUNT 文件, 耗时 ${TAR_ELAPSED}s)"
else
    warn "uploads 目录为空或不存在，跳过"
    UPLOADS_TAR=""
    UPLOADS_SHA=""
    UPLOADS_FILE_COUNT=0
    TAR_SIZE=0
fi

# ---------- 9. 写 manifest ----------
SOURCE_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
HOSTNAME_VAL=$(hostname)

cat > "$MANIFEST" <<EOF
# Export manifest for site ${SITE_ID}
# Created by 4-export-old.sh at $(date -Iseconds)
# Restore: 5-restore-new.sh --site-id ${SITE_ID} --source-domain ${DOMAIN}

site_id: ${SITE_ID}
source_domain: ${DOMAIN}
source_ip: ${SOURCE_IP}
source_hostname: ${HOSTNAME_VAL}
exported_at: $(date -Iseconds)

# Database dump
db_name: ${DB_NAME}
dump_file: $(basename "$DUMP_FILE")
dump_size_bytes: ${DUMP_SIZE}
dump_sha256: ${DUMP_SHA}
dump_entry_count: ${ENTRY_COUNT}
dump_elapsed_seconds: ${DUMP_ELAPSED}

# Pre-dump row counts (for post-restore verification)
pre_dump_row_counts: |
$(cat "$PRE_ROWS_FILE" | sed 's/^/  /')

# Uploads
uploads_tar: $(basename "${UPLOADS_TAR:-}")
uploads_tar_size_bytes: ${TAR_SIZE}
uploads_tar_sha256: ${UPLOADS_SHA}
uploads_file_count: ${UPLOADS_FILE_COUNT}
uploads_age_filter_days: ${SKIP_UPLOADS_AGE}
EOF

# ---------- 10. 完成 ----------
echo ""
info "==========================================="
info "  ✅ 导出完成"
info "==========================================="
echo "  位置: $SITE_OUT"
ls -lh "$SITE_OUT"
echo ""
echo "  下一步 (在新服务器执行):"
echo ""
echo "    # 拉取整个 site 目录"
echo "    rsync -avz --progress \\"
echo "      ${SOURCE_IP}:${SITE_OUT}/ \\"
echo "      /tmp/im-hub-import/site_${SITE_ID}/"
echo ""
echo "    # 还原 (带防呆)"
echo "    bash /opt/im-hub/migration/5-restore-new.sh \\"
echo "      --site-id ${SITE_ID} \\"
echo "      --source-domain ${DOMAIN}"
echo ""
echo "  ★ 旧服务器现在还在跑 (没动业务)"
echo "  ★ 真正的停机点是 restore 验证通过 → systemctl stop im-agent-hub → 切 DNS"
echo ""
