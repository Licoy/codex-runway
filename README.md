<p align="center">
  <img src="Resources/AppIcon.png" alt="Codex Runway logo" width="128" height="128">
</p>

# Codex Runway

中文 | [English](./README_EN.md)

你的 Codex 还可以跑多久？

Codex Runway 是一个原生 macOS 状态栏应用，帮你在菜单栏里查看 Codex 配额、reset credits、API 等价成本、本机会话和更新状态。

## 亮点

- 菜单栏查看 Codex 剩余额度。
- 查看 5 小时、每周和附加额度窗口。
- 显示当前 Codex 账号和订阅类型。
- 查看 reset credits 数量、状态和到期时间。
- 查看本周期 API 等价成本和 token 用量。
- 查看最近 Codex 会话、项目、状态和用量摘要。
- 修复本机会话索引。
- 支持浅色、深色、跟随系统和中英文界面。
- 支持内置更新检测。

## 截图

<p align="center">
  <img src="docs/images/1.png" alt="Codex Runway 配额概览" width="260">
  <img src="docs/images/2.png" alt="Codex Runway 重置次数详情" width="260">
  <img src="docs/images/3.png" alt="Codex Runway API 等价成本" width="260">
  <img src="docs/images/4.png" alt="Codex Runway 设置页面" width="260">
  <img src="docs/images/5.png" alt="Codex Runway 最近会话" width="260">
</p>

## 安装

从 GitHub Release 下载与你的 Mac 匹配的压缩包：

- Apple Silicon：`CodexRunway-macos-arm64.zip`
- Intel：`CodexRunway-macos-x86_64.zip`

解压后把 `CodexRunway.app` 放到 `Applications` 或任意目录运行。

### macOS 安全阻挡

当前 Release 是 ad-hoc signed，未 notarized。首次打开如果提示“无法验证开发者”或“未经安全验证”，请右键点击 `CodexRunway.app`，选择“打开”，或在“系统设置 > 隐私与安全性”中点击“仍要打开”。

如果提示“CodexRunway.app 已损坏，无法打开。您应该将它移到废纸篓”，通常是下载隔离属性导致的。把 app 放入 `Applications` 后运行：

```bash
xattr -dr com.apple.quarantine /Applications/CodexRunway.app
```

然后再次打开应用。

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

## 社区支持

- [LinuxDO](https://linux.do/)

## 许可证

本项目遵循仓库中的 [LICENSE](LICENSE)。
