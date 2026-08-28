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

大型 BCC、Unihan、字符目录数据库和 RIME-LMDG 输入不进入 Git。其大小和 SHA-256 记录在 `data/external_inputs.lock.json`；必须先放入不属于任何 Git 仓库的独立归档/工作目录，并设置 `YIME_LEXICON_EXTERNAL_ROOT`。锁文件不保存原型或其它仓库路径，也不存在自动回退：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\verify_external_inputs.py `
  --external-root D:\YimeLexiconInputs
```

这是“从原始证据完整重建”的发布级前置，不是运行时、普通构建、常规 CI 或已批准交接重放的
前置。仅克隆仓库时可以运行 `test.ps1`、构建安装包和执行下文的单仓交接重放；直接运行
`verify_external_inputs.py` 而未提供外部根时，`external input root is required` 是刻意的失败。
如果刚通过用户级环境变量设置了根目录，需要新开终端，或同时为当前 PowerShell 进程赋值。

若路径位于原型或其它 Git 仓库，命令默认失败。确有必要时，必须先取得明确授权，并在
`tools/data_import_approvals/` 保存精确到输入 ID、最长 31 天的审查记录；该例外不取代内容哈希和
正式来源审查。完整政策见[仓库数据边界](../../docs/project/YIME_REPOSITORY_DATA_BOUNDARY.md)。

## 外部归档恢复演练

`data/external_archive.lock.json` 记录确定性 ZIP 的文件名、大小、SHA-256、输入锁身份和 90 天恢复证据时限。ZIP 和解包归档都必须留在 Git 工作树外。先从已经验证的正式输入制作归档：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\package_external_inputs.py `
  --source-root C:\YimeData\lexicon-inputs-v1 `
  --bundle C:\YimeData\yime-lexicon-external-inputs-20260821.zip
```

输出的 `size` 和 `sha256` 必须与 `external_archive.lock.json` 一致。维护者将 ZIP 上传到授权的 HTTPS 对象存储或离线介质后，设置 `YIME_LEXICON_ARCHIVE_URL`；本地镜像可使用 `file:///C:/...`。工具先验证整个 ZIP，再只解出输入锁列出的成员：

```powershell
$env:YIME_LEXICON_ARCHIVE_URL = 'file:///C:/YimeData/yime-lexicon-external-inputs-20260821.zip'
$env:YIME_LEXICON_ARCHIVE_ROOT = 'D:\YimeLexiconArchive\20260821'
.\tools\lexicon\invoke-python.ps1 tools\lexicon\materialize_external_archive.py
```

若归档根已经存在，物化命令直接逐文件验证，不要求 URL。可将 `YIME_LEXICON_ARCHIVE_ROOT` 写入用户环境变量；清单绝不保存某台机器的绝对路径，也不搜索其它仓库。

恢复演练要求归档根目录和恢复根目录都位于 Git 工作树之外，恢复根目录不存在或为空；工具不会把大型数据库复制进仓库。以下命令会从环境变量解析稳定归档，完整预检后复制到全新的恢复目录，逐项复核恢复文件的大小和 SHA-256，最后重新打开整棵恢复树验证：

```powershell
.\tools\lexicon\invoke-python.ps1 `
  tools\lexicon\restore_external_inputs.py `
  --restore-root E:\YimeLexiconRestoreDrill\run-20260822 `
  --evidence .\.generated\lexicon_external_restore\run-20260822.evidence.json
```

缺失、大小不符或 SHA-256 不符均返回非零；无论成功或失败，指定证据文件都会被本次结果原子替换，失败证据不能通过发布校验。恢复证据只保存路径、大小、摘要和状态，不包含词库或数据库正文。至少每 90 天和每次外部输入锁变更后运行一次；超过 90 天的证据会被发布就绪检查拒绝。

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

## BCC 组合输入路径验证

已重建统一来源库和候选研究覆盖层后，可以只读抽取高频、没有整串合规读音的 BCC 字串，验证其组件拼音能否通过正式音元链生成三模式输入码：

```powershell
python tools/validate_bcc_composition_paths.py `
  --output-dir .generated/bcc_recursive_validation
```

工具以 SQLite `mode=ro` 打开 `source_lexicon.sqlite3` 和 `input_model.sqlite3`，只把 JSON、TSV 和 manifest 写到指定生成目录。输出是“组件组合输入拼音/编码路径”，不是目标整串的规范读音；BCC 只提供频次，工具不会写 assessment、递归证据表、运行词典或用户候选。每个已报告目标保留全部结构和组件读音路径；超过配置上限的目标整项跳过并记录原因，不输出截断路径。

持续抽样检查使用独立的日报脚本。它默认以 UTC 日期作为确定性 seed，随机抽取未编码 BCC 目标，先生成离线路径，再用 full、variable、shorthand 三个 compact index 启动无用户模型的 YimeCore 实例逐路径回放。运行时成功要求独立句子状态等于目标并能精确提交；普通候选列表可见性仅作为诊断字段，不替代提交验证。

```powershell
.\tools\yimecore\run-daily-bcc-validation.ps1 `
  -IndexRoot C:\path\to\indexes
```

也可通过 `YIMECORE_INDEX_ROOT` 指定索引目录；未指定时脚本会尝试寻找最新安装的 YimeCore Experimental Trial 索引。默认产物位于 `.generated/bcc_daily_validation/<UTC 日期>/seed-<seed 哈希>/`，包括离线路径 JSON/TSV、离线 manifest、YimeCore 回放 JSON、`failures.tsv`、`developer_alerts.json` 和 `daily_summary.json`。离线跳过与每条运行时失败路径分别报告；`blocking` 区分“该模式没有任何可输出路径”和“另有成功路径的替代拆解失败”。

回放诊断区分运行索引图缺少目标路径、目标路径被 production beam 淘汰、路径保留但最终排序落后，以及输入路径无效。各模式分别报告精确提交的 Top-1 成功率和“目标完整路径仍在 beam 前 9 条”的保守可纠正率；后者不表示候选窗已经可见或已经提交。开发者告警汇总这些诊断和各模式失败率，给出索引覆盖、beam 压力或排序调查建议；告警状态不改变默认退出码，需要 CI 风格门禁时仍须显式添加 `-FailOnMismatch`。输入数据库不会重建或写入，日报目标不会进入用户模型、静态词典或轻量重排器训练。

Windows 每日任务的注册脚本默认只打印计划，不修改 Task Scheduler：

```powershell
.\tools\yimecore\register-daily-bcc-validation-task.ps1 `
  -IndexRoot C:\path\to\indexes

# 审阅计划后才执行注册或替换，默认每天本地时间 03:00 运行。
.\tools\yimecore\register-daily-bcc-validation-task.ps1 `
  -IndexRoot C:\path\to\indexes `
  -Apply
```

`tools/build_two_level_runtime_trial.py` 不再接受仓内可变 `pinyin_hanzi.db` 默认值。若要研究性重建，必须显式传入 `--source-runtime-database`，并由调用方保证该输入只读且有内容锁。
