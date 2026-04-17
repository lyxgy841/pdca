# AI-Test

基于 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的 PDCA（计划-执行-检查-处理）编码工作流实验项目。

## 概述

本项目探索如何利用 Claude Code 的 Agent SDK 子代理机制，将经典 PDCA 质量管理循环应用于 AI 辅助编码任务。通过将计划、执行、检查、处理四个阶段分配给不同的 Agent 角色，实现：

- **主 Agent** 负责任务规划和最终决策
- **执行 Agent（Do）** 独立实施子任务
- **检查 Agent（Check）** 独立验证验收标准
- Agent 之间仅通过文件系统传递信息，不共享上下文

## 工作流程

```
Plan（主 Agent）
  ├── 拆分任务为子任务，定义量化验收标准
  │
  └── 逐个子任务循环 ──→ Do（执行 Agent）→ Check（检查 Agent）→ Act（主 Agent）
                                                    │
                                              PASS → 下一子任务
                                              FAIL → 重做当前子任务
```

## 项目结构

```
CLAUDE.md                    # Claude Code 项目指令（PDCA 工作流规范）
.claude/
├── settings.json            # Hook 配置（PrePromptSubmit / Stop）
├── settings.local.json      # 本地权限配置
├── scripts/
│   └── pdca.sh              # PDCA 状态管理脚本
└── pdca/
    ├── state.json           # 全局状态（当前周期、阶段、子任务进度）
    ├── history/
    │   └── log.md           # 历史周期摘要日志
    ├── prompts/
    │   ├── do-prompt.md     # 执行阶段 Agent 提示词
    │   ├── check-prompt.md  # 检查阶段 Agent 提示词
    │   └── act-prompt.md    # 处理阶段 Agent 提示词
    └── <NNN>-<任务名>/      # 每个周期自动创建的独立文件夹
        ├── plan.md          # 计划（含子任务和验收标准）
        ├── do.md            # 执行日志
        ├── check.md         # 检查报告
        └── act.md           # 处理决策
```

## 状态管理脚本

通过 `bash .claude/scripts/pdca.sh` 操作：

| 命令 | 说明 |
|------|------|
| `init "<任务>"` | 初始化新 PDCA 周期 |
| `transition <阶段>` | 切换阶段 |
| `step "<描述>"` | 记录完成的步骤 |
| `status` | 查看当前详细状态 |
| `history` | 查看历史日志 |
| `reset` | 重置为空闲状态 |

## 阶段流转

```
IDLE → PLANNING → PLANNED → DOING → DONE → CHECKING → CHECKED → ACTING
                                            ↑                         │
                                            └── FAIL（重做） ─────────┘
                                                                       → COMPLETED
```

## 前置要求

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)（CLI 或 IDE 扩展）
- Python 3（状态脚本依赖）
- Bash 环境

## 快速开始

1. 使用 Claude Code 打开本项目
2. 给出一个编码任务（如"实现用户登录功能"）
3. Claude Code 将自动按照 PDCA 流程执行：拆分子任务 → 逐个执行 → 检查 → 决策

> 详细的流程规范见 [CLAUDE.md](CLAUDE.md)。
