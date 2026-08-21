# 离线词库与编码资料

本目录保存从 `Yime-python-prototype` 迁入、仍用于解释和维护正式拼音—音元—布局—词库链的架构资料。代码和规范数据已经放回与原型相同的仓内相对路径（`syllable/`、`yime/`、`internal_data/`、`external_data/`、`tools/`），以便迁移期直接运行原有正式门禁。

这些文档中的历史仓名、旧绝对路径和阶段状态仅代表来源快照；当前实施状态以 `docs/project/PROTOTYPE_RETIREMENT_MIGRATION_PLAN.md`、`tools/lexicon/data/prototype_source_snapshot.json` 和 Yime 当前代码为准。

关键约束：

- `internal_data/manual_key_layout.json` 是唯一可编辑布局真源；Windows 数据目录中的布局是派生投影。
- `syllable/codec/yinjie_code.json` 是正式管线生成并由锁验证的审计/运行输入，不得人工补行。
- `tools/lexicon/data/external_inputs.lock.json` 只记录大型外部输入的身份，不把它们复制进 Git。
- 连接语流音变保持为有来源、可移除的词/短语别名，不能回写规范拼音或基础音节码。
