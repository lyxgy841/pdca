#!/usr/bin/env bash
# PDCA 循环管理脚本
# 用法：bash .claude/scripts/pdca.sh <命令> [参数]
set -euo pipefail

# 确保 Python 输出使用 UTF-8 编码
export PYTHONIOENCODING=utf-8

PDCA_DIR=".claude/pdca"
STATE_FILE="$PDCA_DIR/state.json"
HISTORY_DIR="$PDCA_DIR/history"
HISTORY_LOG="$PDCA_DIR/history/log.md"

PYTHON="python"

# --- 工具函数 ---

pdca_read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"phase":"IDLE","task":"","cycle_id":"","cycle_dir":"","started_at":"","current_phase_started_at":"","current_subtask":0,"total_subtasks":0,"subtask_results":[],"steps_completed":[],"phase_history":[]}'
    fi
}

get_cycle_dir() {
    $PYTHON -c "import json,sys; print(json.load(sys.stdin).get('cycle_dir',''))" < "$STATE_FILE" 2>/dev/null || echo ""
}

# 清理任务名用于文件夹名：保留中文、字母、数字，其余替换为短横线，截断30字符
sanitize_dirname() {
    local name="$1"
    # 替换文件系统不安全字符为短横线
    name=$(echo "$name" | sed 's/[\/\\:*?"<>| ,.]/-/g' | sed 's/--*/-/g')
    # 截断到30字符
    name=$(echo "$name" | cut -c1-30)
    # 去掉首尾短横线
    name=$(echo "$name" | sed 's/^-*//' | sed 's/-*$//')
    echo "$name"
}

# 扫描已有编号文件夹，返回下一个编号（3位补零）
next_cycle_number() {
    local max=0
    if [[ -d "$PDCA_DIR" ]]; then
        for dir in "$PDCA_DIR"/[0-9][0-9][0-9]-*; do
            if [[ -d "$dir" ]]; then
                local num
                num=$(basename "$dir" | cut -c1-3)
                num=$((10#$num))
                if [[ $num -gt $max ]]; then
                    max=$num
                fi
            fi
        done
    fi
    printf "%03d" $((max + 1))
}

# --- 命令函数 ---

cmd_context() {
    local state
    state=$(pdca_read_state)
    local phase task cycle_id current_st total_st passed cycle_dir
    phase=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('phase','IDLE'))" <<< "$state" 2>/dev/null || echo "IDLE")

    if [[ "$phase" == "IDLE" ]]; then
        echo "[PDCA] 状态：空闲。无活跃周期。"
        return
    fi

    task=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('task','')[:60])" <<< "$state" 2>/dev/null || echo "")
    cycle_id=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('cycle_id',''))" <<< "$state" 2>/dev/null || echo "")
    current_st=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_subtask',0))" <<< "$state" 2>/dev/null || echo "0")
    total_st=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_subtasks',0))" <<< "$state" 2>/dev/null || echo "0")
    passed=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for r in d.get('subtask_results',[]) if r.get('status')=='PASS'))" <<< "$state" 2>/dev/null || echo "0")
    cycle_dir=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('cycle_dir',''))" <<< "$state" 2>/dev/null || echo "")

    local phase_label="?"
    case "$phase" in
        PLANNING) phase_label="1(计划)" ;;
        PLANNED)  phase_label="1(计划)->2(执行)" ;;
        DOING)    phase_label="2(执行)" ;;
        DONE)     phase_label="2(执行)->3(检查)" ;;
        CHECKING) phase_label="3(检查)" ;;
        CHECKED)  phase_label="3(检查)->4(处理)" ;;
        ACTING)   phase_label="4(处理)" ;;
    esac

    echo "[PDCA] 阶段：$phase [$phase_label] | 任务：$task | 子任务：$current_st/$total_st（通过：$passed）"
    echo "[PDCA] 目录：$cycle_dir/"
}

