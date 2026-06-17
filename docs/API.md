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

原 `pinyin.*` helper 包与根目录 `legacy/` 归档树已移除，不再属于当前公开 API 或打包面。
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

当前主线没有把 `db_manager.py` 作为默认数据库 API 入口；该模块已于 2026-06 Phase E 删除。
如果你的目标是重建当前拼音数据链，请优先使用：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `internal_data/pinyin_source_db/validate_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_single_char_import.py`）
- `yime/import_duozi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_phrase_import.py`）
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）

---

### 2. Legacy-compatible 数据库管理器（已删除）

`yime.db_manager` 与 `run_db_setup` 已于 2026-06 Phase E 删除。历史 API 说明保留在 git 历史中；当前主线请改看 `docs/project/PINYIN_DATA_MIGRATION.md`。

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
