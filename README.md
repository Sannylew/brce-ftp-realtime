---
## ⚠️🚨 **重要声明** 🚨⚠️

### 🔴 **此仓库为个人开发测试项目**
### 🔴 **仅供学习和技术研究使用**
### 🔴 **生产环境使用风险自负**

---

# BRCE FTP Realtime

**双向零延迟FTP同步工具 v1.0.0**

一个专业的FTP配置脚本，支持双向实时同步、自定义目录和用户名配置。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

## 🚀 核心特性

- **零延迟双向同步**：文件变化立即同步，FTP↔源目录实时互通
- **自定义配置**：支持自定义目录路径和FTP用户名
- **在线更新**：一键从GitHub更新到最新版本
- **简单易用**：全默认配置，也支持完全自定义

## 📦 快速开始

### 安装使用

```bash
# 下载脚本
wget https://raw.githubusercontent.com/Sannylew/brce-ftp-realtime/main/brce_ftp_setup.sh

# 运行脚本
sudo chmod +x brce_ftp_setup.sh
sudo ./brce_ftp_setup.sh
```

### 配置选项

**目录配置**：
- 默认：`/opt/brec/file`
- 自定义：输入任意路径，支持相对和绝对路径

**用户名配置**：
- 默认：`sunny`
- 自定义：支持字母数字下划线，3-16位长度

### 功能菜单

```
1) 🚀 安装/配置BRCE FTP服务
2) 📊 查看FTP服务状态
3) 🔄 重启FTP服务
4) 🧪 测试双向实时同步功能
5) 🗑️ 卸载FTP服务
6) 🔄 在线更新脚本
0) 退出
```

## 📋 连接信息

安装完成后获得：
```
服务器: [你的服务器IP]
端口: 21
用户: [自定义用户名，默认sunny]
密码: [自动生成的安全密码]
目录: [自定义目录，默认/opt/brec/file]
```

## 💡 核心优势

- **零延迟**：文件变化立即可见，无需刷新
- **双向同步**：root操作↔FTP操作完全同步
- **一键配置**：全部选择默认选项即可使用
- **智能处理**：自动创建目录，处理权限

## ⚡ 系统要求

- **系统**：Ubuntu/Debian/CentOS/RHEL
- **权限**：root权限
- **依赖**：脚本自动安装所需组件

## 🔧 常见问题

**服务检查**：
```bash
sudo systemctl status vsftpd
sudo systemctl status brce-ftp-sync
```

**重启服务**：
```bash
sudo ./brce_ftp_setup.sh  # 选择菜单选项3
```

**查看日志**：
```bash
sudo journalctl -u brce-ftp-sync
```

## 📜 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

**如果这个项目对你有帮助，请给个Star支持一下！⭐**
