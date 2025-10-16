#!/bin/bash

###############################################################################
# macOS 微信多开脚本 - 最终版
# 适用于微信 4.0 及以上版本
# 
# 功能：
# 1. 支持创建多个微信分身应用（2个、3个、4个...）
# 2. 自动修改 Bundle Identifier
# 3. 移除隔离属性（解决图标禁用问题）
# 4. 重新签名应用
# 5. 启动指定的微信实例
# 6. 数据安全保护：重新创建应用不会丢失数据
#
# 使用方法：
#   sudo bash wechat_multi_open_final.sh [数量]
#   sudo bash wechat_multi_open_final.sh 3      # 创建3个微信（原版+2个分身）
#   sudo bash wechat_multi_open_final.sh        # 默认创建2个微信（原版+1个分身）
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
NC='\033[0m' # No Color

# 配置变量
WECHAT_APP="/Applications/WeChat.app"
BASE_BUNDLE_ID="com.tencent.xinWeChat"
DATA_BASE_PATH="$HOME/Library/Containers"

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

# 显示使用帮助
show_help() {
    echo "使用方法："
    echo "  sudo bash $0 [数量]"
    echo ""
    echo "参数说明："
    echo "  数量    - 要创建的微信总数（包括原版），默认为 2"
    echo ""
    echo "示例："
    echo "  sudo bash $0        # 创建 2 个微信（原版 + 1 个分身）"
    echo "  sudo bash $0 3      # 创建 3 个微信（原版 + 2 个分身）"
    echo "  sudo bash $0 5      # 创建 5 个微信（原版 + 4 个分身）"
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
}

# 解析命令行参数
parse_arguments() {
    TOTAL_COUNT=${1:-2}  # 默认创建2个微信
    
    # 验证参数
    if ! [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]]; then
        print_error "参数必须是数字"
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
    
    print_info "将创建 $TOTAL_COUNT 个微信实例（原版 + $CLONE_COUNT 个分身）"
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
            local size=$(du -sh "$data_path" 2>/dev/null | cut -f1)
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

# 创建单个微信分身
create_wechat_clone() {
    local index=$1
    local wechat_clone="/Applications/WeChat${index}.app"
    local bundle_id="${BASE_BUNDLE_ID}${index}"
    local plist_file="${wechat_clone}/Contents/Info.plist"
    local exec_file="${wechat_clone}/Contents/MacOS/WeChat"
    local data_path="${DATA_BASE_PATH}/${bundle_id}"
    
    print_step "创建第 $index 个微信分身..."
    
    # 检查是否有现有数据
    if [ -d "$data_path" ]; then
        local size=$(du -sh "$data_path" 2>/dev/null | cut -f1)
        print_data "  检测到现有数据（大小: $size），将自动关联"
    fi
    
    # 1. 复制应用
    print_info "  [1/5] 复制应用..."
    cp -R "$WECHAT_APP" "$wechat_clone"
    
    if [ ! -d "$wechat_clone" ]; then
        print_error "应用复制失败"
        return 1
    fi
    
    # 2. 移除隔离属性（解决图标禁用问题）
    print_info "  [2/5] 移除隔离属性..."
    xattr -cr "$wechat_clone" 2>/dev/null || true
    
    # 验证隔离属性是否已移除
    if xattr "$wechat_clone" 2>/dev/null | grep -q "com.apple.quarantine"; then
        print_warning "  隔离属性可能未完全移除，但不影响使用"
    fi
    
    # 3. 修改 Bundle Identifier
    print_info "  [3/5] 修改 Bundle Identifier 为 $bundle_id"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist_file"
    
    # 验证修改
    local current_bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_file")
    if [ "$current_bundle_id" != "$bundle_id" ]; then
        print_error "Bundle Identifier 修改失败"
        return 1
    fi
    
    # 4. 重新签名
    print_info "  [4/5] 重新签名应用..."
    codesign --force --deep --sign - "$wechat_clone" 2>&1 | grep -v "replacing existing signature" || true
    
    if [ $? -ne 0 ] && [ ${PIPESTATUS[0]} -ne 0 ]; then
        print_error "应用签名失败"
        return 1
    fi
    
    # 5. 启动应用
    print_info "  [5/5] 启动微信实例..."
    nohup "$exec_file" >/dev/null 2>&1 &
    
    sleep 1
    
    print_info "✓ WeChat${index}.app 创建并启动成功"
    
    # 显示数据关联状态
    if [ -d "$data_path" ]; then
        print_data "  → 已关联到数据文件夹: ${bundle_id}"
    else
        print_data "  → 首次启动，将创建新的数据文件夹"
    fi
    
    echo ""
    
    return 0
}

