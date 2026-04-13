#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# AIX-Xray 脚本管理工具 - 终极稳定版
# 新增：1. 菜单内一键更新脚本功能
#       2. 修复 Reality 协议支持 (flow/xtls-rprx-vision)
#       3. 修复 SS 配置支持 (uot: true)
#       4. 修复 JSON 生成语法错误
# ═══════════════════════════════════════════════════════════════

XRAY_DIR="$HOME/Documents/Xray-macos-64"
XRAY_BIN="$XRAY_DIR/xray"
SUBS_DIR="$XRAY_DIR/subs"
PID_FILE="$TMPDIR/aix_xray.pid"
LOG_FILE="$HOME/.aix_xray.log"
LAST_NODE_FILE="$HOME/.aix_last_node"
AUTOSTART_PLIST="$HOME/Library/LaunchAgents/com.user.aix-autostart.plist"
NETWORK_SERVICE=""
SOCKS_IP="127.0.0.1"
SOCKS_PORT="10808"
REPO_URL="https://raw.githubusercontent.com/321CMO/AIX/main/aix"

# ───────── 基础工具 ─────────
rotate_log() {
    [ -f "$LOG_FILE" ] || return
    local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 2097152 ]; then
        [ -f "$LOG_FILE.2" ] && rm -f "$LOG_FILE.2"
        [ -f "$LOG_FILE.1" ] && mv "$LOG_FILE.1" "$LOG_FILE.2"
        mv "$LOG_FILE" "$LOG_FILE.1"
        touch "$LOG_FILE"
    fi
}

cleanup_processes() {
    if [ -f "$PID_FILE" ]; then
        kill -9 "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    pkill -9 -f "xray run -config" 2>/dev/null
    sleep 1
}

url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# ───────── 脚本在线更新 ─────────
update_script() {
    echo "📥 正在从 GitHub 下载最新版..."
    # 强制走代理下载，确保成功率
    curl -x socks5h://127.0.0.1:$SOCKS_PORT -fsSL "$REPO_URL" -o ~/bin/aix 2>/dev/null
    if [ $? -eq 0 ]; then
        chmod +x ~/bin/aix
        echo "✅ 更新成功！"
        echo "💡 当前代理未断开。请退出后重新运行 'aix' 以使用新版本。"
    else
        echo "✗ 下载失败，请检查网络或代理状态。"
    fi
    read -p "按回车继续..."
}

