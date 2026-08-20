#!/bin/bash
# ============================================
#  SH 云端卡密验证系统 v2.0 PRO - 全面加固版
#  无后端 | MD5+盐卡密 | 网络时间 | 反调试
#  设备绑定 | 远程开关 | 公告系统 | 自清理
# ============================================

# ===================== 配置区 =====================
CONFIG_URL="https://raw.githubusercontent.com/Lxr123456520/sh-verify/main/config.txt"
KEY_URL="https://raw.githubusercontent.com/Lxr123456520/sh-verify/main/key.txt"
VERSION="2.0.0"
AUTHOR="Lxr123456520"
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
SALT=""
SYS_STATUS=""
SYS_NOTICE=""

# ============================================
#  1. 初始化 Logo + 加载动画
# ============================================
init_logo() {
    clear
    echo -e "${BLUE}"
    echo "   ╔══════════════════════════════════════╗"
    echo "   ║      ____  _   _ _____   ____        ║"
    echo "   ║     / ___|| | | |_   _| / ___|       ║"
    echo "   ║     \\___ \\| |_| | | |   \\___ \\       ║"
    echo "   ║      ___) |  _  | | |    ___) |      ║"
    echo "   ║     |____/|_| |_| |_|   |____/       ║"
    echo "   ║                                        ║"
    echo "   ║      SH Cloud Verify  v2.0  PRO       ║"
    echo "   ╚══════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}  版本: ${VERSION}  |  作者: ${AUTHOR}${NC}"
    echo -e "${YELLOW}  ========================================${NC}"
    echo ""
    echo -ne "${BLUE}[初始化]${NC} 正在启动系统 "
    for i in {1..3}; do echo -n "."; sleep 0.3; done
    echo -e " ${GREEN}OK${NC}"
}

# ============================================
#  2. 反调试检测
# ============================================
anti_debug() {
    if ps aux 2>/dev/null | grep -E "strace|ltrace|gdb|radare2" | grep -v grep &>/dev/null; then
        echo -e "${RED}[安全]${NC} 检测到调试工具，程序终止"
        exit 1
    fi
}

# ============================================
#  3. 系统依赖校验
# ============================================
check_system() {
    echo -e "${BLUE}[系统校验]${NC} 正在检查运行环境..."
    for cmd in curl md5sum base64; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}[错误]${NC} 未安装 $cmd，执行: apt install -y coreutils curl"
            exit 1
        fi
    done
    if ! curl -s --connect-timeout 5 https://www.baidu.com &>/dev/null; then
        echo -e "${RED}[错误]${NC} 网络连接失败"
        exit 1
    fi
    echo -e "${GREEN}[系统校验]${NC} 环境检查通过 ✓"
    sleep 0.5
}

# ============================================
#  4. 获取网络时间（防改本地时间）
# ============================================
get_network_time() {
    for host in "https://www.baidu.com" "https://www.bing.com" "https://github.com"; do
        local sdate=$(curl -sI --connect-timeout 3 "$host" 2>/dev/null | grep -i "^date:" | head -1 | cut -d' ' -f2-)
        if [ -n "$sdate" ]; then
            local ts=$(date -d "$sdate" +%s 2>/dev/null)
            if [ -n "$ts" ] && [ "$ts" -gt 1700000000 ] 2>/dev/null; then
                echo "$ts"; return
            fi
        fi
    done
    date +%s
}

# ============================================
#  5. 生成设备码（MAC+CPU+磁盘+主机名）
# ============================================
get_device_code() {
    local mac cpu_id disk_id host_id
    if command -v ip &>/dev/null; then
        mac=$(ip link show 2>/dev/null | grep -oP '(?<=link/ether )[a-f0-9:]+' | head -1)
    elif command -v ifconfig &>/dev/null; then
        mac=$(ifconfig 2>/dev/null | grep -oP '(?<=ether )[a-f0-9:]+' | head -1)
    fi
    [ -f /proc/cpuinfo ] && cpu_id=$(grep -m1 "model name" /proc/cpuinfo | awk -F: '{print $2}' | tr -d ' ')
    command -v blkid &>/dev/null && disk_id=$(blkid 2>/dev/null | head -1 | grep -oP 'UUID="\K[^"]+')
    host_id=$(hostname)
    echo -n "${mac}|${cpu_id}|${disk_id}|${host_id}" | md5sum | awk '{print $1}'
}

# ============================================
#  6. 加载远程配置（含盐值）
# ============================================
load_config() {
    echo -e "${BLUE}[加载配置]${NC} 正在连接云端..."
    local config_data=$(curl -sL --connect-timeout 10 "$CONFIG_URL")
    if [ -z "$config_data" ]; then
        echo -e "${RED}[错误]${NC} 云端配置加载失败"; exit 1
    fi
    SYS_STATUS=$(echo "$config_data" | grep -i "^status=" | head -1 | cut -d'=' -f2 | tr -d '\r ')
    SYS_NOTICE=$(echo "$config_data" | grep -i "^notice=" | head -1 | cut -d'=' -f2- | tr -d '\r')
    SALT=$(echo "$config_data" | grep -i "^salt=" | head -1 | cut -d'=' -f2- | tr -d '\r ')
    if [ "$SYS_STATUS" != "on" ]; then
        echo -e "${RED}[系统关闭]${NC} 脚本已被作者关闭，请稍后再试"; exit 1
    fi
    if [ -z "$SALT" ]; then
        echo -e "${RED}[错误]${NC} 配置缺失盐值，验证系统无法启动"; exit 1
    fi
    echo -e "${GREEN}[加载配置]${NC} 云端连接成功 ✓"
    sleep 0.5
}

