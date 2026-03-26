cat << 'EOF' > /usr/local/bin/aix
#!/bin/sh

# --- 路径与全局变量 ---
DB_DIR="/etc/aix"
DB_FILE="$DB_DIR/data.json"
NFT_TABLE="aix_guard"
mkdir -p "$DB_DIR"

# --- 内部工具：单位转换 ---
to_bytes() { echo "$1 * 1073741824" | bc | cut -d. -f1; }
fmt_size() {
    local b=$1
    if [ "$b" -gt 1073741824 ]; then
        echo "$(echo "scale=2; $b/1073741824" | bc) GB"
    else
        echo "$(echo "scale=2; $b/1048576" | bc) MB"
    fi
}

# --- 核心守护进程 (同步内核与数据库) ---
daemon_check() {
    local now_ts=$(date +%s)
    # 确保 nftables 表结构存在
    nft add table inet $NFT_TABLE 2>/dev/null
    nft add chain inet $NFT_TABLE count_chain { type filter hook input priority 0 \; } 2>/dev/null
    nft add chain inet $NFT_TABLE drop_chain { type filter hook input priority 1 \; } 2>/dev/null
    
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)
    for port in $(jq -r 'keys[]' "$DB_FILE" 2>/dev/null); do
        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        local expire=$(jq -r ".\"$port\".expire" "$DB_FILE")
        local last_reset=$(jq -r ".\"$port\".last_reset" "$DB_FILE")
        
        # 1. 30天自动重置检查
        if [ $((now_ts - last_reset)) -ge 2592000 ]; then
            nft reset rule inet $NFT_TABLE count_chain tcp dport $port >/dev/null 2>&1
            last_reset=$now_ts
            jq ".\"$port\".last_reset = $last_reset" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
        fi

        # 2. 从内核提取字节数
        local cur_bytes=$(echo "$stats" | grep "tcp dport $port" | grep "counter" | sed 's/.*bytes \([0-9]*\).*/\1/')
        [ -z "$cur_bytes" ] || [ "$cur_bytes" = "$stats" ] && cur_bytes=0
        jq ".\"$port\".used = $cur_bytes" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"

        # 3. 封禁逻辑判定
        local is_stop=false
        [ "$cur_bytes" -ge "$limit" ] && is_stop=true
        if [ "$expire" != "永久" ]; then
            local exp_ts=$(date -d "$expire" +%s 2>/dev/null || echo 0)
            [ "$now_ts" -ge "$exp_ts" ] && is_stop=true
        fi

        # 4. 执行防火墙动作
        if [ "$is_stop" = true ]; then
            if ! nft list chain inet $NFT_TABLE drop_chain | grep -q "tcp dport $port drop"; then
                nft add rule inet $NFT_TABLE drop_chain tcp dport $port drop
            fi
        else
            local handle=$(nft -a list chain inet $NFT_TABLE drop_chain | grep "tcp dport $port drop" | awk '{print $NF}')
            [ -n "$handle" ] && nft delete rule inet $NFT_TABLE drop_chain handle $handle 2>/dev/null
        fi
    done
}

# --- 主交互菜单 ---
show_menu() {
    clear
    echo "========================================"
    echo "    AIX (Alpine Internal X-monitor)    "
    echo "========================================"
    echo "1. 查看流量看板"
    echo "2. 添加/修改计费端口"
    echo "3. 手动重置流量 (清零)"
    echo "4. 删除计费端口"
    echo "5. 立即同步计费状态"
    echo "0. 退出"
    echo "----------------------------------------"
    read -p "请选择 [0-5]: " opt
    
    case "$opt" in
        1)
            daemon_check
            echo "----------------------------------------------------------------"
            printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "端口" "状态" "已用" "总额度" "有效期"
            echo "----------------------------------------------------------------"
            for port in $(jq -r 'keys[]' "$DB_FILE" 2>/dev/null | sort -n); do
                local u=$(jq -r ".\"$port\".used" "$DB_FILE")
                local l=$(jq -r ".\"$port\".limit" "$DB_FILE")
                local e=$(jq -r ".\"$port\".expire" "$DB_FILE")
                local s="运行"
                [ "$u" -ge "$l" ] && s="溢出"
                if [ "$e" != "永久" ] && [ "$(date +%s)" -ge "$(date -d "$e" +%s 2>/dev/null || echo 0)" ]; then s="过期"; fi
                printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "$port" "$s" "$(fmt_size $u)" "$(fmt_size $l)" "$e"
            done
            echo "----------------------------------------------------------------"
            read -p "按回车键返回主菜单..." dummy; show_menu ;;
        
        2)
            read -p "请输入端口号 (13031-13040): " p
            if [ -z "$p" ]; then echo "输入不能为空！"; sleep 1; show_menu; fi
            read -p "月流量额度 (GB): " g
            read -p "有效期 (格式 YYYY-MM-DD, 留空为永久): " e
            [ -z "$e" ] && e="永久"
            
            # 写入数据库
            jq ".\"$p\" = {\"limit\": $(to_bytes $g), \"used\": 0, \"expire\": \"$e\", \"last_reset\": $(date +%s)}" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
            
            # 更新防火墙规则
            nft add rule inet $NFT_TABLE count_chain tcp dport $p counter accept 2>/dev/null
            echo "端口 $p 配置已更新/添加！"
            sleep 1; show_menu ;;
            
        3)
            read -p "请输入要重置的端口: " p
            if jq -e ".\"$p\"" "$DB_FILE" >/dev/null; then
                nft reset rule inet $NFT_TABLE count_chain tcp dport $p >/dev/null 2>&1
                jq ".\"$p\".last_reset = $(date +%s)" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
                echo "端口 $p 流量已清零并开始新周期。"
            else
                echo "未找到该端口配置。"
            fi
            sleep 1; show_menu ;;

        4)
            read -p "请输入要删除的端口: " p
            jq "del(.\"$p\")" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
            # 清理防火墙计数器和封禁规则
            local handles=$(nft -a list table inet $NFT_TABLE | grep "tcp dport $p" | awk '{print $NF}')
            for h in $handles; do nft delete rule inet $NFT_TABLE count_chain handle $h 2>/dev/null; done
            echo "端口 $p 已删除。"
            sleep 1; show_menu ;;

        5)
            daemon_check
            echo "同步完成！所有状态已根据最新流量刷新。"
            sleep 1; show_menu ;;

        0) exit 0 ;;

        *)
            echo "错误：无效指令 '$opt'，请输入 0-5 之间的数字。"
            sleep 1.5; show_menu ;;
    esac
}

# --- 入口判定 ---
if [ "$1" = "daemon" ]; then
    daemon_check
else
    show_menu
fi
EOF
chmod +x /usr/local/bin/aix
