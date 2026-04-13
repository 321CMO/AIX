#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AIX-Xray 一键安装/升级脚本 - 完整版
# 支持：新设备安装 | 旧版本升级 | 配置备份 | 代理友好
# ═══════════════════════════════════════════════════════════════

set -e

# 配置区
REPO="321CMO/AIX"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="$HOME/bin"
SCRIPT_NAME="aix"
XRAY_DIR="$HOME/Documents/Xray-macos-64"
BACKUP_DIR="$HOME/.aix_backup_$(date +%Y%m%d%H%M%S)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测系统
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_err "仅支持 macOS 系统"
    exit 1
fi

echo "🚀 AIX-Xray 安装/升级脚本"
echo "─────────────────────────────────────"

# ───────── 1. 备份旧配置（升级时） ─────────
if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    log_info "检测到旧版本，正在备份..."
    mkdir -p "$BACKUP_DIR"
    cp -f "$INSTALL_DIR/$SCRIPT_NAME" "$BACKUP_DIR/" 2>/dev/null || true
    cp -f "$HOME/.aix_xray.log" "$BACKUP_DIR/" 2>/dev/null || true
    cp -f "$HOME/.aix_last_node" "$BACKUP_DIR/" 2>/dev/null || true
    [ -d "$XRAY_DIR/subs" ] && cp -rf "$XRAY_DIR/subs" "$BACKUP_DIR/" 2>/dev/null || true
    log_info "备份至: $BACKUP_DIR"
fi

# ───────── 2. 创建目录 ─────────
mkdir -p "$INSTALL_DIR"
mkdir -p "$XRAY_DIR"

# ───────── 3. 下载主脚本（带重试+代理） ─────────
log_info "正在下载主脚本..."
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retry=3
    local retry=0
    
    while [ $retry -lt $max_retry ]; do
        # 优先走代理
        if curl -x socks5h://127.0.0.1:10808 -fsSL --max-time 30 "$url" -o "$output" 2>/dev/null; then
            return 0
        fi
        # 备用：直连
        if curl -fsSL --max-time 30 "$url" -o "$output" 2>/dev/null; then
            return 0
        fi
        ((retry++))
        sleep 1
    done
    return 1
}

if ! download_with_retry "${RAW_BASE}/${SCRIPT_NAME}" "$INSTALL_DIR/${SCRIPT_NAME}.tmp"; then
    log_err "下载失败，请检查网络或代理状态"
    rm -f "$INSTALL_DIR/${SCRIPT_NAME}.tmp"
    exit 1
fi

# 验证下载内容
if ! grep -q "AIX-Xray" "$INSTALL_DIR/${SCRIPT_NAME}.tmp" 2>/dev/null; then
    log_err "下载内容异常，请检查 GitHub 仓库配置"
    rm -f "$INSTALL_DIR/${SCRIPT_NAME}.tmp"
    exit 1
fi

# 原子替换
mv -f "$INSTALL_DIR/${SCRIPT_NAME}.tmp" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
log_info "主脚本安装完成"

# ───────── 4. 配置环境变量 ─────────
configure_path() {
    local profile=""
    for f in ~/.zshrc ~/.bash_profile ~/.bashrc ~/.profile; do
        [ -f "$f" ] && profile="$f" && break
    done
    
    if [ -n "$profile" ]; then
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$profile" 2>/dev/null; then
            echo '' >> "$profile"
            echo '# AIX-Xray' >> "$profile"
            echo 'export PATH="$HOME/bin:$PATH"' >> "$profile"
            log_info "已配置环境变量至 $profile"
        fi
    else
        log_warn "未找到 shell 配置文件，请手动添加:"
        echo '  export PATH="$HOME/bin:$PATH"'
    fi
}
configure_path

# 当前终端立即生效
export PATH="$INSTALL_DIR:$PATH"

# ───────── 5. 检查 Xray 核心 ─────────
if [ ! -x "$XRAY_DIR/xray" ]; then
    log_warn "未检测到 Xray 核心文件"
    echo ""
    echo "📦 请手动下载 Xray 到: $XRAY_DIR"
    echo ""
    echo "macOS 10.14 用户（推荐 v23.3.1）:"
    echo "  cd $XRAY_DIR"
    echo "  curl -LO https://github.com/XTLS/Xray-core/releases/download/v23.3.1/Xray-macos-64.zip"
    echo "  unzip -o Xray-macos-64.zip && chmod +x xray"
    echo ""
    echo "macOS 10.15+ 用户（最新版）:"
    echo "  cd $XRAY_DIR"
    echo "  curl -LO https://github.com/XTLS/Xray-core/releases/latest/download/Xray-macos-64.zip"
    echo "  unzip -o Xray-macos-64.zip && chmod +x xray"
    echo ""
else
    log_info "Xray 核心已存在: $XRAY_DIR/xray"
fi

# ───────── 6. 检查配置文件 ─────────
if [ ! -f "$XRAY_DIR/config-hkt.json" ] && [ ! -d "$XRAY_DIR/subs" ]; then
    log_warn "未检测到配置文件"
    echo ""
    echo "📝 请将你的节点配置文件放入: $XRAY_DIR"
    echo "   命名格式: config-<节点名>.json"
    echo "   示例: config-hkt.json, config-jp.json"
    echo ""
    echo "💡 或使用脚本的「导入订阅」功能自动获取配置"
    echo ""
fi

# ───────── 7. 完成 ─────────
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  🎉 AIX-Xray 安装/升级完成！              ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "🚀 使用方法："
echo "   1. 重启终端 或执行: source ~/.bash_profile"
echo "   2. 输入: $SCRIPT_NAME"
echo ""
echo "🔄 后续更新："
echo "   • 方式1: 重新运行本安装命令"
echo "   • 方式2: 运行 $SCRIPT_NAME → 选择「10) 检查脚本更新」"
echo ""
echo "📁 重要路径："
echo "   • 主脚本: $INSTALL_DIR/$SCRIPT_NAME"
echo "   • Xray 目录: $XRAY_DIR"
echo "   • 日志文件: ~/.aix_xray.log"
echo "   • 订阅配置: $XRAY_DIR/subs/"
echo ""
echo "⚠️  注意："
echo "   • 首次使用请先下载 Xray 核心（见上方提示）"
echo "   • 配置文件需放在 $XRAY_DIR 目录下"
echo "   • macOS 10.14 请使用 Xray v23.3.1 或更早版本"
echo ""
