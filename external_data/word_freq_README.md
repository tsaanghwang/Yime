# word_freq 口径说明

本目录保存外部 `word,freq` 原始频次文件（通常不受 git 跟踪）。

## 数据来源

合并后的词频来自 [北京语言大学 BCC 语料库](https://bcc.blcu.edu.cn/) 下载中心提供的字词频统计。BCC 提供两类下载：**词频**（`word,freq`，行内可含单字）与 **字频**（`char,freq`，仅单字）。仓库用两条合并链分别处理：

| 输出 | 路径 | 合并脚本 | 含义 |
|------|------|----------|------|
| 多字词频 | `external_data/word_freq/merged_word_freq.txt` | `tools/merge_word_freq.py` | 词频频道 `*.txt` 中 `len(word) >= 2` 的条目，各频道取 **max(freq)** |
| 词频中的单字 | `external_data/char_freq/word_freq_merged_single_char_freq.txt` | `tools/merge_word_freq.py`（同上） | 词频频道里 **`len(word) == 1`** 的条目；反映「语料词表统计里出现的单字频」，与专用字频频道不是同一文件 |
| 字频频道单字 | `external_data/char_freq/merged_char_freq.txt` | `tools/merge_char_freq.py` | `char_freq/` 下各频道 `*.txt`（专用字频下载），各频道取 **max(freq)** |

**Yime 写库与 runtime 字频导入统一使用 `merged_char_freq.txt`**（专用字频频道 + `char_frequency_policy` 合成兜底）。`word_freq_merged_single_char_freq.txt` 仍保留，用于对照词频派生单字与专用字频频道的差异，或离线分析；二者键集与 count 可能不一致（词频单字 ⊂ 或 ≠ 字频频道，且同字 max 值可能不同）。

原始频道文件示例：`modern_chinese_word_freq.txt`、`news_total_word_freq.txt`、`literature_word_freq.txt`、`dialogue_word_freq.txt`、`classical_chinese_word_freq.txt`、`multi_domain_total_word_freq.txt`。

## 引用要求

在研究成果、文档或对外说明中使用 BCC 词频数据时，请规范引用：

> 荀恩东, 饶高琦, 肖晓悦, 臧娇娇. 大数据背景下 BCC 语料库的研制[J]. 语料库语言学, 2016(1).

BCC 在线语料库：https://bcc.blcu.edu.cn/

## 口径

- `freq` 按原始整数 **count** 理解，不是归一化权重。
- 单字频写库真源：`external_data/char_freq/merged_char_freq.txt`（BCC **字频频道**）。
- 词频派生单字：`external_data/char_freq/word_freq_merged_single_char_freq.txt`（BCC **词频频道**里的单字行，由 `tools/merge_word_freq.py` 分出，不用于写库）。
- BCC 未命中的单字，各导入脚本按同一 **Unihan 合成序位** 写入有效频率（严格小于 BCC 最小正值 6）：
  - `kTGHZ2013` → 5
  - `kHanyuPinlu` → 4（flat，不解析 Pinlu 内嵌相对频）
  - `kXHC1983` → 3
  - `kHanyuPinyin` → 2
  - `kMandarin` → 1
  - 五列皆无 → 0
- 多列并存取 **max**；BCC 命中时 **只用 BCC**，`frequency_source = external_data/BCC-word-freq`。
- 导入 Yime 后，`phrase_inventory.phrase_frequency` 为 **BCC 原始整数 count**（命中时），否则 **词库默认 1**（表示词条在 curated 词库中至少有一次收录）。
- `char_inventory.char_frequency_abs` 写入 **有效频率**（BCC 或合成值）；`frequency_source` 标记来源。历史列 `char_frequency_rel` 已废弃，不再写入。
- 运行时排序对缺失值仍可用 `COALESCE(..., 0)`；词库导入后短语频率不再留 `NULL`。

## 导入 Yime runtime

Phase 1：dry-run 看命中率

```bash
python yime/import_blcu_word_frequency.py --dry-run
```

Phase 2：测试绿后写库并刷新 runtime JSON

```bash
python yime/import_blcu_word_frequency.py
```

或：

```bash
scripts/import_blcu_word_frequency.cmd
```

行为说明：

- 多字词频按 `phrase_inventory.phrase` 文本 join；BCC 未命中时写入 **1**。
- 单字频按 `char_inventory.hanzi` join；BCC 未命中时使用 Unihan 合成序位（见上）。
- 写库前会清空原有 `phrase_frequency` / `char_frequency_*`，并清空 `char_pinyin_map.reading_weight`。
- 若历史库中 `phrase_inventory.phrase_frequency` 仍为 `REAL`，导入时会自动迁移为 `INTEGER` 并写入 BCC 原始 count。
- 字频写入 `char_inventory.char_frequency_abs`（INTEGER）与 `frequency_source`；不再使用 `char_frequency_rel`。
- `yime/refresh_runtime_yime_codes.py --apply` 也会读取 BCC 单字频，用于 `char_modern_common_profile` 与 `char_usage_profile` 辅助排序。
- 默认在写库前备份 `yime/pinyin_hanzi.db` 到 `yime/backup/`。

## 与词库层的关系

- **词库真源**：`internal_data/phrase_pinyin/phrase_pinyin.txt`（约 41 万词，带拼音）
- **频表真源**：本目录合并后的 BCC 计数
- 频表只影响候选排序，不扩展发音词库边界
