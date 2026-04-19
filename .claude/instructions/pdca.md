# PDCA 编码工作流

本项目对所有非简单的编码任务强制执行 **PDCA（计划-执行-检查-处理）** 循环。核心原则：**计划阶段统一规划所有子任务，执行阶段按子任务逐个走完 Do-Check-Act 后再进入下一个**。

## 何时使用 PDCA

**需要使用 PDCA 的场景：**
- 涉及 3 个以上文件修改的任务
- 需要做出架构决策的任务
- 功能实现、Bug 修复、代码重构
- 任何对正确性有要求的任务

**无需使用 PDCA 的场景：**
- 关于代码库的简单提问
- 单行修复（拼写错误、变量重命名）
- 仅阅读/浏览代码而不做修改
- 快速的一次性命令

## 状态管理

全局状态在 `.claude/pdca/state.json`，其中 `cycle_dir` 字段指向当前周期的工作目录。每个周期的文件独立存放在编号文件夹中（如 `.claude/pdca/003-用户登录/`），互不覆盖。

```bash
bash .claude/scripts/pdca.sh <命令>
```

可用命令：`init "<任务>"`、`transition <阶段>`、`step "<描述>"`、`status`、`history`、`reset`

## 整体流程

```
阶段 1：计划（Plan） — 主 Agent，规划所有子任务
        ↓
阶段 2-4：按子任务循环 — 每个子任务独立走完 Do → Check → Act
        ├── 子任务 1: Do → Check → Act(PASS) ──→ 继续
        ├── 子任务 2: Do → Check → Act(FAIL) ──→ 重做子任务 2
        ├── 子任务 2: Do → Check → Act(PASS) ──→ 继续
        ├── 子任务 3: Do → Check → Act(PASS) ──→ 继续
        └── 全部通过 → COMPLETED
```

---

## 阶段 1：计划 PLAN（主 Agent）

**执行者：** 主 Agent

**操作步骤：**
1. 运行 `bash .claude/scripts/pdca.sh init "<任务描述>"` 启动周期
2. 分析需求，探索代码库，评估影响范围
3. **将任务拆分为多个子任务**，每个子任务：
   - 描述的是**需求**（要达到什么效果），而非实现细节
   - 有 **可量化的验收标准**（能用"是/否"或具体数值判定）
4. 写入 `{cycle_dir}/plan.md`（路径由 `state.json` 的 `cycle_dir` 指定），结构：
   ```
   ### 子任务 N：<名称>
   - **需求描述：**<要达到什么效果>
   - **验收标准（可量化）：**
     - [ ] <具体条件>
   ```
5. 更新 `state.json`：设置 `total_subtasks` 为子任务总数，`current_subtask` 为 1
6. 运行 `bash .claude/scripts/pdca.sh step "计划完成：N 个子任务已拆分"`
7. 运行 `bash .claude/scripts/pdca.sh transition PLANNED`

---

## 阶段 2-4：按子任务循环 Do-Check-Act

以下三个步骤**对每个子任务重复执行**，当前子任务通过后才进入下一个。

### 2.1 执行 DO — 当前子任务（子代理）

**执行者：** 全新的 `general-purpose` 子代理

**调用方式：**
```
Agent({
  description: "PDCA-DO: 子任务 <N>",
  subagent_type: "general-purpose",
  prompt: <.claude/pdca/prompts/do-prompt.md 的内容>
})
```

**子代理行为：**
1. 读 `state.json` 获取 `cycle_dir`（工作目录）和 `current_subtask` 编号
2. 读 `{cycle_dir}/plan.md` 获取该子任务的**需求和验收标准**
3. 探索代码库，确定实现方案
4. 实施变更
5. 将结果追加到 `{cycle_dir}/do.md`（仅当前子任务的段落）
6. 运行 `pdca.sh step "子任务 N: <名称> 完成"`
7. 更新 `state.json`：`phase` → `"DONE"`

**主 Agent 在 Do 子代理完成后：**
- 读 `{cycle_dir}/do.md` 确认当前子任务完成
- 运行 `transition CHECKING` 进入检查

---

### 2.2 检查 CHECK — 当前子任务（不同子代理）

