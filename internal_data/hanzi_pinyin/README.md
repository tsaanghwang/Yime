# hanzi_pinyin.db

Yime 使用的汉字 **普通话读音** SQLite 库。读音来自 Unihan 合并结果（`external_data/hanzi_pinyin.txt`），本目录脚本负责建库、导入与导出。

## 前置数据

先构建 Unihan 库并导出 TSV（见 `external_data/unihan_readings/README.md`）：

```bash
cd external_data/unihan_readings
python build_all.py
```

产物：`external_data/hanzi_pinyin.txt`（约 4.4 万条有读音汉字）。

## 一键构建

```bash
cd internal_data/hanzi_pinyin
python build_valid_pinyin.py
```

按顺序执行：

1. **hanzi_codepoint.py** — 从 Unicode 块生成 `hanzi` 主表（约 9.9 万条）
2. **hanzi_pinyin.py** — 创建空表 `hanzi_pinyin` 及检视视图
3. **hanzi_frequency.py** — 导入字频 → `hanzi_frequency`（BCC `merged_char_freq.txt` + Unihan 合成序位；逻辑见 `yime/utils/char_frequency_policy.py`）
4. **pinyin_source_staging.py** — 从 `hanzi_pinyin.txt` 导入 → `pinyin_source_staging`
5. **append_pinyin.py** — 将 staging 原样写入 `hanzi_pinyin`（仅存有拼音汉字）
6. **export_hanzi_txt.py** — 导出 → `pinyin.txt`

## 产物

| 文件              | 说明                                       |
| ----------------- | ------------------------------------------ |
| `hanzi_pinyin.db` | SQLite 库                                  |
| `pinyin.txt`      | 制表符导出，字段与 `hanzi_pinyin.txt` 一致 |

## 核心表

| 表                      | 说明                                            |
| ----------------------- | ----------------------------------------------- |
| `hanzi`                 | 全量 Unicode 汉字（码点、块名）                 |
| `hanzi_frequency`       | 字频                                            |
| `pinyin_source_staging` | 本次导入的 Unihan 读音（与源 TSV 一致）         |
| `hanzi_pinyin`          | **产品用**有读音汉字（稀疏表，与 staging 一致） |

`common_reading` / `readings` / `common_reading_source` / `is_single` 均来自 Unihan 合并，本库不做二次选取。

## 人工检视

| 视图                             | 用途                                               |
| -------------------------------- | -------------------------------------------------- |
| `hanzi_pinyin`                   | 直接浏览有拼音记录（约 4.4 万条）                  |
| `view_pinyin_without_pinyin`     | `hanzi` 中无读音的字                               |
| `view_pinyin_inspection`         | 全量汉字 + 拼音 + 字频 + 多音标记                  |
| `view_pinyin_with_multireadings` | 多音字                                             |
| `view_pinyin_staging_diff`       | staging 与 `hanzi_pinyin` 差异（正常应为 0）       |
| `view_staging_invalid_pinyin`    | 候选音相对 Yime 音节码表的异常（仅 staging 侧 QA） |

## 脚本一览

| 脚本                        | 作用                                           |
| --------------------------- | ---------------------------------------------- |
| `build_valid_pinyin.py`     | 一键流水线                                     |
| `hanzi_catalog.py`          | Unicode 块定义（供 `hanzi_codepoint.py` 使用） |
| `hanzi_pinyin_source_io.py` | TSV 解析与表 DDL 共享模块                      |
