#!/bin/bash
# ============================================================
#  5-restore-new.sh  — 在新服务器上跑，带防呆校验的数据还原
#
#  防呆机制 (按执行顺序):
#    1. 必传 --site-id 和 --source-domain，从 manifest 校验匹配
#    2. 校验 dump 文件 sha256
#    3. 校验 uploads.tar.gz 的 sha256
#    4. pg_restore --list 自检 dump 完整性
#    5. 检查目标 PG database 是否为空 (非空必须 --force-overwrite)
#    6. 停 systemd 服务
#    7. pg_restore + tar 解压
#    8. 启动 systemd 服务
#    9. 行数比对 (新库 vs export_manifest 里的 pre_dump_row_counts)
#   10. 文件数比对
#   11. curl 健康检查
#
#  用法 (必须传两个参数交叉验证):
#    bash 5-restore-new.sh --site-id 03 --source-domain site03.com
#    bash 5-restore-new.sh --site-id 03 --source-domain site03.com --force-overwrite
# ============================================================
set -euo pipefail

BASE_DIR="/opt/im-hub"
SITES_DIR="${BASE_DIR}/sites"
IMPORT_DIR="${IMPORT_DIR:-/tmp/im-hub-import}"

SITE_ID=""
SOURCE_DOMAIN=""
FORCE_OVERWRITE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --site-id) SITE_ID="$2"; shift 2 ;;
        --source-domain) SOURCE_DOMAIN="$2"; shift 2 ;;
        --force-overwrite) FORCE_OVERWRITE=1; shift ;;
        --import-dir) IMPORT_DIR="$2"; shift 2 ;;
        *) echo "unknown: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- 参数校验 ----------
[[ "$SITE_ID" =~ ^[0-9]{2}$ ]] || error "必传 --site-id (两位数字)"
[ -n "$SOURCE_DOMAIN" ] || error "必传 --source-domain (用于防呆校验)"