**执行者：** 另一个独立的 `general-purpose` 子代理

**调用方式：**
```
Agent({
  description: "PDCA-CHECK: 子任务 <N>",
  subagent_type: "general-purpose",
  prompt: <.claude/pdca/prompts/check-prompt.md 的内容>
})
```

**子代理行为：**
1. 读 `state.json` 获取 `cycle_dir` 和 `current_subtask`
2. 读 `{cycle_dir}/plan.md` 获取该子任务的量化验收标准
3. 读 `{cycle_dir}/do.md` 中该子任务的实现记录
4. **逐条验证验收标准**，给出 ✅/❌ 及具体证据
5. 将结果追加到 `{cycle_dir}/check.md`（仅当前子任务的段落）
6. 为当前子任务评级：PASS / FAIL / PARTIAL
7. 运行 `pdca.sh step "检查完成：子任务 N <PASS/FAIL>"`
8. 更新 `state.json`：`phase` → `"CHECKED"`

**主 Agent 在 Check 子代理完成后：**
- 读 `{cycle_dir}/check.md` 获取当前子任务的审查结论
- 运行 `transition ACTING` 进入处理

---

### 2.3 处理 ACT — 当前子任务（主 Agent）

**执行者：** 主 Agent

**操作步骤：**
1. 读 `{cycle_dir}/check.md` 中当前子任务的审查结论
2. 做出决策：

   **PASS：**
   - 在 `{cycle_dir}/act.md` 追加：子任务 N ✅ 通过
   - 更新 `state.json`：在 `subtask_results` 中记录 `{"index": N, "status": "PASS"}`
   - 递增 `current_subtask`
   - 如果 `current_subtask > total_subtasks`：
     - 运行 `pdca.sh step "全部子任务通过，周期完成"`
     - 运行 `pdca.sh transition COMPLETED`
   - 否则：
     - 运行 `pdca.sh step "子任务 N 通过，进入子任务 N+1"`
     - 运行 `pdca.sh transition DOING`（开始下一个子任务）

   **FAIL / PARTIAL（需修正）：**
   - 在 `{cycle_dir}/act.md` 追加：子任务 N ❌ 未通过，原因 + 纠正方向
   - 更新 `state.json`：在 `subtask_results` 中记录 `{"index": N, "status": "FAIL"}`
   - **不递增** `current_subtask`（重做同一个）
   - 运行 `pdca.sh step "子任务 N 未通过，重新执行"`
   - 运行 `pdca.sh transition DOING`（重新开始该子任务）

---

## 文件结构

```
.claude/pdca/
├── state.json                         ← 全局状态（cycle_dir 指向当前周期目录）
├── history/
│   └── log.md                         ← 所有周期的摘要日志
├── 001-用户注册/                       ← 周期 1 的独立文件夹
│   ├── plan.md
│   ├── do.md
│   ├── check.md
│   └── act.md
├── 002-登录功能/                       ← 周期 2 的独立文件夹
│   ├── plan.md
│   ├── do.md
│   ├── check.md
│   └── act.md
└── ...                                 ← 新周期自动递增编号
```

`{cycle_dir}` 是 `state.json` 中的字段，指向当前活跃周期的文件夹路径。所有子代理通过读取 `state.json` 获取此路径，不硬编码。

## 状态流转

```
IDLE → PLANNING → PLANNED
  ┌──────────────────────────────────────────────────┐
  │ → DOING(子任务1) → DONE → CHECKING → CHECKED → ACTING
  │     ↑                                    │
  │     │ ← FAIL（重做同一子任务）←──────────┘
  │     │ ← PASS（下一子任务）──────────────→ DOING(子任务2) → ...
  └──────────────────────────────────────────────────┘
                                                → COMPLETED（全部通过）
```

## 规则

- **计划阶段统一拆分，执行阶段逐个子任务走完 Do-Check-Act**
- **子代理之间绝不共享上下文**，仅通过文件传递信息
- **验收标准必须可量化**，每条标准能用"是/否"判定
- **每步必记录**：`pdca.sh step` 跟踪每个子任务的每步进展
- **执行代理自行决定实现方式**，计划只描述需求
- **检查代理必须读实际源码**，逐条核对量化验收标准
