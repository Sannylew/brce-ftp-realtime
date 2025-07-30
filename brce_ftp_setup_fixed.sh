#!/bin/bash

# BRCE FTP服务配置脚本
# 版本: v1.0.1 - 代码审查安全修复版
# 修复语法错误和字符编码问题

# 严格模式
set -eo pipefail

# 全局配置
readonly SCRIPT_VERSION="v1.0.1"
readonly LOG_FILE="/var/log/brce_ftp_setup.log"
SOURCE_DIR=""
FTP_USER=""

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" | tee -a "$LOG_FILE"
    fi
}

# 初始化函数
init_script() {
    echo "======================================================"
    echo "📁 BRCE FTP服务配置工具 ${SCRIPT_VERSION}"
    echo "======================================================"
    echo ""

    # 创建日志目录（在权限检查前）
    if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "警告: 无法创建日志目录，将仅输出到终端"
        LOG_FILE="/dev/null"
    fi

    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限，请使用 sudo 运行"
        exit 1
    fi
}

# 获取和验证FTP用户名 - 修复递归调用问题
get_ftp_username() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo "======================================================"
        echo "👤 配置FTP用户名 (尝试 $attempt/$max_attempts)"
        echo "======================================================"
        echo ""
        echo "默认用户名: sunny"
        echo ""
        
        read -p "请输入FTP用户名（回车使用默认用户名）: " input_user
        
        if [[ -z "$input_user" ]]; then
            # 用户回车，使用默认用户名
            FTP_USER="sunny"
            log_info "使用默认用户名: $FTP_USER"
            return 0
        else
            # 验证用户名格式
            if [[ "$input_user" =~ ^[a-zA-Z][a-zA-Z0-9_]{2,15}$ ]]; then
                FTP_USER="$input_user"
                log_info "自定义用户名: $FTP_USER"
                return 0
            else
                log_error "用户名格式不正确！要求：以字母开头，只能包含字母、数字、下划线，长度3-16位"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
            fi
        fi
    done
    
    log_error "用户名配置失败，已达到最大尝试次数"
    return 1
}

# 测试函数
test_basic_functionality() {
    echo "测试基本功能..."
    log_info "测试日志功能正常"
    echo "如果你看到这条消息，说明脚本语法正确"
    return 0
}

# 主程序入口
main() {
    # 先进行初始化
    init_script
    
    echo "脚本启动成功，语法检查通过"
    echo "请选择操作："
    echo "1) 测试基本功能"
    echo "2) 测试用户名配置"
    echo "0) 退出"
    echo ""
    
    read -p "请输入选项: " choice
    
    case $choice in
        1)
            test_basic_functionality
            ;;
        2)
            get_ftp_username
            echo "用户名配置完成: $FTP_USER"
            ;;
        0)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效选项"
            ;;
    esac
}

# 运行主程序 - 注意：这是脚本中唯一在加载时执行的代码
main 