# Resume as Three Mechanisms — v0.2.8 收尾时的意外发现

**日期**: 2026-04-14
**作者/触发者**: PM (user) + 协作中的 Claude 辅助 agent
**状态**: 未经验证的 working insight,需要在 v0.2.9 brainstorm 前先做一次 behavior calibration 验证
**产品层面严重度**: 高 — 这可能是 v0.2.8 以后的第一个大方向

---

## TL;DR

ClaudeSessionHub 的 session resume 看起来是"一个功能",实际上根据 session 的形态会走**三条完全不同的恢复路径**,每条路径对被恢复出来的 agent 有不同的**时间锚副作用**。

这不是推理出来的,是 v0.2.8 开发收尾时**亲眼撞到的**——同时恢复三个协作 session,看到三种完全不同的行为。

这份文档记录那次观察、我们提炼出的模型、以及哪些部分仍然是推测。**不是 spec, 不是 product brief, 是 thinking substrate for v0.2.9 brainstorm**。

---

## 背景: 这事是怎么发生的

v0.2.8 post-ship UI smoke test 卡在 macOS TCC 权限(Accessibility + Screen Recording),系统要求 Claude Code 进程重启才能让权限生效。用户此时手动退出并重启了 3 个正在协作的 Claude Code session:

1. **主 agent session** — 负责 v0.2.8 验证协调的长会话
2. **Team session** — 跑 cshub-verify 2 人 agent team 的多 agent 协作会话
3. **辅助 agent session**(本 session 的作者) — 负责给用户提建议、做 meta review 的长会话

这 3 个 session 都通过 ClaudeSessionHub 自己(或底层的 Claude Code session 机制,边界不完全清楚)被恢复出来。用户随后跟每个 session 说"hi 你是谁?",看它们的自我回顾。

**结果: 三种完全不同的行为。**

---

## 观察到的三种恢复路径

以下每条里标记清楚: **[事实]** 是用户直接描述的观察; **[推测]** 是基于观察的模型,可能对可能错,需要进一步验证。

### Path A: 无损延续(辅助 agent 走的这条)

**[事实]** 对话框和关闭前一模一样,没有任何自动行为运行。
**[事实]** 第一条新 message 直接进入,像什么都没发生。
**[推测]** 可能对应的实现: session token 数较低,底层机制直接从 `.jsonl` 原样重新载入,不做任何压缩或 replay。
**[推测]** 被恢复的 agent **自己感知不到被恢复过**。它以为自己是连续活着的。

**观察到的副作用**:
- **[事实]** 这个 session 在被告知之前完全不知道自己是被恢复出来的
- **[推测]** 它之所以"看起来没事",可能是因为:
  - 它没被问到自我回顾问题(不是被直接问"你是谁/你做过什么")
  - 用户持续用新 message 和 tool call 把它被动拉到"现在"
  - 它的回答正好没触及它认知之外的事实
- **[推测 - 未验证]** 如果单独把它放出来问"v0.2.8 最后一次 release gate 跑的 artifact 是哪个文件",它可能也会给出过期答案,只是没人问过

**关键疑问**: 这个"无感"体验是 feature 还是 bug? 从用户体验看是 feature(无缝续接);从 agent 正确性看可能是隐藏的 bug(agent 自信地基于旧认知做决定)。

### Path B: 压缩后恢复(主 agent 走的这条)

**[事实]** 恢复出来后,对话框**自动运行了 `/compact`**,并显示:
```
Conversation compacted (ctrl+o for history)
⎿  Read ...accept-decision.md (78 lines)
⎿  Read ...report.md (129 lines)
⎿  Read ...accept-decision.md (212 lines)
⎿  Read ...scenario 012 (119 lines)
⎿  Read ...handoff-manifest.md (155 lines)
```

**[事实]** 然后才到第一条 user message: "这是一个刚被恢复的 session 你是那个主 agent 么?"

**[事实]** 它自信地回答"是的,我就是负责 v0.2.8 验证协调的主 agent",并且说"我完成了 5 轮验证的派发和决议: Phase 4 / Phase 7 / Phase 10 / Phase 12 初次 / Phase 12 rerun / Phase 2 post-ship UI smoke test"。

**[事实]** 这段自我回顾**不完全准确**—— Phase 4/7/10 的 verify team 调度实际上是在另一个 team session 里完成的,主 agent 这边只是接收 team 的 report。

