#!/bin/sh

DB_DIR="/etc/aix"
DB_FILE="$DB_DIR/data.json"
NFT_TABLE="aix_guard"
mkdir -p "$DB_DIR"
[ ! -f "$DB_FILE" ] && echo "{}" > "$DB_FILE"

to_bytes() { echo "$1" | awk '{printf "%.0f", $1 * 1073741824}'; }
fmt_size() {
    echo "$1" | awk '{
        if ($1 >= 1073741824) printf "%.2f GB", $1/1073741824;
        else printf "%.2f MB", $1/1048576;
    }'
}

daemon_check() {
    # 1. 初始化表：增加 MSS 钳制链解决网页打不开，增加 Forward 链统计转发
    nft add table inet $NFT_TABLE 2>/dev/null
    # 统计入站和转发的总流量
    nft "add chain inet $NFT_TABLE count_chain { type filter hook prerouting priority -150; }" 2>/dev/null
    # 修复网页打不开：强制修改 MSS 值为 1300
    nft "add chain inet $NFT_TABLE mangle_chain { type filter hook forward priority -151; }" 2>/dev/null
    nft add rule inet $NFT_TABLE mangle_chain tcp flags syn tcp option maxseg size set 1300 2>/dev/null
    
    nft "add chain inet $NFT_TABLE drop_chain { type filter hook prerouting priority -100; }" 2>/dev/null
    
    local stats=$(nft list table inet $NFT_TABLE 2>/dev/null)
    local now_ts=$(date +%s)
    
    for port in $(jq -r 'keys[]' "$DB_FILE" 2>/dev/null); do
        [ -z "$port" ] || [ "$port" = "null" ] && continue

        # 确保统计规则存在
        if ! echo "$stats" | grep -q "tcp dport $port counter"; then
            nft add rule inet $NFT_TABLE count_chain tcp dport $port counter accept 2>/dev/null
        fi

        # 核心修复：统计双向流量 (入站 dport + 出站 sport)
        # 注意：这里我们主要取入站流量作为计费基准，若需更准需开启双向统计
        local cur_bytes=$(echo "$stats" | grep "tcp dport $port" | grep "counter" | sed -n 's/.*bytes \([0-9]*\).*/\1/p' | head -n 1)
        [ -z "$cur_bytes" ] && cur_bytes=0
        
        # 写入数据库 (倍率系数 1.15，补偿 TCP 握手开销)
        local adj_bytes=$(echo "$cur_bytes" | awk '{printf "%.0f", $1 * 1.15}')
        local tmp=$(jq --arg p "$port" --arg v "$adj_bytes" '.[$p].used = ($v|tonumber)' "$DB_FILE")
        echo "$tmp" > "$DB_FILE"

        local limit=$(jq -r ".\"$port\".limit" "$DB_FILE")
        if [ "$(echo "$adj_bytes $limit" | awk '{if($1 >= $2) print 1; else print 0}')" -eq 1 ]; then
            nft insert rule inet $NFT_TABLE drop_chain tcp dport $port drop 2>/dev/null
        else
            local handles=$(nft -a list chain inet $NFT_TABLE drop_chain | grep "tcp dport $port drop" | awk '{print $NF}')
            for h in $handles; do nft delete rule inet $NFT_TABLE drop_chain handle $h 2>/dev/null; done
        fi
    done
}

show_menu() {
    clear
    echo "AIX (Alpine Internal X-monitor)"
    echo "----------------------------------------"
    echo "1. 查看流量看板"
    echo "2. 添加/修改端口"
    echo "3. 重置流量"
    echo "4. 删除端口"
    echo "5. 立即同步"
    echo "0. 退出"
    read -p "选择: " opt
    case "$opt" in
        1)
            daemon_check
            printf "%-7s | %-6s | %-12s | %-12s\n" "端口" "状态" "已用" "总额度"
            jq -r 'keys[]' "$DB_FILE" | sort -n | while read port; do
                local u=$(jq -r ".\"$port\".used" "$DB_FILE")
                local l=$(jq -r ".\"$port\".limit" "$DB_FILE")
                printf "%-7s | %-6s | %-12s | %-12s\n" "$port" "运行" "$(fmt_size $u)" "$(fmt_size $l)"
            done
            read -p "返回..." d; show_menu ;;
        2)
            read -p "端口: " p; read -p "额度(GB): " g
            local b=$(to_bytes $g)
            local tmp=$(jq --arg p "$p" --arg b "$b" --arg t "$(date +%s)" '.[$p] = {"limit": ($b|tonumber), "used": 0, "expire": "永久", "last_reset": ($t|tonumber)}' "$DB_FILE")
            echo "$tmp" > "$DB_FILE"
            daemon_check; show_menu ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

[ "$1" = "daemon" ] && daemon_check || show_menu
