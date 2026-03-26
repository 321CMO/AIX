#!/bin/sh

# --- 全局路径与数据库初始化 ---
DB_DIR="/etc/aix"
DB_FILE="$DB_DIR/data.json"
NFT_TABLE="aix_guard"
mkdir -p "$DB_DIR"
[ ! -f "$DB_FILE" ] && echo "{}" > "$DB_FILE"

# --- 内部工具：使用 awk 处理大数字转换防止溢出 ---
to_bytes() { 
    echo "$1" | awk '{printf "%.0f", $1 * 1073741824}'
}

fmt_size() {
    echo "$1" | awk '{
        if ($1 >= 1073741824) printf "%.2f GB", $1/1073741824;
        else printf "%.2f MB", $1/1048576;
    }'
}

# --- 核心逻辑：流量同步与封禁控制 ---
daemon_check() {
    # 确保防火墙表和链存在
    nft add table inet $NFT_TABLE 2>/dev/null
    nft "add chain inet $NFT_TABLE count_chain { type filter hook input priority 0; }" 2>/dev/null
    nft "add chain inet $NFT_TABLE drop_chain { type filter hook input priority 1; }" 2>/dev/null
    
    local now_ts=$(date +%s)
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)
    
    # 循环处理数据库中的每个端口
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

        # 2. 从内核提取字节数 (精准提取 bytes 后的数字)
        local cur_bytes=$(echo "$stats" | grep "tcp dport $port" | grep "counter" | sed -n 's/.*bytes \([0-9]*\).*/\1/p')
        [ -z "$cur_bytes" ] && cur_bytes=0
        
        # 更新数据库中的已用流量
        jq ".\"$port\".used = $cur_bytes" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"

        # 3. 封禁判定逻辑 (支持大数字对比)
        local is_stop=false
        # 使用 awk 进行大数字对比
        local over_limit=$(echo "$cur_bytes $limit" | awk '{if($1 >= $2) print "true"; else print "false"}')
        [ "$over_limit" = "true" ] && is_stop=true
        
        if [ "$expire" != "永久" ]; then
            local exp_ts=$(date -d "$expire" +%s 2>/dev/null || echo 0)
            [ "$now_ts" -ge "$exp_ts" ] && is_stop=true
        fi

        # 4. 执行防火墙封禁或解封
        if [ "$is_stop" = true ]; then
            if ! nft list chain inet $NFT_TABLE drop_chain | grep -q "tcp dport $port drop"; then
                nft add rule inet $NFT_TABLE drop_chain tcp dport $port drop 2>/dev/null
            fi
        else
            local handles=$(nft -a list chain inet $NFT_TABLE drop_chain | grep "tcp dport $port drop" | awk '{print $NF}')
            for h in $handles; do
                nft delete rule inet $NFT_TABLE drop_chain handle $h 2>/dev/null
            done
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
                [ "$(echo "$u $l" | awk '{if($1>=$2) print 1; else print 0}')" -eq 1 ] && s="溢出"
                if [ "$e" != "永久" ] && [ "$(date +%s)" -ge "$(date -d "$e" +%s 2>/dev/null || echo 0)" ]; then s="过期"; fi
                printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "$port" "$s" "$(fmt_size $u)" "$(fmt_size $l)" "$e"
            done
            echo "----------------------------------------------------------------"
            read -p "按回车键返回主菜单..." dummy; show_menu ;;
        
        2)
            read -p "请输入端口号 (如 13031): " p
            [ -z "$p" ] && show_menu
            read -p "设置月流量额度 (GB): " g
            [ -z "$g" ] && g=1000
            read -p "有效期 (YYYY-MM-DD, 留空永久): " e
            [ -z "$e" ] && e="永久"
            
            jq ".\"$p\" = {\"limit\": $(to_bytes $g), \"used\": 0, \"expire\": \"$e\", \"last_reset\": $(date +%s)}" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
            nft add rule inet $NFT_TABLE count_chain tcp dport $p counter accept 2>/dev/null
            echo "端口 $p 配置已保存！"
            sleep 1; show_menu ;;
            
        3)
            read -p "输入要清零流量的端口: " p
            if jq -e ".\"$p\"" "$DB_FILE" >/dev/null; then
                nft reset rule inet $NFT_TABLE count_chain tcp dport $p >/dev/null 2>&1
                jq ".\"$p\".last_reset = $(date +%s)" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
                echo "端口 $p 流量已重置。"
            else
                echo "错误：未找到端口 $p"
            fi
            sleep 1; show_menu ;;

        4)
            read -p "输入要删除的端口: " p
            jq "del(.\"$p\")" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
            local handles=$(nft -a list table inet $NFT_TABLE | grep "tcp dport $p" | awk '{print $NF}')
            for h in $handles; do nft delete rule inet $NFT_TABLE count_chain handle $h 2>/dev/null; done
            echo "端口 $p 已删除。"
            sleep 1; show_menu ;;

        5)
            daemon_check; echo "同步成功！"; sleep 1; show_menu ;;

        0) exit 0 ;;

        *)
            echo "无效选项，请重新输入。"
            sleep 1; show_menu ;;
    esac
}

# --- 脚本入口判定 ---
if [ "$1" = "daemon" ]; then
    daemon_check
else
    show_menu
fi
