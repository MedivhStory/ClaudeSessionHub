# ClaudeSessionHub 待办清单 — v0.2.8.x closure

**最后更新**: 2026-04-20
**v0.2.8.x 产品线状态**: 收官（v0.2.8 / v0.2.8.1 / v0.2.8.2 / v0.2.8.3 均已 ship）

---

## v0.2.8.2 完成项

- ~~#1 Token 计数为零~~ — skip `<synthetic>` entries (PR #21)
- ~~#2 About 页面空白~~ — AboutView + AppVersion (PR #21)
- ~~#3.5 README 内部路径暴露~~ — 重写 Data Sources 段落 (PR #21)
- ~~#8 AI 理解 card 无 AXButton~~ — accessibilityAction + label (PR #21)
- ~~#9 3 个 AXHeading 无 value/name~~ — isHeader trait (PR #21)
- ~~API key 启动时未加载~~ — eager load at init (PR #21, smoke test 发现)

## v0.2.8.3 完成项

- ~~#5 UUID fallback title~~ — verb pattern 扩展 (partial fix, PR #22)
- ~~#10 菜单栏 AI enhance 命令~~ — AI > 批量 AI 增强全部会话 ⇧⌘E (PR #22)
- ~~#4 extractKeyTurns dead API~~ — removed (PR #22)
- ~~Dead code~~ — formatTokenCount + contextBarColor removed (PR #22)

## 已关闭（非 bug）

- ~~#6 Keychain scoping~~ — 误诊，实为 lazy load bug，已在 v0.2.8.2 修复
- ~~#11 ui-test-mode 堆叠~~ — intentional FixtureProvider test-harness 行为

## 已知限制（carry forward）

- **#5 的 10+50 window limitation** — verb pattern 扩展是 partial fix，首条有意义用户文本在 index 10 之后的 session 仍可能 fallback。deeper fix 待后续评估
- **#7 prompt scope-creep 子句** — v0.2.8.1 revert 的 3 条子句，如未来 AI 增强仍漏项目名则重新评估。归 v0.2.9 AI 质量主题

## v0.2.9 候选 backlog（AI 理解增强+，唯一主题）

| # | 主题 | 优先级 |
|---|------|--------|
| 3 | AI 增强质量（超长多主题 session） | 高 |
| 7 | prompt scope-creep 子句评估 | 中 |
| 23 | Phantom capability validation | 高 |
| 26 | Persisted prompts → stale context bombs | 高 |
| 27 | Agent spawn model flag 不继承 [1m] | 高 |
| 29 | Synthetic fixture ≠ real sample (release gate 盲区) | 高 |
| 32 | Session resume 时间锚 calibration | 高 |
| 30 | Dual-build CI linter | 中 |
| 31 | Unit test fake fixture shape | 中 |
| 33 | 普世型脱敏 UX | 中 |
| 34 | Dual-build membership linter | 中 |

完整分析见:
- `REFLECTIONS/2026-04-14-resume-as-three-mechanisms.md` (Appendix B)

## 独立 housekeeping（不是产品 scope）

| 项目 | 状态 |
|------|------|
| #18 Reflection Appendix C | 未写 |
| 封版旧工作目录 | V0.2.8 / V0.2.8.2 / V0.2.8.3 均可封版 |
| cshub-verify team config 证据 | 保留在 `~/.claude/teams/cshub-verify/`，已 snapshot |

## 环境问题（不影响用户）

| # | 问题 | 说明 |
|---|------|------|
| 12 | screencapture frozen frame | 向日葵远程桌面相关 |
| 13 | desktop-pilot MCP 连接失败 | macos-automator 作为 fallback |
| 14 | Gatekeeper 阻止 unsigned UI test runner | CI 不受影响 |
| 15 | v0.2.8 tag 不触发 release.yml | 根因已知，不需 fix |
