# 状态反馈速记

这页只回答一个问题：当前系统出了结果以后，应该去哪里看。

## 1. 先看状态栏

输入法候选框底部状态栏是第一出口。

适合在这里看的信息：

- 复制或回贴是否成功
- 当前输入是前缀等待、反查命中还是运行时未找到
- 加入用户词库、删除用户词库是否成功
- seed 用户词库在启动时是否已导入、已跳过或为空
- 选中候选后，调序频率是否已经记住

当前状态栏里有两个直接可识别的前缀：

- `反查:` 表示当前显示的是汉字字词反查路径的结果
- `解码:` 表示当前显示的是按编码解码路径得到的结果

其中 `解码:` 下面目前优先收敛成几种稳定短句：

- `解码: 前缀等待，继续输入。`
- `解码: 前缀等待，可先选单字，继续输入可收窄结果。`
- `解码: 已找到候选。`
- `解码: 当前编码未找到候选。`

调序当前有一条最小提示策略：

- 选中候选后，如果持久调序频率已写入，状态栏会显示：
  `调序已记录：<候选>（累计 N 次）。如需追查请用 diagnose_candidate_order.py。`

原则：

- 只要是当前这次操作的直接结果，先写状态栏
- 状态栏文案尽量直接包含“动作 + 对象 + 结果”

## 2. 再看弹窗

弹窗只用于需要用户明确注意的场景。

当前主要包括：

- 加入用户词库成功或失败
- 从用户词库删除成功或失败
- 输入不合法、无法推导音元编码等需要立刻改正的情况

原则：

- 能只靠状态栏说明的，不额外弹窗
- 需要用户停下来确认或修正输入的，再弹窗

## 3. 查长期状态看脚本

如果你问的不是“刚才成功了没”，而是“系统长期记住了什么”，不要只看状态栏，要直接查脚本输出。

常用入口：

- `python tools/query_phrase_code.py 日本`
  用来看词条是否存在、编码是什么、`persisted_reorder_frequency` 是多少
- `python tools/manage_user_lexicon.py list-recent --limit 20`
  用来看最近补进或更新了哪些 `user_phrase_entries`
- `python tools/manage_user_lexicon.py list-freq --limit 20`
  用来看哪些候选已经积累了 `persisted_reorder_frequency`
- `python tools/diagnose_candidate_order.py --numeric-pinyin "ri4 ben3" --limit 10`
  用来看某组候选为什么这样排序；关键字段会直接显示 `candidate_text` 和 `persisted_reorder_frequency`

## 4. 安装包相关看验收脚本

如果问题是“安装包首次启动时 seed 有没有自动落进去”，直接运行：

```bash
python tools/verify_seed_install_flow.py
```

它会模拟安装目录并给出三类结果：

- 没有 `user_lexicon.db` 时能否导入
- 只有空库时能否导入
- 第二次启动时是否会重复导入

CLI 结果字段现在也尽量复用同一套词：

- 用户词库路径统一叫 `user_lexicon_db`
- 用户词条数量统一叫 `user_phrase_entries`
- 持久调序频率统一叫 `persisted_reorder_frequency`
- 候选文本统一叫 `candidate_text`
- seed 安装验收统一看 `acceptance_result`、`scenario`、`seed_import_state`

## 5. 以后继续做什么

当前最优先不是再增加一个新的提示渠道，而是继续统一现有三层：

1. 状态栏负责本次操作结果
2. 弹窗负责必须注意的成功/失败与输入错误
3. 脚本负责长期状态、排序原因和安装验收
