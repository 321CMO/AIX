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

# --- 核心守护进程 (每分钟同步) ---
daemon_check() {
    local now_ts=$(date +%s)
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)
    
    for port in $(jq -r 'keys[]' "$DB_FILE"); do
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
        local cur_bytes=$(echo "$stats" | grep "tcp dport $port" | grep "counter" | sed 's/.*bytes \([0-9]*\).*/\1/')
        [ -z "$cur_bytes" ] || [ "$cur_bytes" = "$stats" ] && cur_bytes=0
        
        # 更新数据库
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
            [ -n "$handle" ] && nft delete rule inet $NFT_TABLE drop_chain handle $handle
        fi
    done
}

# --- 菜单：看板显示 ---
show_dashboard() {
    daemon_check
    echo "================== AIX 流量计费看板 =================="
    printf "%-8s | %-8s | %-12s | %-12s | %-10s\n" "端口" "状态" "已用" "总额度" "有效期"
    echo "------------------------------------------------------"
    for port in $(jq -r 'keys[]' "$DB_FILE" | sort -n); do
        local used=$(jq -r ".\"$port\".used" "$DB_FILE")
        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        local expire=$(jq -r ".\"$port\".expire" "$DB_FILE")
        
        local status="运行"
        [ "$used" -ge "$limit" ] && status="溢出"
        if [ "$expire" != "永久" ]; then
             [ "$(date +%s)" -ge "$(date -d "$expire" +%s 2>/dev/null || echo 0)" ] && status="过期"
        fi
        
        printf "%-8s | %-8s | %-12s | %-12s | %-10s\n" \
            "$port" "$status" "$(fmt_size $used)" "$(fmt_size $limit)" "$expire"
    done
    echo "======================================================"
}

# --- 脚本入口 ---
case "$1" in
    "daemon") daemon_check ;;
    "init") echo "已初始化" ;;
    *)
        clear
        echo "AIX (Alpine Internal X-monitor) 管理系统"
        echo "----------------------------------------"
        echo "1. 查看流量看板"
        echo "2. 添加计费用户"
        echo "3. 删除计费用户"
        echo "4. 立即同步计费状态"
        echo "0. 退出"
        read -p "请选择: " opt
        case $opt in
            1) show_dashboard ;;
            2) 
                read -p "端口: " p
                read -p "额度(GB): " g
                read -p "有效期(YYYY-MM-DD, 留空永久): " e
                [ -z "$e" ] && e="永久"
                jq ".\"$p\" = {\"limit\": $(to_bytes $g), \"used\": 0, \"expire\": \"$e\", \"last_reset\": $(date +%s)}" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
                nft add rule inet $NFT_TABLE count_chain tcp dport $p counter accept
                echo "用户 $p 添加成功。"
                ;;
            3) 
                read -p "输入要删除的端口: " p
                jq "del(.\"$p\")" "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
                # 同时清理防火墙规则
                local handle=$(nft -a list table inet $NFT_TABLE | grep "tcp dport $p" | awk '{print $NF}')
                for h in $handle; do nft delete rule inet $NFT_TABLE count_chain handle $h 2>/dev/null; done
                echo "用户 $p 已删除。"
                ;;
            4) daemon_check; echo "同步完成！" ;;
            *) exit 0 ;;
        esac
        ;;
esac
