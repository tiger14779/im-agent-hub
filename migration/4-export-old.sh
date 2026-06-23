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
#    - uploads 默认只导最近 30 天 (聊天图片/文件), 老的留在旧服务器
#
#  用法:
#    bash 4-export-old.sh --site-id 03 --domain site03.com               # uploads 默认 30 天
#    bash 4-export-old.sh --site-id 03 --domain site03.com --uploads-days 0   # 导全部 uploads
#    bash 4-export-old.sh --site-id 03 --domain site03.com --uploads-days 90  # 改 90 天
# ============================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/im-agent-hub}"
CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"
UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"
EMOJI_DIR="${INSTALL_DIR}/server/data/Emoji"
OUT_DIR="/tmp/im-hub-export"

SITE_ID=""
DOMAIN=""
# 默认只导出最近 30 天的 uploads (聊天图片/文件, 老的留在旧服务器, 业务无影响)
# 想导全部用: --uploads-days 0  (0 = 无过滤, 全量)
SKIP_UPLOADS_AGE=30

while [[ $# -gt 0 ]]; do
    case $1 in
        --site-id) SITE_ID="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --uploads-days) SKIP_UPLOADS_AGE="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; CONFIG_FILE="${INSTALL_DIR}/server/config/config.yaml"; UPLOADS_DIR="${INSTALL_DIR}/server/data/uploads"; EMOJI_DIR="${INSTALL_DIR}/server/data/Emoji"; shift 2 ;;
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

# ---------- 0. 装 rsync (新服务器拉数据时需要旧服务器装 rsync) ----------
if ! command -v rsync >/dev/null; then
    echo "[INFO]  装 rsync (新服务器拉数据时需要)..."
    apt-get install -y -qq rsync >/dev/null 2>&1 || echo "[WARN]  rsync 装失败, 后续传数据可能要改用 scp"
fi

# ---------- 2. 读 DB 名 (复现代码的 base + local override 合并逻辑) ----------
[ -f "$CONFIG_FILE" ] || error "找不到 $CONFIG_FILE"
command -v sudo >/dev/null || error "sudo 未装"

LOCAL_CONFIG="${INSTALL_DIR}/server/config/config.local.yaml"
USING_LOCAL=0
[ -f "$LOCAL_CONFIG" ] && USING_LOCAL=1

awk_yaml() {
    local file="$1" section="$2" key="$3"
    [ -f "$file" ] || return
    awk -v sec="$section" -v key="$key" '
        /^[A-Za-z_]+:\s*$/ { cur=$0; sub(/:.*/, "", cur); next }
        cur==sec && $0 ~ "^[[:space:]]+" key "[[:space:]]*:" {
            sub("^[[:space:]]+" key "[[:space:]]*:[[:space:]]*", "")
            sub(/^"/, ""); sub(/"$/, ""); sub(/[[:space:]]*#.*$/, "")
            print; exit
        }
    ' "$file"
}
get_yaml_section() {
    local section="$1" key="$2" val=""
    [ "$USING_LOCAL" -eq 1 ] && val=$(awk_yaml "$LOCAL_CONFIG" "$section" "$key")
    [ -z "$val" ] && val=$(awk_yaml "$CONFIG_FILE" "$section" "$key")
    echo "$val"
}
DB_NAME=$(get_yaml_section database dbname)
[ -n "$DB_NAME" ] || error "无法从 config 解析 database.dbname"
[ "$USING_LOCAL" -eq 1 ] && info "检测到 config.local.yaml, 使用合并后的配置"

# ★ 改用 sudo -u postgres 走 peer 认证, 不依赖 yaml 里的 host/port/user/password
# 这样兼容 docker 时代的 host:postgres 配置, 也不受端口同名混淆影响
PG_DUMP_AS_POSTGRES="sudo -u postgres pg_dump"
PSQL_AS_POSTGRES="sudo -u postgres psql -d $DB_NAME -tA"

# ---------- 3. 准备输出目录 ----------
TS=$(date +%Y%m%d-%H%M%S)
SITE_OUT="${OUT_DIR}/site_${SITE_ID}"
mkdir -p "$SITE_OUT"

DUMP_FILE="${SITE_OUT}/${DOMAIN}__site${SITE_ID}__${TS}.dump"
UPLOADS_TAR="${SITE_OUT}/${DOMAIN}__site${SITE_ID}__${TS}.uploads.tar.gz"
EMOJI_TAR="${SITE_OUT}/${DOMAIN}__site${SITE_ID}__${TS}.emoji.tar.gz"
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
$PSQL_AS_POSTGRES -c "
SELECT relname || '=' || n_live_tup
FROM pg_stat_user_tables
ORDER BY relname;
" > "$PRE_ROWS_FILE"
cat "$PRE_ROWS_FILE" | sed 's/^/  /'

# ---------- 5. pg_dump (走 peer 认证, sudo -u postgres, 输出到 stdout) ----------
info "执行 pg_dump (custom format)..."
START=$(date +%s)
# stdout 管到 root 进程, 文件由 root 创建, 避免 postgres 用户写权限问题
$PG_DUMP_AS_POSTGRES -d "$DB_NAME" -Fc --no-owner --no-acl > "$DUMP_FILE"
DUMP_ELAPSED=$(($(date +%s) - START))
DUMP_SIZE=$(stat -c%s "$DUMP_FILE")
# 完整性立刻自检 (空文件或 pg_dump 失败会 0 字节)
[ "$DUMP_SIZE" -gt 100 ] || error "dump 文件异常 (${DUMP_SIZE} bytes), pg_dump 可能失败"
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

# ---------- 8b. tar Emoji (公共表情资源, 用户上传的自定义表情, 不能丢) ----------
if [ -d "$EMOJI_DIR" ] && [ "$(ls -A "$EMOJI_DIR" 2>/dev/null)" ]; then
    info "打包 Emoji/ ..."
    tar czf "$EMOJI_TAR" -C "$EMOJI_DIR" .
    EMOJI_TAR_SIZE=$(stat -c%s "$EMOJI_TAR")
    EMOJI_FILE_COUNT=$(tar tzf "$EMOJI_TAR" 2>/dev/null | grep -v '/$' | wc -l)
    sha256sum "$EMOJI_TAR" | awk '{print $1}' > "${EMOJI_TAR}.sha256"
    EMOJI_SHA=$(cat "${EMOJI_TAR}.sha256")
    info "Emoji 打包: $(du -h "$EMOJI_TAR" | cut -f1) ($EMOJI_FILE_COUNT 表情)"
else
    warn "Emoji 目录为空或不存在，跳过"
    EMOJI_TAR=""
    EMOJI_SHA=""
    EMOJI_FILE_COUNT=0
    EMOJI_TAR_SIZE=0
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

# Emoji (公共表情资源, 全量打包)
emoji_tar: $(basename "${EMOJI_TAR:-}")
emoji_tar_size_bytes: ${EMOJI_TAR_SIZE}
emoji_tar_sha256: ${EMOJI_SHA}
emoji_file_count: ${EMOJI_FILE_COUNT}
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
echo "    # 拉取整个 site 目录 (mkdir -p 必须有, rsync 不会自动建父目录)"
echo "    mkdir -p /tmp/im-hub-import && \\"
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
