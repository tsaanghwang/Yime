# Yime 离线词库工具

本目录承接原 `Yime-python-prototype` 中仍属于产品构建链的离线能力。这里的 Python 工具只用于来源整理、正式编码、词库生成、布局实验和验收，不进入 Windows 安装包，也不参与输入法运行时。

离线工具以 Python 3.14 为最低版本和 CI 当前稳定主版本；补丁版本由环境获取该系列的最新稳定更新。这里不依赖 `pywin32`、`pynput`、Tk 或 PyInstaller，也不读取原型仓的 `venv312`。本机可用 `YIME_LEXICON_PYTHON` 或 `-Python` 指向独立解释器。

迁移按 `docs/project/PROTOTYPE_RETIREMENT_MIGRATION_PLAN.md` 分阶段进行。当前 Phase 0 只冻结和验证已经批准的 1,167,501 条 Windows 交接身份；在正式重建链能够精确复现它以前，不得更新 baseline 或覆盖运行词典。

运行目标锁校验：

```powershell
python tools/lexicon/verify_target_lock.py
```

统一运行测试和目标锁：

```powershell
.\tools\lexicon\test.ps1
```

校验新的原型重建候选时，必须同时提供词典和 selection：

```powershell
python tools/lexicon/verify_target_lock.py `
  --candidate-dictionary C:\path\to\two_level_full.dict.yaml `
  --candidate-selection C:\path\to\selection.tsv
```

只有命令返回 0 且 `candidate_exact_match=true`，候选才与当前产品身份相同。

大型 BCC、Unihan、字符目录数据库和 RIME-LMDG 输入不进入 Git。其大小和 SHA-256 记录在 `data/external_inputs.lock.json`；迁移期可验证旧位置，完成外部归档后应设置 `YIME_LEXICON_EXTERNAL_ROOT` 并使用 `--no-legacy-paths` 验证：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\verify_external_inputs.py `
  --external-root D:\YimeLexiconInputs `
  --no-legacy-paths
```

## 单仓交接重放

批准的唯一等长源词典保存在 `handoff/yime_core_fixed.dict.yaml`，其来源证据保存在同目录的 `yime_core_fixed.evidence.json`。三模式仍由 Go `codemode` 派生，不在 Python 中维护三份词典。可在全新输出目录中重放并验证：

```powershell
.\tools\lexicon\replay-approved-handoff.ps1 `
  -Python C:\path\to\python.exe `
  -OutputDir .\.generated\approved_core_handoff_replay
```

该命令只写入指定生成目录，不覆盖 `go-backend/input_methods/yime/data`。它要求 full、variable、shorthand、反查拼音源、词条数、不同文本数、源词典哈希和 selection 身份全部与目标锁一致。

固定交接物解决的是“Windows 当前批准身份可在 Yime 内独立重放”，不等同于“当前来源链已经重新生成出 1,167,501 条”。后者仍须先解决历史运行数据库与音变增量的完整可复现性；在此之前不得刷新 baseline。

`tools/build_two_level_runtime_trial.py` 不再接受仓内可变 `pinyin_hanzi.db` 默认值。若要研究性重建，必须显式传入 `--source-runtime-database`，并由调用方保证该输入只读且有内容锁。
