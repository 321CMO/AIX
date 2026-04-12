# AIX-Xray 脚本管理工具

[![macOS](https://img.shields.io/badge/macOS-10.14+-silver.svg)](https://www.apple.com/macos)
[![Xray](https://img.shields.io/badge/Xray-core-blue.svg)](https://github.com/XTLS/Xray-core)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> 一款专为 macOS 设计的 Xray 代理管理工具，简洁高效，后台稳定运行

## ✨ 功能特性

-  **一键启停** - 终端输入 `aix` 即可管理代理
- 🔄 **节点切换** - 支持多节点快速切换，自动清理旧进程
- 📊 **实时延迟** - 显示当前节点网络延迟（ms）
- 🌐 **出口IP** - 查看节点 IPv4/IPv6 地址
- 🔧 **后台运行** - 关闭终端后代理持续稳定运行
- 📝 **日志轮转** - 自动管理日志文件（>2MB 自动归档）
- ⚡ **开机自启** - 可选配置系统开机自动启动
- 🔍 **延迟测试** - 一键测试所有节点延迟并排序

## 📦 一键安装

打开终端，执行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/AIX-Xray/main/install.sh | bash
