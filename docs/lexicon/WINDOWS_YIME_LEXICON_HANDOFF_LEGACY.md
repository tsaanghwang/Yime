# 默认核心词库交接到 Windows Yime

原型负责完整来源、拼音审查、正式音节编码、候选筛选和评测；Windows Yime 负责安装运行、动态组句
和用户学习。完整大词库是离线真源，不是 Windows 默认运行词库。

## 当前交接物

| 交接物 | 职责 |
| --- | --- |
| `internal_data/runtime_lexicon_filter_policy.json` | 全部已编码单字、一级组件、二级预组合及门禁策略 |
| `two_level_full.dict.yaml` | 原型正式两级选择输出；由 Windows importer 读取，不直接打包 |
| `yime_full/variable/shorthand.dict.yaml` | Windows 三模式运行词典，每套 1,167,501 条 |
| `yime_lexicon_manifest.json` / `yime_core_source_manifest.json` | 三模式输出 SHA、原型核心 SHA、选择与排名证据 |
| `yime_runtime_profile.json` | Windows 默认方案、三模式运行文件及候选层 |
| 拼音显示与音节分解资产 | 反查、显示和正式编码审计 |

完整来源数据库继续用于离线筛选、差异诊断和回归；Windows 只接收正式两级选择派生出的三模式
运行词典。

## 构建与校验

```powershell
.\venv312\Scripts\python.exe tools\build_two_level_runtime_trial.py

.\venv312\Scripts\python.exe tools\verify_default_runtime_handoff.py `
  --windows-repo C:\dev\Yime `
  --output .generated\default_runtime_handoff.json
```

验证器必须确认：

1. 原型策略与 Windows 默认 schema 均为 `yime_variable`，且声明完整三模式；
2. 原型核心 SHA 同时等于 Windows runtime manifest 与 source manifest 的来源 SHA；
3. 三模式词典实际 SHA-256 与 manifest 一致，条目数和排名摘要与原型 evidence 一致；
4. 原型唯一布局真源与 Windows 布局映射完全相同，canonical digest 一致；
5. 拼音码表、音节分解、规范拼音和 PUA 显示四个旁车文件逐一同 SHA。

正式交接由 Windows `tools/import-yime-core-lexicon.ps1` 生成三模式词典、反查真源及审核覆盖层；安装后
可另用 `tools/verify-installed-runtime.ps1` 检查源码/安装哈希，本交接校验本身不修改用户安装目录。

## 发布语义

- “完整长词未预装”不表示“未编码”：只要组件已有正式编码，就由动态组句恢复；
- 第1–5级14,000字保持常用核心排序，第6–8级32,095字作为低频外围，
  但全部可以单字输入并参与动态组句；
- 来源库允许保留未决、古旧和动态残差材料，运行库只接受通过来源与 R0–R5 覆盖门禁的组件；
- 用户实际选择进入个人学习库，不自动反写公共系统库；
- 高频晋升扫描只产生待审建议，不能绕过拼音和编码门禁；
- 字符或实际读音本身缺少可信来源时仍须失败并报告，不允许 AI 猜码。

当前证据包括2,449条固定回放、540,000次加速学习漂移，以及
`experiments/default_runtime_clean_cold_start_20260727.json` 的纯净用户态人工闭环。人工小样本验证
机制，不替代总体统计。
