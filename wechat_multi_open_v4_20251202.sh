#!/bin/bash

###############################################################################
# macOS 微信多开脚本
# 修复：https://github.com/LiJunYi2/WeChat-Split/issues/3 ，重启电脑后，分身网络问题
# 适用于微信 4.0 及以上版本
# 
# 功能：
# 1. 支持创建多个微信分身应用（2个、3个、4个...）
# 2. 自动修改 Bundle Identifier
# 3. 移除隔离属性（解决图标禁用问题）
# 4. 重新签名应用并配置网络权限
# 5. 启动指定的微信实例
# 6. 数据安全保护：重新创建应用不会丢失数据
# 7. 改进的数据删除功能
# 8. 修复网络连接问题
#
# 使用方法：
#   sudo bash wechat_multi_open_v4_20251202.sh [数量] [名字列表]
#   sudo bash wechat_multi_open_v4_20251202.sh 3      # 创建3个微信（原版+2个分身，默认名 WeChat2/WeChat3）
#   sudo bash wechat_multi_open_v4_20251202.sh 3 "工作,生活"  # 自定义分身显示名
#   sudo bash wechat_multi_open_v4_20251202.sh --names "微信-工作,微信-生活" # 自动推断数量
#   sudo bash wechat_multi_open_v4_20251202.sh        # 默认创建2个微信（原版+1个分身）
#   sudo bash wechat_multi_open_v4_20251202.sh clean  # 清理所有分身（保留数据）
#   sudo bash wechat_multi_open_v4_20251202.sh remove # 删除所有分身和数据
#
# 自定义名字说明：
# - 第二参数或 --names/-n 为逗号分隔的显示名列表，数量需等于 分身数(总数-1)
# - 默认名仍为 WeChat2/WeChat3...，传参后将覆盖 CFBundleDisplayName/CFBundleName 及 zh-Hans/zh-Hant/en 本地化
# - 修复 BUG：旧版仅改 Info.plist，中文系统下 Spotlight/Finder 仍显示“微信”，2.1 起同步修复 InfoPlist.strings
#
# 注意事项：
# - 需要 sudo 权限执行
# - 微信升级后需要重新运行此脚本
# - 重新运行不会丢失聊天数据
###############################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 配置变量
WECHAT_APP="/Applications/WeChat.app"
BASE_BUNDLE_ID="com.tencent.xinWeChat"
DATA_BASE_PATH="$HOME/Library/Containers"
SCRIPT_VERSION="2.1"
# 分身显示名列表（全局数组，索引0对应 WeChat2）
declare -a CLONE_DISPLAY_NAMES=()

# 打印带颜色的消息
print_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[步骤]${NC} $1"
}

print_data() {
    echo -e "${CYAN}[数据]${NC} $1"
}

print_success() {
    echo -e "${MAGENTA}[成功]${NC} $1"
}

# 显示使用帮助
show_help() {
    echo "使用方法："
    echo "  sudo bash $0 [数量] [名字列表]"
    echo "  sudo bash $0 [选项]"
    echo ""
    echo "命令："
    echo "  数字              - 创建指定数量的微信（包括原版），默认为 2"
    echo "  clean             - 清理所有分身应用（保留数据）"
    echo "  remove            - 删除所有分身应用和数据（危险操作）"
    echo "  fix               - 修复网络连接问题"
    echo "  help              - 显示此帮助信息"
    echo ""
    echo "选项："
    echo "  -n, --names \"名1,名2\" - 逗号分隔的自定义显示名（分身数=总数-1）"
    echo "  -c, --count 数字     - 等同于直接传数字，指定总数"
    echo ""
    echo "示例："
    echo "  sudo bash $0                          # 创建 2 个微信（WeChat + WeChat2）"
    echo "  sudo bash $0 3                        # 创建 3 个微信（WeChat2, WeChat3）"
    echo "  sudo bash $0 3 \"工作,生活\"           # 创建 3 个，显示名为 工作/生活"
    echo "  sudo bash $0 3 \"微信-工作,微信-生活\" # 同上，支持中文/英文任意"
    echo "  sudo bash $0 --names \"A,B,C\"        # 自动推断总数为 4（1+3）"
    echo "  sudo bash $0 4 -n \"A,B,C\"           # 显式指定总数 + 自定义名"
    echo "  sudo bash $0 clean                    # 清理所有分身应用"
    echo "  sudo bash $0 fix                      # 修复网络问题"
    echo ""
    echo "说明："
    echo "  未传名字时默认 WeChat2/3/...；传入数量少于分身数时剩余用默认值补齐"
    echo "  传入多于分身数时多余忽略并警告"
    echo ""
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 sudo 运行此脚本"
        echo ""
        show_help
        exit 1
    fi
}

