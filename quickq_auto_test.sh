#!/bin/bash

# ===== 配置参数 =====
APP_NAME="QuickQ"
APP_PATH="/Applications/QuickQ For Mac.app"
MAX_RETRY=3
retry_count=0

# 坐标参数
DROP_DOWN_BUTTON_X=200
DROP_DOWN_BUTTON_Y=430
CONNECT_BUTTON_X=200
CONNECT_BUTTON_Y=260
SETTINGS_BUTTON_X=349
SETTINGS_BUTTON_Y=165

# ===== 函数定义 =====

# VPN连接检测
check_vpn_connection() {
    local TEST_URLS=("https://x.com" "https://www.google.com")
    local TIMEOUT=3
    
    for url in "${TEST_URLS[@]}"; do
        if curl --silent --head --fail --max-time $TIMEOUT "$url" &> /dev/null; then
            echo "[$(date +"%T")] 检测：可通过 "
            last_vpn_status="connected"
            retry_count=0  # 成功时重置计数器
            return 0
        fi
    done
    
    last_vpn_status="disconnected"
    return 1
}

# 窗口调整
adjust_window() {
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    
    osascript <<'EOF'
    tell application "System Events"
        tell process "QuickQ For Mac"
            repeat 3 times
                if exists window 1 then
                    set position of window 1 to {0, 0}
                    set size of window 1 to {400, 300}
                    exit repeat
                else
                    delay 0.5
                end if
            end repeat
        end tell
    end tell
EOF
    echo "[$(date +"%T")] 窗口位置已校准"
    sleep 1
}

# 连接流程
connect_procedure() {
    # 显示窗口并激活
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 0.5
    
    # 调整窗口并点击连接
    adjust_window
    cliclick c:${DROP_DOWN_BUTTON_X},${DROP_DOWN_BUTTON_Y}
    echo "[$(date +"%T")] 已点击下拉菜单"
    sleep 1
    
    cliclick c:${CONNECT_BUTTON_X},${CONNECT_BUTTON_Y}
    echo "[$(date +"%T")] 已发起连接请求"
    sleep 15
    
    # 连接后检查状态
    check_vpn_connection
}

# 应用初始化
initialize_app() {
    echo "[$(date +"%T")] 执行初始化操作..."
    osascript -e 'tell application "System Events" to set visible of process "QuickQ For Mac" to true'
    osascript -e 'tell application "QuickQ For Mac" to activate'
    sleep 1
    
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已点击设置按钮"
    sleep 2
    
    connect_procedure
}

# 终止并重启应用
terminate_and_restart() {
    echo "[$(date +"%T")] 达到最大重试次数，重启应用..."
    pkill -9 -f "$APP_NAME" && echo "[$(date +"%T")] 已终止进程"
    sleep 2
    
    open "$APP_PATH"
    echo "[$(date +"%T")] 重新启动应用中..."
    sleep 10
    
    initialize_app
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
    if check_vpn_connection; then
        echo "[$(date +"%T")] ✅ 已连接"
        next_check_time=$(date -v +10M +"%T")  # 计算10分钟后的时间
        echo "[$(date +"%T")] ⏳ 下次检测时间: $next_check_time"
        
        # 每30秒检查程序是否运行
        for ((i=0; i<20; i++)); do  # 20次 × 30秒 = 10分钟
            if ! pgrep -f "$APP_NAME" &> /dev/null; then
                echo "[$(date +"%T")] ❌ 程序未运行，正在启动..."
                open "$APP_PATH"
                sleep 10
                initialize_app
            else
                echo "[$(date +"%T")] ✅ 程序运行正常（已连接）"
            fi
            sleep 30
        done
        
    else
        echo "[$(date +"%T")] ❌ 未连接，尝试重连... ($((retry_count+1))/$MAX_RETRY)"
        connect_procedure
        
        # 检查是否重连成功
        if ! check_vpn_connection; then
            ((retry_count++))
            
            if [ $retry_count -ge $MAX_RETRY ]; then
                terminate_and_restart
                retry_count=0
            fi
        fi
        
        sleep 30
    fi
done