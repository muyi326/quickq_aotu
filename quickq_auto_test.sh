#!/bin/bash

# ===== 依赖检查与安装 =====
check_and_install_dependencies() {
    log "🔍 检查系统依赖..."
    local missing_deps=()
    
    # 检查必要的命令行工具
    for cmd in osascript curl pgrep pkill cliclick; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
            log "❌ 未找到依赖: $cmd"
        else
            log "✅ 已安装: $cmd"
        fi
    done
    
    # 如果有缺失的依赖
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "⚠️ 缺少必要依赖: ${missing_deps[*]}"
        log "🔄 尝试自动安装缺失依赖..."
        
        # 特殊处理 cliclick
        if [[ " ${missing_deps[@]} " =~ " cliclick " ]]; then
            install_cliclick
            # 检查是否安装成功
            if command -v cliclick &> /dev/null; then
                log "✅ cliclick 安装成功"
                missing_deps=("${missing_deps[@]/cliclick}")
            else
                log "❌ cliclick 安装失败"
            fi
        fi
        
        # 特殊处理 curl (极少数情况可能没有)
        if [[ " ${missing_deps[@]} " =~ " curl " ]]; then
            log "安装 curl..."
            if command -v brew &> /dev/null; then
                brew install curl
            elif command -v apt-get &> /dev/null; then
                sudo apt-get install -y curl
            elif command -v yum &> /dev/null; then
                sudo yum install -y curl
            else
                log "❌ 无法识别包管理器来安装curl"
            fi
            
            if command -v curl &> /dev/null; then
                log "✅ curl 安装成功"
                missing_deps=("${missing_deps[@]/curl}")
            else
                log "❌ curl 安装失败"
            fi
        fi
        
        # 如果还有缺失的依赖
        if [ ${#missing_deps[@]} -gt 0 ]; then
            log "❌ 以下依赖自动安装失败，请手动安装:"
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    "osascript") log "  - osascript: 这是macOS系统组件，通常应该已安装" ;;
                    "curl") log "  - curl: 请通过系统包管理器安装" ;;
                    "pgrep"|"pkill") log "  - $dep: 这是基本系统工具，通常应该已安装" ;;
                    "cliclick") 
                        log "  - cliclick: 请手动安装:"
                        log "     1. 下载: sudo curl -L https://www.bluem.net/files/cliclick/latest/cliclick -o /usr/local/bin/cliclick"
                        log "     2. 授权: sudo chmod +x /usr/local/bin/cliclick"
                        ;;
                    *) log "  - $dep: 未知依赖" ;;
                esac
            done
            exit 1
        fi
    fi
    
    log "✅ 所有依赖已满足"
}

install_cliclick() {
    log "尝试安装 cliclick..."
    
    # 方法1: 直接下载
    log "尝试直接下载安装..."
    if sudo curl -L https://www.bluem.net/files/cliclick/latest/cliclick -o /usr/local/bin/cliclick 2>/dev/null; then
        sudo chmod +x /usr/local/bin/cliclick
        return 0
    fi
    
    # 方法2: 通过Homebrew安装
    log "尝试通过Homebrew安装..."
    if ! command -v brew &>/dev/null; then
        log "Homebrew未安装，尝试安装Homebrew..."
        if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            log "✅ Homebrew安装成功"
            # 确保brew在PATH中
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        else
            log "❌ Homebrew安装失败"
            return 1
        fi
    fi
    
    if command -v brew &>/dev/null; then
        if brew install cliclick; then
            return 0
        fi
    fi
    
    return 1
}

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
is_fresh_start=true
last_restart_time=$(date +%s)
next_app_check_time=0
next_vpn_check_time=0