# 检查微信是否已安装
check_wechat_installed() {
    if [ ! -d "$WECHAT_APP" ]; then
        print_error "未找到微信应用，请先安装微信"
        exit 1
    fi
    print_info "检测到微信应用: $WECHAT_APP"
    
    # 获取微信版本
    local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WECHAT_APP/Contents/Info.plist" 2>/dev/null || echo "未知")
    print_info "微信版本: $version"
}

# 检查并修复网络连接
check_and_fix_network() {
    print_step "检查网络连接..."
    
    # 检查网络连接
    if ping -c 1 -W 2 qq.com >/dev/null 2>&1; then
        print_info "网络连接正常"
    else
        print_warning "网络连接可能有问题，尝试修复..."
        
        # 清理 DNS 缓存
        sudo dscacheutil -flushcache 2>/dev/null || true
        sudo killall -HUP mDNSResponder 2>/dev/null || true
        
        # 重置网络接口
        local interface=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
        if [ ! -z "$interface" ]; then
            sudo ifconfig "$interface" down 2>/dev/null || true
            sleep 1
            sudo ifconfig "$interface" up 2>/dev/null || true
        fi
        
        print_info "网络修复完成"
    fi
}

# 解析命令行参数
parse_arguments() {
    MODE="create"
    TOTAL_COUNT=""
    CUSTOM_NAMES_RAW=""
    CLONE_DISPLAY_NAMES=()
    local COUNT_SET=false

    if [ $# -eq 0 ]; then
        TOTAL_COUNT=2
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                help|--help|-h)
                    show_help
                    exit 0
                    ;;
                clean)
                    MODE="clean"
                    shift
                    if [[ $# -gt 0 ]]; then print_warning "clean 模式忽略多余参数: $*"; fi
                    return
                    ;;
                remove)
                    MODE="remove"
                    shift
                    if [[ $# -gt 0 ]]; then print_warning "remove 模式忽略多余参数: $*"; fi
                    return
                    ;;
                fix)
                    MODE="fix"
                    shift
                    if [[ $# -gt 0 ]]; then print_warning "fix 模式忽略多余参数: $*"; fi
                    return
                    ;;
                -n|--names)
                    if [[ -z "$2" ]]; then print_error "--names 需要参数"; show_help; exit 1; fi
                    CUSTOM_NAMES_RAW="$2"
                    shift 2
                    ;;
                --names=*)
                    CUSTOM_NAMES_RAW="${1#*=}"
                    shift
                    ;;
                -c|--count)
                    if [[ -z "$2" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then print_error "--count 需要数字参数"; show_help; exit 1; fi
                    TOTAL_COUNT="$2"
                    COUNT_SET=true
                    shift 2
                    ;;
                --count=*)
                    TOTAL_COUNT="${1#*=}"
                    if ! [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]]; then print_error "--count 需要数字"; show_help; exit 1; fi
                    COUNT_SET=true
                    shift
                    ;;
                *)
                    if [[ "$1" =~ ^[0-9]+$ ]] && [ "$COUNT_SET" = false ] && [ -z "$TOTAL_COUNT" ]; then
                        TOTAL_COUNT="$1"
                        COUNT_SET=true
                        shift
                    elif [[ "$1" == *","* ]] || [[ ! "$1" =~ ^[0-9]+$ ]]; then
                        if [ -n "$CUSTOM_NAMES_RAW" ]; then
                            print_error "重复的自定义名字参数: $1"
                            show_help
                            exit 1
                        fi
                        CUSTOM_NAMES_RAW="$1"
                        shift
                    else
                        print_error "未知或多余参数: $1"
                        show_help
                        exit 1
                    fi
                    ;;
            esac
        done
    fi

    if [ "$MODE" != "create" ]; then
        return
    fi

    # 未指定数量时按名字数推断
    if [ -z "$TOTAL_COUNT" ]; then
        if [ -n "$CUSTOM_NAMES_RAW" ]; then
            local _tmp_count=$(echo "$CUSTOM_NAMES_RAW" | awk -F',' '{print NF}')
            TOTAL_COUNT=$((_tmp_count + 1))
            COUNT_SET=true
            print_info "未指定数量，按名字数自动推断总数为 $TOTAL_COUNT"
        else
            TOTAL_COUNT=2
        fi
    fi

    if ! [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]]; then
        print_error "数量参数必须是数字"
        show_help
        exit 1
    fi
    
    if [ "$TOTAL_COUNT" -lt 2 ]; then
        print_error "数量至少为 2（原版 + 1 个分身）"
        exit 1
    fi
    
    if [ "$TOTAL_COUNT" -gt 10 ]; then
        print_warning "创建过多微信实例可能会占用大量磁盘空间和内存"
        read -p "确定要创建 $TOTAL_COUNT 个微信吗？(y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    fi
    
    CLONE_COUNT=$((TOTAL_COUNT - 1))  # 需要创建的分身数量

    # 解析自定义名字为数组
    if [ -n "$CUSTOM_NAMES_RAW" ]; then
        CUSTOM_NAMES_RAW=$(echo "$CUSTOM_NAMES_RAW" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        IFS=',' read -ra RAW_NAMES <<< "$CUSTOM_NAMES_RAW"
        for name in "${RAW_NAMES[@]}"; do
            name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            name=$(echo "$name" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            if [ -n "$name" ]; then
                CLONE_DISPLAY_NAMES+=("$name")
            fi
        done
        local expected=$CLONE_COUNT
        local provided=${#CLONE_DISPLAY_NAMES[@]}
        if [ "$provided" -lt "$expected" ]; then
            print_warning "自定义名字数量($provided)少于分身数($expected)，剩余将使用默认名 WeChatX 补齐"
        elif [ "$provided" -gt "$expected" ]; then
            print_warning "自定义名字数量($provided)多于分身数($expected)，多余的将被忽略"
            CLONE_DISPLAY_NAMES=("${CLONE_DISPLAY_NAMES[@]:0:$expected}")
        fi
        print_info "自定义显示名: ${CLONE_DISPLAY_NAMES[*]:-(无，使用默认)}"
    fi
    
    if [ ${#CLONE_DISPLAY_NAMES[@]} -eq 0 ]; then
        print_info "将创建 $TOTAL_COUNT 个微信实例（原版 + $CLONE_COUNT 个分身），默认名 WeChat2...WeChat${TOTAL_COUNT}"
    else
        print_info "将创建 $TOTAL_COUNT 个微信实例（原版 + $CLONE_COUNT 个分身）"
    fi
}

# 检查数据文件夹是否存在
check_data_folders() {
    print_step "检查现有数据..."
    echo ""
    
    local has_data=false
    
    for i in $(seq 2 10); do
        local data_path="${DATA_BASE_PATH}/${BASE_BUNDLE_ID}${i}"
        if [ -d "$data_path" ]; then
            has_data=true
            local size=$(du -sh "$data_path" 2>/dev/null | cut -f1 || echo "未知")
            print_data "发现 WeChat${i} 的数据文件夹（大小: $size）"
        fi
    done
    
    if [ "$has_data" = true ]; then
        echo ""
        print_info "数据安全说明："
        echo "  • 删除应用程序不会删除数据文件夹"
        echo "  • 重新创建应用后，数据会自动关联"
        echo "  • 聊天记录、登录信息都会保留"
        echo "  • 数据存储位置: ~/Library/Containers/com.tencent.xinWeChatX/"
        echo ""
    else
        print_info "未发现现有数据，这是首次创建"
        echo ""
    fi
}

# 删除旧的微信分身（如果存在）
remove_old_wechat_clones() {
    print_step "检查并清理旧的应用程序..."
    
    local removed_count=0
    for i in $(seq 2 10); do
        local wechat_clone="/Applications/WeChat${i}.app"
        if [ -d "$wechat_clone" ]; then
            print_warning "删除旧的应用程序: WeChat${i}.app（数据文件夹会保留）"
            rm -rf "$wechat_clone"
            removed_count=$((removed_count + 1))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        print_info "已删除 $removed_count 个旧的应用程序"
    else
        print_info "未发现旧的应用程序"
    fi
    
    echo ""
}

# 删除微信分身数据（改进版）
remove_wechat_clone_data() {
    local bundle_id=$1
    local data_path="${DATA_BASE_PATH}/${bundle_id}"
    
    if [ -d "$data_path" ]; then
        print_info "正在删除 ${bundle_id} 的数据..."
        
        # 获取实际的用户名（非root）
        local actual_user=$(who am i | awk '{print $1}')
        
        # 方法1：先尝试正常删除
        rm -rf "$data_path" 2>/dev/null
        
        # 方法2：如果还存在，使用更强制的方法
        if [ -d "$data_path" ]; then
            print_warning "正常删除失败，尝试强制删除..."
            
            # 先终止可能正在使用该文件夹的进程
            pkill -f "$bundle_id" 2>/dev/null || true
            sleep 1
            
            # 移除扩展属性
            xattr -cr "$data_path" 2>/dev/null || true
            
            # 移除不可变标志
            chflags -R nouchg "$data_path" 2>/dev/null || true
            
            # 修改权限
            chmod -R 777 "$data_path" 2>/dev/null || true
            
            # 再次尝试删除
            rm -rf "$data_path" 2>/dev/null
        fi
        
        # 方法3：使用 Finder 的方式删除
        if [ -d "$data_path" ]; then
            print_warning "强制删除失败，尝试使用 Finder 方式..."
            
            # 使用 osascript 通过 Finder 删除
            osascript -e "tell application \"Finder\" to delete POSIX file \"$data_path\"" 2>/dev/null || true
            
            # 清空废纸篓
            osascript -e "tell application \"Finder\" to empty trash" 2>/dev/null || true
        fi
        
        # 最终检查
        if [ -d "$data_path" ]; then
            print_error "无法完全删除数据文件夹"
            print_warning "这可能是由于 .com.apple.containermanagerd.metadata.plist 文件的保护"
            echo ""
            print_info "请尝试以下方法手动删除："
            echo ""
            echo "  方法1：使用 Finder"
            echo "    1. 打开 Finder"
            echo "    2. 按 Cmd+Shift+G，输入: ~/Library/Containers/"
            echo "    3. 找到 ${bundle_id} 文件夹"
            echo "    4. 将其拖到废纸篓"
            echo "    5. 清空废纸篓"
            echo ""
            echo "  方法2：安全模式删除"
            echo "    1. 重启 Mac，按住 Shift 键进入安全模式"
            echo "    2. 在终端执行: sudo rm -rf $data_path"
            echo "    3. 重启回正常模式"
            echo ""
            echo "  方法3：关闭 SIP（不推荐）"
            echo "    1. 重启到恢复模式（Command+R）"
            echo "    2. 打开终端，执行: csrutil disable"
            echo "    3. 重启，删除文件夹"
            echo "    4. 再次进入恢复模式，执行: csrutil enable"
            echo ""
        else
            print_success "数据文件夹已成功删除"
        fi
    else
        print_info "数据文件夹不存在: ${bundle_id}"
    fi
}

# 创建单个微信分身（改进版，支持自定义显示名 + 修复本地化）
create_wechat_clone() {
    local index=$1
    local custom_name="$2"
    local wechat_clone="/Applications/WeChat${index}.app"
    local bundle_id="${BASE_BUNDLE_ID}${index}"
    local plist_file="${wechat_clone}/Contents/Info.plist"
    local exec_file="${wechat_clone}/Contents/MacOS/WeChat"
    local data_path="${DATA_BASE_PATH}/${bundle_id}"
    # 确定最终显示名：优先用传入的 $2，否则从全局数组取，否则默认 WeChat${index}
    local display_name="$custom_name"
    if [ -z "$display_name" ] && [ ${#CLONE_DISPLAY_NAMES[@]} -ge $((index-1)) ]; then
        local arr_idx=$((index-2))
        if [ -n "${CLONE_DISPLAY_NAMES[$arr_idx]}" ]; then
            display_name="${CLONE_DISPLAY_NAMES[$arr_idx]}"
        fi
    fi
    if [ -z "$display_name" ]; then
        display_name="WeChat${index}"
    fi
    
    print_step "创建第 $index 个微信分身 (显示名: $display_name)..."
    
    # 检查是否有现有数据
    if [ -d "$data_path" ]; then
        local size=$(du -sh "$data_path" 2>/dev/null | cut -f1 || echo "未知")
        print_data "  检测到现有数据（大小: $size），将自动关联"
    fi
    
    # 1. 复制应用
    print_info "  [1/9] 复制应用..."
    cp -R "$WECHAT_APP" "$wechat_clone"
    
    if [ ! -d "$wechat_clone" ]; then
        print_error "应用复制失败"
        return 1
    fi
    
    # 2. 移除所有扩展属性（解决图标禁用问题）
    print_info "  [2/9] 移除扩展属性..."
    xattr -cr "$wechat_clone" 2>/dev/null || true
    
    # 3. 修改 Bundle Identifier
    print_info "  [3/9] 修改 Bundle Identifier 为 $bundle_id"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist_file"
    
    # 4. 修改应用名称（避免冲突，支持自定义）
    print_info "  [4/9] 修改显示名称为 $display_name"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $display_name" "$plist_file" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$plist_file" 2>/dev/null || true
    
    # 4.1 修复本地化显示（解决 Spotlight/Finder 仍显示“微信”问题）
    print_info "  [5/9] 修复本地化显示..."
    for lang in zh-Hans zh-Hant en; do
        local strings_file="${wechat_clone}/Contents/Resources/${lang}.lproj/InfoPlist.strings"
        if [ -f "$strings_file" ]; then
            local tmp_utf8="/tmp/wechat_${index}_${lang}_utf8.txt"
            local tmp_utf8_new="/tmp/wechat_${index}_${lang}_new.txt"
            if iconv -f UTF-16 -t UTF-8 "$strings_file" > "$tmp_utf8" 2>/dev/null; then
                local esc_name=$(printf '%s' "$display_name" | sed 's/[&\/\\]/\\&/g; s/"/\\"/g')
                sed -e "s/\"CFBundleDisplayName\"[[:space:]]*=[[:space:]]*\".*\";/\"CFBundleDisplayName\" = \"$esc_name\";/" \
                    -e "s/\"CFBundleName\"[[:space:]]*=[[:space:]]*\".*\";/\"CFBundleName\" = \"$esc_name\";/" \
                    "$tmp_utf8" > "$tmp_utf8_new"
                if iconv -f UTF-8 -t UTF-16 "$tmp_utf8_new" > "$strings_file" 2>/dev/null; then
                    print_info "    已更新 $lang.lproj 显示名为: $display_name"
                else
                    print_warning "    $lang.lproj 转换回 UTF-16 失败，保留原文件"
                fi
                rm -f "$tmp_utf8" "$tmp_utf8_new"
            else
                print_warning "    无法读取 $lang.lproj/InfoPlist.strings，跳过"
            fi
        fi
    done
    
    # 5. 清理旧的代码签名
    print_info "  [6/9] 清理旧签名..."
    codesign --remove-signature "$wechat_clone" 2>/dev/null || true
    
    # 6. 创建 entitlements 文件（包含网络权限）
    print_info "  [7/9] 配置权限..."
    local entitlements_file="/tmp/wechat_entitlements_${index}.plist"
    cat > "$entitlements_file" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.personal-information.photos-library</key>
    <true/>
</dict>
</plist>
EOF
    
    # 7. 重新签名（使用 entitlements）
    print_info "  [8/9] 重新签名应用..."
    codesign --force --deep --sign - --entitlements "$entitlements_file" "$wechat_clone" 2>&1 | grep -v "replacing existing signature" || true
    
    # 清理临时文件
    rm -f "$entitlements_file"
    
    # 8. 设置正确的权限
    print_info "  [9/9] 设置权限..."
    chmod -R 755 "$wechat_clone"
    
    # 9. 注册到 Launch Services
    print_info "  注册应用..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$wechat_clone" 2>/dev/null || true
    
    print_success "WeChat${index}.app 创建成功 (显示名: $display_name)"
    
    # 显示数据关联状态
    if [ -d "$data_path" ]; then
        print_data "  → 已关联到数据文件夹: ${bundle_id}"
    else
        print_data "  → 首次启动，将创建新的数据文件夹"
    fi
    
    echo ""
    
    return 0
}

# 启动微信分身
launch_wechat_clone() {
    local index=$1
    local wechat_clone="/Applications/WeChat${index}.app"
    local exec_file="${wechat_clone}/Contents/MacOS/WeChat"
    
    if [ ! -d "$wechat_clone" ]; then
        print_warning "WeChat${index}.app 不存在，跳过启动"
        return 1
    fi
    
    print_info "启动 WeChat${index}..."
    
    # 先终止可能已经运行的实例
    pkill -f "WeChat${index}" 2>/dev/null || true
    sleep 1
    
    # 方法1：使用 open 命令（推荐）
    open -n "$wechat_clone" --args --disable-gpu-sandbox 2>/dev/null &
    
    # 检查是否启动成功
    sleep 2
    if ! pgrep -f "$exec_file" >/dev/null 2>&1; then
        print_warning "使用备用方式启动..."
        # 方法2：直接执行
        nohup "$exec_file" >/dev/null 2>&1 &
    fi
    
    return 0
}

# 创建所有微信分身
create_all_clones() {
    print_step "开始创建微信分身..."
    echo ""
    
    local success_count=0
    local fail_count=0
    
    for i in $(seq 2 $TOTAL_COUNT); do
        local idx=$((i-2))
        local dname="${CLONE_DISPLAY_NAMES[$idx]:-WeChat${i}}"
        if create_wechat_clone "$i" "$dname"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            print_error "WeChat${i}.app 创建失败"
            echo ""
        fi
    done
    
    print_info "创建完成: 成功 $success_count 个，失败 $fail_count 个"
    echo ""
    
    # 启动所有成功创建的分身
    print_step "启动微信分身..."
    echo ""
    
    for i in $(seq 2 $TOTAL_COUNT); do
        launch_wechat_clone $i
    done
    
    echo ""
}

# 清理所有分身（仅删除应用）
clean_all_clones() {
    print_step "清理所有微信分身应用..."
    echo ""
    
    local removed_count=0
    for i in $(seq 2 10); do
        local wechat_clone="/Applications/WeChat${i}.app"
        if [ -d "$wechat_clone" ]; then
            print_info "删除 WeChat${i}.app..."
            rm -rf "$wechat_clone"
            removed_count=$((removed_count + 1))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        print_success "已删除 $removed_count 个分身应用"
        print_info "数据文件夹已保留，下次创建时会自动关联"
    else
        print_info "没有找到需要清理的分身应用"
    fi
    
    echo ""
}

# 删除所有分身和数据
remove_all_completely() {
    print_warning "即将删除所有微信分身应用和数据！"
    echo ""
    read -p "这将永久删除所有聊天记录和登录信息，确定继续吗？(yes/N) " -r
    echo
    
    if [[ ! $REPLY == "yes" ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    print_step "删除所有微信分身和数据..."
    echo ""
    
    # 先删除应用
    clean_all_clones
    
    # 再删除数据
    print_step "删除数据文件夹..."
    for i in $(seq 2 10); do
        remove_wechat_clone_data "${BASE_BUNDLE_ID}${i}"
    done
    
    echo ""
    print_success "清理完成"
}

# 修复网络问题
fix_network_issues() {
    print_step "修复微信网络连接问题..."
    echo ""
    
    # 1. 检查并修复网络
    check_and_fix_network
    
    # 2. 重置防火墙规则
    print_info "重置防火墙规则..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --remove /Applications/WeChat.app 2>/dev/null || true
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Applications/WeChat.app 2>/dev/null || true
    
    for i in $(seq 2 10); do
        local wechat_clone="/Applications/WeChat${i}.app"
        if [ -d "$wechat_clone" ]; then
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --remove "$wechat_clone" 2>/dev/null || true
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$wechat_clone" 2>/dev/null || true
        fi
    done
    
    # 3. 重置 Launch Services
    print_info "重置应用注册..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -kill -r -domain local -domain system -domain user
    
    # 4. 重启 Dock
    killall Dock
    
    echo ""
    print_success "网络修复完成"
    print_info "请重新启动微信应用"
}

# 显示数据文件夹信息
show_data_info() {
    echo ""
    print_step "微信分身数据文件夹信息"
    echo ""
    
    echo "微信分身数据存储在以下位置（按 Bundle Identifier 区分）："
    echo ""
    
    local has_data=false
    for i in $(seq 2 $TOTAL_COUNT); do
        local idx=$((i-2))
        local dname="${CLONE_DISPLAY_NAMES[$idx]:-WeChat${i}}"
        local data_path="${DATA_BASE_PATH}/${BASE_BUNDLE_ID}${i}"
        if [ -d "$data_path" ]; then
            has_data=true
            local size=$(du -sh "$data_path" 2>/dev/null | cut -f1 || echo "未知")
            echo "  $((i-1)). WeChat${i}.app (显示名: $dname)"
            echo "     Bundle ID: ${BASE_BUNDLE_ID}${i}"
            echo "     数据路径: ~/Library/Containers/${BASE_BUNDLE_ID}${i}/"
            echo "     数据大小: $size"
            echo ""
        else
            echo "  $((i-1)). WeChat${i}.app (显示名: $dname)"
            echo "     Bundle ID: ${BASE_BUNDLE_ID}${i}"
            echo "     数据路径: ~/Library/Containers/${BASE_BUNDLE_ID}${i}/"
            echo "     数据大小: 尚未创建（首次登录后生成）"
            echo ""
        fi
    done
    
    if [ "$has_data" = false ] && [ "$TOTAL_COUNT" -gt 1 ]; then
        print_info "提示：首次登录后会自动创建数据文件夹"
    fi
}

# 显示结果摘要
show_summary() {
    echo ""
    echo "================================================"
    echo "     ✨ 创建完成！"
    echo "================================================"
    echo ""
    print_success "已创建的微信分身："
    echo ""
    
    local count=0
    for i in $(seq 2 $TOTAL_COUNT); do
        local idx=$((i-2))
        local dname="${CLONE_DISPLAY_NAMES[$idx]:-WeChat${i}}"
        local wechat_clone="/Applications/WeChat${i}.app"
        if [ -d "$wechat_clone" ]; then
            echo "  ✓ WeChat${i}.app (显示名: $dname)"
            count=$((count + 1))
        fi
    done
    
    if [ $count -eq 0 ]; then
        print_warning "没有成功创建的分身"
        return
    fi
    
    show_data_info
    
    echo ""
    print_info "重要说明："
    echo "  1. 所有微信分身已在后台启动"
    echo "  2. 可以在 Dock 或启动台中找到它们"
    echo "  3. 图标应该正常显示（无禁用标志）"
    echo "  4. 每个分身可以登录不同的账号"
    echo "  5. 微信升级后需要重新运行此脚本"
    echo "  6. 重新运行不会丢失数据（数据和应用是分离的）"
    echo ""
    
    print_info "常用操作："
    echo "  • 清理分身：sudo bash $0 clean"
    echo "  • 删除所有：sudo bash $0 remove"
    echo "  • 修复网络：sudo bash $0 fix"
    echo ""
    
    print_info "如需手动删除某个分身："
    echo "  • 删除应用：在应用程序文件夹中将 WeChatX.app 拖到废纸篓"
    echo "  • 删除数据：在 Finder 中前往 ~/Library/Containers/ 删除对应文件夹"
    echo ""
}

# 显示完成后的建议
show_post_install_tips() {
    echo ""
    echo "================================================"
    echo "     💡 使用建议"
    echo "================================================"
    echo ""
    
    print_info "为确保最佳体验，建议执行以下操作："
    echo ""
    echo "  1. 重启 Dock 和 Finder（立即生效）："
    echo "     killall Dock && killall Finder"
    echo ""
    echo "  2. 如果遇到网络问题："
    echo "     sudo bash $0 fix"
    echo ""
    echo "  3. 如果双击图标打开错误的微信："
    echo "     重启电脑或执行："
    echo "     /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
    echo ""
    echo "================================================"
    echo ""
}

# 主函数
main() {
    echo ""
    echo "================================================"
    echo "     macOS 微信多开自动化脚本 v${SCRIPT_VERSION}"
    echo "================================================"
    echo ""
    
    check_root
    
    # 解析参数
    parse_arguments "$@"
    
    # 根据模式执行不同操作
    case "$MODE" in
        clean)
            clean_all_clones
            ;;
        remove)
            remove_all_completely
            ;;
        fix)
            fix_network_issues
            ;;
        create)
            check_wechat_installed
            check_and_fix_network
            check_data_folders
            remove_old_wechat_clones
            create_all_clones
            show_summary
            show_post_install_tips
            ;;
        *)
            print_error "未知的操作模式"
            exit 1
            ;;
    esac
}

# 捕获错误
trap 'print_error "脚本执行出错，请检查错误信息"' ERR

# 执行主函数
main "$@"

# 正常退出
exit 0
