# 统一词库与音节编码入口

当前生产真源是：

```text
.generated/lexicon_source_bundle/source_lexicon.sqlite3
```

它由 `tools/build_lexicon_source_bundle.py` 从 Unihan、pypinyin、万象和 BCC
的原始来源重建，集中保存字词、合规读音、来源证据、来源分类、BCC 分域频次和
万象权重。只有其中通过门禁的规范读音才能进入正式音节分解与音元编码链。

旧 `.generated/source_pinyin.db`、仓库内旧同步副本及环境变量
`YIME_SOURCE_PINYIN_DB` 已退出生产链。旧构建器只保留历史格式解析、审计和
少量兼容测试用途；不得把它重新接到 prototype 或 runtime 的默认入口。

## 一键重建

```powershell
.\venv312\Scripts\python.exe internal_data\pinyin_source_db\rebuild_pinyin_assets.py
.\venv312\Scripts\python.exe -m yime.import_danzi_into_prototype_tables
.\venv312\Scripts\python.exe -m yime.import_duozi_into_prototype_tables
.\venv312\Scripts\python.exe -m yime.refresh_runtime_yime_codes --apply --skip-runtime-export
```

第一条命令执行以下生产链：

```text
原始来源
  -> 统一合规门禁
  -> source_lexicon.sqlite3
  -> 物化音节清单
  -> pinyin_normalized.json
  -> 正式音节编码器与一致性检查
```

若来源中出现结构合法、已有明确注音、但尚未存在于当前物化音节表的拼音，运行
`tools/audit_missing_source_syllables.py` 生成按 BCC 频次排列的审查报告。只有登记在
`syllable_admission_reviews.json` 且状态为 `approved` 的项目才可临时跨过旧音节表门禁；
重建后即由正式音节编码链生成。登记文件不得保存音元 ID、码元或键位，也不得补齐未出现的声调。
轻声不逐项登记：标调制度完整的上游在多字完整词音中实际给出的无调音节，按 GB/T 16159-2012
的轻声标写规则准入，不要求为词汇性轻声虚构本调。孤立无调记录可保存为词境证据，但只有
`pronunciation_scope=standalone` 才进入单字候选；标调制度不明的来源标为 `unmarked_ambiguous`。
这里只接纳来源实例，不从本调自动生成任何词语轻声。
各来源“无调是否明确表示轻声”的制度集中登记在 `neutral_tone_source_policy.json`；未登记来源默认
按未定无调处理，不能借用其他来源的约定。

指定另一份统一库时，只接受新变量 `YIME_LEXICON_SOURCE_DB`。

## 数据库接口

- `accepted_readings`：通过门禁的逐来源证据，保留来源标调原貌。
- `canonical_readings`：供生产消费的规范读音、来源汇总、分类和频次。
- `char_readings`：兼容读取视图，包含全部单字读音。
- `phrase_readings`：兼容读取视图，只暴露每个多字条目的首选生产读音。
- `bcc_frequency_evidence`：BCC 原始分域、字频/词频频道证据。
- `metadata`、`source_files`：构建角色、计数和逐文件溯源。

`char_readings` 与 `phrase_readings` 是统一库内部的消费视图，不表示旧
`source_pinyin.db` 重新成为了一层真源。

## 补充清单的边界

`pinyin_normalized_patch.json` 和 `numeric_pinyin_patch.csv` 只能登记已经审查的
数字调/标调表现形式，不能写入四个 Yinyuan ID、键位或手工音元码。发现新读音时，
应先补上游来源和合规规则，再重建统一库；不得从中间码表修补。

编码规则与布局约束另见：

- `docs/SYLLABLE_ENCODING_RULES.md`
- `docs/LAYOUT_CHANGE_LOCK.md`
- `PATCH_POLICY.md`
- `docs/LEXICON_SOURCE_BUNDLE.md`
