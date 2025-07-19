#!/bin/bash

# ===== 配置参数 =====
APP_NAME="QuickQ For Mac"
APP_PATH="/Applications/QuickQ For Mac.app"
MAX_RETRY=3
RESTART_INTERVAL=7200  # 2小时（秒）
APP_CHECK_INTERVAL=20   # 应用检测间隔（秒）
VPN_CHECK_INTERVAL=300  # VPN检测间隔（秒）

# 按钮坐标（根据您的实际设置）
SETTINGS_BUTTON_X=1869
SETTINGS_BUTTON_Y=165
DROP_DOWN_BUTTON_X=1720
DROP_DOWN_BUTTON_Y=430
CONNECT_BUTTON_X=1720
CONNECT_BUTTON_Y=260

# ===== 状态变量 =====
retry_count=0
is_fresh_start=true  # 初始状态设为首次启动
last_restart_time=$(date +%s)
last_app_check_time=0
last_vpn_check_time=0

# ===== 带时间戳的输出函数 =====
log() {
    echo "[$(date +"%T")] $1"
}

# ===== 函数定义 =====

adjust_window() {
    log "🔄 调整应用窗口位置..."
    osascript <<'EOF'
    tell application "System Events"
        tell process "QuickQ For Mac"
            set position of window 1 to {1520, 0}
            set size of window 1 to {400, 300}
        end tell
    end tell
EOF
    sleep 1
    log "✅ 窗口调整完成"
}

check_vpn_connection() {
    log "🔍 启动VPN通道检测..."
    local start_time=$(date +%s)
    local success=false

    # 测试端点列表（轻量级204接口）
    local endpoints=(
        "https://www.google.com/generate_204"
        "https://www.youtube.com/generate_204"
    )

    # 遍历检测所有端点
    for url in "${endpoints[@]}"; do
        domain=$(echo "$url" | awk -F/ '{print $3}')
        log "  🌐 正在测试 $domain ..."
        
        if curl --max-time 10 --silent --fail "$url" >/dev/null; then
            log "  ✅ $domain 检测通过 (204)"
            success=true
            break
        else
            log "  ❌ $domain 检测失败 (curl代码: $?)"
        fi
    done

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if $success; then
        log "🟢 VPN通道正常 (耗时: ${elapsed}s)"
        return 0
    else
        log "🔴 VPN通道异常 (总耗时: ${elapsed}s)"
        return 1
    fi
}

connect_procedure() {
    log "🔌 启动VPN连接流程..."
    
    # 激活窗口
    log "🖥️ 激活应用窗口..."
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 1
    
    # 调整窗口
    adjust_window
    
    # 连接操作
    log "🖱️ 点击设置按钮 ($SETTINGS_BUTTON_X,$SETTINGS_BUTTON_Y)..."
    cliclick c:$SETTINGS_BUTTON_X,$SETTINGS_BUTTON_Y
    sleep 1
    
    log "🖱️ 点击下拉菜单 ($DROP_DOWN_BUTTON_X,$DROP_DOWN_BUTTON_Y)..."
    cliclick c:$DROP_DOWN_BUTTON_X,$DROP_DOWN_BUTTON_Y 
    sleep 1
    
    log "🖱️ 点击连接按钮 ($CONNECT_BUTTON_X,$CONNECT_BUTTON_Y)..."
    cliclick c:$CONNECT_BUTTON_X,$CONNECT_BUTTON_Y
    sleep 10
    
    # 检测连接结果
    if check_vpn_connection; then
        log "✅ VPN连接成功"
        retry_count=0
        is_fresh_start=false
        return 0
    else
        ((retry_count++))
        log "❌ VPN连接失败 (尝试 $retry_count/$MAX_RETRY)"
        return 1
    fi
}

force_restart() {
    log "🔄 开始强制重启应用..."
    log "⏹️ 终止进程..."
    pkill -9 -f "$APP_NAME" && log "✅ 进程已终止"
    sleep 2
    
    log "🚀 重新启动应用..."
    open "$APP_PATH"
    sleep 10
    
    is_fresh_start=true
    retry_count=0
    connect_procedure
    last_restart_time=$(date +%s)
    log "🔄 应用重启流程完成"
}

# ===== 主循环 =====
log "🚀 启动QuickQ自动化管理脚本..."
log "⏱️ 应用检测间隔: ${APP_CHECK_INTERVAL}秒 | VPN检测间隔: ${VPN_CHECK_INTERVAL}秒"

while :; do
    current_time=$(date +%s)
    
    # 1. 计算下次检测时间
    next_app_check=$((last_app_check_time + APP_CHECK_INTERVAL - current_time))
    next_vpn_check=$((last_vpn_check_time + VPN_CHECK_INTERVAL - current_time))
    
    [ $next_app_check -lt 0 ] && next_app_check=0
    [ $next_vpn_check -lt 0 ] && next_vpn_check=0
    
    log "⏳ 状态: [应用检测: ${next_app_check}秒后] [VPN检测: ${next_vpn_check}秒后]"
    
    # 2. 定期重启检查
    restart_in=$((last_restart_time + RESTART_INTERVAL - current_time))
    [ $restart_in -lt 0 ] && restart_in=0
    log "🕒 下次定期重启: ${restart_in}秒后"
    
    if [ $restart_in -eq 0 ]; then
        force_restart
        continue
    fi
    
    # 3. 首次启动特殊处理
    if $is_fresh_start; then
        if [ $retry_count -ge $MAX_RETRY ]; then
            log "⚠️ 首次启动达到最大重试次数，强制重启..."
            force_restart
        else
            if ! check_vpn_connection; then
                log "🔄 首次启动VPN未连接，尝试连接 ($((retry_count+1))/$MAX_RETRY)..."
                connect_procedure
            else
                is_fresh_start=false
            fi
        fi
        sleep 5
        continue  # 跳过常规检测，直接进入下一次循环
    fi
    
    # 4. 常规运行状态检测（非首次启动）
    if [ $((current_time - last_app_check_time)) -ge $APP_CHECK_INTERVAL ]; then
        log "🔍 开始应用运行状态检测..."
        last_app_check_time=$(date +%s)
        
        if ! pgrep -f "$APP_NAME" >/dev/null; then
            log "❌ 检测到应用未运行，正在启动..."
            open "$APP_PATH"
            sleep 10
            is_fresh_start=true  # 应用重启视为首次启动
            retry_count=0
            continue
        else
            log "✔️ 应用运行正常"
        fi
    fi
    
    # 5. VPN状态检测（非首次启动）
    if [ $((current_time - last_vpn_check_time)) -ge $VPN_CHECK_INTERVAL ]; then
        log "🌐 开始VPN连接状态检测..."
        last_vpn_check_time=$(date +%s)
        
        if ! check_vpn_connection; then
            log "🏃 运行中检测到VPN断开，直接重启..."
            force_restart
        else
            log "✅ VPN连接状态正常"
        fi
    fi
    
    # 6. 计算最小等待时间
    sleep_time=1
    [ $next_app_check -gt 0 ] && sleep_time=$next_app_check
    [ $next_vpn_check -gt 0 ] && [ $next_vpn_check -lt $sleep_time ] && sleep_time=$next_vpn_check
    
    log "⏸️ 等待${sleep_time}秒后继续..."
    sleep $sleep_time
done