# ───────── 订阅管理 ─────────
import_subscription() {
    echo ""
    echo -n "输入订阅链接: "
    read -r sub_url
    [ -z "$sub_url" ] && { echo "取消导入"; read -p "按回车继续..."; return 1; }
    
    echo -n "输入订阅名称（文件夹名）: "
    read -r sub_name
    [ -z "$sub_name" ] && { echo "取消导入"; read -p "按回车继续..."; return 1; }
    
    mkdir -p "$SUBS_DIR/$sub_name"
    
    echo "📥 正在下载订阅..."
    local content=$(curl -fsSL "$sub_url" 2>/dev/null)
    [ -z "$content" ] && { echo "✗ 下载失败"; read -p "按回车继续..."; return 1; }
    
    local decoded=$(echo "$content" | base64 -D 2>/dev/null)
    [ -z "$decoded" ] && { echo "✗ 解码失败"; read -p "按回车继续..."; return 1; }
    
    local count=0 success=0
    echo "🔄 正在解析节点..."
    
    local IFS_BAK=$IFS
    IFS=$'\n'
    local lines=($decoded)
    IFS=$IFS_BAK
    
    for line in "${lines[@]}"; do
        [ -z "$line" ] && continue
        ((count++))
        echo -ne "  进度: $count 节点\r"
        
        if [[ "$line" =~ ^vmess:// ]]; then
            parse_and_save_vmess "$line" "$sub_name" && ((success++))
        elif [[ "$line" =~ ^ss:// ]]; then
            parse_and_save_ss "$line" "$sub_name" && ((success++))
        fi
    done
    
    echo ""
    echo "✅ 导入完成: $success/$count 节点成功"
    
    cat > "$SUBS_DIR/$sub_name/.sub-info" << INFOEOF
url=$sub_url
name=$sub_name
updated=$(date +%s)
nodes=$success
INFOEOF
    
    read -p "按回车继续..."
}

parse_and_save_vmess() {
    local url="$1"
    local sub_dir="$2"
    
    local json_str=$(echo "$url" | sed 's/vmess:\/\///' | base64 -D 2>/dev/null)
    [ -z "$json_str" ] && return 1
    
    local add=$(echo "$json_str" | grep -o '"add":"[^"]*"' | cut -d'"' -f4)
    local port=$(echo "$json_str" | grep -o '"port":[0-9]*' | cut -d':' -f2)
    local id=$(echo "$json_str" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    local ps=$(echo "$json_str" | grep -o '"ps":"[^"]*"' | cut -d'"' -f4)
    local net=$(echo "$json_str" | grep -o '"net":"[^"]*"' | cut -d'"' -f4)
    local tls=$(echo "$json_str" | grep -o '"tls":"[^"]*"' | cut -d'"' -f4)
    local host=$(echo "$json_str" | grep -o '"host":"[^"]*"' | cut -d'"' -f4)
    local path=$(echo "$json_str" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
    local security=$(echo "$json_str" | grep -o '"security":"[^"]*"' | cut -d'"' -f4)
    local sni=$(echo "$json_str" | grep -o '"sni":"[^"]*"' | cut -d'"' -f4)
    local pbk=$(echo "$json_str" | grep -o '"pbk":"[^"]*"' | cut -d'"' -f4)
    local sid=$(echo "$json_str" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)
    local flow=$(echo "$json_str" | grep -o '"flow":"[^"]*"' | cut -d'"' -f4)
    
    [ -z "$ps" ] && ps="vmess-unknown"
    local name=$(echo "$ps" | tr -d '\/:*?"<>|' | sed 's/ /-/g')
    local outfile="$SUBS_DIR/$sub_dir/config-${name}.json"
    
    # 构建流控设置
    local stream_settings=""
    local user_flow=""
    [ -n "$flow" ] && user_flow=", \"flow\": \"$flow\""

    if [ "$security" = "reality" ]; then
        stream_settings="\"network\": \"$net\", \"security\": \"reality\", \"realitySettings\": { \"show\": false, \"fingerprint\": \"chrome\", \"serverName\": \"${sni:-$host}\", \"publicKey\": \"$pbk\", \"shortId\": \"$sid\" }"
    elif [ "$tls" = "tls" ] || [ "$security" = "tls" ]; then
        stream_settings="\"network\": \"$net\", \"security\": \"tls\", \"tlsSettings\": { \"serverName\": \"${sni:-$host}\" }"
    else
        stream_settings="\"network\": \"$net\", \"security\": \"none\""
    fi
    
    cat > "$outfile" << VMESSEOF
{
  "log": { "loglevel": "info" },
  "dns": { "servers": ["1.1.1.1", "8.8.8.8", "localhost"] },
  "inbounds": [{ "tag": "socks-in", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": { "auth": "noauth", "udp": true }, "sniffing": { "enabled": true, "destOverride": ["http", "tls"] } }],
  "outbounds": [{
    "tag": "proxy",
    "protocol": "vmess",
    "settings": {
      "vnext": [{
        "address": "$add",
        "port": $port,
        "users": [{ "id": "$id", "alterId": 0, "security": "auto" $user_flow }]
      }]
    },
    "streamSettings": { $stream_settings }
  }, { "tag": "direct", "protocol": "freedom" }, { "tag": "block", "protocol": "blackhole" }],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "domain": ["geosite:cn", "geosite:private"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:cn"], "outboundTag": "direct" },
      { "type": "field", "domain": ["openai.com", "google.com", "youtube.com", "gstatic.com"], "outboundTag": "proxy" },
      { "type": "field", "network": "tcp,udp", "outboundTag": "proxy" }
    ]
  }
}
VMESSEOF
    return 0
}

parse_and_save_ss() {
    local url="$1"
    local sub_dir="$2"
    
    local encoded=$(echo "$url" | sed 's/ss:\/\///' | cut -d'#' -f1)
    local remark=$(url_decode "$(echo "$url" | grep -o '#.*' | sed 's/#//')")
    
    local decoded=$(echo "$encoded" | base64 -D 2>/dev/null)
    [ -z "$decoded" ] && return 1
    
    local method=$(echo "$decoded" | cut -d':' -f1)
    local pass_host_port=$(echo "$decoded" | cut -d':' -f2-)
    local pass=$(echo "$pass_host_port" | cut -d'@' -f1)
    local host_port=$(echo "$pass_host_port" | cut -d'@' -f2)
    local host=$(echo "$host_port" | cut -d':' -f1)
    local port=$(echo "$host_port" | cut -d':' -f2)
    
    [ -z "$remark" ] && remark="ss-unknown"
    local name=$(echo "$remark" | tr -d '\/:*?"<>|' | sed 's/ /-/g')
    local outfile="$SUBS_DIR/$sub_dir/config-${name}.json"
    
    cat > "$outfile" << SSEOF
{
  "log": { "loglevel": "info" },
  "dns": { "servers": ["1.1.1.1", "8.8.8.8", "localhost"] },
  "inbounds": [{ "tag": "socks-in", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": { "auth": "noauth", "udp": true }, "sniffing": { "enabled": true, "destOverride": ["http", "tls"] } }],
  "outbounds": [{
    "tag": "proxy",
    "protocol": "shadowsocks",
    "settings": { "servers": [{ "address": "$host", "port": $port, "method": "$method", "password": "$pass", "uot": true }] }
  }, { "tag": "direct", "protocol": "freedom" }, { "tag": "block", "protocol": "blackhole" }],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "domain": ["geosite:cn", "geosite:private"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:cn"], "outboundTag": "direct" },
      { "type": "field", "domain": ["openai.com", "google.com", "youtube.com", "gstatic.com"], "outboundTag": "proxy" },
      { "type": "field", "network": "tcp,udp", "outboundTag": "proxy" }
    ]
  }
}
SSEOF
    return 0
}

check_auto_update_async() {
    [ ! -d "$SUBS_DIR" ] && return
    local now=$(date +%s)
    
    for sub_dir in "$SUBS_DIR"/*/; do
        [ -d "$sub_dir" ] || continue
        local info_file="$sub_dir/.sub-info"
        [ -f "$info_file" ] || continue
        
        local updated=$(grep '^updated=' "$info_file" | cut -d'=' -f2-)
        local interval=$((now - updated))
        
        if [ "$interval" -gt 86400 ]; then
            local sub_name=$(basename "$sub_dir")
            (
                local content=$(curl -fsSL "$(grep '^url=' "$info_file" | cut -d'=' -f2-)" 2>/dev/null)
                if [ -n "$content" ]; then
                    local decoded=$(echo "$content" | base64 -D 2>/dev/null)
                    if [ -n "$decoded" ]; then
                        local new_count=$(echo "$decoded" | wc -l | tr -d ' ')
                        cat > "$info_file" << EOF
url=$(grep '^url=' "$info_file" | cut -d'=' -f2-)
name=$sub_name
updated=$now
nodes=$new_count
EOF
                    fi
                fi
            ) &
        fi
    done
}

update_subscription() {
    local sub_name="$1"
    [ -z "$sub_name" ] && {
        echo ""
        echo "可用订阅:"
        local subs=($(ls -1 "$SUBS_DIR" 2>/dev/null | grep -v '^\.'))
        [ ${#subs[@]} -eq 0 ] && { echo "暂无订阅"; read -p "按回车继续..."; return 1; }
        
        local i=1
        for sub in "${subs[@]}"; do echo "  $i) $sub"; ((i++)); done
        echo -n "选择 (1-${#subs[@]}): "
        read -r idx
        sub_name="${subs[$((idx-1))]}"
    }
    
    echo "🔄 正在更新: $sub_name"
    import_subscription 2>/dev/null || echo "✗ 更新失败"
    read -p "按回车继续..."
}

# ───────── 节点管理 ─────────
detect_nodes() {
    local nodes=()
    if [ -d "$XRAY_DIR" ]; then
        for config in "$XRAY_DIR"/config-*.json; do
            [ -f "$config" ] && [[ ! "$config" =~ /subs/ ]] && nodes+=("$(basename "$config" | sed 's/config-\(.*\)\.json/\1/')")
        done
    fi
    if [ -d "$SUBS_DIR" ]; then
        for config in "$SUBS_DIR"/*/config-*.json; do
            [ -f "$config" ] && nodes+=("$(basename "$config" | sed 's/config-\(.*\)\.json/\1/')")
        done
    fi
    local unique_nodes=()
    for n in "${nodes[@]}"; do
        [[ ! " ${unique_nodes[*]} " =~ " ${n} " ]] && unique_nodes+=("$n")
    done
    echo "${unique_nodes[@]}"
}

get_node_config() {
    local node="$1"
    [ -f "$XRAY_DIR/config-${node}.json" ] && echo "$XRAY_DIR/config-${node}.json" && return
    if [ -d "$SUBS_DIR" ]; then
        for config in "$SUBS_DIR"/*/config-${node}.json; do
            [ -f "$config" ] && echo "$config" && return
        done
    fi
}

# ───────── 其他功能 ─────────
is_proxy_running() { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }
is_autostart_enabled() { [ -f "$AUTOSTART_PLIST" ] && launchctl list | grep -q "com.user.aix-autostart" 2>/dev/null && echo "yes" || echo "no"; }
get_current_latency() {
    is_proxy_running || { echo "-1"; return; }
    local time=$(curl -x socks5h://127.0.0.1:$SOCKS_PORT -s -o /dev/null -w "%{time_total}" --max-time 2 http://www.gstatic.com/generate_204 2>/dev/null)
    if [ -n "$time" ] && [ "$time" != "0.000000" ]; then
        awk "BEGIN {printf \"%.0f\", $time * 1000}"
    else
        echo "-1"
    fi
}
get_node_ipv4() { is_proxy_running || { echo "-"; return; }; local ipv4=$(curl -x socks5h://127.0.0.1:$SOCKS_PORT -s --max-time 3 https://ipinfo.io/ip 2>/dev/null); [ -n "$ipv4" ] && echo "$ipv4" || echo "-"; }
get_node_ipv6() { is_proxy_running || { echo "-"; return; }; local ipv6=$(curl -x socks5h://127.0.0.1:$SOCKS_PORT -s -6 --max-time 3 https://v6.ipinfo.io/ip 2>/dev/null); [ -n "$ipv6" ] && echo "$ipv6" || echo "-"; }

start_proxy() {
    local node="${1:-$(cat "$LAST_NODE_FILE" 2>/dev/null)}"
    [ -z "$node" ] && { echo "请先选择节点"; read -p "按回车继续..."; return 1; }
    local config=$(get_node_config "$node")
    [ -z "$config" ] && { echo "配置文件不存在: $node"; read -p "按回车继续..."; return 1; }
    
    if [ -f "$PID_FILE" ]; then
        echo "停止旧进程..."
        cleanup_processes
    fi
    
    echo "启动 Xray ($node)..."
    cd "$XRAY_DIR" || return 1
    nohup "$XRAY_BIN" run -config "$config" >> "$LOG_FILE" 2>&1 &
    disown
    echo $! > "$PID_FILE"
    echo "$node" > "$LAST_NODE_FILE"
    sleep 2
    
    if ! is_proxy_running; then
        echo "✗ 启动失败，查看日志: tail -f $LOG_FILE"
        read -p "按回车继续..."
        return 1
    fi
    
    sudo /usr/sbin/networksetup -setsocksfirewallproxy "$NETWORK_SERVICE" "$SOCKS_IP" "$SOCKS_PORT" 2>/dev/null
    sudo /usr/sbin/networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" on 2>/dev/null
    echo "✓ 连接成功"
    read -p "按回车继续..."
}

stop_proxy() {
    echo "正在停止..."
    cleanup_processes
    sudo /usr/sbin/networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" off 2>/dev/null
    echo "✓ 已停止"
    read -p "按回车继续..."
}

view_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "最近 50 行日志:"; echo "─────────────────────────"; tail -n 50 "$LOG_FILE"
    else
        echo "暂无日志"
    fi
    read -p "按回车继续..."
}

setup_autostart() {
    [ -f "$AUTOSTART_PLIST" ] && { echo "已配置过开机自启"; read -p "按回车继续..."; return; }
    echo "配置sudo免密..."
    echo "$USER ALL=(root) NOPASSWD: /usr/sbin/networksetup *" | sudo tee /etc/sudoers.d/aix-proxy > /dev/null
    sudo chmod 0440 /etc/sudoers.d/aix-proxy
    
    cat > "$AUTOSTART_PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.aix-autostart</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>sleep 15 && /Users/$USER/bin/aix --autostart</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLISTEOF
    launchctl load "$AUTOSTART_PLIST" 2>/dev/null
    echo "✓ 开机自启已启用"
    read -p "按回车继续..."
}

disable_autostart() {
    if [ -f "$AUTOSTART_PLIST" ]; then
        launchctl unload "$AUTOSTART_PLIST" 2>/dev/null
        rm -f "$AUTOSTART_PLIST"
        echo "✓ 开机自启已禁用"
    else
        echo "未配置开机自启"
    fi
    read -p "按回车继续..."
}

# ───────── 主菜单 ─────────
show_main_menu() {
    clear
    rotate_log
    check_auto_update_async
    
    local xray_ver="unknown"
    [ -x "$XRAY_BIN" ] && xray_ver=$("$XRAY_BIN" version 2>/dev/null | head -n 1 | awk '{print $2}')
    
    local running=$(is_proxy_running && echo "yes" || echo "no")
    local current_node=$(cat "$LAST_NODE_FILE" 2>/dev/null || echo "-")
    local latency=$(get_current_latency)
    local latency_display="$latency"
    [ "$latency" != "-1" ] && latency_display="${latency}ms"
    [ "$latency" = "-1" ] && latency_display="-"
    
    local autostart_status="未启用"
    [ "$(is_autostart_enabled)" = "yes" ] && autostart_status="已启用"
    local node_count=$(detect_nodes | wc -w | tr -d ' ')
    local node_ipv4=$(get_node_ipv4)
    local node_ipv6=$(get_node_ipv6)
    
    echo ""
    echo "AIX-Xray 脚本管理工具"
    echo "Xray 版本: $xray_ver"
    echo "可用节点: $node_count"
    echo "=============================="
    echo ""
    
    if [ "$running" = "yes" ]; then echo "代理状态: 已连接"; else echo "代理状态: 未连接"; fi
    echo ""
    echo "当前节点: $current_node"
    echo "网络延迟: $latency_display"
    echo "网卡接口: $NETWORK_SERVICE"
    echo "节点 IPv4: $node_ipv4"
    echo "节点 IPv6: $node_ipv6"
    echo "开机自启: $autostart_status"
    echo ""
    
    echo "功能菜单："
    echo "1) 启动节点"
    echo "2) 停止代理"
    echo "3) 测试所有节点延迟"
    echo "4) 查看日志"
    echo "5) 开机自启设置"
    echo "6) 导入订阅"
    echo "7) 更新订阅"
    echo "8) 更新所有订阅"
    echo "9) 列出订阅"
    echo "10) 检查脚本更新"
    echo "11) 退出程序"
    echo ""
    echo -n "选择操作 [1-11]: "
}

main() {
    NETWORK_SERVICE=$(/usr/sbin/networksetup -listallnetworkservices 2>/dev/null | grep -v '\*' | head -n 1)
    [ -z "$NETWORK_SERVICE" ] && NETWORK_SERVICE="Wi-Fi"
    trap 'echo -e "\n已退出"; exit 0' INT
    
    while true; do
        show_main_menu
        read -r choice
        case $choice in
            1)
                echo ""; echo "可用节点:"
                local nodes=($(detect_nodes))
                local i=1; for node in "${nodes[@]}"; do echo "  $i) $node"; ((i++)); done
                echo -n "选择 (1-${#nodes[@]}): "; read -r node_idx
                if [ "$node_idx" -ge 1 ] && [ "$node_idx" -le "${#nodes[@]}" ]; then
                    start_proxy "${nodes[$((node_idx-1))]}"
                else echo "无效选择"; read -p "按回车继续..."; fi
                ;;
            2) stop_proxy ;;
            3)
                echo ""; echo "测试所有节点延迟..."; echo "─────────────────────────"
                for node in $(detect_nodes); do echo -n "$node: "; local lat=$(test_node_latency "$node"); [ "$lat" != "9999" ] && echo "${lat}ms" || echo "超时"; done
                read -p "按回车继续..." ;;
            4) view_logs ;;
            5)
                echo ""; echo "1) 启用 2) 禁用"; echo -n "选择: "; read -r c
                case $c in 1) setup_autostart ;; 2) disable_autostart ;; esac ;;
            6) import_subscription ;;
            7) update_subscription ;;
            8)
                echo ""; echo "正在更新所有订阅..."
                [ -d "$SUBS_DIR" ] && for sub_dir in "$SUBS_DIR"/*/; do
                    [ -d "$sub_dir" ] || continue
                    local sub_name=$(basename "$sub_dir")
                    echo "→ 更新: $sub_name"
                    update_subscription "$sub_name"
                done || echo "暂无订阅"
                read -p "按回车继续..." ;;
            9)
                echo ""; echo "已导入的订阅:"; echo "─────────────────────────"
                [ ! -d "$SUBS_DIR" ] && { echo "暂无订阅"; read -p "按回车继续..."; return; }
                for sub_dir in "$SUBS_DIR"/*/; do
                    [ -d "$sub_dir" ] || continue
                    local sub_name=$(basename "$sub_dir")
                    local info_file="$sub_dir/.sub-info"
                    if [ -f "$info_file" ]; then
                        local nodes=$(grep '^nodes=' "$info_file" | cut -d'=' -f2-)
                        local updated=$(grep '^updated=' "$info_file" | cut -d'=' -f2-)
                        local date_str=$(date -r "$updated" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "未知")
                        echo "  • $sub_name"
                        echo "    节点: ${nodes:-?} | 更新: $date_str"
                    else
                        echo "  • $sub_name (未解析)"
                    fi
                done
                echo ""; read -p "按回车继续..." ;;
            10) update_script ;;
            11) echo "感谢使用，再见！"; exit 0 ;;
            *) echo "无效输入"; sleep 1 ;;
        esac
    done
}

test_node_latency() {
    local node="$1"
    local config=$(get_node_config "$node")
    [ -z "$config" ] && echo "9999" && return
    
    nohup "$XRAY_BIN" run -config "$config" >/dev/null 2>&1 &
    local temp_pid=$!
    sleep 2
    local time=$(curl -x socks5h://127.0.0.1:$SOCKS_PORT -s -o /dev/null -w "%{time_total}" --max-time 3 http://www.gstatic.com/generate_204 2>/dev/null)
    kill $temp_pid 2>/dev/null
    
    if [ -n "$time" ] && [ "$time" != "0.000000" ]; then
        awk "BEGIN {printf \"%.0f\", $time * 1000}"
    else
        echo "9999"
    fi
}

if [ "$1" = "--autostart" ]; then
    NETWORK_SERVICE=$(/usr/sbin/networksetup -listallnetworkservices 2>/dev/null | grep -v '\*' | head -n 1)
    [ -z "$NETWORK_SERVICE" ] && NETWORK_SERVICE="Wi-Fi"
    node=$(cat "$LAST_NODE_FILE" 2>/dev/null)
    if [ -n "$node" ]; then
        config=$(get_node_config "$node")
        if [ -n "$config" ]; then
            cd "$XRAY_DIR"
            nohup "$XRAY_BIN" run -config "$config" >> "$LOG_FILE" 2>&1 &
            disown
            sleep 2
            sudo /usr/sbin/networksetup -setsocksfirewallproxy "$NETWORK_SERVICE" "$SOCKS_IP" "$SOCKS_PORT" 2>/dev/null
            sudo /usr/sbin/networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" on 2>/dev/null
        fi
    fi
    exit 0
fi

main
