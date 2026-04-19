# AI-Test 项目

基于 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的 PDCA 编码工作流实验项目。

## 编码工作流

本项目使用 PDCA（计划-执行-检查-处理）循环管理非简单的编码任务，详细规则见 [.claude/instructions/pdca.md](.claude/instructions/pdca.md)。

## 项目结构

```
CLAUDE.md                        # 项目基础信息（本文件）
README.md                        # 项目说明文档
.claude/
├── instructions/
│   └── pdca.md                  # PDCA 工作流详细规则
├── settings.json                # Hook 配置
├── settings.local.json          # 本地权限配置
├── scripts/
│   └── pdca.sh                  # PDCA 状态管理脚本
└── pdca/
    ├── state.json               # 全局状态
    ├── history/
    │   └── log.md               # 历史周期日志
    ├── prompts/
    │   ├── do-prompt.md         # 执行阶段提示词
    │   ├── check-prompt.md      # 检查阶段提示词
    │   └── act-prompt.md        # 处理阶段提示词
    └── <NNN>-<任务名>/           # 周期工作目录（自动创建）
```

## 前置要求

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)（CLI 或 IDE 扩展）
- Bash 环境
