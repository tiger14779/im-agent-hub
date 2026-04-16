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
