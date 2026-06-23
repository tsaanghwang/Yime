# phrase_pinyin.db

Yime 使用的 **词语普通话读音** SQLite 库。上游数据来自 [phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data) 的冒号格式文本，本目录负责导入、音节码表校验、建库与导出。

## 前置数据

将上游词语拼音文件放到：

`external_data/phrase_pinyin.txt`

格式示例（`#` 开头为注释行）：

```text
# version: 0.19.0
词语: pīn yīn
一一对应: yī yī duì yìng
```

同一词语若源文件出现多次，staging 会合并为一条，`readings` 内以 `|` 分隔多种读音。

## 一键构建

```bash
cd internal_data/phrase_pinyin
python build_valid_pinyin.py
```

按顺序执行：

1. **phrase_pinyin.py** — 创建空表 `phrase_pinyin` 及检视视图
2. **phrase_source_staging.py** — 从 `external_data/phrase_pinyin.txt` 导入 → `phrase_source_staging`
3. **append_pinyin.py** — 对照 Yime 音节码表校验 staging，写入 `phrase_pinyin`
4. **export_phrase_txt.py** — 导出 → `phrase_pinyin.txt`

## 产物

| 文件                | 说明                     |
| ------------------- | ------------------------ |
| `phrase_pinyin.db`  | SQLite 库                |
| `phrase_pinyin.txt` | 制表符导出（供人工检视） |

## 核心表

| 表                      | 说明                                   |
| ----------------------- | -------------------------------------- |
| `phrase_source_staging` | 本次从上游导入的原始读音（合并后）     |
| `phrase_pinyin`         | **产品用**校验通过的词语读音（稀疏表） |

字段说明：

| 列               | 含义                     |
| ---------------- | ------------------------ |
| `phrase`         | 词语文本（主键）         |
| `phrase_len`     | 词语字数                 |
| `common_reading` | 默认读音（空格分隔音节） |
| `readings`       | 全部候选读音，以竖线分隔 |

## 人工检视

| 视图 / 文件                | 用途                             |
| -------------------------- | -------------------------------- |
| `phrase_pinyin`            | 直接浏览有读音词条（约 41 万条） |
| `phrase_pinyin.txt`        | 同上，TSV 格式便于表格工具打开   |
| `view_phrase_inspection`   | 读音数量、是否有拼音、是否多音   |
| `view_phrase_staging_diff` | staging 与 `phrase_pinyin` 差异  |
| `view_staging_inspection`  | staging 侧检视                   |

校验未通过的词条不会进入 `phrase_pinyin`；`append_pinyin.py` 运行时会打印 `invalid_phrases` 计数与示例。

## 单独执行

```bash
# 仅重新导入 staging
python phrase_source_staging.py --source ../../external_data/phrase_pinyin.txt

# 校验并写入 phrase_pinyin（staging 已就绪时）
python append_pinyin.py

# 仅导出（库已构建时）
python export_phrase_txt.py
```

## 与 hanzi_pinyin 的区别

| 维度         | hanzi_pinyin    | phrase_pinyin                       |
| ------------ | --------------- | ----------------------------------- |
| 上游源       | Unihan 合并 TSV | phrase-pinyin-data 冒号文本         |
| 是否音节校验 | 否（原样写入）  | 是（对照 `pinyin_normalized.json`） |
| 多读音分隔   | `,`（音节级）   | 竖线分隔（整句读音级）              |
