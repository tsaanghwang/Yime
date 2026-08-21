# Yime 单仓评估工具

本目录替代原型中依赖可变 `pinyin_hanzi.db`、数 GB 候选快照、Tk 候选窗和键盘钩子的评估路径。所有评估首先验证 `tools/lexicon/data/yime_core_target.lock.json`，并记录 1,167,501 条词库身份和唯一布局摘要。

三模式静态效率：

```powershell
.\tools\lexicon\invoke-python.ps1 tools\evaluation\evaluate_modes.py
```

布局草案比较：先复制 `internal_data/manual_key_layout.json` 到生成目录，只修改副本中的 `yinyuan_id` 分配，再运行：

```powershell
.\tools\lexicon\invoke-python.ps1 tools\evaluation\compare_layout.py `
  --candidate-layout .\.generated\evaluation\candidate-layout.json
```

比较器只输出 `report.json` 与 `candidate.patch.json`，没有应用 patch 或写回真源的入口。正式采用布局时仍须人工审查后只修改 `internal_data/manual_key_layout.json`，并运行布局锁及完整交接门禁。

这些指标用于同一 Yime 身份内部的相对比较。静态冲突桶不等于真实候选窗口表现；真实 librime 回放仍是独立的发布门禁。
