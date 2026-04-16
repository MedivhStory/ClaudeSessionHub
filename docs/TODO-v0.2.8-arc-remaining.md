# ClaudeSessionHub 全量待办清单

**生成时间**: 2026-04-16
**生成 Session**: `6a7b8e24-e480-45d2-98c8-b17d5ea11a8d`
**当前已 ship**: v0.2.8 (tag 57cd04f) + v0.2.8.1 (tag e64daba)，均已 merge 到 main
**v0.2.8.1 draft release**: 已在 GitHub，等 Publish

---

## 🔴 P0 — 新发现的 Bug（v0.2.8.2 或 v0.2.9 scope，用户直接报告）

| # | Bug | 描述 | 发现方式 |
|---|-----|------|---------|
| 1 | **Token 计数为零** | Session `b9d0af85` 的 token 使用量显示 0 | 用户使用产品时发现 |
| 2 | **About 页面空白** | 没有版本号、作者、简述、GitHub 仓库链接、许可证 | 用户使用产品时发现 |
| 3 | **AI 增强质量仍有问题** | Session `6a7b8e24`（本 session 自身）AI 生成 title/summary 不理想 | 用户使用产品时发现。v0.2.8.1 修了 extractor 但对超长多主题 session 可能覆盖不足 |

| 3.5 | **README.md Claude Code 味道过浓** | README 里直接暴露了 `~/.claude/projects/<key>/<id>.jsonl`、`~/.claude/sessions/<pid>.json`、`~/.claude/tasks/<id>/*.json` 等 Claude Code 内部实现路径。面向用户的 README 不应该泄漏实现细节——用户关心的是"这个 app 能干什么"，不是"它读哪个隐藏目录"。需要重写 Data sources 段落，改成用户视角的功能描述 | 用户审查 README 时发现 |

**决策点**: #1-3 走 v0.2.8.2 hotfix 还是 v0.2.9？#3.5 走 v0.2.9 README 重写？用户未决定。

---

## 🟡 P1 — 已知代码/产品问题（已记录，未修）

| # | 问题 | 来源 | 说明 |
|---|------|------|------|
| 4 | **extractKeyTurns 是 dead-but-public API** | v0.2.8.1 state report | 零 live caller，需加 `@available(*, deprecated)` 或在 v0.3 删除 |
| 5 | **Rule engine 仍用 10+50 窗口** | v0.2.8.1 主 agent flag | sdk-cli session 在 session list 里显示 UUID fallback title，只有手动触发 AI enhance 才改善。产品层面的 asymmetry，非 bug |
| 6 | **Keychain scoping** | v0.2.8.1 post-ship smoke | Release build 从 DerivedData 读不到 DashScope key，dev build 能读 |
| 7 | **v0.2.8 prompt scope-creep 子句被 revert** | v0.2.8.1 commit surgery | "产品/领域/项目名锚点保护" 3 条子句被 revert（无证据证明必要），如果未来 AI 增强仍漏项目名，需要重新评估是否加回 |

---

## 🟡 P1 — Accessibility / UX 问题（post-ship UI smoke 发现）

| # | 问题 | 描述 |
|---|------|------|
| 8 | **"AI 理解" card 无 AXButton** | VoiceOver 用户无法触发 AI enhance |
| 9 | **3 个 AXHeading 无 value/name** | 屏幕阅读器用户看不到标签 |
| 10 | **无菜单栏 AI enhance 命令** | 键盘可发现性差 |
| 11 | **--ui-test-mode 下 4 个 session 堆叠在 detail pane** | 可能 intentional，需确认 |

---

## 🟢 P2 — 基础设施/环境问题（不影响用户，影响开发流程）

| # | 问题 | 说明 |
|---|------|------|
| 12 | **screencapture frozen frame** | 这台开发机上 screencapture 输出 pinned 在同一帧。和向日葵远程桌面相关但关隐私屏后仍 frozen。需要重启机器或修 WindowServer |
| 13 | **desktop-pilot MCP 连接失败** | 安装第一天就有，始终未解决。macos-automator 作为 fallback 工作正常 |
| 14 | **Gatekeeper 阻止 unsigned UI test runner** | 本地 xcodebuild UITests 无法跑，CI 不受影响 |
| 15 | **v0.2.8 tag 永不触发 release.yml** | feature branch 切自 workflow 文件加入 main 之前。已解释根因（tagged commit 上没有 .github/workflows/），不需 fix |

---

## 📋 Deferred ship tasks（v0.2.8 arc 遗留，可立刻执行）

