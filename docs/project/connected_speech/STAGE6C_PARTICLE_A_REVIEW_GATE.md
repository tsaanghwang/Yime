# 阶段 6C：语气词“啊”首批人工复核门禁

阶段 6C 从阶段 6B 的 6,657 条显式记录中，按六类各选 5 条高频且较自然的短语，共 30 条，建立
小批量持久化复核入口。机器快照、来源说明和人工判决分别保存，不能相互覆盖：

- [首批复核清单](particle_a_stage6c_review.tsv)；
- [来源与局限](particle_a_stage6c_sources.tsv)；
- [人工判决表](particle_a_stage6c_decisions.tsv)。

当前 30 条全部为 `pending_human_review / not_approved`，人工判决表只有表头。复核门禁会先刷新阶段
6B，再逐条核对文字、规范与条件读法、类别、记录 ID、权重以及三模式投影。六类必须各有 5 条，
每条三模式均只能替换 `a5` 的首音位置且码长增量必须为 0。

其中 `PA-NG` 的 5 条单列为 `semantic_only_shared_key`：N26 与 N12 共用 `'`，所以音元语义变化，
物理输入码不变，不能把它们统计为新增输入别名。其余 25 条为 `input_alias_key_change`，三模式物理码
都必须与规范路径不同。

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-stage6c-particle-a-review.ps1
```

当前结果为：复核项 30、匹配 30、待人工复核 30、共键语义样本 5、键码变化样本 25、三模式投影
90、未决 0、运行时别名 0。只有项目负责人逐条写入人工判决后，才能讨论下一阶段的小规模运行时
试点；批准项也必须使用 `parallel_alias_keep_canonical`，不得替换规范输入路径。
