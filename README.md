# AIX-Xray

[![macOS](https://img.shields.io/badge/macOS-10.14+-silver.svg)](https://www.apple.com/macos)
[![Xray](https://img.shields.io/badge/Xray-core-blue.svg)](https://github.com/XTLS/Xray-core)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> 专为 macOS 设计的轻量级 Xray 代理管理工具，终端交互，后台稳定运行。

## ✨ 功能特性

- 🚀 **一键启停** - 终端输入 `aix` 即可管理代理
- 🔄 **节点切换** - 自动扫描配置，快速切换节点
- 📊 **实时延迟** - 显示当前节点网络延迟（ms）
- 🌐 **出口IP** - 查看节点 IPv4/IPv6 地址
- 🔧 **后台运行** - 关闭终端窗口代理不中断
- 📝 **日志轮转** - 自动管理日志文件（>2MB 自动归档）
- ⚡ **开机自启** - 可选配置系统登录自动启动
- 🔍 **延迟测试** - 一键测试所有节点延迟

## 📦 一键安装

打开终端，执行以下命令：

    curl -fsSL https://raw.githubusercontent.com/321CMO/AIX/main/install.sh | bash

安装完成后，重启终端或执行：

    source ~/.bash_profile  # 或 source ~/.zshrc

## 📖 使用方法

    aix

进入交互菜单后根据提示操作：

- `1` 启动节点（自动检测 `~/Documents/Xray-macos-64/config-*.json`）
- `2` 停止代理
- `3` 测试所有节点延迟
- `4` 查看运行日志
- `5` 开机自启设置
- `6` 退出程序

**关闭终端**：直接关闭窗口即可，代理会在后台继续运行。

## 📁 目录结构

    ~/Documents/Xray-macos-64/
    ├── xray                    # Xray 核心文件
    ├── config-hkt.json        # 示例：香港节点配置
    ├── config-jp.json         # 示例：日本节点配置
    └── ...                    # 其他节点配置

    ~/.aix_xray.log            # 运行日志（自动轮转）
    ~/bin/aix                  # 管理脚本

## ⚙️ 配置说明

脚本自动扫描 `~/Documents/Xray-macos-64/` 目录下所有 `config-*.json` 文件。

- 命名格式必须为 `config-<节点标识>.json`
- 节点标识将作为菜单中的节点名称显示

## 🔧 常见问题

**Q1: 关闭终端后代理断开？**

A: 确保通过 `aix` 菜单启动。脚本已配置 `nohup` + `disown` 脱离终端控制。若仍断开，请检查日志 `tail -f ~/.aix_xray.log`。

**Q2: macOS 10.14 无法运行最新版 Xray？**

A: Go 1.21+ 已放弃支持 macOS 10.14。请下载兼容版本（推荐 v23.3.1）替换 `xray` 二进制文件。

**Q3: 如何添加新节点？**

A: 将配置文件保存为 `config-<节点名>.json` 放入 `~/Documents/Xray-macos-64/`，重新运行 `aix` 即可识别。

**Q4: 如何卸载？**

A: 删除 `~/bin/aix` 及相关隐藏配置文件即可：

    rm ~/bin/aix ~/.aix_xray.log ~/.aix_last_node

## 🖥️ 系统要求

- macOS 10.14 (Mojave) 或更高版本
- Bash 或 Zsh（系统自带）
- Xray Core v22.x ~ v24.x

## 📄 协议

MIT License
