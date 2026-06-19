#!/bin/bash
# ============================================================
#  6-verify.sh  — 在新服务器跑，全站验证
#
#  读 sites.csv，对每个 site 检查:
#    - systemd 服务是否 active
#    - 监听端口是否正确
#    - HTTP 直连端口能否响应
#    - 通过 Nginx (Host 头) 能否响应
#    - DB 总行数 (非零说明数据导入了)
#    - uploads 文件数 + 大小
#    - SSL 证书是否就位 (端口 443)
#
#  用法:
#    bash 6-verify.sh
#    bash 6-verify.sh --site-id 03    # 只验证一个站
# ============================================================
set -uo pipefail

BASE_DIR="/opt/im-hub"
SITES_DIR="${BASE_DIR}/sites"
SITES_CSV="${BASE_DIR}/sites.csv"

ONLY_SITE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --site-id) ONLY_SITE="$2"; shift 2 ;;
        --sites-csv) SITES_CSV="$2"; shift 2 ;;
        *) echo "unknown: $1"; exit 1 ;;
    esac
done

[ -f "$SITES_CSV" ] || { echo "找不到 $SITES_CSV"; exit 1; }

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BLUE='\033[0;34m'
ok()   { echo -e "${GREEN}✅${NC} $*"; }
bad()  { echo -e "${RED}❌${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }

TOTAL=0
PASS=0
FAIL=0
PROBLEMS=()

check_site() {
    local SITE_ID="$1"
    local DOMAIN="$2"
    local PORT=$((8080 + 10#$SITE_ID))
    local DB_NAME="imhub_${SITE_ID}"
    local SITE_DIR="${SITES_DIR}/${SITE_ID}"
    local LOCAL_FAIL=0

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}site ${SITE_ID}  →  ${DOMAIN}  →  :${PORT}  →  ${DB_NAME}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 1. systemd
    if systemctl is-active --quiet "im-hub@${SITE_ID}"; then
        ok "systemd: im-hub@${SITE_ID} active"
    else
        bad "systemd: im-hub@${SITE_ID} NOT active"
        PROBLEMS+=("site${SITE_ID}: systemd not active")
        LOCAL_FAIL=1
    fi

    # 2. 端口监听
    if ss -tlnp 2>/dev/null | grep -q ":${PORT}\s"; then
        ok "端口 :${PORT} 监听中"
    else
        bad "端口 :${PORT} 没有监听"
        PROBLEMS+=("site${SITE_ID}: port ${PORT} not listening")
        LOCAL_FAIL=1
    fi

    # 3. HTTP 直连端口
    LOCAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
    if echo "$LOCAL_CODE" | grep -qE "^(200|301|302|404)$"; then
        ok "直连 :${PORT} 响应 HTTP ${LOCAL_CODE}"
    else
        bad "直连 :${PORT} 响应 HTTP ${LOCAL_CODE} (异常)"
        PROBLEMS+=("site${SITE_ID}: direct port returned ${LOCAL_CODE}")
        LOCAL_FAIL=1
    fi

    # 4. Nginx 路由 (用 Host 头模拟域名访问)
    NGINX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: ${DOMAIN}" "http://127.0.0.1/" 2>/dev/null || echo "000")
    if echo "$NGINX_CODE" | grep -qE "^(200|301|302|404)$"; then
        ok "Nginx 路由 (Host: ${DOMAIN}) 响应 HTTP ${NGINX_CODE}"
    else
        bad "Nginx 路由 (Host: ${DOMAIN}) 响应 HTTP ${NGINX_CODE} (异常)"
        PROBLEMS+=("site${SITE_ID}: nginx route returned ${NGINX_CODE}")
        LOCAL_FAIL=1
    fi

    # 5. DB 行数
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" 2>/dev/null | grep -q 1; then
        TOTAL_ROWS=$(sudo -u postgres psql -tAc "
SELECT COALESCE(SUM(n_live_tup), 0)
FROM pg_stat_user_tables
WHERE schemaname='public';
" "$DB_NAME" 2>/dev/null || echo "0")
        DB_SIZE=$(sudo -u postgres psql -tAc "SELECT pg_size_pretty(pg_database_size('${DB_NAME}'));" 2>/dev/null || echo "?")
        if [ "$TOTAL_ROWS" -gt 0 ]; then
            ok "DB ${DB_NAME}: ${TOTAL_ROWS} 行, ${DB_SIZE}"
        else
            warn "DB ${DB_NAME}: 0 行 (可能还未导入数据)"
        fi
    else
        bad "DB ${DB_NAME} 不存在"
        PROBLEMS+=("site${SITE_ID}: database missing")
        LOCAL_FAIL=1
    fi

    # 6. uploads
    if [ -d "${SITE_DIR}/data/uploads" ]; then
        UP_COUNT=$(find "${SITE_DIR}/data/uploads" -type f 2>/dev/null | wc -l)
        UP_SIZE=$(du -sh "${SITE_DIR}/data/uploads" 2>/dev/null | awk '{print $1}')
        ok "uploads: ${UP_COUNT} 文件, ${UP_SIZE}"
    else
        warn "uploads 目录不存在"
    fi

    # 7. 配置文件 site_id sanity check
    if [ -f "${SITE_DIR}/config.yaml" ]; then
        CFG_PORT=$(grep -E "^\s*port\s*:" "${SITE_DIR}/config.yaml" | head -1 | grep -oE '[0-9]+')
        CFG_DB=$(grep -E "^\s*dbname\s*:" "${SITE_DIR}/config.yaml" | sed -E 's/.*:\s*//')
        if [ "$CFG_PORT" = "$PORT" ] && [ "$CFG_DB" = "$DB_NAME" ]; then
            ok "config.yaml: port=${CFG_PORT} dbname=${CFG_DB} (匹配)"
        else
            bad "config.yaml: port=${CFG_PORT} dbname=${CFG_DB} (不匹配! 期望 port=${PORT} dbname=${DB_NAME})"
            PROBLEMS+=("site${SITE_ID}: config mismatch")
            LOCAL_FAIL=1
        fi
    else
        bad "找不到 ${SITE_DIR}/config.yaml"
        PROBLEMS+=("site${SITE_ID}: config missing")
        LOCAL_FAIL=1
    fi

    # 8. SSL 证书
    if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        EXP=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" 2>/dev/null | cut -d= -f2)
        ok "SSL: ${DOMAIN} 证书在 (到期 ${EXP})"
    else
        warn "SSL: ${DOMAIN} 还没申请证书 (跑 certbot --nginx -d ${DOMAIN})"
    fi

    TOTAL=$((TOTAL + 1))
    if [ "$LOCAL_FAIL" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

# ---------- 主循环 ----------
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  IM Agent Hub 全站验证                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"

while IFS=',' read -r SID DOMAIN _; do
    # 跳过表头和注释
    [[ "$SID" == "site_id" ]] && continue
    [[ "$SID" =~ ^# ]] && continue
    [[ -z "$SID" ]] && continue
    # 过滤
    [ -n "$ONLY_SITE" ] && [ "$SID" != "$ONLY_SITE" ] && continue

    check_site "$SID" "$DOMAIN"
done < "$SITES_CSV"

# ---------- 总结 ----------
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  验证总结                                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo "  总计: $TOTAL"
echo -e "  ${GREEN}通过: $PASS${NC}"
[ "$FAIL" -gt 0 ] && echo -e "  ${RED}失败: $FAIL${NC}" || echo "  失败: 0"

if [ ${#PROBLEMS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}问题清单:${NC}"
    for p in "${PROBLEMS[@]}"; do
        echo "  - $p"
    done
    echo ""
    exit 1
fi

echo ""
echo -e "${GREEN}✅ 全部通过！${NC}"
echo ""
