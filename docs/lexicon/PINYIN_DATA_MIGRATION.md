# 拼音数据与运行库重建

## 当前唯一生产链

```text
Unihan / pypinyin / 万象 / BCC 原始来源
  -> 第一轮拼音合规门禁
  -> .generated/lexicon_source_bundle/source_lexicon.sqlite3
  -> 规范音节清单
  -> SyllableEncodingPipeline / YinjieEncoder
  -> 四个 Yinyuan ID 与三模式编码
  -> prototype tables
  -> runtime_candidates_materialized
```

`source_lexicon.sqlite3` 是字词、读音、来源证据、分类频次和编码输入的唯一生产
真源。旧 `source_pinyin.db` 已退出默认解析、导入和回退链；生产导入器遇到旧
schema 会直接失败。环境覆盖只接受 `YIME_LEXICON_SOURCE_DB`。

单字九级分级也物化在该统一库的 `character_tiers` 表中。构建器从同版本
Unihan伴生文件和 `hanzi_pinyin.db` 字符全集生成它；运行库只消费结果，不再
自行读取 `unihan_readings.db` 或仓库外的 `kXHC1983.txt`。只需重算分级而不
重建整个大语料包时，可运行：

```powershell
.\venv312\Scripts\python.exe tools\rebuild_character_tiers.py
```

## 完整重建

```powershell
.\venv312\Scripts\python.exe internal_data\pinyin_source_db\rebuild_pinyin_assets.py
.\venv312\Scripts\python.exe -m yime.import_danzi_into_prototype_tables
.\venv312\Scripts\python.exe -m yime.import_duozi_into_prototype_tables
.\venv312\Scripts\python.exe -m yime.refresh_runtime_yime_codes --apply --skip-runtime-export
```

第一条命令会先重建统一库，再验证、刷新物化音节清单并导出
`pinyin_normalized.json`。若只复用已经生成的统一库，可加
`--skip-bundle-build`。只有明确要替换音节编码产物时才使用
`--apply-codebook`。

单字导入会重建公共数字调拼音清单，因此运行库重写必须保持“单字 → 词语 →
运行时候选”顺序，不能只执行其中一段。

## 运行时消费

默认运行时主路径为 `yime/pinyin_hanzi.db` 的
`runtime_candidates_materialized`。`.generated/runtime_candidates_by_code_true.json`
是可选审计/备用导出，不是另一套来源真源。

## 变更门禁

修改来源、合规策略、规范化、切分或编码规则后，还必须运行：

```powershell
.\venv312\Scripts\python.exe tools\export_syllable_decomposition.py
.\venv312\Scripts\python.exe tools\check_layout_change_lock.py
```

不得从 `yinjie_code.json`、运行库、键位或 Yinyuan ID 中间层反向补读音。
布局变化只能修改 `internal_data/manual_key_layout.json`。