# 创建所有微信分身
create_all_clones() {
    print_step "开始创建微信分身..."
    echo ""
    
    local success_count=0
    local fail_count=0
    
    for i in $(seq 2 $TOTAL_COUNT); do
        if create_wechat_clone $i; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            print_error "WeChat${i}.app 创建失败"
            echo ""
        fi
    done
    
    print_info "创建完成: 成功 $success_count 个，失败 $fail_count 个"
}

# 显示数据文件夹信息
show_data_info() {
    echo ""
    print_step "微信分身数据文件夹信息"
    echo ""
    
    echo "微信分身数据存储在以下位置（按 Bundle Identifier 区分）："
    echo ""
    
    # 只显示分身微信，不显示原版
    for i in $(seq 2 $TOTAL_COUNT); do
        local data_path="${DATA_BASE_PATH}/${BASE_BUNDLE_ID}${i}"
        if [ -d "$data_path" ]; then
            local size=$(du -sh "$data_path" 2>/dev/null | cut -f1)
            echo "  $((i-1)). WeChat${i}.app"
            echo "     Bundle ID: ${BASE_BUNDLE_ID}${i}"
            echo "     数据路径: ~/Library/Containers/${BASE_BUNDLE_ID}${i}/"
            echo "     数据大小: $size"
            echo ""
        else
            echo "  $((i-1)). WeChat${i}.app"
            echo "     Bundle ID: ${BASE_BUNDLE_ID}${i}"
            echo "     数据路径: ~/Library/Containers/${BASE_BUNDLE_ID}${i}/"
            echo "     数据大小: 尚未创建（首次登录后生成）"
            echo ""
        fi
    done
}

# 显示结果摘要
show_summary() {
    echo ""
    echo "================================================"
    echo "     创建完成！"
    echo "================================================"
    echo ""
    print_info "已创建的微信分身："
    echo ""
    
    for i in $(seq 2 $TOTAL_COUNT); do
        local wechat_clone="/Applications/WeChat${i}.app"
        if [ -d "$wechat_clone" ]; then
            echo "  $((i-1)). WeChat${i}.app"
        fi
    done
    
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
    
    print_info "如需删除某个分身："
    echo "  • 删除应用：在应用程序文件夹中将 WeChatX.app 拖到废纸篓"
    echo "  • 删除数据：手动删除 ~/Library/Containers/com.tencent.xinWeChatX/"
    echo ""
}

# 主函数
main() {
    echo ""
    echo "================================================"
    echo "     macOS 微信多开自动化脚本 - 最终版"
    echo "================================================"
    echo ""
    
    check_root
    parse_arguments "$@"
    check_wechat_installed
    check_data_folders
    remove_old_wechat_clones
    create_all_clones
    show_summary
}

# 显示重启提醒
show_reboot_reminder() {
    echo ""
    echo "================================================"
    echo "     ⚠️  重要提醒  ⚠️"
    echo "================================================"
    echo ""
    print_warning "为确保双击应用能正确打开对应的微信实例，请执行以下操作之一："
    echo ""
    echo "  方案 1：重启电脑（推荐）"
    echo "    sudo reboot"
    echo ""
    echo "  方案 2：重建 Launch Services 数据库"
    echo "    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Dock"
    echo ""
    print_info "说明："
    echo "  • 不执行上述操作，双击 WeChat2.app 可能会打开原版微信"
    echo "  • 重启电脑是最简单且无副作用的方案"
    echo "  • 重建 Launch Services 可能需要重新设置部分文件关联"
    echo ""
    echo "================================================"
    echo ""
}

# 执行主函数
main "$@"

# 显示重启提醒
show_reboot_reminder

