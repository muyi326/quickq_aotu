#!/bin/bash

# ===== 配置参数 =====
APP_NAME="QuickQ"
APP_PATH="/Applications/QuickQ For Mac.app"
MAX_RETRY=3
retry_count=0
just_started=false
last_restart_time=$(date +%s)
RESTART_INTERVAL=$((4*3600))  # 4小时转换为秒数
connection_verified=false

# 坐标参数
DROP_DOWN_BUTTON_X=1720 # 下拉按钮X  1720在右边 200在左边
DROP_DOWN_BUTTON_Y=430
CONNECT_BUTTON_X=1720  # 连接按钮X。1720在右边 200在左边
CONNECT_BUTTON_Y=260
SETTINGS_BUTTON_X=1869  # 设置按钮X   1869在右边。349在左边
SETTINGS_BUTTON_Y=165

# ===== 函数定义 =====

# 打印预计重启时间
print_restart_time() {
    local current_time=$(date +%s)
    local next_restart_time=$((last_restart_time + RESTART_INTERVAL))
    local remaining_seconds=$((next_restart_time - current_time))
    
    if [ $remaining_seconds -le 0 ]; then
        echo "[$(date +"%T")] ⏰ 即将执行定期重启..."
        return
    fi
    
    local remaining_hours=$((remaining_seconds / 3600))
    local remaining_minutes=$(( (remaining_seconds % 3600) / 60 ))
    local remaining_secs=$((remaining_seconds % 60))
    
    echo "[$(date +"%T")] ⏳ 预计重启时间: ${remaining_hours}小时${remaining_minutes}分钟${remaining_secs}秒后"
}

# VPN连接检测
check_vpn_connection() {
    # 如果刚启动应用，直接返回失败（不实际检查）
    if $just_started; then
        return 1
    fi

    local TEST_URLS=("https://x.com" "https://www.google.com")
    local TIMEOUT=20
    
    for url in "${TEST_URLS[@]}"; do
        if curl --silent --head --fail --max-time $TIMEOUT "$url" &> /dev/null; then
            echo "[$(date +"%T")] 检测：VPN连接正常"
            last_vpn_status="connected"
            retry_count=0  # 成功时重置计数器
            connection_verified=true
            return 0
        fi
    done
    
    last_vpn_status="disconnected"
    connection_verified=false
    return 1
}

# 窗口调整 - 将窗口放在右上角
adjust_window() {
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    
    osascript <<'EOF'
    tell application "System Events"
        tell process "QuickQ For Mac"
            repeat 3 times
                if exists window 1 then
                    -- 使用固定坐标将窗口放在右上角
                    -- 假设显示器分辨率为1920x1080，右上角坐标为(1520,0)
                    set position of window 1 to {1520, 0}
                    set size of window 1 to {400, 300}
                    exit repeat
                else
                    delay 0.5
                end if
            end repeat
        end tell
    end tell
EOF
    echo "[$(date +"%T")] 窗口位置已校准到右上角"
    sleep 1
}

# 连接流程
connect_procedure() {
    echo "[$(date +"%T")] 启动连接流程..."
    # 显示窗口并激活
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 2
    
    # 调整窗口并点击连接
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已点击设置按钮"
    sleep 1.5
    
    cliclick c:${DROP_DOWN_BUTTON_X},${DROP_DOWN_BUTTON_Y}
    echo "[$(date +"%T")] 已点击下拉菜单"
    sleep 1.5
    
    cliclick c:${CONNECT_BUTTON_X},${CONNECT_BUTTON_Y}
    echo "[$(date +"%T")] 已发起连接请求"
    sleep 10  # 等待连接建立
    
    # 连接后严格检查状态
    if check_vpn_connection; then
        echo "[$(date +"%T")] ✅ VPN连接成功"
        connection_verified=true
    else
        echo "[$(date +"%T")] ❌ VPN连接失败"
        connection_verified=false
    fi
}

# 应用初始化
initialize_app() {
    echo "[$(date +"%T")] 执行初始化操作..."
    just_started=true
    connection_verified=false
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 3
    
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已点击设置按钮"
    sleep 2
    
    connect_procedure
    just_started=false
    last_restart_time=$(date +%s)
    print_restart_time
}

# 终止并重启应用
terminate_and_restart() {
    echo "[$(date +"%T")] ⏰ 已达到4小时运行时间，执行定期重启..."
    pkill -9 -f "$APP_NAME" && echo "[$(date +"%T")] 已终止进程"
    sleep 2
    
    open "$APP_PATH"
    echo "[$(date +"%T")] 重新启动应用中..."
    sleep 10
    
    initialize_app
}

# 检查是否需要定期重启
check_regular_restart() {
    local current_time=$(date +%s)
    local elapsed_seconds=$((current_time - last_restart_time))
    
    if [ $elapsed_seconds -ge $RESTART_INTERVAL ]; then
        terminate_and_restart
    fi
}

# ===== 依赖检查 =====
if ! command -v cliclick &> /dev/null; then
    echo "正在通过Homebrew安装cliclick..."
    if ! command -v brew &> /dev/null; then
        echo "错误：请先安装Homebrew (https://brew.sh)"
        exit 1
    fi
    brew install cliclick
    
    # 触发权限请求
    echo "[$(date +"%T")] 依赖安装完成，正在执行一次性权限触发操作..."
    open "$APP_PATH"
    sleep 5
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 1
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已触发点击事件，请检查系统权限请求"
    sleep 10
    pkill -9 -f "$APP_NAME"
    exit 0
fi

# ===== 主循环 =====
while :; do
    # 检查是否需要定期重启
    check_regular_restart
    
    if ! $just_started; then
        if check_vpn_connection; then
            echo "[$(date +"%T")] ✅ VPN已连接"
            
            # 每30秒检查程序是否运行
            for ((i=0; i<20; i++)); do
                check_regular_restart
                print_restart_time
                
                if ! pgrep -f "$APP_NAME" &> /dev/null; then
                    echo "[$(date +"%T")] ❌ 程序未运行，正在启动..."
                    open "$APP_PATH"
                    sleep 10
                    initialize_app
                    break
                elif ! check_vpn_connection; then
                    echo "[$(date +"%T")] ⚠️ VPN连接断开，尝试重新连接..."
                    connect_procedure
                else
                    echo "[$(date +"%T")] ✅ 程序运行正常（VPN已连接）"
                fi
                sleep 30
            done
        else
            echo "[$(date +"%T")] ❌ VPN未连接，尝试重连... ($((retry_count+1))/$MAX_RETRY)"
            connect_procedure
            
            # 检查是否重连成功
            if ! check_vpn_connection; then
                ((retry_count++))
                echo "[$(date +"%T")] ⚠️ 第${retry_count}次重试失败"
                
                if [ $retry_count -ge $MAX_RETRY ]; then
                    terminate_and_restart
                    retry_count=0
                fi
            else
                retry_count=0
            fi
        fi
    fi
    
    print_restart_time
    sleep 10
done