DB_NAME="imhub_${SITE_ID}"
DB_USER="imhub_${SITE_ID}"
SITE_DIR="${SITES_DIR}/${SITE_ID}"
SITE_IMPORT="${IMPORT_DIR}/site_${SITE_ID}"
PORT=$((8080 + 10#$SITE_ID))

[ -d "$SITE_IMPORT" ] || error "找不到导入目录: $SITE_IMPORT
请先 rsync 旧服务器的 /tmp/im-hub-export/site_${SITE_ID}/ 过来"

[ -d "$SITE_DIR" ] || error "site 目录不存在: $SITE_DIR
请先跑 3-init-site.sh ${SITE_ID}"

# ---------- 1. 读 export_manifest ----------
MANIFEST="${SITE_IMPORT}/export_manifest.yaml"
[ -f "$MANIFEST" ] || error "找不到 $MANIFEST"

get_y() {
    grep -E "^\s*$1\s*:" "$MANIFEST" | head -1 | sed -E "s/^\s*$1\s*:\s*//;s/^\"//;s/\"$//"
}

M_SITE_ID=$(get_y site_id)
M_SOURCE_DOMAIN=$(get_y source_domain)
M_DB_NAME=$(get_y db_name)
M_DUMP_FILE=$(get_y dump_file)
M_DUMP_SHA=$(get_y dump_sha256)
M_DUMP_BYTES=$(get_y dump_size_bytes)
M_UPLOADS_TAR=$(get_y uploads_tar)
M_UPLOADS_SHA=$(get_y uploads_tar_sha256)
M_UPLOADS_COUNT=$(get_y uploads_file_count)

info "==========================================="
info "  还原 site ${SITE_ID}"
info "==========================================="
info "  manifest 声明:"
info "    site_id       = $M_SITE_ID"
info "    source_domain = $M_SOURCE_DOMAIN"
info "    db_name (src) = $M_DB_NAME"
info "    dump_file     = $M_DUMP_FILE"
info "  目标:"
info "    site_id       = $SITE_ID"
info "    source_domain = $SOURCE_DOMAIN"
info "    db_name (dst) = $DB_NAME"

# ---------- 2. 防呆: 交叉校验 ----------
if [ "$M_SITE_ID" != "$SITE_ID" ]; then
    error "❌ manifest.site_id ($M_SITE_ID) ≠ --site-id ($SITE_ID)
你可能搞错了 import 目录！这个 dump 是 site${M_SITE_ID} 的，不是 site${SITE_ID} 的"
fi

if [ "$M_SOURCE_DOMAIN" != "$SOURCE_DOMAIN" ]; then
    error "❌ manifest.source_domain ($M_SOURCE_DOMAIN) ≠ --source-domain ($SOURCE_DOMAIN)
你可能搞错了归属！这个 dump 来自 $M_SOURCE_DOMAIN，不是你说的 $SOURCE_DOMAIN"
fi
info "✅ 防呆校验通过"

# ---------- 3. 校验 sha256 ----------
DUMP_FILE_PATH="${SITE_IMPORT}/${M_DUMP_FILE}"
[ -f "$DUMP_FILE_PATH" ] || error "找不到 dump 文件: $DUMP_FILE_PATH"

info "校验 dump sha256..."
ACTUAL_SHA=$(sha256sum "$DUMP_FILE_PATH" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$M_DUMP_SHA" ]; then
    error "❌ dump sha256 不匹配
  期望: $M_DUMP_SHA
  实际: $ACTUAL_SHA
传输可能损坏，请重新 rsync"
fi
info "✅ dump sha256 通过"

if [ -n "$M_UPLOADS_TAR" ] && [ "$M_UPLOADS_TAR" != "" ]; then
    UPLOADS_TAR_PATH="${SITE_IMPORT}/${M_UPLOADS_TAR}"
    if [ -f "$UPLOADS_TAR_PATH" ]; then
        info "校验 uploads sha256..."
        ACTUAL_TSHA=$(sha256sum "$UPLOADS_TAR_PATH" | awk '{print $1}')
        if [ "$ACTUAL_TSHA" != "$M_UPLOADS_SHA" ]; then
            error "❌ uploads sha256 不匹配"
        fi
        info "✅ uploads sha256 通过"
    else
        warn "manifest 声明有 uploads 但找不到文件 $UPLOADS_TAR_PATH"
        UPLOADS_TAR_PATH=""
    fi
else
    UPLOADS_TAR_PATH=""
fi

# ---------- 4. dump 完整性自检 ----------
info "校验 dump 可解析..."
pg_restore --list "$DUMP_FILE_PATH" >/dev/null || error "dump 文件损坏"
info "✅ dump 可解析"

# ---------- 5. 检查目标 DB 是否为空 ----------
info "检查目标 database $DB_NAME 是否为空..."
ROW_COUNT=$(sudo -u postgres psql -tAc "
SELECT COALESCE(SUM(n_live_tup), 0)
FROM pg_stat_user_tables
WHERE schemaname='public';
" "$DB_NAME" 2>/dev/null || echo "0")

if [ "$ROW_COUNT" -gt 0 ] && [ "$FORCE_OVERWRITE" -eq 0 ]; then
    error "❌ 目标 database $DB_NAME 已有 $ROW_COUNT 行数据
如果你确实要覆盖 (会丢失现有数据!)，请加 --force-overwrite
但是更可能你搞错了 site_id，请重新检查"
fi
[ "$ROW_COUNT" -gt 0 ] && warn "⚠️  目标库非空但 --force-overwrite，将覆盖 $ROW_COUNT 行数据"

# ---------- 6. 停 systemd 服务 (★ 真正的停机点) ----------
info "停止 im-hub@${SITE_ID} ..."
systemctl stop "im-hub@${SITE_ID}" 2>/dev/null || true
sleep 1

# ---------- 7. 重建 DB (确保干净) ----------
if [ "$FORCE_OVERWRITE" -eq 1 ] || [ "$ROW_COUNT" -gt 0 ]; then
    warn "DROP + CREATE database $DB_NAME ..."
    # 先断开所有连接
    sudo -u postgres psql -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname='$DB_NAME' AND pid <> pg_backend_pid();
" >/dev/null
    sudo -u postgres dropdb --if-exists "$DB_NAME"
    sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
fi

# ---------- 8. pg_restore ----------
info "执行 pg_restore (单线程, 因为数据量小)..."
START=$(date +%s)
sudo -u postgres pg_restore \
    -d "$DB_NAME" \
    --no-owner --role="$DB_USER" \
    --no-acl \
    "$DUMP_FILE_PATH" 2>&1 | tail -20 || warn "pg_restore 有 warning (正常情况下可以忽略)"
RESTORE_ELAPSED=$(($(date +%s) - START))
info "pg_restore 完成 (耗时 ${RESTORE_ELAPSED}s)"

# 确保新库的所有权
sudo -u postgres psql -d "$DB_NAME" -c "
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname='public' LOOP
    EXECUTE 'ALTER TABLE '||quote_ident(r.schemaname)||'.'||quote_ident(r.tablename)||' OWNER TO ${DB_USER}';
  END LOOP;
  FOR r IN SELECT schemaname, sequencename FROM pg_sequences WHERE schemaname='public' LOOP
    EXECUTE 'ALTER SEQUENCE '||quote_ident(r.schemaname)||'.'||quote_ident(r.sequencename)||' OWNER TO ${DB_USER}';
  END LOOP;
END\$\$;
" >/dev/null

# ---------- 9. 解压 uploads ----------
if [ -n "$UPLOADS_TAR_PATH" ]; then
    info "解压 uploads → ${SITE_DIR}/data/uploads/ ..."
    mkdir -p "${SITE_DIR}/data/uploads"
    # 清空再解 (确保不混旧数据)
    rm -rf "${SITE_DIR}/data/uploads"
    mkdir -p "${SITE_DIR}/data/uploads"
    tar xzf "$UPLOADS_TAR_PATH" -C "${SITE_DIR}/data/uploads/"
    info "uploads 解压完成"
fi

# ---------- 10. 启动服务 ----------
info "启动 im-hub@${SITE_ID} ..."
systemctl start "im-hub@${SITE_ID}"
sleep 3
systemctl is-active --quiet "im-hub@${SITE_ID}" || {
    journalctl -u "im-hub@${SITE_ID}" -n 30 --no-pager
    error "服务启动失败！查上面日志"
}

# ---------- 11. 验证: 行数比对 ----------
info "验证: 比对行数..."
sleep 2
NEW_ROWS=$(sudo -u postgres psql -tAc "
SELECT relname || '=' || n_live_tup
FROM pg_stat_user_tables
WHERE schemaname='public'
ORDER BY relname;
" "$DB_NAME")

echo "  新库行数:"
echo "$NEW_ROWS" | sed 's/^/    /'

# manifest 里 pre_dump_row_counts 是 yaml block scalar
echo "  源库行数 (来自 manifest):"
awk '/pre_dump_row_counts:/{flag=1;next} flag && /^[a-z]/{flag=0} flag' "$MANIFEST" | sed 's/^/  /'

# ---------- 12. 验证: 文件数 ----------
if [ -n "$UPLOADS_TAR_PATH" ]; then
    ACTUAL_FILES=$(find "${SITE_DIR}/data/uploads" -type f 2>/dev/null | wc -l)
    info "uploads 文件数: 期望 $M_UPLOADS_COUNT, 实际 $ACTUAL_FILES"
    if [ "$ACTUAL_FILES" != "$M_UPLOADS_COUNT" ]; then
        warn "⚠️  文件数不一致 (可能是导出时的过滤导致，检查 manifest.uploads_age_filter_days)"
    fi
fi

# ---------- 13. 验证: HTTP 健康检查 ----------
info "HTTP 健康检查..."
HTTP_OK=0
for i in $(seq 1 10); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/" || true)
    if echo "$CODE" | grep -qE "^(200|301|302|404)$"; then
        info "✅ 端口 $PORT 响应 HTTP $CODE"
        HTTP_OK=1
        break
    fi
    sleep 1
done
[ "$HTTP_OK" -eq 1 ] || warn "⚠️  HTTP 检查未通过，看 journalctl -u im-hub@${SITE_ID} -n 50"

# 通过域名 (Nginx) 测一遍
NGINX_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${SOURCE_DOMAIN}" "http://127.0.0.1/" || true)
info "Nginx 路由 (Host: ${SOURCE_DOMAIN}): HTTP $NGINX_CODE"

# ---------- 14. 完成 ----------
echo ""
info "==========================================="
info "  ✅ site ${SITE_ID} (${SOURCE_DOMAIN}) 还原完成"
info "==========================================="
echo "  端口:       $PORT"
echo "  数据库:     $DB_NAME"
echo "  uploads:    ${SITE_DIR}/data/uploads/"
echo "  systemd:    im-hub@${SITE_ID} (active)"
echo ""
echo "  下一步:"
echo "    1. 在旧服务器停服务:"
echo "       systemctl stop im-agent-hub"
echo "    2. 切 DNS: ${SOURCE_DOMAIN} A 记录 → 新服务器 IP"
echo "    3. 等 5~10 分钟后:"
echo "       curl https://${SOURCE_DOMAIN}/   # 验证 HTTPS 正常"
echo "    4. ★ 旧服务器保留 14 天 (不要关机/删盘)"
echo ""
echo "  跑 6-verify.sh 做全站轮询验证"
echo ""
