# SwiftGNUInfo

一个使用 `Swift + SwiftUI + Swift Package Manager` 构建的 macOS 桌面应用，用于手动记录 SSH 连接信息，并保存对应的 Linux/Unix 内核版本与最后更新信息。

## 功能

- 手动新增、编辑、删除 SSH 连接记录
- 记录主机、端口、用户名、备注
- 以历史列表形式保存 Linux/Unix 内核版本和更新记录
- 支持手动补录或通过 SSH 自动追加新的系统信息快照
- 为每条连接指定一个应用来打开 `ssh://` 链接
- 支持中英文界面切换
- 支持跟随系统 / 浅色 / 深色主题切换

## 运行

```bash
swift run
```

也可以在 Xcode 中直接打开 `Package.swift` 运行。

## 指定应用打开 SSH

应用会把连接转换成 `ssh://username@host:port` 形式的 URL，然后：

- 如果填写了应用路径，则使用该应用打开
- 如果未填写，则使用系统默认应用打开

适合配合支持 `ssh://` URL 的终端或 SSH 客户端使用，例如 `Terminal.app`、`iTerm.app`、`Termius.app`。

## 通过 SSH 自动读取系统信息

应用会调用系统自带的 `/usr/bin/ssh` 读取远端信息：

- 内核版本通过 `uname` 获取
- 最近更新时间会按常见包管理器缓存或日志路径探测
- 每次读取会追加一条带时间戳的历史记录，不覆盖旧值
- 优先复用密钥、`ssh-agent` 和 `~/.ssh/config`
- 如果远端需要密码，应用会弹出 macOS 图形密码框；取消输入会终止本次读取

## 数据保存位置

数据默认保存在：

`~/Library/Application Support/SwiftGNUInfo/connections.json`
