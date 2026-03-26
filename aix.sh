#!/bin/sh

# ======================================================
# 脚本名称: AIX (Alpine Internal X-monitor)
# 适用系统: Alpine Linux (3.x +)
# 核心技术: nftables + jq + bc
# 功能: 端口级双向流量计费、30天自动重置、有效期管理
# ======================================================

# --- 路径与全局变量 ---
DB_DIR="/etc/aix"
DB_FILE="$DB_DIR/data.json"
NFT_TABLE="aix_guard"
ALIAS_NAME="aix"
BIN_PATH="/usr/local/bin/$ALIAS_NAME"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# --- 检查并安装环境 ---
init_env() {
    if [ ! -f /etc/alpine-release ]; then
        echo -e "${RED}错误: 此脚本仅支持 Alpine Linux 系统！${PLAIN}"
        exit 1
    fi

    echo -e "${BLUE}[1/3] 检查并安装依赖工具...${PLAIN}"
    apk add nftables jq bc util-linux > /dev/null 2>&1
    
    mkdir -p "$DB_DIR"
    [ ! -f "$DB_FILE" ] && echo "{}" > "$DB_FILE"
    
    echo -e "${BLUE}[2/3] 配置防火墙服务...${PLAIN}"
    rc-update add nftables > /dev/null 2>&1
    rc-service nftables start > /dev/null 2>&1
    
    # 初始化 nftables 表结构
    nft add table inet $NFT_TABLE 2>/dev/null
    nft add chain inet $NFT_TABLE count_chain { type filter hook input priority 0 \; }
    nft add chain inet $NFT_TABLE drop_chain { type filter hook input priority 1 \; }

    echo -e "${BLUE}[3/3] 设置快捷指令 [$ALIAS_NAME]...${PLAIN}"
    cp "$0" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    
    # 写入定时任务 (每分钟检查一次)
    if ! crontab -l | grep -q "$BIN_PATH daemon"; then
        (crontab -l 2>/dev/null; echo "* * * * * $BIN_PATH daemon >/dev/null 2>&1") | crontab -
    fi
    
    echo -e "${GREEN}环境初始化完成！输入 $ALIAS_NAME 即可管理。${PLAIN}"
}

# --- 内部工具：单位转换 ---
to_bytes() {
    echo "$1 * 1073741824" | bc | cut -d. -f1
}

fmt_size() {
    local b=$1
    if [ "$b" -gt 1073741824 ]; then
        echo "$(echo "scale=2; $b/1073741824" | bc) GB"
    else
        echo "$(echo "scale=2; $b/1048576" | bc) MB"
    fi
}

# --- 核心守护进程 (每分钟运行) ---
daemon_check() {
    local now_ts=$(date +%s)
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)

    for port in $(jq -r 'keys[]' "$DB_FILE"); do
        # 1. 读取数据库配置
        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        local expire_str=$(jq -r ".\"$port\".expire" "$DB_FILE")
        local start_ts=$(jq -r ".\"$port\".start_ts" "$DB_FILE")
        local last_reset=$(jq -r ".\"$port\".last_reset" "$DB_FILE")
        
        # 2. 检查 30 天周期重置 (2592000秒)
        if [ $((now_ts - last_reset)) -ge 2592000 ]; then
            nft reset rule inet $NFT_TABLE count_chain tcp dport $port >/dev/null 2>&1
            last_reset=$now_ts
            jq ".\"$port\".last_reset = $last_reset" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
        fi

        # 3. 获取当前内核流量
        local cur_bytes=$(echo "$stats" | grep "dport $port" | grep "counter" | awk '{print $7}' | head -n 1)
        [ -z "$cur_bytes" ] && cur_bytes=0
        
        # 更新数据库中的已用流量
        jq ".\"$port\".used = $cur_bytes" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"

        # 4. 判断逻辑：过期或超额
        local is_stop=false
        # 检查流量
        [ "$cur_bytes" -ge "$limit" ] && is_stop=true
        # 检查时间 (如果非空)
        if [ "$expire_str" != "永久" ]; then
            local exp_ts=$(date -d "$expire_str" +%s 2>/dev/null || echo 0)
            [ "$now_ts" -ge "$exp_ts" ] && is_stop=true
        fi

        # 执行动作
        if [ "$is_stop" = true ]; then
            if ! nft list chain inet $NFT_TABLE drop_chain | grep -q "tcp dport $port drop"; then
                nft add rule inet $NFT_TABLE drop_chain tcp dport $port drop
            fi
        else
            local handle=$(nft -a list chain inet $NFT_TABLE drop_chain | grep "tcp dport $port drop" | awk '{print $NF}')
            [ -n "$handle" ] && nft delete rule inet $NFT_TABLE drop_chain handle $handle
        fi
    done
}

# --- 菜单：实时看板 ---
show_dashboard() {
    echo -e "${BLUE}================== AIX 流量计费实时看板 ==================${PLAIN}"
    printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "端口" "状态" "已用" "额度" "有效期"
    echo "----------------------------------------------------------"
    
    for port in $(jq -r 'keys[]' "$DB_FILE" | sort -n); do
        local used=$(jq -r ".\"$port\".used" "$DB_FILE")
        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        local exp=$(jq -r ".\"$port\".expire" "$DB_FILE")
        
        local status="${GREEN}运行${PLAIN}"
        [ "$used" -ge "$limit" ] && status="${RED}溢出${PLAIN}"
        if [ "$exp" != "永久" ]; then
             [ "$(date +%s)" -ge "$(date -d "$exp" +%s 2>/dev/null || echo 0)" ] && status="${RED}过期${PLAIN}"
        fi

        printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" \
            "$port" "$status" "$(fmt_size $used)" "$(fmt_size $limit)" "$exp"
    done
    echo -e "${BLUE}==========================================================${PLAIN}"
}

# --- 菜单：添加端口 ---
add_user() {
    read -p "请输入端口号: " port
    read -p "月流量额度 (GB): " gb
    read -p "有效期 (YYYY-MM-DD, 留空为永久): " exp
    [ -z "$exp" ] && exp="永久"
    
    local bytes=$(to_bytes $gb)
    local now=$(date +%s)
    
    jq ".\"$port\" = {\"limit\": $bytes, \"used\": 0, \"expire\": \"$exp\", \"start_ts\": $now, \"last_reset\": $now}" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
    
    nft add rule inet $NFT_TABLE count_chain tcp dport $port counter accept
    echo -e "${GREEN}用户 $port 添加成功！30天计费周期已开启。${PLAIN}"
}

# --- 主交互入口 ---
case "$1" in
    "daemon") daemon_check ;;
    "init") init_env ;;
    *)
        if [ ! -d "$DB_DIR" ]; then init_env; fi
        clear
        echo -e "${YELLOW}AIX (Alpine Internal X-monitor) 管理系统${PLAIN}"
        echo "1. 查看流量看板"
        echo "2. 添加计费用户"
        echo "3. 修改/删除用户"
        echo "4. 立即同步计费状态"
        echo "0. 退出"
        read -p "请选择: " opt
        case $opt in
            1) show_dashboard ;;
            2) add_user ;;
            3) read -p "输入要操作的端口: " p; jq "del(.\"$p\")" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"; echo "已删除，请手动同步规则。" ;;
            4) daemon_check; echo "同步完成！";;
            *) exit 0 ;;
        esac
        ;;
esac
