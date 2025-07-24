#!/bin/bash

# ===== 配置参数 =====
APP_NAME="QuickQ For Mac"
APP_PATH="/Applications/QuickQ For Mac.app"
MAX_RETRY=3
RESTART_INTERVAL=7200  # 2小时（秒）
APP_CHECK_INTERVAL=20  # 应用检测间隔（秒）
VPN_CHECK_INTERVAL=300 # VPN检测间隔（秒）

# 按钮坐标（根据实际设置调整）
SETTINGS_BUTTON_X=1869
SETTINGS_BUTTON_Y=165
DROP_DOWN_BUTTON_X=1720
DROP_DOWN_BUTTON_Y=430
CONNECT_BUTTON_X=1720
CONNECT_BUTTON_Y=260

# ===== 状态变量 =====
retry_count=0
is_fresh_start=true
last_restart_time=$(date +%s)
next_app_check_time=0
next_vpn_check_time=0

# ===== 日志函数 =====
log() {
    echo "[$(date +"%Y-%m-%d %T")] $1"
}

# ===== 专为Mac M系列优化的依赖安装 =====
install_dependencies() {
    log "🔍 检查Mac系统依赖..."
    local missing_deps=()

    # 检查基本命令
    for cmd in osascript curl pgrep pkill; do
        if ! command -v $cmd &>/dev/null; then
            missing_deps+=("$cmd")
            log "❌ 系统缺少命令: $cmd"
        fi
    done

    # 检查cliclick
    if ! command -v cliclick &>/dev/null || ! cliclick -h &>/dev/null; then
        missing_deps+=("cliclick")
        log "❌ cliclick未安装或损坏"
    fi

    if [ ${#missing_deps[@]} -eq 0 ]; then
        log "✅ 所有依赖已就绪"
        return 0
    fi

    log "🔄 开始安装缺失依赖..."
    
    # 安装Homebrew（如果缺失）
    if ! command -v brew &>/dev/null; then
        log "🍺 安装Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    # 通过Homebrew安装缺失组件
    for dep in "${missing_deps[@]}"; do
        if [ "$dep" == "cliclick" ]; then
            log "🖱️ 安装cliclick..."
            if ! brew install cliclick; then
                log "❌ cliclick安装失败，尝试直接下载..."
                sudo curl -L https://github.com/BlueM/cliclick/releases/download/5.0.1/cliclick -o /usr/local/bin/cliclick
                sudo chmod +x /usr/local/bin/cliclick
            fi
        else
            log "📦 通过brew安装$dep..."
            brew install $dep
        fi

        # 验证安装
        if ! command -v $dep &>/dev/null; then
            log "❌ $dep 安装失败，请手动处理"
            return 1
        fi
    done

    log "✅ 所有依赖安装完成"
    return 0
}

# ===== 窗口控制函数 =====
adjust_window() {
    log "🖥️ 调整应用窗口..."
    osascript <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        set position of window 1 to {1520, 0}
        set size of window 1 to {400, 300}
    end tell
end tell
EOF
    sleep 1
}

# ===== VPN检测函数 =====
check_vpn_connection() {
    log "🌐 检测VPN连接..."
    local success=false
    local test_urls=(
        "https://www.google.com/generate_204"
        "https://www.apple.com/library/test/success.html"
    )

    for url in "${test_urls[@]}"; do
        if curl --max-time 5 --silent --fail "$url" >/dev/null; then
            log "✅ 网络检测通过: $(echo "$url" | awk -F/ '{print $3}')"
            success=true
            break
        fi
    done

    if $success; then
        log "🟢 VPN连接正常"
        return 0
    else
        log "🔴 VPN连接失败"
        return 1
    fi
}

# ===== 连接流程函数 =====
connect_procedure() {
    log "🔌 开始连接流程..."
    
    # 激活应用
    osascript -e "tell application \"$APP_NAME\" to activate"
    sleep 1
    
    # 调整窗口
    adjust_window
    
    # 执行点击操作
    log "🖱️ 操作应用界面..."
    cliclick "c:$SETTINGS_BUTTON_X,$SETTINGS_BUTTON_Y" || return 1
    sleep 1
    cliclick "c:$DROP_DOWN_BUTTON_X,$DROP_DOWN_BUTTON_Y" || return 1
    sleep 1
    cliclick "c:$CONNECT_BUTTON_X,$CONNECT_BUTTON_Y" || return 1
    sleep 10
    
    # 验证连接
    if check_vpn_connection; then
        log "✅ 连接成功"
        retry_count=0
        is_fresh_start=false
        return 0
    else
        ((retry_count++))
        log "⚠️ 连接失败 (尝试 $retry_count/$MAX_RETRY)"
        return 1
    fi
}

# ===== 强制重启函数 =====
force_restart() {
    log "🔄 强制重启应用..."
    
    # 结束进程
    pkill -9 -f "$APP_NAME" && log "✅ 已终止进程" || log "⚠️ 进程终止失败"
    sleep 2
    
    # 重新启动
    if open "$APP_PATH"; then
        log "✅ 应用启动成功"
        sleep 10
        is_fresh_start=true
        retry_count=0
        last_restart_time=$(date +%s)
        return 0
    else
        log "❌ 应用启动失败"
        return 1
    fi
}

# ===== 主程序 =====
log "🚀 启动QuickQ自动化脚本 (专为Mac M优化)"
install_dependencies || exit 1

log "⏱️ 检测间隔: 应用${APP_CHECK_INTERVAL}秒 VPN${VPN_CHECK_INTERVAL}秒"

# 初始化计时器
next_app_check_time=$(($(date +%s) + 5))  # 5秒后首次检测
next_vpn_check_time=$(($(date +%s) + 10)) # 10秒后首次检测
next_restart_time=$(($(date +%s) + RESTART_INTERVAL))

while true; do
    current_time=$(date +%s)
    
    # 1. 定期重启检查
    if [ $current_time -ge $next_restart_time ]; then
        force_restart
        next_restart_time=$(($(date +%s) + RESTART_INTERVAL))
        next_app_check_time=$(($(date +%s) + 10))
        next_vpn_check_time=$(($(date +%s) + 20))
        continue
    fi
    
    # 2. 应用状态检测
    if [ $current_time -ge $next_app_check_time ]; then
        if ! pgrep -f "$APP_NAME" &>/dev/null; then
            log "❌ 应用未运行，正在启动..."
            if open "$APP_PATH"; then
                sleep 10
                connect_procedure || {
                    [ $retry_count -ge $MAX_RETRY ] && force_restart
                }
            fi
        fi
        next_app_check_time=$(($(date +%s) + APP_CHECK_INTERVAL))
    fi
    
    # 3. VPN状态检测
    if [ $current_time -ge $next_vpn_check_time ] && ! $is_fresh_start; then
        if ! check_vpn_connection; then
            log "🔴 VPN断开，尝试重新连接..."
            connect_procedure || {
                [ $retry_count -ge $MAX_RETRY ] && force_restart
            }
        fi
        next_vpn_check_time=$(($(date +%s) + VPN_CHECK_INTERVAL))
    fi
    
    # 计算等待时间
    sleep_time=$((next_app_check_time - current_time))
    [ $sleep_time -le 0 ] && sleep_time=1
    
    log "⏳ 状态: [应用检测: $((next_app_check_time - current_time))秒] [VPN检测: $((next_vpn_check_time - current_time))秒]"
    sleep $sleep_time
done
