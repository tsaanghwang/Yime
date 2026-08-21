# 核心候选三模式运行链

Yime for Windows 只运行整理、重新赋权后的候选集。当前运行字典包含1,166,753条不重复映射、
1,151,404个不同文本；其中46,095个已编码单字全部可达，前14,000字保持核心排序，
其余32,095字位于低频外围。变长、等长、省键词典由这份固定长度真源确定性派生，变长模式为默认方案。

## 数据边界

- 原型负责候选池、来源证据、构式判定、排序证据和回归样本。
- Yime 只导入通过门禁的核心真源，不复制候选池，也没有候选池回退路径。
- `yime_core_source_manifest.json` 锁定源词典、筛选结果和排序策略的 SHA-256。
- `yime_lexicon_manifest.json` 锁定三模式派生规则、条目数和三个输出哈希。
- 安装包必须同时携带 `yime_variable`、`yime_full`、`yime_shorthand` 的 dict 和 schema。

排序证据采用 `BCC 优先 → RIME-LMDG 补充 → 结构保底`。三类来源分区排序，不把补充值伪装成
BCC 频次，也不把两个语料库的原始计数直接相加。

## 候选层

每种模式的候选链都由四层组成：

1. 整理后的系统核心候选；
2. Rime 模式专属 userdb，包括人工选择和整句学习；
3. 从 `yime_user_phrases.txt` 同步生成的三模式自定义词；
4. `yime_blocklist.txt` 驱动的统一候选输出过滤。

系统核心只提供可组合材料。没有预装的长词可以由单字、短部件和构式部件动态组成；人工纠正进入
用户学习层，不反写系统核心。自定义词和屏蔽词也属于用户层，不改变可复现的发布词典。

## 导入与验证

```powershell
powershell -ExecutionPolicy Bypass -File tools/import-yime-core-lexicon.ps1 `
  -InputPath <prototype>\two_level_full.dict.yaml `
  -EvidenceManifest <prototype>\dictionary.manifest.json `
  -PronunciationEntries <prototype>\lexicon_source_bundle\entries.tsv `
  -SourceRevision <prototype-commit>

cd go-backend
go test ./input_methods/yime/...
```

导入脚本先校验原型证据清单和输入 SHA-256，再一次性重建三模式词典。构建门禁验证三套词典、
三套 schema、两个 manifest 和运行配置均存在，同时拒绝已退役的过渡方案文件。
