# unihan_readings.db

Yime 使用的汉字 **Unihan 普通话读音** SQLite 库，由 `external_data/unihan_readings/` 下脚本构建，产物为 `unihan_readings.db`。

数据来自 Unicode Unihan Database 的五列普通话字段，经 **全量合并**（各列有读音即并入选集）、少量 merge 后补充与人工校正，得到产品用的 `mandarin_readings_merged`。

本目录保留 Unicode 17.0.0 原始数据文件：

- `Unihan_Readings.txt`：普通话读音与辞书来源字段
- `Unihan_OtherMappings.txt`：其它映射字段；其中 `kTGH` 是《通用规范汉字表》8,105 字的正式编号与分级依据

## 构建流水线

`build_all.py` 按顺序执行：

1. **build_hanzi.py** — 从 Unicode 块生成 `hanzi` 主表（含 CJK 扩展及单独收录的「〇」）
2. **import_unihan_readings.py** — 解析 `Unihan_Readings.txt` 中五列普通话字段，写入 `unihan_readings_raw` / `unihan_readings_clean`（不导入粤语、日语、释义等其它 Unihan 读音列）
3. **import_hanzi_frequency.py** — 导入字频
4. **build_mandarin_readings_merged.py** — 五列全合并 → `mandarin_readings_merged`，merge 后补充「〇」并应用经审查的 CJK 兼容码点读音别名
5. **sync_mandarin_readings_corrections.py** — 从 `mandarin_readings_corrections.txt` 导入并 apply 已审核校正
6. **cleanup_unihan.py** — 重建 Unihan / merged / corrections 相关视图
7. **export_hanzi_pinyin_txt.py** — 导出 `mandarin_readings_merged` → `external_data/hanzi_pinyin.txt`

单独重建 merged 表：

```bash
python build_mandarin_readings_merged.py
```

## 核心表

| 表                              | 说明                                                                                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `hanzi`                         | 码点、汉字、Unicode 块名                                                                                                                 |
| `unihan_readings_raw`           | 五列普通话原始值（`kHanyuPinlu` 保留频度，供选常用音）                                                                                   |
| `unihan_readings_clean`         | 五列普通话清洗后（与 merged 合并源一致）                                                                                                 |
| `mandarin_readings_merged`      | **产品用**普通话读音：五列全合并 + merge 后补充 + approved 校正                                                                          |
| `mandarin_readings_corrections` | 人工审核覆盖（仅 `status=approved` 在 apply 时 UPDATE merged）                                                                           |
| `hanzi_frequency`               | BCC 有效单字频 + `frequency_source`（`import_hanzi_frequency.py` 自 `merged_char_freq.txt` 导入；BCC 未命中时用 Unihan 合成序位 5..1/0） |

### 分层用视图

| 视图                      | 说明                                                                                                             |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `view_TGHZ2013`           | 《通用规范汉字表》8105 字：`codepoint`, `hanzi`, `reading`                                                       |
| `view_hanzi_frequency`    | 全部已导入字频：`codepoint`, `hanzi`, `frequency`                                                                |
| `view_tghz2013_frequency` | TGHZ2013 字 + BCC 单字频；`yime/refresh_runtime_yime_codes.py` 据此构建 `char_usage_profile` 3500/6500/8105 分层 |

`cleanup_unihan.py` 会重建上述视图。

上表中的分层视图仅供旧库检查。当前生产分级由统一
`.generated/lexicon_source_bundle/source_lexicon.sqlite3` 的
`character_tiers` 表承担；构建器读取 `Unihan_OtherMappings.txt` 的正式
`kTGH` 编号和 `Unihan_Readings.txt` 的辞书字段，runtime 不再直接消费这些旧视图。

文本导出（非表）：**`external_data/hanzi_pinyin.txt`**，由 `export_hanzi_pinyin_txt.py` 在 `build_all.py` 末尾生成（制表符分隔，含 common_reading / readings 等列）。

### mandarin_readings_merged 合并规则

从下列 Unihan 字段取 **并集**（去重、按频度或列序选常用音）：

- `kTGHZ2013`
- `kHanyuPinlu`
- `kXHC1983`
- `kHanyuPinyin`
- `kMandarin`

仅当 `unihan_readings_clean` 中至少一列有非空普通话读音时，该字才会进入 merged。**Unihan 未收录读音的码点**不会出现在 merged 中，除非经下文「merge 后补充」或（对已有 merged 行的）approved 校正。

### CJK 兼容码点读音别名

`dictionary_pinyin_compliance_policy.json.source_aliases` 登记少量一对一兼容码点。构建器逐项验证
Python Unicode 数据中的 NFKC 结果必须恰好是登记的单个统一字，再复制该统一字已经合并的 Unihan
普通话读音。别名行保留原始 code point，`common_reading_source` 记录
`compatibility_alias:U+XXXX`；策略本身不保存拼音。没有规范分解的独立表意文字不得进入该机制。

## merge 后补充：小写零字「〇」（U+3007）

### 背景

| 项目                 | 情况                                                                             |
| -------------------- | -------------------------------------------------------------------------------- |
| Unicode / `hanzi` 表 | U+3007「〇」在 `hanzi_catalog` 中单独列为块「小写零字」                          |
| Unihan Database      | 五列普通话字段 **均无** U+3007                                                   |
| 规范辞书             | 较新版本《新华字典》《现代汉语词典》收「〇」，释 **「零的空位」**，读音 **líng** |

辞书释「〇」为 **零的空位**（数字书写中表示零的占位符）。输入法需要支持，但不应伪造进 `unihan_readings_clean`（非 Unihan 官方数据）。

### 实现

**`mandarin_readings_supplement.py`**，在 **`build_mandarin_readings_merged.py`** 五列合并之后：

- 若 U+3007 **不存在或 `readings` 为空**，写入 `líng` / `common_reading_source=supplement`
- 若 Unihan 日后提供读音且 merge 已有非空 `readings`，**不覆盖**

读音依据较新版本《新华字典》《现代汉语词典》，仅收录 **líng**。

## 人工校正

**`mandarin_readings_corrections.txt`** 记录经审核、需覆盖自动合并结果的条目。`# note:` 应写明 **Unihan 各列**、《通用规范汉字表》或辞书依据；`origin=manual`。`status=approved` 在构建时 UPDATE 对应 `mandarin_readings_merged` 行（码点须已在 merged 中）。

## 参考资料

- [Unicode Unihan Database](http://www.unicode.org/charts/unihan.html)
