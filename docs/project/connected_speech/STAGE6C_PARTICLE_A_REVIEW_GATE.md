# 阶段 6C：语气词“啊”首批人工复核门禁

阶段 6C 从阶段 6B 的 6,657 条显式记录中，按六类各选 5 条高频且较自然的短语，共 30 条，建立
小批量持久化复核入口。机器快照、来源说明和人工判决分别保存，不能相互覆盖：

- [首批复核清单](particle_a_stage6c_review.tsv)；
- [来源与局限](particle_a_stage6c_sources.tsv)；
- [人工判决表](particle_a_stage6c_decisions.tsv)。

复核清单保留机器快照的 `pending_human_review / not_approved` 状态，人工判决另表追加，避免覆盖原始
快照。项目负责人已将 30 条全部核准，适用范围限定为“句末通常语境；无特殊强调、引述或韵律阻断”。
复核门禁会先刷新阶段 6B，再逐条核对文字、规范与条件读法、类别、记录 ID、权重以及三模式投影。
六类必须各有 5 条，每条三模式均只能替换 `a5` 的首音位置且码长增量必须为 0。

舌尖前类的派生首音统一记为 `ɹ`，相应条件读法写成 `ɹa5`。这里的 `ɹ` 是 IPA 式记号；不得写成
`za5`，因为规范拼音声母 `z` 对应 `[ts]` 和 N13，而本类只投影到 N27。

其中 `PA-NG` 的 5 条单列为 `semantic_only_shared_key`：N26 与 N12 共用 `'`，所以音元语义变化，
物理输入码不变，不能把它们统计为新增输入别名。其余 25 条为 `input_alias_key_change`，三模式物理码
都必须与规范路径不同。

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-stage6c-particle-a-review.ps1
```

当前结果为：复核项 30、匹配 30、核准 30、待人工复核 0、共键语义样本 5、键码变化样本 25、
三模式投影 90、未决 0、本复核阶段运行时别名 0。这 30 条后来成为阶段 6D 全量实现前的分层样本
门禁：25 条验证键码变化，5 条验证 N26/N12 共键时不生成重复行。所有条件读法均使用
`parallel_alias_keep_canonical`，不得替换规范输入路径。全量运行接入见
[阶段 6D](STAGE6D_PARTICLE_A_RUNTIME.md)。