cmd_init() {
    local task="${1:-未命名任务}"
    local cycle_id
    cycle_id=$(date -u +"%Y%m%d%H%M%S")
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 创建编号文件夹
    local num
    num=$(next_cycle_number)
    local safe_name
    safe_name=$(sanitize_dirname "$task")
    local cycle_dir="$PDCA_DIR/${num}-${safe_name}"
    mkdir -p "$cycle_dir"

    # 写入状态（cycle_dir 指向当前周期的文件夹）
    $PYTHON -c "
import json
state = {
    'phase': 'PLANNING',
    'task': '''$task''',
    'cycle_id': '$cycle_id',
    'cycle_dir': '''$cycle_dir''',
    'started_at': '$now',
    'current_phase_started_at': '$now',
    'current_subtask': 0,
    'total_subtasks': 0,
    'subtask_results': [],
    'steps_completed': [],
    'phase_history': [
        {'phase': 'PLANNING', 'entered_at': '$now', 'exited_at': None}
    ]
}
with open('$STATE_FILE', 'w', encoding='utf-8') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
"

    # 在周期文件夹内初始化各阶段输出文件
    cat > "$cycle_dir/plan.md" << TEMPLATE
# 计划 — $task

## 任务描述
<!-- 在此描述总体任务目标 -->

## 分析
<!-- 需求分析、约束条件、依赖关系 -->

## 子任务列表

### 子任务 1：<名称>
- **需求描述：**<要达到什么效果，解决什么问题>
- **验收标准（可量化）：**
  - [ ] <具体可度量的条件 1>
  - [ ] <具体可度量的条件 2>

### 子任务 2：<名称>
- **需求描述：**<要达到什么效果，解决什么问题>
- **验收标准（可量化）：**
  - [ ] <具体可度量的条件>
  - [ ] <具体可度量的条件>

### 子任务 3：<名称>
- **需求描述：**<要达到什么效果，解决什么问题>
- **验收标准（可量化）：**
  - [ ] <具体可度量的条件>

## 架构决策
<!-- 关键决策及其理由 -->

---
*阶段转换记录将在下方自动追加。*
TEMPLATE

    cat > "$cycle_dir/do.md" << 'TEMPLATE'
# 执行日志

<!-- 每个子任务的执行记录按顺序累积追加 -->

## 遇到的问题
<!-- 任何阻碍或偏离需求的情况记录在此 -->
TEMPLATE

    cat > "$cycle_dir/check.md" << 'TEMPLATE'
# 检查报告

<!-- 每个子任务的检查结果按顺序累积追加 -->
TEMPLATE

    cat > "$cycle_dir/act.md" << 'TEMPLATE'
# 处理总结

<!-- 每个子任务的处理决策按顺序累积追加 -->

## 子任务汇总

| 子任务 | 结果 | 轮次 | 备注 |
|--------|------|------|------|
TEMPLATE

    mkdir -p "$HISTORY_DIR"
    if [[ ! -f "$HISTORY_LOG" ]]; then
        echo "# PDCA 历史日志" > "$HISTORY_LOG"
        echo "" >> "$HISTORY_LOG"
        echo "> 每次会话结束时自动追加记录。" >> "$HISTORY_LOG"
        echo "" >> "$HISTORY_LOG"
    fi

    echo "PDCA 周期已初始化：$cycle_id"
    echo "任务：$task"
    echo "目录：$cycle_dir/"
    echo "阶段：PLANNING（计划）"
}

cmd_transition() {
    local new_phase="${1:?用法：pdca.sh transition <阶段>}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local cycle_dir
    cycle_dir=$(get_cycle_dir)

    $PYTHON -c "
import json, sys

with open('$STATE_FILE', 'r', encoding='utf-8') as f:
    state = json.load(f)

old_phase = state['phase']

for entry in reversed(state.get('phase_history', [])):
    if entry['exited_at'] is None:
        entry['exited_at'] = '$now'
        break

state['phase_history'].append({
    'phase': '$new_phase',
    'entered_at': '$now',
    'exited_at': None
})

state['phase'] = '$new_phase'
state['current_phase_started_at'] = '$now'

with open('$STATE_FILE', 'w', encoding='utf-8') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)

print(f'阶段转换：{old_phase} -> $new_phase 于 $now')
"

    if [[ -n "$cycle_dir" && -f "$cycle_dir/plan.md" ]]; then
        echo "" >> "$cycle_dir/plan.md"
        echo "---" >> "$cycle_dir/plan.md"
        echo "阶段转换至 $new_phase 于 $now" >> "$cycle_dir/plan.md"
    fi
}

cmd_step() {
    local description="${1:?用法：pdca.sh step <描述>}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    $PYTHON -c "
import json

with open('$STATE_FILE', 'r', encoding='utf-8') as f:
    state = json.load(f)

state.setdefault('steps_completed', []).append({
    'description': '''$description''',
    'completed_at': '$now',
    'phase': state['phase'],
    'subtask': state.get('current_subtask', 0)
})

with open('$STATE_FILE', 'w', encoding='utf-8') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)

print(f'步骤已记录：$description [$now]')
"
}

