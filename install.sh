#!/bin/bash
# AIX-Xray 一键安装脚本
set -e

echo "🚀 开始安装 AIX-Xray 管理工具..."

# 1. 创建用户 bin 目录
mkdir -p ~/bin

# 2. 下载主脚本（请替换为你的 GitHub Raw 链接）
RAW_URL="https://raw.githubusercontent.com/你的GitHub用户名/AIX-Xray/main/aix"
echo "📥 下载脚本到 ~/bin/aix ..."
if curl -fsSL "$RAW_URL" -o ~/bin/aix; then
    echo "✅ 下载成功"
else
    echo "❌ 下载失败，请检查网络或 Raw 链接"
    exit 1
fi

# 3. 赋予执行权限
chmod +x ~/bin/aix

# 4. 自动配置 PATH
PROFILE_FILE=""
if [[ -f ~/.zshrc ]]; then
    PROFILE_FILE=~/.zshrc
elif [[ -f ~/.bash_profile ]]; then
    PROFILE_FILE=~/.bash_profile
elif [[ -f ~/.bashrc ]]; then
    PROFILE_FILE=~/.bashrc
fi

if [[ -n "$PROFILE_FILE" ]]; then
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$PROFILE_FILE"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$PROFILE_FILE"
        echo "✅ 已自动配置环境变量至 $PROFILE_FILE"
    else
        echo "ℹ️  环境变量已存在，跳过配置"
    fi
    # 当前会话立即生效
    export PATH="$HOME/bin:$PATH"
else
    echo "⚠️  未找到 shell 配置文件，请手动将 ~/bin 加入 PATH"
fi

echo ""
echo "🎉 安装完成！"
echo "💡 使用方法：打开新终端，输入 aix 即可启动"
echo "📖 文档地址：https://github.com/你的GitHub用户名/AIX-Xray"
echo ""
echo "🔄 如需更新，请重新运行此安装脚本"