# ============================================
#  7. 卡密验证（MD5+盐，不存明文）
# ============================================
verify_key() {
    echo ""
    read -p "  请输入卡密: " USER_KEY
    [ -z "$USER_KEY" ] && { echo -e "${RED}[错误]${NC} 卡密不能为空"; exit 1; }
    echo -e "${BLUE}[验证中]${NC} 正在校验卡密..."

    local key_data=$(curl -sL --connect-timeout 10 "$KEY_URL")
    [ -z "$key_data" ] && { echo -e "${RED}[错误]${NC} 卡密数据加载失败"; exit 1; }

    # 计算 MD5(用户输入+盐)
    local user_hash=$(echo -n "${USER_KEY}${SALT}" | md5sum | awk '{print $1}')
    local match_line=$(echo "$key_data" | grep -F "$user_hash" | head -1)
    [ -z "$match_line" ] && { echo -e "${RED}[验证失败]${NC} 卡密无效或不存在"; exit 1; }

    local stored_hash=$(echo "$match_line" | cut -d'|' -f1)
    local bound_device=$(echo "$match_line" | cut -d'|' -f2)
    local expire_time=$(echo "$match_line" | cut -d'|' -f3)
    [ "$stored_hash" != "$user_hash" ] && { echo -e "${RED}[验证失败]${NC} 卡密无效"; exit 1; }

    local current_device=$(get_device_code)

    # ---- 设备绑定 ----
    if [ "$bound_device" = "未绑定" ] || [ -z "$bound_device" ]; then
        echo -e "${YELLOW}[设备绑定]${NC} 首次使用，正在绑定设备..."
        echo -e "${GREEN}[设备绑定]${NC} 设备绑定成功 ✓"
        echo ""
        echo -e "${CYAN}  ╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}  ║   请将以下设备码发给作者完成绑定     ║${NC}"
        echo -e "${CYAN}  ║                                        ║${NC}"
        echo -e "${CYAN}  ║   ${current_device}   ║${NC}"
        echo -e "${CYAN}  ╚══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}[提示]${NC} 绑定后该卡密仅限本设备使用"
        echo -e "${YELLOW}[提示]${NC} 请联系作者完成绑定后重新运行脚本"
        exit 0
    else
        if [ "$bound_device" != "$current_device" ]; then
            echo -e "${RED}[验证失败]${NC} 该卡密已绑定其他设备，一机一码"
            echo -e "${YELLOW}[提示]${NC} 如需更换设备请联系作者"; exit 1
        fi
    fi

    # ---- 过期校验（网络时间）----
    local current_time=$(get_network_time)
    if [ -n "$expire_time" ] && [ "$expire_time" != "永久" ]; then
        if ! [[ "$expire_time" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}[错误]${NC} 卡密过期时间格式错误"; exit 1
        fi
        if [ "$current_time" -gt "$expire_time" ]; then
            echo -e "${RED}[验证失败]${NC} 卡密已过期"
            echo -e "${YELLOW}[提示]${NC} 过期时间: $(date -d @$expire_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo未知)"
            exit 1
        fi
        local remain_sec=$((expire_time - current_time))
        local remain_days=$((remain_sec / 86400))
        local remain_hours=$(( (remain_sec % 86400) / 3600 ))
        echo -e "${GREEN}[有效期]${NC} 剩余 ${remain_days}天 ${remain_hours}小时"
    else
        echo -e "${GREEN}[有效期]${NC} 永久授权"
    fi

    # ---- 验证通过 ----
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ✅ 卡密验证通过 ✅            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    [ -n "$SYS_NOTICE" ] && { echo ""; echo -e "${YELLOW}[公告]${NC} $SYS_NOTICE"; }
    echo ""
    echo -e "${BLUE}正在进入主程序...${NC}"
    sleep 2
    main_program
}

# ============================================
#  8. 主程序（验证通过后执行）
# ============================================
main_program() {
    clear
    init_logo
    echo -e "${GREEN}欢迎使用，验证已通过！${NC}"
    echo ""
    echo "  这里是你的主程序逻辑"
    echo "  验证通过后的所有业务代码写在这里"
    echo ""
    while true; do
        echo "  1. 功能一"
        echo "  2. 功能二"
        echo "  3. 查看当前设备码"
        echo "  0. 退出"
        echo ""
        read -p "  请选择: " choice
        case $choice in
            1) echo "执行功能一" ;;
            2) echo "执行功能二" ;;
            3) echo "当前设备码: $(get_device_code)" ;;
            0) echo "再见！"; exit 0 ;;
            *) echo "无效选择" ;;
        esac
        echo ""
    done
}

# ============================================
#  9. 退出清理
# ============================================
cleanup() { rm -f /tmp/.sh_verify_* 2>/dev/null; }
trap cleanup EXIT

# ============================================
#  主流程
# ============================================
init_logo
anti_debug
check_system
load_config
verify_key
