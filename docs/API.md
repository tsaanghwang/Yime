# API 参考手册

## 概述

YIME（音元输入法编辑器）提供了一套完整的 Python API，用于汉语拼音到音元编码的转换。本文档详细说明了所有公开 API 的使用方法。

## 术语前提

本文档中的“音元”“片音”“时段”等术语，不应按传统音位学或传统语音学的习惯直译理解。

在阅读 API 之前，建议先看以下两份术语文档：

- [音元系统术语说明](YINYUAN_TERMINOLOGY.md)
- [Terminology of the Yinyuan System](YINYUAN_TERMINOLOGY_EN.md)

对 API 文档而言，至少应先接受以下术语前提：

1. “时段”对应 `temporal slot`，表示语流中可被语音单位占据的时间位置或时间段。
2. “片音”对应 `phonic slice`，表示按时域切分出来的语音片片，而不是传统意义上的 `phonetic segment`。
3. “音元”在较一般的理论层面上更适合直接写作 `yinyuan`，表示按某语言中的区别性语音属性划分、并占据时段的抽象单位。
4. 一个音元不是单独对应某一个片音，而是由一类片音来实现。

由于当前 API 主要服务于现代通用汉语，文中的“音元”在实现语境里通常可以进一步理解为汉语特例下主要按音高和音质组织的 `yinyuan`；但这只是当前实现对象的语言特例，不应反过来当作整个理论框架的总定义。

如果跳过这些定义，后文中的“音元编码”“音节结构”“首音/干音分析”等术语都容易被误读成传统音位系统里的旧概念。

---

## 核心模块

原 `pinyin.*` helper 包已归档到 `legacy/`，不再属于当前公开 API 或打包面。
当前主线请改看 `internal_data/pinyin_source_db/*` 与 `yime/*` 相关入口；下面开始列出现行仍保留的 API。

### 1. 音节解码器 (SyllableDecoder)

#### 类：`yime.syllable_decoder.SyllableDecoder`

将编码音节解码为音元结构。

##### 初始化

```python
from yime.syllable_decoder import SyllableDecoder

decoder = SyllableDecoder()
```

**参数**：

- `code_file`: 编码映射文件路径（可选，默认读取 `syllable/codec/yinjie_code.json`）

##### 主要方法

###### `split_encoded_syllable(encoded: str) -> SyllableStructure`

将编码音节分割为完整的音元结构。

**参数**：

- `encoded`: 编码后的音节字符串

**返回**：

- `SyllableStructure`: 音节结构对象

**异常**：

- `ValueError`: 输入为空

**示例**：

```python
result = decoder.split_encoded_syllable("zhong")
print(result.initial)  # 首音
print(result.ganyin)   # 干音
```

---

### 2. 音节结构 (SyllableStructure)

#### 类：`yime.syllable_structure.SyllableStructure`

表示汉语音节的层次结构。

##### 初始化

```python
from yime.syllable_structure import SyllableStructure

syllable = SyllableStructure(
    initial="zh",
    ascender="o",
    peak="n",
    descender="g"
)
```

**参数**：

- `initial`: 首音（噪音）
- `ascender`: 呼音（乐音）
- `peak`: 主音（乐音）
- `descender`: 末音（乐音）

##### 主要属性

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `initial` | str | 首音 |
| `ascender` | str | 呼音 |
| `peak` | str | 主音 |
| `descender` | str | 末音 |
| `ganyin` | str | 干音（属性） |
| `rime` | dict | 韵音（属性） |

##### 主要方法

###### `classify_codes() -> Tuple[List[str], List[str]]`

分类音元为噪音和乐音。

**返回**：

- `tuple`: (噪音列表, 乐音列表)

**示例**：

```python
syllable = SyllableStructure(initial="zh", peak="a")
noise, musical = syllable.classify_codes()
print(f"噪音: {noise}")    # ['zh']
print(f"乐音: {musical}")  # ['a']
```

---

## 数据库 API

### 1. 当前主线数据入口

当前主线没有把 `db_manager.py / hanzi_db_manager.py` 作为默认数据库 API 入口。
如果你的目标是重建当前拼音数据链，请优先使用：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `internal_data/pinyin_source_db/validate_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`

如果你的目标只是从仓库内 YAML 词库导出 JSON，请使用：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`

---

### 2. Legacy-compatible 数据库管理器

以下 API 属于 legacy-compatible 中文表结构接口，不是当前主线 rebuild 入口。
当前主线请改看 `docs/project/PINYIN_DATA_MIGRATION.md` 中的 `source_pinyin.db -> prototype tables -> runtime` 链。

#### 类：`yime.db_manager.数据库管理器`

封装数据库连接和基本操作。

##### 使用示例

```python
from yime.db_manager import 数据库管理器, 表管理器

# legacy-compatible 通用数据库操作示例
# 这里的 pinyin_hanzi.db 是现有数据库文件路径，不表示当前主线 rebuild 入口
with 数据库管理器("pinyin_hanzi.db") as conn:
    表管理器.创建表

    # 执行数据库操作
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    results = cursor.fetchall()
```

##### 旧中文表示例

如果你确实在维护 legacy-compatible 中文表结构，才继续使用类似下面的查询：

```python
from yime.db_manager import 数据库管理器

# legacy-compatible 中文表查询示例
with 数据库管理器("pinyin_hanzi.db") as conn:
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM "音元拼音"')
    results = cursor.fetchall()
```

`音元拼音` 表的语义边界：

- 这张表保存的是按音元分析法拆开的单音节结构结果。
- 它的核心用途不是当前 runtime 候选生成，而是保留 `全拼 -> 简拼` 和 `全拼 -> 音节组成部分` 的结构信息。
- 常见列可以这样理解：`全拼` 是完整音元编码，`简拼` 是对完整结构做规则化压缩后的缩写；`首音/干音/呼音/主音/末音/间音/韵音` 则分别保留音节在不同观察角度下的组成部分。
- 如果你是在维护当前主线输入链，请优先修改 `prototype tables`、`mapping_yime_code`、`runtime_candidates` 相关对象，而不是把 `音元拼音` 当成 runtime 主线表。
- 如果后续需要面向外部工具提供 ASCII 名称，建议新增视图或别名层，而不是直接把这张中文表当场改名。

---

## 工具函数

## 异常处理

所有 API 方法都可能抛出以下异常：

| 异常类型 | 说明 | 处理建议 |
| --- | --- | --- |
| `ValueError` | 输入参数无效 | 检查输入格式和内容 |
| `TypeError` | 类型错误 | 检查参数类型 |
| `sqlite3.Error` | 数据库错误 | 检查数据库连接和SQL语句 |
| `FileNotFoundError` | 文件不存在 | 检查文件路径 |

### 异常处理示例

```python
try:
    result = converter.convert(invalid_input)
except ValueError as e:
    print(f"输入错误: {e}")
except Exception as e:
    print(f"未知错误: {e}")
```

---

## 性能优化建议

### 1. 批量处理

```python
# 推荐：批量处理
yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}
result = converter.convert(yunmu_dict)

# 不推荐：逐个处理
for yunmu in constants.REQUIRED_FINALS:
    result = converter.convert({yunmu: ""})
```

### 2. 缓存结果

```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def cached_convert(yunmu):
    return converter.convert({yunmu: ""})
```

## 版本兼容性

- Python: 3.10+
- SQLite: 3.35+
- Node.js: 16+ (前端)

---

## 更多资源

- [开发者指南](DEVELOPMENT.md)
- [常见问题](FAQ.md)
- [安装说明](INSTALL.md)
- [使用说明](USAGE.md)