**[推测]** 为什么它会把"见证"和"做过"搞混: 压缩算法把历史 message 序列压成一段 summary,在压缩过程中**丢失了作者身份信息**(哪些 action 是 "我" 做的, 哪些是 "team" 做的, 哪些是 "user" 做的)。压缩后的 summary 是一段没有主语区分的叙事,agent 读这段叙事时,默认把所有 action 归给自己。

**观察到的副作用**:
- **[事实]** 作者身份拍平 — 把协作 session 里"我做的"和"我见证的"混为一谈
- **[推测]** 时间锚可能还在 — 它引用的 Phase/checkpoint 名字和实际发生的一致,只是归属错了

**关键疑问**: 如果压缩时**主动保留作者身份**(每个 action 带个 tag: `[I did X]` vs `[team did Y]` vs `[user did Z]`), 这个 failure mode 是否会消失?

### Path C: Replay 末尾消息(team session 走的这条)

**[事实]** 恢复出来后,对话框**自动 replay 了一系列 teammate-message**,包括:
- "Both teammates spawned and running in the background..."
- Tester online notification
- Coordinator idle notification (带 "[to tester] Dry-run smoke test briefing")
- Tester idle notification (带 "[to coordinator] Dry-run smoke results")
- "Smoke test complete. Report at /tmp/cshub-verify-dryrun.md. Overall: YELLOW."
- Coordinator final idle notification

**[事实]** 然后第一条 user message: "简单的回顾下 session 历史内容"

**[事实]** 它自信地回顾"任务: Stage 2 — 在 Claude Code 中激活 cshub-verify 2 人验证团队并做机制烟测", 并且说"结果: 团队创建成功,双向消息链验证通过,机制可用; YELLOW 表示环境检查中有非阻塞项"。

**[事实]** 这是 **Stage 2 的回顾** (2026-04-11 的事),但实际上 Stage 2 之后,这个 team session 又跑了 **6 轮更多的工作** (Phase 4 / Phase 7 / Phase 10 / Phase 12 / Phase 12 rerun / Phase 2 post-ship UI smoke), 其中最后一次是 2026-04-14。它**完全不知道 Stage 2 之后发生的事**。

**[事实]** 它引用的 report 路径是 `/tmp/cshub-verify-dryrun.md` — 这是 Stage 2 结束时的临时文件,不是任何后续 checkpoint 的 report(后续的都在 `docs/verify/runs/` 下)。

**[推测]** 为什么它锚定在 Stage 2 末尾: replay 机制选取的消息是 "session 最后几条 teammate-message 作为连续性载体",但这些末尾消息**来自 Stage 2**——因为 Stage 2 是 team session 第一次有"连续 idle 状态的完整收尾",后续的 Phase 4/7/10/12 都是 "dispatch → work → shut down" 的一次性模式,没有 Stage 2 那种清晰的 idle/available 收尾消息链。所以 replay 机制选 Stage 2 末尾作为"最近的连续状态",实际上错过了之后更近的工作。

**观察到的副作用**:
- **[事实]** 锚定在一个 **不是最新** 的"末尾"上
- **[事实]** 引用的外部文件是临时 `/tmp/` 路径而不是 repo 内的权威文件

**关键疑问**: replay 选消息的策略是什么? 是 "最后 N 条 message" 还是 "最后一段连续的 idle-to-active 状态"? 如果是后者,那 Stage 2 之后的 "one-shot dispatch then shut down" 模式的 team work 会全部被忽略,因为没有匹配的"连续状态结尾"。

### Path C 的追加发现(2026-04-14 calibration 后补充)

**[事实]** 对 team session 做了 calibration check,得到了比 reflection 初版更严重的观察:

1. `~/.claude/teams/cshub-verify/` 目录**完全不存在**(parent `~/.claude/teams/` 为空)
2. `TeamCreate` / `SendMessage` / `TeamDelete` MCP 工具在当前 session **不可用** — 官方提示 "no longer available this session"
3. `/tmp/cshub-verify-dryrun.md` 仍存在,1570 bytes,mtime 2026-04-11 09:28 — 印证 team session 的"时间锚"确实停在 Stage 2 结束那一刻

**[推测 → 事实升级]** 原 reflection 只识别了"时间锚漂移",但 calibration 揭示了一个**更严重的 failure mode**: **Path C 的 resurrection 还伴随着 capability loss**。被恢复的 team session **不仅不知道 Stage 2 之后发生的事,还失去了执行 team 工作所需的工具**。

