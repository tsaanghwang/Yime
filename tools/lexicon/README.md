# Yime 离线词库工具

本目录承接原 `Yime-python-prototype` 中仍属于产品构建链的离线能力。这里的 Python 工具只用于来源整理、正式编码、词库生成、布局实验和验收，不进入 Windows 安装包，也不参与输入法运行时。

迁移按 `docs/project/PROTOTYPE_RETIREMENT_MIGRATION_PLAN.md` 分阶段进行。当前 Phase 0 只冻结和验证已经批准的 1,167,501 条 Windows 交接身份；在正式重建链能够精确复现它以前，不得更新 baseline 或覆盖运行词典。

运行目标锁校验：

```powershell
python tools/lexicon/verify_target_lock.py
```

校验新的原型重建候选时，必须同时提供词典和 selection：

```powershell
python tools/lexicon/verify_target_lock.py `
  --candidate-dictionary C:\path\to\two_level_full.dict.yaml `
  --candidate-selection C:\path\to\selection.tsv
```

只有命令返回 0 且 `candidate_exact_match=true`，候选才与当前产品身份相同。