cmd_record_stop() {
    local state
    state=$(pdca_read_state)
    local phase cycle_id now task current_st total_st cycle_dir
    phase=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('phase','IDLE'))" <<< "$state" 2>/dev/null || echo "IDLE")

    if [[ "$phase" == "IDLE" ]]; then
        return
    fi

    cycle_id=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('cycle_id',''))" <<< "$state" 2>/dev/null || echo "unknown")
    task=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('task',''))" <<< "$state" 2>/dev/null || echo "")
    cycle_dir=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('cycle_dir',''))" <<< "$state" 2>/dev/null || echo "")
    current_st=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_subtask',0))" <<< "$state" 2>/dev/null || echo "0")
    total_st=$($PYTHON -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_subtasks',0))" <<< "$state" 2>/dev/null || echo "0")
    now=$(date -u +"%Y%m%dT%H%M%SZ")

    # 在周期文件夹内保存快照
    if [[ -n "$cycle_dir" ]]; then
        mkdir -p "$cycle_dir"
        echo "$state" > "$cycle_dir/state-snapshot-${phase}_${now}.json"
    fi

    # 全局历史也保留一份
    echo "$state" > "$HISTORY_DIR/${cycle_id}_${phase}_${now}.json"

    local steps_summary
    steps_summary=$($PYTHON -c "
import json, sys
d = json.load(sys.stdin)
steps = d.get('steps_completed', [])
if not steps:
    print('  无已完成步骤')
else:
    for s in steps:
        st = s.get('subtask', 0)
        label = f'[子任务{st}]' if st > 0 else ''
        print(f'  - [{s.get(\"phase\",\"?\")}] {label} {s.get(\"description\",\"\")}')
" <<< "$state" 2>/dev/null)

    local now_readable
    now_readable=$(date -u +"%Y-%m-%d %H:%M UTC")

    {
        echo "### $now_readable — 周期 $cycle_id"
        echo "**任务：**$task"
        echo "**目录：**$cycle_dir/"
        echo "**停留阶段：**$phase | **子任务进度：**$current_st/$total_st"
        echo "**已完成步骤：**"
        echo "$steps_summary"
        echo ""
    } >> "$HISTORY_LOG"

    echo "会话已记录：$cycle_dir/"
    echo "摘要已追加到：$HISTORY_LOG"
}

cmd_status() {
    local state
    state=$(pdca_read_state)
    $PYTHON -c "
import json, sys
d = json.load(sys.stdin)
print('=== PDCA 状态 ===')
print(f'阶段：{d.get(\"phase\", \"IDLE\")}')
print(f'任务：{d.get(\"task\", \"\")}')
print(f'周期编号：{d.get(\"cycle_id\", \"\")}')
print(f'周期目录：{d.get(\"cycle_dir\", \"\")}')
print(f'启动时间：{d.get(\"started_at\", \"\")}')
print(f'当前子任务：{d.get(\"current_subtask\", 0)} / {d.get(\"total_subtasks\", 0)}')
results = d.get('subtask_results', [])
if results:
    print('子任务结果：')
    for r in results:
        print(f'  - 子任务 {r.get(\"index\",\"?\")}: {r.get(\"status\",\"?\")} (第{r.get(\"iterations\",\"?\")}轮)')
print(f'已完成步骤：{len(d.get(\"steps_completed\", []))}')
for s in d.get('steps_completed', []):
    st = s.get('subtask', 0)
    label = f'[子任务{st}]' if st > 0 else ''
    print(f'  - [{s.get(\"phase\",\"?\")}] {label} {s.get(\"description\",\"\")} 于 {s.get(\"completed_at\",\"\")}')
print('阶段历史：')
for h in d.get('phase_history', []):
    print(f'  - {h.get(\"phase\")}：{h.get(\"entered_at\")} -> {h.get(\"exited_at\", \"进行中\")}')
" <<< "$state"
}

cmd_history() {
    if [[ -f "$HISTORY_LOG" ]]; then
        cat "$HISTORY_LOG"
    else
        echo "暂无历史记录。"
    fi
}

cmd_reset() {
    $PYTHON -c "
import json
state = {
    'phase': 'IDLE',
    'task': '',
    'cycle_id': '',
    'cycle_dir': '',
    'started_at': '',
    'current_phase_started_at': '',
    'current_subtask': 0,
    'total_subtasks': 0,
    'subtask_results': [],
    'steps_completed': [],
    'phase_history': []
}
with open('$STATE_FILE', 'w', encoding='utf-8') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
print('PDCA 周期已重置为空闲状态')
"
}

case "${1:-context}" in
    context)        cmd_context ;;
    init)           cmd_init "${2:-}" ;;
    transition)     cmd_transition "${2:-}" ;;
    step)           shift; cmd_step "$*" ;;
    record-stop)    cmd_record_stop ;;
    status)         cmd_status ;;
    history)        cmd_history ;;
    reset)          cmd_reset ;;
    *)
        echo "用法：bash .claude/scripts/pdca.sh <命令> [参数]"
        echo "命令："
        echo "  context              显示当前 PDCA 状态（用于钩子）"
        echo "  init <任务>          初始化新的 PDCA 周期（自动创建编号文件夹）"
        echo "  transition <阶段>    转换到新阶段"
        echo "  step <描述>          记录一个已完成的步骤"
        echo "  record-stop          记录会话摘要（用于 Stop 钩子）"
        echo "  status               显示详细状态（含子任务进度）"
        echo "  history              显示历史日志"
        echo "  reset                重置为空闲状态（不删除已有文件夹）"
        exit 1
        ;;
esac
