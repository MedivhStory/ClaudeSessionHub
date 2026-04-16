# Agent Team Reference

ClaudeSessionHub 的开发过程使用了 Claude Code 的 experimental agent teams 功能进行自动化验证。

**Agent team 不是本产品的 feature，是开发组织的基础设施。**

## 基建材料在哪

所有 agent team 的设计文档、角色定义、状态报告、findings、forensic 证据：

```
/Users/medivh_openclaw/Documents/本机建设/claude agent team/
```

本项目里只保留 agent team 的**执行产物**（verify runs、scenarios、accept-decisions），不保留 agent team 的基建材料。

## 本项目中的 agent team 产物

```
docs/verify/runs/           ← 每轮 verify 的报告和决策
docs/verify/scenarios/       ← verify 场景定义
REFLECTIONS/                 ← Appendix B 有 agent team 的 7 findings（产品反思上下文）
```

## 源头 Session

所有 agent team 基建 + v0.2.8 verify 工作的原始对话：

```
Session ID: 6a7b8e24-e480-45d2-98c8-b17d5ea11a8d
```

这个 session 同时也是本项目的 `real-snapshot-01` fixture 数据源（脱敏后）。需要详查任何 agent team 决策的上下文时，回这个 session 的 `.jsonl`。

## 更多信息

→ `/Users/medivh_openclaw/Documents/本机建设/claude agent team/projects/claudesessionhub/v0.2.8-usage-notes.md`
