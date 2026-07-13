# SwiftHoppy

> **说明：** 提交 [`91c3a4d`](https://github.com/WHYBBE/SwiftHoppy/commit/91c3a4dc7033b77bbab169b0365d65c6e19de19a)（*Rename app to SwiftHoppy*）及之前的开发由 **GPT-5.4** 完成。

使用 **Swift + SwiftUI + Swift Package Manager** 构建的 macOS 桌面应用，用于管理 SSH 连接记录，并持续跟踪 Linux/Unix 系统信息。

[English](README.md)

## 功能

- 新增、编辑、删除 SSH 连接记录
- 记录主机、端口、用户名、显示名称与备注
- 支持 **本机** 条目（打开本地终端、读取本机系统信息）
- 手动补录或通过 SSH 自动追加系统快照（内核、最近更新、运行时间）
- 读取并保存硬件信息（系统名称、架构、CPU、核心数、内存）
- 每条连接可维护备注，支持手动排序或按时间排序
- 侧边栏分割线，以及按手动 / 名称 / IP 排序
- 可在侧边栏隐藏 IP 等敏感信息
- 用指定终端应用（或系统默认）打开 `ssh://` 链接
- 连接数据 JSON 导入 / 导出
- 中英文界面
- 跟随系统 / 浅色 / 深色主题
- 现代化分栏界面：侧边概览、连接详情、系统历史

## 系统要求

- macOS 13 或更高
- Swift 5.9+（Xcode 或 Swift 工具链）

## 运行

```bash
swift run
```

也可在 Xcode 中打开 `Package.swift` 或 `SwiftHoppy.xcodeproj`，运行 **SwiftHoppy** scheme。

## 指定应用打开 SSH

应用会将连接转换为 `ssh://username@host:port`：

- 若填写了应用路径，则用该应用打开
- 未填写则使用系统默认处理程序

适合支持 `ssh://` 的终端或 SSH 客户端，例如 Terminal、iTerm2、Termius、Warp、Kitty、Ghostty、WezTerm 等。

本机条目会直接打开终端，不经过 SSH。

## 通过 SSH 自动读取系统信息

应用调用系统自带的 `/usr/bin/ssh`：

| 字段 | 来源 |
|------|------|
| 内核 | `uname` |
| 最近更新 | 常见包管理器缓存/日志路径（apt、dnf、yum、zypper、pacman、apk、FreeBSD pkg 等） |
| 运行时间 | 可读时通过 `/proc/uptime` 或 `uptime` 获取 |
| 硬件 | 系统名称、架构、CPU 型号/核心数、总内存 |

每次读取会 **追加** 一条带时间戳的历史记录，不覆盖旧数据。优先复用密钥、`ssh-agent` 与 `~/.ssh/config`。若远端需要密码，会弹出 macOS 图形密码框；取消输入则终止本次读取。

## 数据保存位置

| 内容 | 路径 |
|------|------|
| 连接数据 | `~/Library/Application Support/SwiftHoppy/connections.json` |
| 偏好设置（语言、主题、终端应用等） | `~/Library/Application Support/SwiftHoppy/terminal-apps.json` |

## 项目结构

```
Sources/
  SwiftHoppyApp.swift          # 应用入口、主窗口与设置
  ContentView.swift            # 侧边栏、详情、编辑器、设置界面
  SSHConnection.swift          # 连接、备注、系统/硬件模型
  SSHConnectionStore.swift     # 持久化、导入导出
  AppPreferencesStore.swift    # 语言、主题、排序、终端发现
  RemoteSystemInfoService.swift# 本机与远端系统/硬件读取
Package.swift
SwiftHoppy.xcodeproj/
```

## 许可

[MIT](LICENSE) © 2026 0x574859
