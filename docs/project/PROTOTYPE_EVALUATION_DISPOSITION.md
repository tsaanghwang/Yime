# 原型评估与布局工具迁移处置

日期：2026-08-22

Phase 4 不迁移 Python 输入法运行壳，而是把仍有产品价值的评估能力改为读取 Yime 当前批准的同一词库和布局身份。

| 原型能力 | Yime 处置 | 原因与替代 |
|---|---|---|
| `generate_efficiency_baseline_report.py` 的码长、简化和冲突统计 | 迁移为 `tools/evaluation/evaluate_modes.py` | 直接读取 Windows 锁定的 full / variable / shorthand，不再读取可变 `pinyin_hanzi.db` 或旧候选 JSON |
| `layout_workbench.py` / `yime/utils/layout_workbench.py` 的内存布局草案比较 | 迁移为 `tools/evaluation/compare_layout.py` | 候选布局必须是唯一真源的副本，只能调整 `yinyuan_id` 分配；输出报告和候选 patch，不提供写回入口 |
| 原型 Tk 布局窗口 | 不迁移 | 会恢复 Tk/Python 桌面运行依赖；布局草案改用 JSON 副本与报告审查 |
| 原型 SQLite 候选窗、键盘 hook、pywin32/pynput 回放 | 不迁移 | Windows 实际候选行为由 Go/Rime、真实 Rime 测试和已安装运行验收负责，不能用第二套 Python 输入法替代 |
| `runtime_candidates_by_code*.json`、效率报告快照、数据库备份 | 不迁移 | 体积大、生成时点混杂；新报告从锁定包内词典按需生成并写入忽略目录 |
| KLC/MSKLC 布局生成和独立 Windows 键盘布局试验 | 暂不迁移 | 当前 Windows Yime 的运行布局真源是 Rime 键投影；除非确认仍有独立产品用途，否则不恢复第二条布局发布链 |
| 输入模型容量、排序证据、动态覆盖评估 | 已在 Phase 2 迁移 | 保持离线模型门禁，不与三模式静态效率报告混为一项 |

统一执行入口：

```powershell
.\tools\evaluation\run.ps1 -Python C:\path\to\python.exe
```

报告必须包含锁 ID、1,166,753 条身份、源词典/selection 哈希和布局投影摘要。当前 Windows 包内拼音码表有 1,733 个音节；正式分解清单中尚未进入该批准码表的 `guai2`、`kuai1`、`ra4`、`tin4` 会被显式排除，不能偷偷并入效率基线。

布局候选正式采用时，仍只能人工审查后修改 `internal_data/manual_key_layout.json`，再运行布局锁、单仓交接重放、Go/Rime 和安装包门禁。候选 patch 本身不是新真源。
