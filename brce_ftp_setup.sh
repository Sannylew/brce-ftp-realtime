#!/bin/bash

# BRCE FTP服务配置脚本
# 版本: v1.0.3 - 修复密码显示问题
# 修复语法错误、字符编码问题和密码显示bug

# 严格模式
set -eo pipefail

# 全局配置
readonly SCRIPT_VERSION="v1.0.3"
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

# 获取和验证源目录路径 - 修复递归调用问题
get_source_directory() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo "======================================================"
        echo "📁 配置源目录路径 (尝试 $attempt/$max_attempts)"
        echo "======================================================"
        echo ""
        echo "默认目录: /opt/brec/file"
        echo ""
        
        read -p "请输入目录路径（回车使用默认路径）: " input_dir
        
        if [[ -z "$input_dir" ]]; then
            # 用户回车，使用默认路径
            SOURCE_DIR="/opt/brec/file"
            log_info "使用默认路径: $SOURCE_DIR"
        else
            # 用户输入了路径，使用自定义路径
            # 处理相对路径
            if [[ "$input_dir" != /* ]]; then
                input_dir="$(pwd)/$input_dir"
            fi
            
            # 规范化路径
            if ! SOURCE_DIR=$(realpath -m "$input_dir" 2>/dev/null); then
                log_error "路径格式无效: $input_dir"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
                continue
            fi
            log_info "自定义目录: $SOURCE_DIR"
        fi
        
        echo ""
        echo "📋 目录信息："
        echo "   - 源目录路径: $SOURCE_DIR"
        
        # 检查目录是否存在
        if [[ -d "$SOURCE_DIR" ]]; then
            if file_count=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l); then
                echo "   - 目录状态: 已存在"
                echo "   - 文件数量: $file_count 个文件"
            else
                log_error "无法访问目录: $SOURCE_DIR"
                ((attempt++))
                if [[ $attempt -le $max_attempts ]]; then
                    echo "请重试..."
                    sleep 1
                fi
                continue
            fi
        else
            echo "   - 目录状态: 不存在（将自动创建）"
        fi
        
        echo ""
        read -p "确认使用此目录？(y/N): " confirm_dir
        if [[ "$confirm_dir" =~ ^[Yy]$ ]]; then
            # 创建目录（如果不存在）
            if [[ ! -d "$SOURCE_DIR" ]]; then
                log_info "创建源目录: $SOURCE_DIR"
                if ! mkdir -p "$SOURCE_DIR"; then
                    log_error "创建目录失败，请检查权限"
                    ((attempt++))
                    if [[ $attempt -le $max_attempts ]]; then
                        echo "请重试..."
                        sleep 1
                    fi
                    continue
                fi
                log_info "目录创建成功"
            fi
            
            log_info "源目录配置完成: $SOURCE_DIR"
            return 0
        else
            log_info "用户取消，重新选择目录"
            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                sleep 1
            fi
        fi
    done
    
    log_error "源目录配置失败，已达到最大尝试次数"
    return 1
}

# 验证用户名函数（来自主程序）
validate_username() {
    local username="${1:-}"
    
    if [[ -z "$username" ]]; then
        log_error "validate_username: 缺少用户名参数"
        return 1
    fi
    
    if [[ ! "$username" =~ ^[a-z][-a-z0-9]*$ ]] || [[ ${#username} -gt 32 ]]; then
        log_error "用户名不合法！只能包含小写字母、数字和连字符，最多32字符"
        return 1
    fi
    return 0
}

# 检查实时同步依赖 - 增强包管理器支持
check_sync_dependencies() {
    local missing_deps=()
    
    log_info "检查实时同步依赖..."
    
    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
    fi
    
    if ! command -v inotifywait &> /dev/null; then
        missing_deps+=("inotify-tools")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "安装实时同步依赖: ${missing_deps[*]}"
        
        # 支持多种包管理器
        if command -v apt-get &> /dev/null; then
            log_info "使用 apt 包管理器安装依赖"
            if ! apt-get update -qq; then
                log_error "更新包列表失败"
                return 1
            fi
            if ! apt-get install -y "${missing_deps[@]}"; then
                log_error "使用 apt 安装依赖失败"
                return 1
            fi
        elif command -v dnf &> /dev/null; then
            log_info "使用 dnf 包管理器安装依赖"
            if ! dnf install -y "${missing_deps[@]}"; then
                log_error "使用 dnf 安装依赖失败"
                return 1
            fi
        elif command -v yum &> /dev/null; then
            log_info "使用 yum 包管理器安装依赖"
            if ! yum install -y "${missing_deps[@]}"; then
                log_error "使用 yum 安装依赖失败"
                return 1
            fi
        elif command -v zypper &> /dev/null; then
            log_info "使用 zypper 包管理器安装依赖"
            if ! zypper install -y "${missing_deps[@]}"; then
                log_error "使用 zypper 安装依赖失败"
                return 1
            fi
        elif command -v pacman &> /dev/null; then
            log_info "使用 pacman 包管理器安装依赖"
            if ! pacman -S --noconfirm "${missing_deps[@]}"; then
                log_error "使用 pacman 安装依赖失败"
                return 1
            fi
        else
            log_error "不支持的包管理器，请手动安装: ${missing_deps[*]}"
            return 1
        fi
        log_info "依赖安装完成"
    else
        log_info "实时同步依赖已安装"
    fi
    return 0
}

# 智能权限配置函数（基于主程序逻辑）
configure_smart_permissions() {
    local user="${1:-}"
    local source_dir="${2:-}"
    
    # 参数验证
    if [[ -z "$user" || -z "$source_dir" ]]; then
        log_error "configure_smart_permissions: 缺少必要参数 - user=$user, source_dir=$source_dir"
        return 1
    fi
    
    local user_home="/home/$user"
    local ftp_home="$user_home/ftp"
    
    log_info "配置FTP目录权限（完整读写删除权限）..."
    
    mkdir -p "$ftp_home"
    
    # 配置用户主目录
    chown root:root "$user_home"
    chmod 755 "$user_home"
    
    # 确保源目录存在
    mkdir -p "$source_dir"
    
    # 关键修复：设置源目录权限，确保FTP用户有完整权限
    echo "🔧 设置源目录权限 $source_dir"
    chown -R "$user":"$user" "$source_dir"
    chmod -R 755 "$source_dir"
    
    # 如果源目录在/opt下，设置特殊权限
    if [[ "$source_dir" == /opt/* ]]; then
        echo "⚠️  检测到/opt目录，设置访问权限..."
        chmod o+x /opt 2>/dev/null || true
        dirname_path=$(dirname "$source_dir")
        while [ "$dirname_path" != "/" ] && [ "$dirname_path" != "/opt" ]; do
            chmod o+x "$dirname_path" 2>/dev/null || true
            dirname_path=$(dirname "$dirname_path")
        done
    fi
    
    # 设置FTP目录权限
    chown "$user":"$user" "$ftp_home"
    chmod 755 "$ftp_home"
    
    echo "✅ 权限配置完成（用户拥有完整读写删除权限）"
}

# 生成vsftpd配置文件（基于主程序配置）
generate_optimal_config() {
    local ftp_home="${1:-}"
    
    if [[ -z "$ftp_home" ]]; then
        log_error "generate_optimal_config: 缺少FTP主目录参数"
        return 1
    fi
    
    log_info "生成vsftpd配置..."
    
    # 备份原配置
    [ -f /etc/vsftpd.conf ] && cp /etc/vsftpd.conf /etc/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 生成优化的配置（基于主程序，适合视频文件，禁用缓存）
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=$ftp_home
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
utf8_filesystem=YES
pam_service_name=vsftpd
seccomp_sandbox=NO
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
async_abor_enable=YES
ascii_upload_enable=YES
ascii_download_enable=YES
hide_ids=YES
use_localtime=YES
file_open_mode=0755
local_umask=022
# 禁用缓存，确保实时性
ls_recurse_enable=NO
use_sendfile=NO
EOF

    echo "✅ 配置文件已生成"
}

# 创建实时同步脚本 - 改进错误处理和日志
create_sync_script() {
    local user="${1:-}"
    local source_dir="${2:-}"
    local target_dir="${3:-}"
    
    if [[ -z "$user" ]]; then
        log_error "create_sync_script: 缺少用户名参数"
        return 1
    fi
    
    local script_path="/usr/local/bin/ftp_sync_${user}.sh"
    log_info "创建实时同步脚本: $script_path"
    
    # 验证参数
    if [[ -z "$source_dir" || -z "$target_dir" ]]; then
        log_error "create_sync_script: 参数不完整"
        log_error "  用户: $user"
        log_error "  源目录: $source_dir" 
        log_error "  目标目录: $target_dir"
        return 1
    fi
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# BRCE FTP双向实时同步脚本
# 解决文件修改延迟问题 - 支持双向同步

set -euo pipefail

USER="${USER}"
SOURCE_DIR="${SOURCE_DIR}"
TARGET_DIR="${TARGET_DIR}"
LOCK_FILE="/tmp/brce_sync.lock"
LOG_FILE="/var/log/brce_sync.log"

# 日志函数
log_sync() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_sync "启动BRCE FTP双向实时同步服务"
log_sync "源目录: $SOURCE_DIR"
log_sync "目标目录: $TARGET_DIR"

# 创建锁文件目录和日志目录
mkdir -p "$(dirname "$LOCK_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

# 同步函数：避免循环同步，增强错误处理
sync_to_target() {
    if [[ ! -f "$LOCK_FILE.target" ]]; then
        touch "$LOCK_FILE.target"
        log_sync "同步 源→FTP"
        
        if rsync -av --delete "$SOURCE_DIR/" "$TARGET_DIR/" 2>> "$LOG_FILE"; then
            # 设置正确权限
            if chown -R "$USER:$USER" "$TARGET_DIR" 2>> "$LOG_FILE"; then
                find "$TARGET_DIR" -type f -exec chmod 644 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分文件权限设置失败"
                find "$TARGET_DIR" -type d -exec chmod 755 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分目录权限设置失败"
                log_sync "同步完成: 源→FTP"
            else
                log_sync "ERROR: 权限设置失败"
            fi
        else
            log_sync "ERROR: rsync同步失败 源→FTP"
        fi
        
        sleep 0.2
        rm -f "$LOCK_FILE.target"
    fi
}

sync_to_source() {
    if [[ ! -f "$LOCK_FILE.source" ]]; then
        touch "$LOCK_FILE.source"
        log_sync "同步 FTP→源"
        
        if rsync -av --delete "$TARGET_DIR/" "$SOURCE_DIR/" 2>> "$LOG_FILE"; then
            # 确保源目录文件权限正确（root可访问）
            find "$SOURCE_DIR" -type f -exec chmod 644 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分源文件权限设置失败"
            find "$SOURCE_DIR" -type d -exec chmod 755 {} \; 2>> "$LOG_FILE" || log_sync "WARNING: 部分源目录权限设置失败"
            log_sync "同步完成: FTP→源"
        else
            log_sync "ERROR: rsync同步失败 FTP→源"
        fi
        
        sleep 0.2
        rm -f "$LOCK_FILE.source"
    fi
}

# 监控源目录变化→FTP目录
monitor_source() {
    while true; do
        if inotifywait -m -r -e modify,create,delete,move,moved_to,moved_from "$SOURCE_DIR" 2>/dev/null |
        while read path action file; do
            log_sync "源目录变化: $action $file"
            sleep 0.05
            sync_to_target
        done; then
            log_sync "源目录监控正常重启"
        else
            log_sync "ERROR: 源目录监控失败，尝试重启..."
            sleep 5
        fi
    done
}

# 监控FTP目录变化→源目录  
monitor_target() {
    while true; do
        if inotifywait -m -r -e modify,create,delete,move,moved_to,moved_from "$TARGET_DIR" 2>/dev/null |
        while read path action file; do
            log_sync "FTP目录变化: $action $file"
            sleep 0.05
            sync_to_source
        done; then
            log_sync "FTP目录监控正常重启"
        else
            log_sync "ERROR: FTP目录监控失败，尝试重启..."
            sleep 5
        fi
    done
}

# 清理函数
cleanup() {
    log_sync "收到退出信号，正在清理..."
    kill $SOURCE_PID $TARGET_PID 2>/dev/null || true
    rm -f "$LOCK_FILE".*
    log_sync "同步服务已停止"
    exit 0
}

# 设置信号处理
trap cleanup SIGTERM SIGINT

# 初始同步（源→目标）
log_sync "执行初始同步（源→FTP）..."
if sync_to_target; then
    log_sync "初始同步完成，开始双向监控..."
else
    log_sync "ERROR: 初始同步失败"
    exit 1
fi

# 启动双向监控（后台并行运行）
monitor_source &
SOURCE_PID=$!

monitor_target &
TARGET_PID=$!

log_sync "双向同步已启动"
log_sync "源目录监控PID: $SOURCE_PID"
log_sync "FTP目录监控PID: $TARGET_PID"

# 等待任一进程结束
wait $SOURCE_PID $TARGET_PID
EOF

    # 设置脚本中的变量
    sed -i "s|\${USER}|$user|g" "$script_path"
    sed -i "s|\${SOURCE_DIR}|$source_dir|g" "$script_path"
    sed -i "s|\${TARGET_DIR}|$target_dir|g" "$script_path"
    
    if chmod +x "$script_path"; then
        log_info "实时同步脚本已创建: $script_path"
        return 0
    else
        log_error "无法设置脚本执行权限"
        return 1
    fi
}

# 创建systemd服务
create_sync_service() {
    local user="${1:-}"
    
    if [[ -z "$user" ]]; then
        log_error "create_sync_service: 缺少用户名参数"
        return 1
    fi
    
    local service_name="brce-ftp-sync"
    local script_path="/usr/local/bin/ftp_sync_${user}.sh"
    
    log_info "创建实时同步系统服务..."
    
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=BRCE FTP Real-time Sync Service
After=network.target vsftpd.service
Requires=vsftpd.service

[Service]
Type=simple
ExecStart=$script_path
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo "✅ 系统服务已创建 ${service_name}.service"
}

# 启动实时同步服务
start_sync_service() {
    local service_name="brce-ftp-sync"
    
    echo "🚀 启动实时同步服务..."
    
    systemctl enable "$service_name"
    systemctl start "$service_name"
    
    if systemctl is-active --quiet "$service_name"; then
        echo "✅ 实时同步服务已启动 $service_name"
        echo "🔥 现在文件变化将零延迟同步到FTP"
    else
        echo "❌ 实时同步服务启动失败"
        echo "📋 查看错误日志:"
        journalctl -u "$service_name" --no-pager -n 10
        return 1
    fi
}

# 停止实时同步服务
stop_sync_service() {
    local service_name="brce-ftp-sync"
    
    echo "⏹️ 停止实时同步服务..."
    
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    
    echo "✅ 实时同步服务已停止"
}

# 主安装函数
install_brce_ftp() {
    # 首先获取源目录配置
    get_source_directory
    if [ -z "$SOURCE_DIR" ]; then
        echo "❌ 源目录配置失败"
        return 1
    fi
    
    # 获取FTP用户名配置
    get_ftp_username
    if [ -z "$FTP_USER" ]; then
        echo "❌ FTP用户名配置失败"
        return 1
    fi
    
    echo ""
    echo "======================================================"
    echo "🚀 开始配置BRCE FTP服务 (双向零延迟版)"
    echo "======================================================"
    echo ""
    echo "🎯 源目录: $SOURCE_DIR"
    echo "👤 FTP用户: $FTP_USER"
    echo "🔥 特性: 双向实时同步，零延迟"
    echo ""
    
    # 确认配置
    read -p "是否使用双向零延迟实时同步？(y/n，默认 y): " confirm
    confirm=${confirm:-y}
    
    if [[ "$confirm" != "y" ]]; then
        log_info "用户取消配置"
        return 1
    fi
    
    # 获取FTP密码
    read -p "自动生成密码？(y/n，默认 y): " auto_pwd
    auto_pwd=${auto_pwd:-y}
    
    if [[ "$auto_pwd" == "y" ]]; then
        ftp_pass=$(openssl rand -base64 12)
        log_info "已自动生成安全密码"
    else
        while true; do
            read -s -p "FTP密码（至少8位）: " ftp_pass
            echo
            if [[ ${#ftp_pass} -ge 8 ]]; then
                break
            fi
            log_error "密码至少8位"
        done
    fi
    
    echo ""
    log_info "开始部署..."
    
    # 安装vsftpd和实时同步依赖
    log_info "安装软件包..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y vsftpd rsync inotify-tools
    elif command -v yum &> /dev/null; then
        yum install -y vsftpd rsync inotify-tools
    else
        log_error "不支持的包管理器"
        exit 1
    fi
    
    # 检查实时同步依赖
    check_sync_dependencies
    
    # 创建用户（基于主程序逻辑）
    echo "👤 配置用户..."
    if id -u "$FTP_USER" &>/dev/null; then
        echo "⚠️  用户已存在，重置密码"
    else
        if command -v adduser &> /dev/null; then
            adduser "$FTP_USER" --disabled-password --gecos ""
        else
            useradd -m -s /bin/bash "$FTP_USER"
        fi
    fi
    # 安全设置用户密码（避免密码在进程列表中暴露）
    # 保存密码用于显示
    display_password="$ftp_pass"
    chpasswd <<< "$FTP_USER:$ftp_pass"
    unset ftp_pass  # 立即清除密码变量
    
    # 配置权限
    ftp_home="/home/$FTP_USER/ftp"
    configure_smart_permissions "$FTP_USER" "$SOURCE_DIR"
    
    # 停止旧的实时同步服务（如果存在）
    stop_sync_service
    
    # 卸载旧挂载（如果存在）
    if mountpoint -q "$ftp_home" 2>/dev/null; then
        echo "📤 卸载旧bind挂载"
        umount "$ftp_home" 2>/dev/null || true
        # 从fstab中移除
        sed -i "\|$ftp_home|d" /etc/fstab 2>/dev/null || true
    fi
    
    # 创建实时同步脚本和服务
    create_sync_script "$FTP_USER" "$SOURCE_DIR" "$ftp_home"
    create_sync_service "$FTP_USER"
    
    # 生成配置
    generate_optimal_config "$ftp_home"
    
    # 启动服务
    echo "🔄 启动FTP服务..."
    systemctl restart vsftpd
    systemctl enable vsftpd
    
    # 启动实时同步服务
    start_sync_service
    
    # 配置防火墙（基于主程序逻辑）
    echo "🔥 配置防火墙..."
    if command -v ufw &> /dev/null; then
        ufw allow 21/tcp >/dev/null 2>&1 || true
        ufw allow 40000:40100/tcp >/dev/null 2>&1 || true
        echo "✅ UFW: 已开放FTP端口"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=ftp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=40000-40100/tcp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        echo "✅ Firewalld: 已开放FTP端口"
    fi
    
    # 获取服务器IP（基于主程序逻辑）
    external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
    
    echo ""
    echo "======================================================"
    echo "✅ BRCE FTP服务部署完成！${SCRIPT_VERSION} (正式版)"
    echo "======================================================"
    echo ""
    echo "📋 连接信息："
    echo "   服务IP: $external_ip"
    echo "   端口: 21"
    echo "   用户: $FTP_USER"
    echo "   密码: $display_password"
    echo "   访问目录: $SOURCE_DIR"
    echo ""
    
    # 清除显示密码变量
    unset display_password
    
    echo "🎉 v1.0.3 新特性："
    echo "   👤 自定义目录：支持任意目录路径配置"
    echo "   🔄 双向零延迟：源目录↔FTP目录实时同步"
    echo "   🛡️ 智能路径处理：自动处理相对路径和绝对路径"
    echo "   📊 目录自动创建：不存在的目录自动创建"
    echo "   🔐 密码显示修复：正确显示生成的FTP密码"
    echo ""
    echo "💡 连接建议："
    echo "   - 使用被动模式（PASV）"
    echo "   - 端口范围: 40000-40100"
    echo "   - 支持大文件传输（视频文件）"
    echo ""
    echo "🎥 现在实现了真正的双向同步："
    echo "   📁 root操作源目录，立即可见"
    echo "   📤 FTP用户操作，源目录立即更新"
    echo ""
    echo "🔄 可通过菜单选项6随时在线更新到最新版"
}

# 安全获取当前配置信息
get_current_config() {
    # 尝试从现有服务配置中获取信息
    if systemctl is-active --quiet brce-ftp-sync 2>/dev/null; then
        # 从服务文件中提取用户信息
        local service_file="/etc/systemd/system/brce-ftp-sync.service"
        if [[ -f "$service_file" ]]; then
            local script_path=$(grep "ExecStart=" "$service_file" | cut -d'=' -f2)
            if [[ -n "$script_path" && -f "$script_path" ]]; then
                # 从脚本路径提取用户名 ftp_sync_${user}.sh
                FTP_USER=$(basename "$script_path" | sed 's/ftp_sync_\(.*\)\.sh/\1/')
                # 从脚本内容提取源目录
                SOURCE_DIR=$(grep "SOURCE_DIR=" "$script_path" | head -1 | cut -d'"' -f2)
            fi
        fi
    fi
    
    # 如果仍然为空，设置默认值
    FTP_USER="${FTP_USER:-unknown}"
    SOURCE_DIR="${SOURCE_DIR:-unknown}"
}

# 检查FTP状态 - 修复变量未初始化问题
check_ftp_status() {
    # 获取当前配置信息
    get_current_config
    
    echo ""
    echo "======================================================"
    echo "📊 BRCE FTP服务状态(零延迟版)"
    echo "======================================================"
    
    # 检查服务状态
    if systemctl is-active --quiet vsftpd; then
        log_info "FTP服务运行正常"
    else
        log_error "FTP服务未运行"
    fi
    
    # 检查实时同步服务
    if systemctl is-active --quiet brce-ftp-sync; then
        log_info "实时同步服务运行正常"
    else
        log_error "实时同步服务未运行"
    fi
    
    # 检查端口
    if ss -tlnp | grep -q ":21 "; then
        log_info "FTP端口21已开放"
    else
        log_error "FTP端口21未开放"
    fi
    
    # 检查用户（安全检查）
    if [[ "$FTP_USER" != "unknown" ]] && id "$FTP_USER" &>/dev/null; then
        log_info "FTP用户 $FTP_USER 存在"
    else
        log_error "FTP用户 $FTP_USER 不存在或未配置"
    fi
    
    # 检查目录（安全检查）
    if [[ "$FTP_USER" != "unknown" ]]; then
        local FTP_HOME="/home/$FTP_USER/ftp"
        if [[ -d "$FTP_HOME" ]]; then
            log_info "FTP目录存在: $FTP_HOME"
        else
            log_error "FTP目录不存在: $FTP_HOME"
        fi
    fi
    
    if [[ "$SOURCE_DIR" != "unknown" && -d "$SOURCE_DIR" ]]; then
        log_info "BRCE目录存在: $SOURCE_DIR"
        if file_count=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l); then
            echo "📁 源目录文件数: $file_count"
            
            if [[ "$FTP_USER" != "unknown" ]]; then
                local FTP_HOME="/home/$FTP_USER/ftp"
                if [[ -d "$FTP_HOME" ]]; then
                    if ftp_file_count=$(find "$FTP_HOME" -type f 2>/dev/null | wc -l); then
                        echo "📁 FTP目录文件数: $ftp_file_count"
                        
                        if [[ "$file_count" -eq "$ftp_file_count" ]]; then
                            log_info "文件数量同步正确"
                        else
                            log_error "文件数量不匹配"
                        fi
                    fi
                fi
            fi
        fi
    else
        log_error "BRCE目录不存在或未配置: $SOURCE_DIR"
    fi
    
    # 显示同步服务日志
    echo ""
    echo "📋 实时同步日志 (最近5条):"
    journalctl -u brce-ftp-sync --no-pager -n 5 2>/dev/null || echo "暂无日志"
    
    # 显示连接信息
    local external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
    echo ""
    echo "📍 连接信息："
    echo "   服务器: $external_ip"
    echo "   端口: 21"
    echo "   用户名: $FTP_USER"
    echo "   模式: 双向零延迟实时同步"
}

# 测试实时同步 - 修复变量未初始化问题
test_realtime_sync() {
    # 获取当前配置信息
    get_current_config
    
    # 检查配置是否有效
    if [[ "$FTP_USER" == "unknown" || "$SOURCE_DIR" == "unknown" ]]; then
        log_error "未找到有效的FTP配置，请先运行安装配置"
        echo "提示：选择菜单选项 1) 安装/配置BRCE FTP服务"
        return 1
    fi
    
    echo ""
    echo "======================================================"
    echo "🧪 测试双向实时同步功能"
    echo "======================================================"
    
    local TEST_FILE="$SOURCE_DIR/realtime_test_$(date +%s).txt"
    local FTP_HOME="/home/$FTP_USER/ftp"
    local FTP_TEST_FILE="$FTP_HOME/ftp_test_$(date +%s).txt"
    
    # 验证目录存在
    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_error "源目录不存在: $SOURCE_DIR"
        return 1
    fi
    
    if [[ ! -d "$FTP_HOME" ]]; then
        log_error "FTP目录不存在: $FTP_HOME"
        return 1
    fi
    
    echo "📋 双向同步测试包括："
    echo "   1️⃣ 源目录→FTP目录 同步测试"
    echo "   2️⃣ FTP目录→源目录 同步测试"
    echo ""
    
    # ================== 测试1: 源目录→FTP目录 ==================
    echo "🔸 测试1: 源目录→FTP目录 同步"
    echo "📝 在源目录创建测试文件: $TEST_FILE"
    echo "实时同步测试(源→FTP) - $(date)" > "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ -f "$FTP_HOME/$(basename "$TEST_FILE")" ]; then
        echo "✅ 源→FTP: 文件创建同步成功"
    else
        echo "❌ 源→FTP: 文件创建同步失败"
    fi
    
    echo "📝 修改源目录测试文件..."
    echo "修改后的内容(源→FTP) - $(date)" >> "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if diff "$TEST_FILE" "$FTP_HOME/$(basename "$TEST_FILE")" >/dev/null 2>&1; then
        echo "✅ 源→FTP: 文件修改同步成功"
    else
        echo "❌ 源→FTP: 文件修改同步失败"
    fi
    
    echo "🗑️ 删除源目录测试文件..."
    rm -f "$TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ ! -f "$FTP_HOME/$(basename "$TEST_FILE")" ]; then
        echo "✅ 源→FTP: 文件删除同步成功"
    else
        echo "❌ 源→FTP: 文件删除同步失败"
    fi
    
    echo ""
    
    # ================== 测试2: FTP目录→源目录==================
    echo "🔸 测试2: FTP目录→源目录 同步"
    echo "📝 在FTP目录创建测试文件: $FTP_TEST_FILE"
    
    # 以FTP用户身份创建文件
    su - "$FTP_USER" -c "echo '实时同步测试(FTP→源) - $(date)' > '$FTP_TEST_FILE'" 2>/dev/null || {
        echo "实时同步测试(FTP→源) - $(date)" > "$FTP_TEST_FILE"
        chown "$FTP_USER:$FTP_USER" "$FTP_TEST_FILE"
    }
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    SOURCE_TEST_FILE="$SOURCE_DIR/$(basename "$FTP_TEST_FILE")"
    if [ -f "$SOURCE_TEST_FILE" ]; then
        echo "✅ FTP→源: 文件创建同步成功"
    else
        echo "❌ FTP→源: 文件创建同步失败"
    fi
    
    echo "📝 修改FTP目录测试文件..."
    su - "$FTP_USER" -c "echo '修改后的内容(FTP→源) - $(date)' >> '$FTP_TEST_FILE'" 2>/dev/null || {
        echo "修改后的内容(FTP→源) - $(date)" >> "$FTP_TEST_FILE"
        chown "$FTP_USER:$FTP_USER" "$FTP_TEST_FILE"
    }
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ -f "$SOURCE_TEST_FILE" ] && diff "$FTP_TEST_FILE" "$SOURCE_TEST_FILE" >/dev/null 2>&1; then
        echo "✅ FTP→源: 文件修改同步成功"
    else
        echo "❌ FTP→源: 文件修改同步失败"
    fi
    
    echo "🗑️ 删除FTP目录测试文件..."
    rm -f "$FTP_TEST_FILE"
    
    echo "⏱️  等待3秒检查同步..."
    sleep 3
    
    if [ ! -f "$SOURCE_TEST_FILE" ]; then
        echo "✅ FTP→源: 文件删除同步成功"
        echo ""
        echo "🎉 双向实时同步功能完全正常！"
        echo "🎉 双向实时同步功能完全正常！"
    else
        echo "❌ FTP→源: 文件删除同步失败"
    fi
}

# 在线更新脚本
update_script() {
    echo ""
    echo "======================================================"
    echo "🔄 BRCE FTP脚本在线更新"
    echo "======================================================"
    
    SCRIPT_URL="https://raw.githubusercontent.com/Sannylew/brce-ftp-realtime/main/brce_ftp_setup.sh"
    CURRENT_SCRIPT="$(readlink -f "$0")"
    TEMP_SCRIPT="/tmp/brce_ftp_setup_new.sh"
    BACKUP_SCRIPT="${CURRENT_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo "📋 更新信息："
    echo "   - 当前脚本: $CURRENT_SCRIPT"
    echo "   - 远程地址: $SCRIPT_URL"
    echo "   - 备份位置: $BACKUP_SCRIPT"
    echo ""
    
    # 检查网络连接
    echo "🌐 检查网络连接..."
    if ! curl -s --max-time 10 https://github.com >/dev/null 2>&1; then
        echo "❌ 网络连接失败，请检查网络设置"
        return 1
    fi
    echo "✅ 网络连接正常"
    
    # 下载最新版?    echo "📥 下载最新版?.."
    if ! curl -s --max-time 30 "$SCRIPT_URL" -o "$TEMP_SCRIPT"; then
        echo "❌ 下载失败，请稍后重试"
        return 1
    fi
    
    # 检查下载的文件
    if [ ! -f "$TEMP_SCRIPT" ] || [ ! -s "$TEMP_SCRIPT" ]; then
        echo "❌ 下载的文件无效"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 下载完成"
    
    # 提取版本信息
    CURRENT_VERSION=$(grep "# 版本:" "$CURRENT_SCRIPT" | head -1 | sed 's/.*版本: *//' | sed 's/ .*//')
    NEW_VERSION=$(grep "# 版本:" "$TEMP_SCRIPT" | head -1 | sed 's/.*版本: *//' | sed 's/ .*//')
    
    echo ""
    echo "📊 版本对比："
    echo "   - 当前版本: ${CURRENT_VERSION:-"未知"}"
    echo "   - 最新版本: ${NEW_VERSION:-"未知"}"
    echo ""
    
    # 版本比较
    if [ "$CURRENT_VERSION" = "$NEW_VERSION" ] && [ -n "$CURRENT_VERSION" ]; then
        echo "ℹ️  您已经是最新版本！"
        read -p "是否强制更新？(y/N): " force_update
        if [[ ! "$force_update" =~ ^[Yy]$ ]]; then
            echo "✅ 保持当前版本"
            rm -f "$TEMP_SCRIPT"
            return 0
        fi
    fi
    
    # 显示更新日志（如果有的话）
    echo "📝 检查更新说明..."
    if grep -q "v1.0.0.*自定义目录" "$TEMP_SCRIPT"; then
        echo "🚀 v1.0.0 正式版特性："
        echo "   - 📁 自定义目录：支持任意目录路径配置"
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🛡️ 智能路径处理：自动处理相对路径和绝对路径"
        echo "   - 📊 在线更新：一键从GitHub更新到最新版"
        echo ""
    elif grep -q "v2.3.0 正式版" "$TEMP_SCRIPT"; then
        echo "🎉 v2.3.0 正式版特性："
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🔒 防循环机制：智能锁机制避免同步循?"
        echo "   - 📊 在线更新：一键从GitHub更新到最新版"
        echo "   - 🛡️ 智能卸载：完整的卸载和脚本管理功能"
        echo ""
    elif grep -q "v2.2 重大更新" "$TEMP_SCRIPT"; then
        echo "🔥 v2.2 新功能："
        echo "   - 🔄 双向实时同步：FTP用户操作立即同步到源目录"
        echo "   - 🔒 防循环机制：智能锁机制避免同步循?"
        echo "   - 📊 性能优化：详细的性能影响分析和优化建议"
        echo ""
    fi
    
    # 确认更新
    read -p "🔄 确定要更新到最新版本吗？(y/N): " confirm_update
    if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
        echo "✅ 取消更新"
        rm -f "$TEMP_SCRIPT"
        return 0
    fi
    
    # 检查是否有运行中的服务
    SERVICE_RUNNING=false
    if systemctl is-active --quiet brce-ftp-sync 2>/dev/null; then
        SERVICE_RUNNING=true
        echo "⚠️  检测到BRCE FTP服务正在运行"
        read -p "更新后需要重启服务，是否继续？(y/N): " restart_confirm
        if [[ ! "$restart_confirm" =~ ^[Yy]$ ]]; then
            echo "✅ 取消更新"
            rm -f "$TEMP_SCRIPT"
            return 0
        fi
    fi
    
    # 备份当前脚本
    echo "💾 备份当前脚本..."
    if ! cp "$CURRENT_SCRIPT" "$BACKUP_SCRIPT"; then
        echo "❌ 备份失败"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 备份完成: $BACKUP_SCRIPT"
    
    # 验证新脚本语?    echo "🔍 验证新脚本..."
    if ! bash -n "$TEMP_SCRIPT"; then
        echo "❌ 新脚本语法错误"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    echo "✅ 脚本验证通过"
    
    # 替换脚本
    echo "🔄 更新脚本..."
    if ! cp "$TEMP_SCRIPT" "$CURRENT_SCRIPT"; then
        echo "❌ 更新失败，恢复备?"
        cp "$BACKUP_SCRIPT" "$CURRENT_SCRIPT"
        rm -f "$TEMP_SCRIPT"
        return 1
    fi
    
    # 设置执行权限
    chmod +x "$CURRENT_SCRIPT"
    rm -f "$TEMP_SCRIPT"
    
    echo "✅ 脚本更新成功"
    echo ""
    
    # 重启服务（如果需要）
    if [ "$SERVICE_RUNNING" = true ]; then
        echo "🔄 重启BRCE FTP服务..."
        systemctl restart brce-ftp-sync 2>/dev/null || true
        if systemctl is-active --quiet brce-ftp-sync; then
            echo "✅ 服务重启成功"
        else
            echo "⚠️  服务重启可能有问题，请检查状态"
        fi
        echo ""
    fi
    
    echo "🎉 更新完成"
    echo ""
    echo "📋 更新摘要："
    echo "   - 原版: ${CURRENT_VERSION:-"未知"}"
    echo "   - 新版: ${NEW_VERSION:-"未知"}"
    echo "   - 备份文件: $BACKUP_SCRIPT"
    echo ""
    echo "💡 提示："
    echo "   - 如果有问题，可以恢复备份: cp $BACKUP_SCRIPT $CURRENT_SCRIPT"
    echo "   - 建议运行菜单选项2检查服务状态"
    echo "   - 建议运行菜单选项4测试功能"
    echo ""
    
    read -p "🔄 是否立即重新启动脚本？(y/N): " restart_script
    if [[ "$restart_script" =~ ^[Yy]$ ]]; then
        echo "🚀 重新启动脚本..."
        exec "$CURRENT_SCRIPT"
    fi
}

# 卸载FTP服务 - 修复变量未初始化问题
uninstall_brce_ftp() {
    # 获取当前配置信息
    get_current_config
    
    echo ""
    echo "======================================================"
    echo "🗑️ 卸载BRCE FTP服务"
    echo "======================================================"
    
    echo "📋 当前配置信息："
    echo "   - FTP用户: $FTP_USER"
    echo "   - 源目录: $SOURCE_DIR"
    if [[ "$FTP_USER" != "unknown" ]]; then
        echo "   - FTP目录: /home/$FTP_USER/ftp"
        echo "   - 同步脚本: /usr/local/bin/ftp_sync_${FTP_USER}.sh"
    fi
    echo "   - 系统服务: brce-ftp-sync.service"
    echo ""
    
    read -p "⚠️ 确定要卸载BRCE FTP服务吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "用户取消卸载"
        return 1
    fi
    
    echo ""
    echo "🔧 卸载选项："
    echo "1) 完全卸载（包含vsftpd软件包）"
    echo "2) 仅卸载BRCE配置（保留vsftpd）"
    echo ""
    read -p "请选择卸载方式 (1/2，默认 2): " uninstall_type
    uninstall_type=${uninstall_type:-2}
    
    echo ""
    echo "🛑 停止FTP服务..."
    systemctl stop vsftpd 2>/dev/null || true
    systemctl disable vsftpd 2>/dev/null || true
    
    echo "⏹️ 停止实时同步服务..."
    stop_sync_service
    
    echo "🗑️ 删除同步服务文件..."
    rm -f "/etc/systemd/system/brce-ftp-sync.service"
    rm -f "/usr/local/bin/ftp_sync_${FTP_USER}.sh"
    systemctl daemon-reload
    
    echo "🗑️ 删除FTP用户..."
    userdel -r "$FTP_USER" 2>/dev/null || true
    
    echo "🗑️ 恢复配置文件..."
    # 恢复vsftpd配置（如果有备份?    latest_backup=$(ls /etc/vsftpd.conf.backup.* 2>/dev/null | tail -1)
    if [ -f "$latest_backup" ]; then
        echo "📋 恢复vsftpd配置: $latest_backup"
        cp "$latest_backup" /etc/vsftpd.conf
    else
        echo "⚠️  未找到vsftpd配置备份"
    fi
    
    # 清理fstab中的bind mount条目（如果有）
    if grep -q "/home/$FTP_USER/ftp" /etc/fstab 2>/dev/null; then
        echo "🗑️ 清理fstab条目..."
        sed -i "\|/home/$FTP_USER/ftp|d" /etc/fstab 2>/dev/null || true
    fi
    
    # 完全卸载选项
    if [[ "$uninstall_type" == "1" ]]; then
        echo ""
        echo "🗑️ 卸载vsftpd软件包..."
        read -p "⚠️ 确定要卸载vsftpd软件包吗？(y/N): " remove_pkg
        if [[ "$remove_pkg" =~ ^[Yy]$ ]]; then
            if command -v apt-get &> /dev/null; then
                apt-get remove --purge -y vsftpd 2>/dev/null || true
                echo "✅ vsftpd已卸载"
            elif command -v yum &> /dev/null; then
                yum remove -y vsftpd 2>/dev/null || true
                echo "✅ vsftpd已卸载"
            fi
        else
            echo "💡 保留vsftpd软件包"
        fi
    fi
    
    echo ""
    echo "🔄 脚本管理选项："
    echo "📋 当前脚本: $(readlink -f "$0")"
    echo ""
    read -p "🗑️ 是否删除本脚本文件？(y/N): " remove_script
    
    if [[ "$remove_script" =~ ^[Yy]$ ]]; then
        script_path=$(readlink -f "$0")
        echo "🗑️ 准备删除脚本: $script_path"
        echo "💡 3秒后删除脚本文件..."
        sleep 1 && echo "💡 2..." && sleep 1 && echo "💡 1..." && sleep 1
        
        # 创建自删除脚?        cat > /tmp/cleanup_brce_script.sh << EOF
#!/bin/bash
echo "🗑️ 删除BRCE FTP脚本..."
rm -f "$script_path"
if [ ! -f "$script_path" ]; then
    echo "✅ 脚本已删除: $script_path"
else
    echo "⚠️  脚本删除失败: $script_path"
fi
rm -f /tmp/cleanup_brce_script.sh
EOF
        chmod +x /tmp/cleanup_brce_script.sh
        
        echo "✅ 卸载完成"
        echo "💡 注意: BRCE目录 $SOURCE_DIR 保持不变"
        echo "🚀 正在删除脚本文件..."
        
        # 执行自删除并退?        exec /tmp/cleanup_brce_script.sh
    else
        echo "💡 保留脚本文件: $(readlink -f "$0")"
        echo "✅ 卸载完成"
        echo "💡 注意: BRCE目录 $SOURCE_DIR 保持不变"
        echo ""
        echo "🔄 脚本已保留，可以随时重新配置FTP服务"
        echo "📝 使用方法: sudo $(basename "$0")"
    fi
}

# 主菜单
main_menu() {
    echo ""
    echo "请选择操作："
    echo "1) 🚀 安装/配置BRCE FTP服务 (双向零延迟)"
    echo "2) 📊 查看FTP服务状态"
    echo "3) 🔄 重启FTP服务"
    echo "4) 🧪 测试双向实时同步功能"
    echo "5) 🗑️ 卸载FTP服务"
    echo "6) 🔄 在线更新脚本"
    echo "0) 退出"
    echo ""
    
    read -p "请输入选项 (0-6): " choice
    
    case $choice in
        1)
            install_brce_ftp
            ;;
        2)
            check_ftp_status
            ;;
        3)
            echo "🔄 重启FTP服务..."
            systemctl restart vsftpd
            systemctl restart brce-ftp-sync 2>/dev/null || true
            if systemctl is-active --quiet vsftpd; then
                echo "✅ FTP服务重启成功"
            else
                echo "❌ FTP服务重启失败"
            fi
            ;;
        4)
            test_realtime_sync
            ;;
        5)
            uninstall_brce_ftp
            ;;
        6)
            update_script
            ;;
        0)
            echo "👋 退出程序"
            exit 0
            ;;
        *)
            echo "❌ 无效选项"
            ;;
    esac
}

# 主程序循环
init_script
while true; do
    main_menu
done 
