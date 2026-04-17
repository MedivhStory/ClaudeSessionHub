[English](./README.md) | [简体中文](./README.zh-CN.md)

<div align="center">

<img src="Resources/AppIcon.png" width="128" height="128" alt="Claude Session Hub 图标">

# Claude Session Hub

**原生 macOS 任务管理器，专为 Claude Code 会话设计。**

一眼掌控所有项目中的会话状态、健康信号和工作进度。

*享受 AI，也别忘了管好 AI。*

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Tests](https://img.shields.io/badge/测试-passing-brightgreen)](.)
[![License](https://img.shields.io/badge/许可-MIT-lightgrey)](LICENSE)

</div>

---

## 安装

1. 从 [Releases](https://github.com/MedivhStory/ClaudeSessionHub/releases/latest) 下载 **ClaudeSessionHub.dmg**
2. 打开 DMG 文件
3. 将 **ClaudeSessionHub** 拖入 **Applications**
4. 从启动台或 Applications 打开

### 首次启动

macOS 可能会阻止未签名应用：

- **右键点击**应用 > 选择**打开** > 在弹窗中点击**打开**

如果仍然无法打开：

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeSessionHub.app
```

---

## 功能

Claude Session Hub 读取本地 Claude Code 数据（`~/.claude/`），提供统一的会话管理面板。核心离线运行，可选 AI 增强。

### 核心功能

- **智能会话命名** — 基于规则的标题生成，自动清理命令噪音、粘贴包装、文件路径
- **最后进展追踪** — 回答"最近完成了什么"而非"最后说了什么"
- **可选 AI 增强** — 连接任何 OpenAI 兼容 API，获取 AI 标题、进展摘要和会话概述
- **双栏展开视图** — 左栏：规则/事实/操作，右栏：AI 理解面板
- **弹性折叠卡片** — 健康会话 2 行，异常会话 3 行
- **内容优先搜索** — 加权搜索智能标题、备注、历史、任务、分支、进展
- **会话关联** — 检测同分支和时间延续关系
- **健康信号** — 停滞、上下文满载、近期错误——仅在需要时显示
- **一键恢复** — 在 Ghostty 或 Terminal.app 中恢复任意会话

### AI 增强（可选）

在 设置 > AI 增强 中配置：

1. 输入 OpenAI 兼容的 API 地址
2. 填入 API Key 和模型名称
3. 点击"测试连接"验证

配置完成后：
- 展开任意会话 > 右栏点击 **"生成 AI 理解"**
- 或使用列表顶部的 **"批量 AI 增强"** 按钮
- AI 结果会缓存，会话更新后标记为"已过期"
- 不配置 AI 也完全可用——规则引擎始终在线

## 系统要求

- **macOS 14**（Sonoma）或更高版本
- 已安装 Claude Code（`~/.claude/` 数据目录）

## 架构

```
SessionStore (@Observable, @MainActor)
  ├─ ScanCoordinator (actor)
  │    └─ ClaudeProvider（动态目录）
  │
  │  规则层（自动，每次扫描）
  ├─ RuleTitleStrategy → TitleStore (titles.json)
  │
  │  LLM 层（手动触发）
  ├─ LLMEnhancer → UnderstandingStore (understanding.json)
  │
  ├─ SignalExtractor (history.jsonl + tasks/)
  ├─ LLMClient (OpenAI 兼容 HTTP)
  └─ SettingsStore (settings.json + LLMConfig)
```

所有会话数据均从 Claude Code 的本地数据目录读取（只读，从不修改）。

## 当前限制

- Codex provider 为桩实现（协议已就绪）
- 未做代码签名和公证（首次启动需右键打开）
- AI 提示词为中文——纯英文模型可能效果欠佳
- API Key 存储在独立本地文件中（受限权限），未使用 Keychain（计划在代码签名后迁移）

## 开发

<details>
<summary>开发者指南</summary>

```bash
# 从源码运行
swift run ClaudeSessionHub

# 单元测试
swift test

# UI 测试（需要 Xcode）
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -scheme ClaudeSessionHub \
  -destination 'platform=macOS' \
  test -only-testing:'ClaudeSessionHubUITests'

# 构建 .app
xcodebuild -project ClaudeSessionHub.xcodeproj \
  -target ClaudeSessionHub \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO CONFIGURATION_BUILD_DIR=./dist
```

</details>

## 许可

MIT — 完整内容见 [LICENSE](LICENSE)。

**MIT 人话版：** 随便用、随便改、随便发布，保留版权声明就行，出了事别找作者。

> *仅为友好总结，以 [LICENSE](LICENSE) 为准。*

---

<div align="center">

*享受 AI，也别忘了管好 AI。*

使用 SwiftUI 构建，为 Claude Code 重度用户设计。

</div>
