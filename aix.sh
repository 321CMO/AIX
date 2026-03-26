#!/bin/sh

# --- 环境初始化 ---
DB_DIR="/etc/aix"
DB_FILE="$DB_DIR/data.json"
NFT_TABLE="aix_guard"
mkdir -p "$DB_DIR"
[ ! -f "$DB_FILE" ] && echo "{}" > "$DB_FILE"

# --- 工具函数 (awk 处理大数字) ---
to_bytes() { echo "$1" | awk '{printf "%.0f", $1 * 1073741824}'; }
fmt_size() {
    echo "$1" | awk '{
        if ($1 >= 1073741824) printf "%.2f GB", $1/1073741824;
        else printf "%.2f MB", $1/1048576;
    }'
}

# --- 核心同步：改为 prerouting 钩子 ---
daemon_check() {
    # 建立表结构，优先级设为 -150 (最先捕捉)
    nft add table inet $NFT_TABLE 2>/dev/null
    nft "add chain inet $NFT_TABLE count_chain { type filter hook prerouting priority -150; }" 2>/dev/null
    nft "add chain inet $NFT_TABLE drop_chain { type filter hook prerouting priority -100; }" 2>/dev/null
    
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)
    local now_ts=$(date +%s)
    
    for port in $(jq -r 'keys[]' "$DB_FILE" 2>/dev/null); do
        [ -z "$port" ] || [ "$port" = "null" ] && continue

        # 确保内核中有该端口的计数器
        if ! echo "$stats" | grep -q "tcp dport $port counter"; then
            nft add rule inet $NFT_TABLE count_chain tcp dport $port counter accept 2>/dev/null
        fi

        # 提取流量并确保是纯数字
        local cur_bytes=$(echo "$stats" | grep "tcp dport $port" | grep "counter" | sed -n 's/.*bytes \([0-9]*\).*/\1/p' | head -n 1)
        [ -z "$cur_bytes" ] && cur_bytes=0
        
        # 写入数据库
        local tmp=$(jq --arg p "$port" --arg v "$cur_bytes" '.[$p].used = ($v|tonumber)' "$DB_FILE")
        echo "$tmp" > "$DB_FILE"

        # 封禁判定
        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        local expire=$(jq -r ".\"$port\".expire" "$DB_FILE")
        local is_stop="false"
        if [ "$(echo "$cur_bytes $limit" | awk '{if($1 >= $2) print 1; else print 0}')" -eq 1 ]; then is_stop="true"; fi
        if [ "$expire" != "永久" ]; then
            local exp_ts=$(date -d "$expire" +%s 2>/dev/null || echo 0)
            [ "$now_ts" -ge "$exp_ts" ] && is_stop="true"
        fi

        # 执行动作
        if [ "$is_stop" = "true" ]; then
            if ! nft list chain inet $NFT_TABLE drop_chain | grep -q "tcp dport $port drop"; then
                nft insert rule inet $NFT_TABLE drop_chain tcp dport $port drop 2>/dev/null
            fi
        else
            local handles=$(nft -a list chain inet $NFT_TABLE drop_chain | grep "tcp dport $port drop" | awk '{print $NF}')
            for h in $handles; do nft delete rule inet $NFT_TABLE drop_chain handle $h 2>/dev/null; done
        fi
    done
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo "========================================"
    echo "    AIX (Alpine Internal X-monitor)    "
    echo "========================================"
    echo "1. 查看流量看板"
    echo "2. 添加/修改计费端口"
    echo "3. 重置流量 (清零)"
    echo "4. 删除计费端口"
    echo "5. 立即同步状态"
    echo "0. 退出"
    echo "----------------------------------------"
    read -p "选择 [0-5]: " opt
    case "$opt" in
        1)
            daemon_check
            printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "端口" "状态" "已用" "总额度" "有效期"
            echo "----------------------------------------------------------------"
            jq -r 'keys[]' "$DB_FILE" | sort -n | while read port; do
                local u=$(jq -r ".\"$port\".used" "$DB_FILE")
                local l=$(jq -r ".\"$port\".limit" "$DB_FILE")
                local e=$(jq -r ".\"$port\".expire" "$DB_FILE")
                local s="运行"
                [ "$(echo "$u $l" | awk '{if($1>=$2) print 1; else print 0}')" -eq 1 ] && s="溢出"
                printf "%-7s | %-6s | %-12s | %-12s | %-10s\n" "$port" "$s" "$(fmt_size $u)" "$(fmt_size $l)" "$e"
            done
            read -p "按回车返回..." dummy; show_menu ;;
        2)
            read -p "端口: " p; [ -z "$p" ] && show_menu
            read -p "额度(GB): " g
            read -p "有效期(YYYY-MM-DD): " e; [ -z "$e" ] && e="永久"
            local b=$(to_bytes $g)
            local tmp=$(jq --arg p "$p" --arg b "$b" --arg e "$e" --arg t "$(date +%s)" '.[$p] = {"limit": ($b|tonumber), "used": 0, "expire": $e, "last_reset": ($t|tonumber)}' "$DB_FILE")
            echo "$tmp" > "$DB_FILE"
            nft add rule inet $NFT_TABLE count_chain tcp dport $p counter accept 2>/dev/null
            echo "已保存"; sleep 1; show_menu ;;
        3)
            read -p "端口: " p
            nft reset rule inet $NFT_TABLE count_chain tcp dport $p >/dev/null 2>&1
            local tmp=$(jq --arg p "$p" --arg t "$(date +%s)" '.[$p].last_reset = ($t|tonumber)' "$DB_FILE")
            echo "$tmp" > "$DB_FILE"
            show_menu ;;
        4)
            read -p "端口: " p
            local tmp=$(jq --arg p "$p" 'del(.[$p])' "$DB_FILE")
            echo "$tmp" > "$DB_FILE"
            local h=$(nft -a list table inet $NFT_TABLE | grep "tcp dport $p" | awk '{print $NF}')
            for i in $h; do nft delete rule inet $NFT_TABLE count_chain handle $i 2>/dev/null; done
            show_menu ;;
        5) daemon_check; show_menu ;;
        *) exit 0 ;;
    esac
}

if [ "$1" = "daemon" ]; then daemon_check; else show_menu; fi