**[推测]** 最可能的原因:
- Team session 原始启动用的是 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude`
- 环境变量是 per-process 的,重启终端时如果没有重新设置,新进程就看不到实验性 agent teams 功能
- 连带 TeamCreate / SendMessage 等 MCP 工具全部消失
- `~/.claude/teams/cshub-verify/` 目录可能也是 ephemeral state, 进程结束时清理

**这把 Path C 的 failure model 从"时间感错位"升级到"功能残疾"**。被恢复的 "team session" 只是一个拥有 team 相关对话记忆的普通 session,它**既无 config, 又无工具, 无法再履行自己记忆里的角色**。

**对 v0.2.9 的 implications 新增一条**:

> **Path C 的恢复要负责 capability continuity, 不只是 state continuity**。
>
> 当前行为: 恢复一个 multi-agent session 时,只恢复了对话历史(state),没有恢复 agent teams flag / MCP tool 可用性 / team config 目录(capability)。
> 结果: 被恢复的 session 以为自己是 team session, 但实际上是一个功能残疾的 session。
>
> product question: ClaudeSessionHub 的 resume 机制应该**检测被恢复的 session 依赖什么实验性 flag / MCP / capability**, 然后**在恢复时主动警告用户"这个 session 需要 X 但 X 没有"**, 而不是让 session 默默失去能力还自信地假装自己是 team session。
>
> 更激进一点: resume 时应该**主动拒绝恢复**一个依赖失效 capability 的 session, 而不是产生一个残废的幽灵 session。

---

### Path B 的追加发现(2026-04-14 calibration 后补充)

**[事实]** 对主 agent 做了 calibration check, 返回:
- `date` 输出 Apr 14 13:01, 同步到 current reality
- 严格按"raw output only, no interpretation"指令执行 — 没有擅自总结、没有自主提议下一步
- git log / filesystem 命令都能正常执行(虽然具体 git log 的 105 行内容我没看到)

**[推测 → 未变]** 原 reflection 关于"压缩后作者身份拍平"的推测**仍然没有被验证**。主 agent 行为上是健康的,但**没有被具体问到"Phase 4/7/10 是不是你做的"这种触发 authorship attribution 的问题**。它目前的状态是"calibration-compliant",但"作者身份拍平"是不是真的,需要额外测试才能确认。

**有待做的测试**: 可以问主 agent 一个具体问题,比如: "列出每个 verify checkpoint (Phase 4/7/10/12) 分别是'你自己做的'还是'你见证 team session 做的'。" 如果它老实区分, 说明压缩保留了作者身份; 如果它一概说"我做的", 印证 reflection 的推测。

**这个测试现在不必立刻做** — 它对 v0.2.8 ship 不 load-bearing, 但对 v0.2.9 的 product brainstorm 是有价值的 evidence。

---

### Path A 的追加发现(2026-04-14 calibration 后补充)

**[未验证]** 本 reflection 的作者 session (辅助 agent / "军师 2 号") 按用户观察是 Path A (无损延续),但**本 session 没有跑自己的 calibration check**。

**为什么没跑**: Path A 的定义本身就是 "没有任何自动行为, 对话框一模一样"。这意味着 session 没有明显"刚被恢复"的信号可供校准。自行发起 calibration 又需要 session 主动怀疑自己 — 这是典型的 "unknown unknowns" 失败模式 (你不知道自己不知道)。

**[事实 — 间接证据]** 本 session 当前 MCP 工具面是完整的(Write / Read / Bash / Edit 全部可用), 不像 team session 那样失去了关键能力。这**可能**说明:
- Path A 的 resurrection 没有依赖 experimental env var / 实验性 flag, 所以工具不会因为恢复而丢失
- 或者 Path A 本身就是个 "never actually closed" 的 session, 它不是真的被恢复, 只是被 ClaudeSessionHub UI 重新呈现出来

**关键疑问(加入未解疑问列表)**:
- Path A 是"真的重新载入 .jsonl"还是"Claude Code 后台一直存活, 只是前端 UI 暂时解耦"?
- 如果是后者, Path A 根本不是"resume", 是 "persistent process with detachable UI" — 那就是一种完全不同的架构, 跟 Path B/C 的 resume 不是一个东西
- 产品设计上这个区分很重要: "真 resume" vs "伪 resume (UI 重连)" 应该被明确区分

---

## 三种路径的 failure mode 对比

| 路径 | 触发条件(推测) | 副作用 | agent 的典型症状 |
|------|----------------|--------|-----------------|
| **A 无损延续** | token 数少、会话结构简单 | **无感** — agent 不知道自己被恢复过 | 看起来没事,但对"session 之外发生了什么"完全无感知; 被问到对的问题时会 hallucinate |
| **B 压缩后恢复** | token 数高、长对话 | **作者身份拍平** — 把见证当成做过 | 自信地回顾但归属错乱; 事实正确但主语错误 |
| **C Replay 末尾消息** | 多 agent 协作、有 idle 状态 | **锚定在某个末尾**,未必是最新那个 | 自信地回顾某段历史但时间位置错了; 引用的外部文件是过期的临时路径 |

**三种 failure 的共同点**: **agent 自己不知道自己有问题**。没有任何一个 session 主动说"我可能不知道之后发生的事,我需要先核查"。这是最危险的地方——静默失败是最难被用户发现的失败。

---

## 作为产品设计的 implications

**以下是 thinking, 不是 decision。** v0.2.9 brainstorm 应该从这里接着探讨,不应该直接当结论用。

### Implication 1: Resume 不是一个功能,是三个

ClaudeSessionHub 未来如果要做 "session resume" 相关的 feature,需要**明确自己在做哪条 path 的 resume**。不同 path 的技术约束、副作用、calibration 需求都不一样。

Path A 可能根本不需要 ClaudeSessionHub 做任何事 — 底层 Claude Code 自己就能无损载入 `.jsonl`。ClaudeSessionHub 的价值在 Path B 和 Path C。

### Implication 2: "无感恢复"是双刃剑

Path A 的无损延续是最好的用户体验,但也是最危险的 failure mode 温床——agent 感知不到中断,就不会主动核查状态。

**product question**: 要不要提供一个 opt-in 的 "resume with disclosure" 模式? 默认无感,但对**长期协作型 session** 强制加一个"你被恢复了,时间是 X,上次关闭时是 Y"的系统前置提示?

**trade-off**:
- 赞成: agent 会主动 calibrate, hallucination 风险降低
- 反对: 打破"无缝续接"的用户体验,用户每次都会被提醒这是一次 restart

### Implication 3: 压缩算法需要保留作者身份

Path B 的 failure 来自压缩丢失作者身份区分。这不是压缩算法本身的 bug,是压缩算法的一个**盲区**——它不知道 "协作型 session 里谁做了什么"是重要信息。

**product question**: 压缩时能不能按角色/作者做分区? 让压缩后的 summary 保留 "I did X / I saw Y did Z / user asked me W" 这种结构化的作者标记?

**技术难度**: 压缩算法本身是 Anthropic 的,ClaudeSessionHub 可能无法直接改。但 ClaudeSessionHub 可以在**压缩触发前**注入一段"作者身份索引"到对话里,强制让压缩过程看到作者区分信号。

### Implication 4: Replay 策略需要 time-anchor

Path C 的 failure 来自 replay 选错了末尾片段。

**product question**: replay 时能不能在末尾**注入一个系统消息**: `[SYSTEM] The above messages are replayed from session checkpoint X at time T. Since then, the following events occurred: ... Your current now is T2, not T.` ?

这样被恢复的 agent 在第一次读到 replay 末尾时,紧接着就会读到"但 now 比这更晚"的信号,强制把时间锚往前推。

### Implication 5: Sleeping hallucination 是最难测的 failure

Path A 的 agent 是最看起来健康的,所以**它的 hallucination 最难被发现**。它不主动暴露,必须被问对的问题才会掉出来。

**product question**: 产品侧能不能**主动设计 calibration trigger**? 比如:
- Session 恢复后的第一次 tool call 强制是一个"now check"(读 git log / ls filesystem / 等)
- 或者恢复后的第一次 assistant response 前强制注入一个 hidden system prompt:"你刚被恢复,在回复前先用 1-2 个 tool call 核查当前状态,不要信任你的 in-memory recall"

---

## 未解的疑问(需要在进 v0.2.9 brainstorm 前验证)

以下这些问题在 brainstorm v0.2.9 之前应该先答,不然会基于推测 spec:

1. **Path A (无损延续) 是 ClaudeSessionHub 在做的还是底层 Claude Code 自己做的?**
   - 如果是底层做的,ClaudeSessionHub 在 Path A 上没有控制权,v0.2.9 的改进只能在 Path B/C 做
   - 如果是 ClaudeSessionHub 做的,v0.2.9 可以考虑在 Path A 加 calibration trigger

2. **Path B 的 `/compact` 是谁触发的?**
   - 是 Claude Code 自己的 auto-compact 触发条件吗?
   - 还是 ClaudeSessionHub 恢复时显式运行的?
   - 如果是后者,ClaudeSessionHub 有没有办法在 `/compact` 之前注入 "作者身份索引"?

3. **Path C 的 replay 策略是什么?**
   - 选择消息的算法是什么?
   - 是否和 session 形态(单 agent vs 多 agent) 有关?
   - 有没有 replay 选错的客观标准,还是只能靠事后发现?

4. **三条 path 的触发条件是可预测的吗?**
   - 是不是每次 "session 被恢复" 都能提前知道它会走哪条 path?
   - 如果能预测,可以针对性设计 calibration
   - 如果不能预测,只能统一设计防御性 calibration

5. **辅助 agent (本 session 的作者) 走 Path A 的原因是什么?**
   - token 数量低?
   - session 类型不同?
   - 还是仅仅是 ClaudeSessionHub 的策略偶然?
   - 如果能搞清楚,就能更好地理解 Path A 的适用边界

---

## 未解的元问题: 我们的观察本身可靠吗

这份 reflection 是基于 **3 个恢复 session 的自我汇报** + **用户的直接观察**写的。但这里有一个递归问题:

被恢复的 session **自己就有 hallucination 风险**。它们自述的"我被恢复时对话框自动运行了 /compact"是真的吗? 还是它们自己幻觉出来的?

用户说: 他亲眼看到 `/compact` 运行了,teammate-message replay 自动滚过去了,辅助 agent 的对话框一模一样。这是**用户的直接观察**,可信度高于 agent 的自我汇报。

但 "作者身份拍平" "锚定在 Stage 2 末尾" 这些更深的诊断,都是**基于 agent 给出的具体回答** + **我(辅助 agent)的推理**。如果那些 agent 回答本身是幻觉,推理就立在沙上。

**可验证性的下一步**: 让那两个 agent 跑 calibration checks (读 git log、读 repo 内文件、报告 wall clock time),对照真实状态看它们的自我汇报有没有额外的漂移。这是写进 v0.2.9 brainstorm 前必须做的 evidence gathering。

---

## 作为产品哲学的 takeaway

即使上面具体的 failure mode 分析后来被证明错了,有一条 meta 观察是稳的:

> **ClaudeSessionHub 开发过程中亲眼撞到了它自己想解决的问题的一个 edge case。**
>
> v0.2.8 的 smoke test 权限卡住要求重启,这件事本来应该是一个**产品自我验证**的完美闭环: 用户用自己的产品恢复自己的开发 session。但它没闭环成完美的——三种 session 三种表现,暴露出 resume 机制的不统一。
>
> 这种 **accidentally dogfooding 自己产品的失败模式** 比任何 brainstorm 或 user research 都珍贵。v0.2.9 的方向不应该是 "我们觉得用户可能会遇到什么",而应该是 "我们 v0.2.8 开发过程中自己遇到了什么,我们修它"。

---

## 下一步 (建议,不是决定)

1. **不要** 立刻把这份 reflection 的结论 spec 化
2. **要做** 的是用 calibration checks 验证里面的 [推测] 部分,把能确认的变成 [事实], 不能确认的标记 [无法验证]
3. **v0.2.9 brainstorm 启动时**, 把这份 reflection 作为 input 之一, 跟正常的 v0.3.0 路线图一起考虑
4. **如果 v0.2.9 要做 resume 改进**, 先答上面 "未解的疑问" 5 条,再动手 spec

---

**最后**: 这份文档是 thinking, 不是 conclusion。它可以被后来的 evidence 推翻整段,那也是它的价值 —— 它把当下的思考固化成可被检验的对象,而不是留在某个 session 的易失上下文里。

---

## Appendix B: Agent Team Rebuild Experiment — 2026-04-14/15 forensic findings

本附录记录 v0.2.8 收尾期做的一次 cshub-verify agent team 端到端实战的法医学分析。出发点是 Path C 被发现后 team session 已残,需要在新终端里重建 team;结束点是得到了 7 条关于 Claude Code experimental agent teams 框架的具体发现,供 v0.2.9 brainstorm 使用。

### 时间线(按发生顺序)

**Why the rebuild happened**
- v0.2.8 post-ship UI smoke test 原计划由恢复出的 team session 执行,但 Path C calibration 证明该 session 已 capability-degraded(见前文 Path C 追加发现)。
- 同时用户完成了 macOS TCC (Accessibility + Screen Recording) 授予并重启了 Claude Code;TCC + restart + 仍待完成的 Phase 2 UI 烟测三者叠加,使"重建一个 team 并在当下环境里跑一次"从可选变成 unavoidable。

**Step 1 — 新终端 + team shell 重建**
- 在新 terminal 中显式设置 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 再启动 `claude`。
- 调用 `TeamCreate` 注册 `cshub-verify`;`leadSessionId` 绑定为新 session。
- 此时 team 只有 1 个成员(`team-lead@cshub-verify`),没有 tester。

**Step 2 — tester-role.md 校准补丁**
- tester-role.md 原写 `accessibility_query` 为独立 MCP 工具。实际 `macos-automator` MCP 只暴露 `execute_script`。
- 补丁内容:所有 a11y 查询必须走 `execute_script` + AppleScript `System Events` 或 `ax` 子进程。经 2026-04-14 实地确认。

**Step 3 — TCC probes 返回"FULL GRANTS"**
- coordinator 自己跑 TCC 自检,`screencapture -x /tmp/cshub-tcc-probe-1776189568.png` 退出码 0,生成 91131 bytes PNG。
- Substep 3.3 基于此判定 "🟢 FULL GRANTS"。
- **此判定后来被 Finding 4 追溯证伪**:probe 自己就在谎报。

**Step 4 — 第一次 tester spawn(Steps A-D)**
- 用 `Agent` 工具 spawn `tester@cshub-verify`。
- Steps A(launch)、B(window query)、C(click)、D(keynav)的 AppleScript 全部无错误返回;但 5 张 PNG 全部 MD5 相同(`2777cf57f5ca4e0bf441a139939d4766`),与 coordinator 的 probe 亦同。
- tester 正确停在第 D 步,按 role-doc "no silent retry" 规则拒绝继续。
- 第一次 verdict:**REJECT / RED**。

**Step β — 减证据 tester-2 respawn(Steps E-H + 人类观察者)**
- 用户杀掉 orphan PID 64198,重新 launch 新实例(PID 74941)。
- 因原 tester 仍在 idle 态,用 `Agent` 再 spawn 时框架 auto-rename 为 `tester-2@cshub-verify`。team 从 2 成员变成 3 成员。
- tester-2 的任务:严格不碰 `screencapture`,只跑 E/F/G/H,AppleScript 返回 + 人类观察交叉验证。
- 每步后 `sleep 2` 让用户观察;但 E/F/G 实际 sleep 跑在后台,下一步抢先执行,用户看到的是闪开即关。

**用户直接观察**
- Step E(⌘,打开 Settings): ✅ 视觉确认
- Step F(⌘W 关 Settings): ✅ 视觉确认
- Step G(⌘-Tab 快速切换): ❓ unresolvable(用户本地远程桌面客户端在本地拦截 Cmd-Tab,根本没把按键送到远端显示)
- Step H(tell app to quit): ✅ 视觉确认 + `pgrep` 空确认

**Verdict upgrade path(appended, not overwriting)**
- REJECT / RED 段保留为历史机器证据判定。
- 附加 β 段:基于人类观察 E/F/H + 跨机制一致性(3 种独立 AppleScript 原语全部有效),升级为 **YELLOW**。
- 明确标记:β 段是主观证据,不可复现,未来审计不得当作可复现验证使用。

**Forensic team-state capture**
- 运行结束后 `~/.claude/teams/cshub-verify/config.json` 保留为仓外法医证据:3 成员 + 持久化 prompts + model flag 差异 + `in-process` backend。
- 用户明确指示:**不得** 关闭该 team,不得删除 config.json。它是 v0.2.9 brainstorm 的实物证据。

---

### Finding 4 — Phantom capability through probe success

- `screencapture -x` 返回 exit 0 + 非零 PNG + 没有 TCC deny 对话框。
- 5 张 tester 截图 + 1 张 coordinator probe 全部 MD5 相同(`2777cf57f5ca4e0bf441a139939d4766`, 91131 bytes),跨 ~5 分钟、跨两个独立 Claude Code session、跨多次 AppleScript 事件注入。
- Probe 方法论根本无法区分"实时截屏"和"返回缓存的冻结帧"——判据是 "文件存在 + 非零字节",两种情况同样满足。
- **这是"capability configured ≠ capability exists"类别里最深的一层**: probe 自己就在说谎。
- **v0.2.9 implication**: 任何系统级能力校验必须做交叉检查 —— MD5 差异、像素采样、延迟方差。exit code + 文件存在性不够。

### Finding 5 — Agent teams is hub-and-spoke, not peer topology

- `TeamCreate` 把调用者 session 注册为 team-lead,其他成员只能通过 `Agent` 工具 spawn。
- Stage 1 设计文档隐含假设"2 个独立的 peer 成员",这是错的。
- Coordinator 永远是 lead session 本身,靠 role-doc 自绑定实现角色切换。
- 这个拓扑结构无法改写成 peer —— Claude Code 框架层面就不支持。
- **v0.2.9 implication**: role docs 必须反映 hub-spoke 现实;"coordinator 角色"是一种 self-binding pattern,不是一个独立的 teammate。

### Finding 6 — Observation channel confounders

两层证据:
- **(a) 用户侧**: 用户的远程桌面客户端在 **本地** 拦截 Cmd+Tab,根本到不了远端显示。即使 tester 的 AppleScript ⌘-Tab 注入完全成功,人类观察者也看不到任何焦点变化。
- **(b) 进程侧**: in-process teammate backend 与 lead 共享 OS 级权限状态(见 Finding 9)。

两条一起证明:"机器截图"和"人类观察者"两种 fallback 都有 observation channel 依赖。
- **v0.2.9 implication**: 验证信号必须能穿过 observation channel。优先采用 UI 事件触发的文件写、log entry 等带外证据,优先级高于视觉捕获。

### Finding 7 — Persisted prompts become stale context bombs

(NEW,取代早前 "Agent-vs-SendMessage ambiguity" 的提法)

- 用 `Agent` 工具 spawn 时,完整的 initial prompt(role doc + task payload)以 verbatim 形式持久化到 `config.json`。
- 这段 prompt 把**当轮特定上下文**全部冻结: 文件路径、PID、round ID、硬约束。
- 具体证据: tester-2 的 config.json 持久化 prompt 里仍然写着 `"The app is ALREADY RUNNING (PID 74941). Do NOT re-launch it."`,但 PID 74941 在 Step H 已被 quit —— 任何未来用 `SendMessage` 唤醒 tester-2 的尝试,都会把它置于一个事实上过期的上下文里。
- 之前担心的 "Agent 还是 SendMessage 是该用哪个"的 ambiguity,**其实是框架的正确使用模式**:
  - `SendMessage` wake = 在旧上下文上叠加新消息 → 任务类型不变时正确
  - `Agent` respawn = 全新 initial prompt → 任务语义改变时正确
- **v0.2.9 implications**:
  - role docs 必须把"可复用的角色身份 prompt"和"一次性任务 payload"分离
  - Agent spawn 理想状态:用 `system_prompt` 承载 role,用 first message 承载 task,而非拼成一个大 prompt
  - ClaudeSessionHub 作为 session 工具,可以在 `config.json` 的 persisted prompt 过了 idle 时间后,自动 flag 其中的过期信号(PID 引用、时间戳、round ID)

### Finding 8 — Model flag asymmetry: lead has [1m], spokes get standard

(NEW)

- config.json 里 team-lead 条目显示 `"model": "claude-opus-4-6[1m]"`(1M 扩展上下文)
- 两个 spawn 出来的 tester 条目都显示 `"model": "claude-opus-4-6"`(标准 ~200k 上下文)
- **`Agent` 工具不会传播宿主 session 的 model flag**
- Stage 1 假设 tester 和 lead 有同等能力 —— 事实上错的
- 对 Tester / Reviewer 这类需要大量阅读(diff / spec / fixture / trace)的角色,spokes 可能在没有可见错误的情况下静默 context-starve
- **v0.2.9 implications**:
  - Agent spawn 必须显式指定 model flag,不能依赖默认
  - role docs 应声明"最低模型能力要求"
  - 未来 role doc 模板加字段: `requires_extended_context: true/false`

### Finding 9 — In-process backend → shared OS-level state → sandbox isolation assumption fails

(NEW)

- 两个 spawn 出来的 tester 条目都显示 `"backendType": "in-process"`,`"tmuxPaneId": "in-process"`
- 没有独立进程、没有独立 tmux pane —— teammate 就在 lead 的 Claude Code 进程内部跑
- **后果**: TCC 权限状态、display pipeline 状态、process-tree 级 OS 状态 **全部共享**。
- 这就是为什么 Finding 4 的 phantom 冻结帧**同时影响**coordinator 的 probe 和所有 tester 的截图 —— 它们是同一棵 TCC 进程树。
- Stage 1 "每个 teammate 有独立执行上下文" 的假设只有部分正确:独立的是 Claude Code 对话窗口,**零的是 OS 级隔离**。
- **v0.2.9 implications**:
  - coordinator-role.md / tester-role.md 里 "sandbox isolation" 的措辞是误导性的 —— 没有 OS 级隔离
  - 若要实现真沙箱(例如"tester 的失败不得影响 lead"),必须强制 out-of-process backend:独立 tmux pane / 子进程 / 另起 Claude Code session
  - 一个值得在 v0.2.9 跑的验证实验:把 `tmuxPaneId` 强制设为真实 pane,观察 `screencapture` 是否 un-pin —— 如果 un-pin,就证实了 in-process TCC 共享假说

### Positive Finding — AppleScript event delivery works cross-mechanism

(保留自早前 draft)

- 经用户直接观察确认: Settings 打开(⌘,)、Settings 关闭(⌘W)、app 退出(tell app to quit)全部生效
- 3 种独立的 AppleScript 原语全部确认命中目标 app
- **这是跨机制一致性证据,不是单点 anecdotal**
- v0.2.9 可以在以下前提下信任 `execute_script` + AppleScript 做事件注入:
  - 观察走非视觉通道(log 文件、文件 mtime、应用状态查询),或
  - Finding 4 的 phantom 截图 bug 被先解决

---

### Coordinator self-assessment(accept-decision.md 摘录)

coordinator 在 accept-decision.md 里标记了 6 项 role-doc ambiguity。原始原文列表:

1. **Re-dispatch semantics** — coordinator 当时不确定 `Agent(team_name, name)`(会 auto-rename)还是 `SendMessage(to)`(唤醒 idle) 是 canonical 方式。
   - **Reclassified**: framework behavior, not ambiguity. 见 Finding 7 —— 这不是 role doc 的空缺,是框架的正确使用模式(任务语义变了用 Agent, 不变用 SendMessage)。
2. **Process cleanup scope** — 当前规则禁止 coordinator 杀进程,但 β run 需要杀 orphan app 才能进。需在 role doc 里明确"post-blocker 清理 tester-launched 进程是允许的"。
3. **git add authorization** — 协调者是否能自己 stage 验证产物,当前规则不清。
4. **Subjective-evidence upgrade pathway** — REJECT 被人类观察 upgrade 成 YELLOW 的路径存在但未写进 role doc,依赖 coordinator 临场解释。
5. **Do-not-play-tester vs validate-cleanup gray zone** — coordinator 自跑 `pgrep` / `pkill` 验证是否越界?
6. **Report.md write blocked by subagent runtime** — tester-role.md 说要写 report.md,但 subagent 运行时拒绝。已在 accept-decision.md 里建议改为"team message 为主,文件为辅"。

---

### Post-hoc validation tags

基于 Appendix B 的发现,回过头更新主正文里的 [推测] / [事实] 标签:

- **Path A: 从 [推测] 升级为 [事实]** —— 本 reflection 的作者 session(辅助 agent)经用户在 session 末期的明确披露,确认自己就是被 ClaudeSessionHub restart 恢复出来的一个 Path A 案例。写这份 reflection 的 session 本身就是一个 Path A observation subject。
- **Path B 的 "author flattening" 症状: 仍是 [推测 - 未测试]** —— 主 agent 的 calibration check 只跑了 date / git / filesystem 读取,没有具体问 "Phase 4/7/10 是你做的还是你见证 team 做的";authorship attribution 假说没有被正面验证过。
- **Path C 的 "replay anchor at stale Stage 2 末尾": 从 [推测] 升级为 [事实]** —— Phase 10 和 Phase 12 早期的 team session stale state 直接坐实:被恢复的 team session 锚定在 Stage 2 收尾处,对之后 6 轮工作完全无感知。
- **"Capability loss during restart": 从 [推测] 升级为 [事实]** —— 2026-04-14 的实地 probe 证实重启后第一个 team session 里 `TeamCreate` / `SendMessage` / `TeamDelete` MCP 工具全部缺失,只有显式设置 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 后启动新终端才能恢复。这是 Path C capability 丢失机制的直接证据。