# ===== 带时间戳的输出函数 =====
log() {
    echo "[$(date +"%Y-%m-%d %T")] $1"
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
    if ! cliclick c:$SETTINGS_BUTTON_X,$SETTINGS_BUTTON_Y; then
        log "❌ 点击设置按钮失败"
        return 1
    fi
    sleep 1
    
    log "🖱️ 点击下拉菜单 ($DROP_DOWN_BUTTON_X,$DROP_DOWN_BUTTON_Y)..."
    if ! cliclick c:$DROP_DOWN_BUTTON_X,$DROP_DOWN_BUTTON_Y; then
        log "❌ 点击下拉菜单失败"
        return 1
    fi
    sleep 1
    
    log "🖱️ 点击连接按钮 ($CONNECT_BUTTON_X,$CONNECT_BUTTON_Y)..."
    if ! cliclick c:$CONNECT_BUTTON_X,$CONNECT_BUTTON_Y; then
        log "❌ 点击连接按钮失败"
        return 1
    fi
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
    pkill -9 -f "$APP_NAME" && log "✅ 进程已终止" || log "⚠️ 终止进程失败"
    sleep 2
    
    log "🚀 重新启动应用..."
    if open "$APP_PATH"; then
        log "✅ 应用启动成功"
    else
        log "❌ 应用启动失败"
        return 1
    fi
    sleep 10
    
    is_fresh_start=true
    retry_count=0
    last_restart_time=$(date +%s)
    
    if ! connect_procedure; then
        log "⚠️ 重启后连接失败"
        return 1
    fi
    
    log "🔄 应用重启流程完成"
    return 0
}

# ===== 主程序 =====
log "🚀 启动QuickQ自动化管理脚本..."

# 首先检查并安装依赖
check_and_install_dependencies

log "⏱️ 应用检测间隔: ${APP_CHECK_INTERVAL}秒 | VPN检测间隔: ${VPN_CHECK_INTERVAL}秒"

# 初始设置检查时间
next_app_check_time=$(($(date +%s) + APP_CHECK_INTERVAL))
next_vpn_check_time=$(($(date +%s) + VPN_CHECK_INTERVAL))
next_restart_time=$(($(date +%s) + RESTART_INTERVAL))

while true; do
    current_time=$(date +%s)
    
    # 1. 定期重启检查
    if [ $current_time -ge $next_restart_time ]; then
        if force_restart; then
            next_restart_time=$(($(date +%s) + RESTART_INTERVAL))
            next_app_check_time=$(($(date +%s) + APP_CHECK_INTERVAL))
            next_vpn_check_time=$(($(date +%s) + VPN_CHECK_INTERVAL))
            continue
        fi
    fi
    
    # 2. 首次启动特殊处理
    if $is_fresh_start; then
        if [ $retry_count -ge $MAX_RETRY ]; then
            log "⚠️ 首次启动达到最大重试次数，强制重启..."
            if force_restart; then
                continue
            fi
        else
            if ! check_vpn_connection; then
                log "🔄 首次启动VPN未连接，尝试连接 ($((retry_count+1))/$MAX_RETRY)..."
                connect_procedure
            else
                is_fresh_start=false
            fi
        fi
        sleep 5
        continue
    fi
    
    # 3. 常规应用状态检测
    if [ $current_time -ge $next_app_check_time ]; then
        log "🔍 开始应用运行状态检测..."
        next_app_check_time=$(($(date +%s) + APP_CHECK_INTERVAL))
        
        if ! pgrep -f "$APP_NAME" >/dev/null; then
            log "❌ 检测到应用未运行，正在启动..."
            if open "$APP_PATH"; then
                sleep 10
                is_fresh_start=true
                retry_count=0
                continue
            else
                log "❌ 应用启动失败"
            fi
        else
            log "✔️ 应用运行正常"
        fi
    fi
    
    # 4. VPN状态检测
    if [ $current_time -ge $next_vpn_check_time ]; then
        log "🌐 开始VPN连接状态检测..."
        next_vpn_check_time=$(($(date +%s) + VPN_CHECK_INTERVAL))
        
        if ! check_vpn_connection; then
            log "🏃 运行中检测到VPN断开，直接重启..."
            if force_restart; then
                continue
            fi
        else
            log "✅ VPN连接状态正常"
        fi
    fi
    
    # 5. 计算最小等待时间
    sleep_time=$((next_app_check_time - current_time))
    [ $sleep_time -le 0 ] && sleep_time=1
    
    vpn_sleep_time=$((next_vpn_check_time - current_time))
    [ $vpn_sleep_time -lt $sleep_time ] && [ $vpn_sleep_time -gt 0 ] && sleep_time=$vpn_sleep_time
    
    restart_sleep_time=$((next_restart_time - current_time))
    [ $restart_sleep_time -lt $sleep_time ] && [ $restart_sleep_time -gt 0 ] && sleep_time=$restart_sleep_time
    
    log "⏳ 状态: [下次应用检测: $((next_app_check_time - current_time))秒] [下次VPN检测: $((next_vpn_check_time - current_time))秒] [下次重启: $((next_restart_time - current_time))秒]"
    log "⏸️ 等待${sleep_time}秒后继续..."
    sleep $sleep_time
done
