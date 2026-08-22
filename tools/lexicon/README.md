# Yime 离线词库工具

本目录承接原 `Yime-python-prototype` 中仍属于产品构建链的离线能力。这里的 Python 工具只用于来源整理、正式编码、词库生成、布局实验和验收，不进入 Windows 安装包，也不参与输入法运行时。

离线工具以 Python 3.14 为最低版本和 CI 当前稳定主版本；补丁版本由环境获取该系列的最新稳定更新。这里不依赖 `pywin32`、`pynput`、Tk 或 PyInstaller，也不读取原型仓的 `venv312`。本机可用 `YIME_LEXICON_PYTHON` 或 `-Python` 指向独立解释器。

迁移按 `docs/project/PROTOTYPE_RETIREMENT_MIGRATION_PLAN.md` 分阶段进行。Phase 0 已按正式流程连续完成两次一致的干净重建；当前批准的 Windows 交接身份为 1,166,753 条映射、1,151,404 个不同文本。历史 1,167,501 条身份保留在目标锁的 `supersedes` 记录和 Git 历史中，不再要求正式流程反向凑数。

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

## 外部归档恢复演练

外部归档根目录必须按 `external_inputs.lock.json` 的 `relative_path` 保存全部文件。恢复演练要求归档根目录和恢复根目录都位于 Git 工作树之外，恢复根目录不存在或为空；工具不会把大型数据库复制进仓库。以下命令先完整预检归档，再复制到全新的恢复目录，逐项复核恢复文件的大小和 SHA-256，最后重新打开整棵恢复树验证：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\restore_external_inputs.py `
  --archive-root D:\YimeLexiconArchive `
  --restore-root E:\YimeLexiconRestoreDrill\run-20260822 `
  --evidence .\.generated\lexicon_external_restore\run-20260822.evidence.json
```

缺失、大小不符或 SHA-256 不符均返回非零；无论成功或失败，指定证据文件都会被本次结果原子替换，失败证据不能通过发布校验。恢复证据只保存路径、大小、摘要和状态，不包含词库或数据库正文。

发布门禁读取证据时会重新对照当前锁文件身份和每一项归档/恢复摘要，不能只凭 `decision=pass` 放行：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\verify_release_readiness.py `
  --require-release `
  --external-restore-evidence .\.generated\lexicon_external_restore\run-20260822.evidence.json
```

完整发布验收入口强制要求 `-ExternalRestoreEvidence`；标签 CI 中不带证据的 `verify_release_readiness.py --require-release` 只验证已版本化的来源重现身份，不代替外部归档恢复门禁：

```powershell
.\tools\lexicon\run-release-acceptance.ps1 `
  -ExternalRestoreEvidence .\.generated\lexicon_external_restore\run-20260822.evidence.json
```

## 单仓交接重放

批准的唯一等长源词典保存在 `handoff/yime_core_fixed.dict.yaml`，其来源证据保存在同目录的 `yime_core_fixed.evidence.json`。三模式仍由 Go `codemode` 派生，不在 Python 中维护三份词典。可在全新输出目录中重放并验证：

```powershell
.\tools\lexicon\replay-approved-handoff.ps1 `
  -Python C:\path\to\python.exe `
  -OutputDir .\.generated\approved_core_handoff_replay
```

该命令只写入指定生成目录，不覆盖 `go-backend/input_methods/yime/data`。它要求 full、variable、shorthand、反查拼音源、词条数、不同文本数、源词典哈希和 selection 身份全部与目标锁一致。

固定交接物与当前正式来源链已经闭合：两轮来源 TSV、来源门禁计数、最终词典和 selection 均一致，运行数据库输入以大小和 SHA-256 记录在交接 evidence 中。`verify_release_readiness.py --require-release` 与单仓重放均须通过后，才允许构建安装包。

`prepare_reproducible_handoff.py` 验证两轮隔离重建并生成 evidence；`promote_handoff_target.py` 默认只做 dry-run，只有显式传入 `--apply` 才会晋升 staging、重算目标锁和发布状态。两者只操作生成证据和既有正式派生产物，不提供手写拼音码或词典正文的入口。

`tools/build_two_level_runtime_trial.py` 不再接受仓内可变 `pinyin_hanzi.db` 默认值。若要研究性重建，必须显式传入 `--source-runtime-database`，并由调用方保证该输入只读且有内容锁。