| # | 任务 | 状态 | 操作 |
|---|------|------|------|
| 16 | **v0.2.8.1 draft release → Publish** | Draft 在 GitHub，有 .dmg (5.5MB) + .zip (4.9MB) | 去 GitHub Releases 页面点 Publish |
| 17 | **PR #18 (docs/phase12-audit-retention) 合进 main** | OPEN | Review + merge（merge commit）|
| 18 | **Reflection Appendix C** | 未写 | v0.2.8.1 的 5 bug + Finding 10/11/12 需要追加到 REFLECTIONS/2026-04-14-resume-as-three-mechanisms.md |
| 19 | **Seal ClaudeSessionHub_V0.2.8 workdir** | 未做 | 按项目惯例封版目录（在 v0.2.8.1 都处理完之后）|
| 20 | **同步 local main + 清理分支** | 本地 main 落后 63+ commits | `git checkout main && git pull` + 可选删除已 merge 的 feature/hotfix 分支 |
| 21 | **v0.2.8 session arc memory 更新** | 未做 | `project_v028_session_arc_complete.md` 需反映 v0.2.8.1 + agent team validation |
| 22 | **cshub-verify team config forensic 证据** | 保留在 `~/.claude/teams/cshub-verify/` | 已 snapshot 到 `本机建设/claude agent team/evidence/`，runtime 状态暂保留 |

---

## 📐 v0.2.9 Feature 候选（from reflection findings）

| # | Finding | 主题 | 优先级估计 |
|---|---------|------|-----------|
| 23 | Finding 4 | Phantom capability — 系统级 validation 需 cross-reference | 高 |
| 24 | Finding 5 | Agent teams hub-spoke topology 文档化 | 中 |
| 25 | Finding 6 | 远程桌面 observation channel confounder | 低 |
| 26 | Finding 7 | Persisted prompts → stale context bombs | 高 |
| 27 | Finding 8 | Agent spawn model flag 不继承 [1m] | 高 |
| 28 | Finding 9 | In-process backend 无 OS 隔离 | 中 |
| 29 | Finding 10 | Synthetic fixture ≠ real sample（release gate 盲区） | 高 |
| 30 | Finding 11 | xcodeproj dual-build repair 不完整 → CI linter | 中 |
| 31 | Finding 12 | Unit test fake fixture shape | 中 |
| 32 | Resume 3 paths | Session resume 时间锚 calibration feature | 高 |
| 33 | 普世型脱敏 UX | 对话式脱敏流程取代 CSV review | v0.2.9+ |
| 34 | Dual-build membership linter | CI 自动检测 disk vs pbxproj diff | 中 |

**注意**: #23-34 的完整分析在以下两处：
- REFLECTIONS/2026-04-14-resume-as-three-mechanisms.md (Appendix B, 已 commit)
- `/Users/medivh_openclaw/Documents/本机建设/claude agent team/findings/v0.2.8-validation-findings.md`

---

## ⚠️ 当前工作树 / git 状态（交接用）

### 未 commit 的文件（在 ClaudeSessionHub_V0.2.8 工作树里）

```
?? docs/AGENT-TEAM-REFERENCE.md    ← 指向本机建设/claude agent team/ 的索引
?? docs/TODO-v0.2.8-arc-remaining.md  ← 本文件
```

这两个文件需要 commit + push（通过 PR 到 main，因为 branch protection 已开启）。

### 分支状态

```
main                                f3cf92c  [behind 63+ of origin/main] ← 严重滞后，需 pull
feature/v0.2.8-ai-eval              fabfaf1  [in sync with origin]
hotfix/v0.2.8.1-extractor-tail-bias e64daba  [当前分支，已 merge 到 main via PR #19]
docs/phase12-audit-retention        fe53c52  [ahead 1 of origin] ← PR #18 OPEN
```

### Tag 状态

```
v0.2.8   → 57cd04f (on feature branch, .github/workflows/ 不存在 → 不触发 release.yml)
v0.2.8.1 → e64daba (on hotfix branch, .github/workflows/ 存在 → draft release 已自动生成)
```

### GitHub 状态

```
PR #18: OPEN (docs/phase12-audit-retention → main)
PR #19: MERGED (v0.2.8.1 hotfix)
Draft release v0.2.8.1: 待 Publish (.dmg + .zip 已生成)
Branch protection on main: 已启用 (require PR + CI green + no force push)
```

---

## 新 session 的推荐启动 prompt

```
继续 ClaudeSessionHub 的工作。先读这些文件建立上下文：

1. docs/TODO-v0.2.8-arc-remaining.md — 全量任务清单（34 条）
2. REFLECTIONS/2026-04-14-resume-as-three-mechanisms.md — 深度反思 + findings
3. docs/AGENT-TEAM-REFERENCE.md — agent team 基建指向

当前最紧急的 3 件事：
- Publish v0.2.8.1 draft release
- Merge PR #18
- Triage P0 #1/#2/#3 (token=0 / About 空白 / AI 增强质量)
```

---

## 关于 Agent Team 的交接

Agent team 不是产品 feature，是组织基建。所有材料在：
```
/Users/medivh_openclaw/Documents/本机建设/claude agent team/
```
本项目只有索引指针 (`docs/AGENT-TEAM-REFERENCE.md`)。

Agent team 当前状态总结：Phase 1 (automated test dispatch) production-ready，Phase 2 (visible UI) partially blocked。详见上述目录下的 `status/2026-04-16-post-v0.2.8.1.md`。
