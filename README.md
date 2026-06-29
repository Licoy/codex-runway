# Codex Runway

中文 | [English](ENGLISH.md)

你的 Codex 还可以跑多久？

Codex Runway 是一个原生 macOS 状态栏应用，帮你在菜单栏里随时掌握 Codex 的剩余额度、重置次数、使用成本和本机会话状态。它面向日常高频使用 Codex 的用户：少打开网页，少猜额度，少错过重置时间。

## 亮点

- 一眼看到 Codex 还能跑多久，适合长任务和连续开发场景。
- 同时关注 5 小时、每周和附加额度，提前发现额度紧张。
- 自动识别当前 Codex 账号和订阅类型，减少多账号混淆。
- 追踪 reset credits 的可用数量和到期风险，避免可用重置次数被浪费。
- 将本周期 Codex 用量换算成 API 等价成本，帮助理解实际使用强度。
- 修复本机会话索引，让 Codex 会话列表恢复一致。
- 原生 macOS 菜单栏体验，支持浅色、深色、跟随系统和中英文界面。
- 内置更新检测，保持应用持续可用。

## 安装

从 GitHub Release 下载与你的 Mac 匹配的压缩包：

- Apple Silicon：`CodexRunway-macos-arm64.zip`
- Intel：`CodexRunway-macos-x86_64.zip`

解压后把 `CodexRunway.app` 放到 `Applications` 或任意目录运行。当前构建使用 ad-hoc signing，不配置 App Store 证书，也不做 notarization；首次打开时 macOS 可能需要在 Finder 中右键选择打开。

## 使用前提

- macOS 12+
- 已登录过 Codex
- 本机存在 `~/.codex/auth.json`

## 本地运行

```bash
swift run CodexRunway
```

自检命令：

```bash
swift run CodexRunway --self-check
```

自检会输出本地诊断信息，token 会被 redacted。

## 隐私

- token 只从本机 `~/.codex/auth.json` 读取。
- access token、refresh token、id token 不会写入日志、README、issue 模板或自检输出。
- API 等价成本默认来自本机会话 JSONL 日志，不上传会话内容。
- 在线用量数据只在本地没有可用 token 数据时作为补全来源。
- 会话修复只处理 `~/.codex/session_index.jsonl`，写入前会创建备份，不删除会话文件。
- 更新检测只访问版本信息，不上传 Codex 账号或会话数据。

## 开发与贡献

```bash
swift test
swift build
swift build -c release
```

贡献说明见 [CONTRIBUTORS.md](CONTRIBUTORS.md)。

## 许可证

本项目遵循仓库中的 [LICENSE](LICENSE)。
