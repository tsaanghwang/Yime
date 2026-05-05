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

### 1. 韵母转换器 (YunmuConverter)

#### 类：`pinyin.yunmu_to_keys.YunmuConverter`

韵母转换器是核心转换引擎，负责将标准拼音韵母转换为音元编码。

##### 初始化

```python
from pinyin.yunmu_to_keys import YunmuConverter

converter = YunmuConverter()
```

##### 主要方法

###### `convert(yunmu_dict: Dict[str, str]) -> Dict[str, str]`

转换韵母字典为音元编码。

**参数**：

- `yunmu_dict`: 韵母字典，键为韵母，值为空字符串或原始编码

**返回**：

- 转换后的字典，键为韵母，值为音元编码

**异常**：

- `ValueError`: 输入不是字典
- `ValueError`: 字典键值不是字符串
- `ValueError`: 缺少必要的韵母

**示例**：

```python
from pinyin.yunmu_to_keys import YunmuConverter
from pinyin.constants import YunmuConstants

converter = YunmuConverter()
constants = YunmuConstants()

# 创建完整韵母字典
yunmu_dict = {yunmu: "" for yunmu in constants.REQUIRED_FINALS}

# 执行转换
result = converter.convert(yunmu_dict)

# 查看结果
print(result["-i"])   # 输出: ir
print(result["ao"])   # 输出: au
print(result["ü"])    # 输出: v
```

###### `get_stats() -> Dict[str, Any]`

获取转换统计信息。

**返回**：

- 统计字典，包含：
  - `total_conversions`: 总转换数
  - `successful_conversions`: 成功转换数
  - `failed_conversions`: 失败转换数
  - `success_rate`: 成功率（百分比）
  - `rule_stats`: 规则应用统计

**示例**：

```python
converter.convert(yunmu_dict)
stats = converter.get_stats()

print(f"成功率: {stats['success_rate']:.2f}%")
print(f"总转换数: {stats['total_conversions']}")
```

###### `validate_input(yunmu_dict: Dict[str, str]) -> None`

验证输入数据的有效性。

**参数**：

- `yunmu_dict`: 待验证的韵母字典

**异常**：

- `ValueError`: 输入无效时抛出

**示例**：

```python
try:
    converter.validate_input(yunmu_dict)
    print("输入有效")
except ValueError as e:
    print(f"输入无效: {e}")
```

---

### 2. 韵母常量 (YunmuConstants)

#### 类：`pinyin.constants.YunmuConstants`

定义所有韵母相关的常量和配置。

##### 初始化

```python
from pinyin.constants import YunmuConstants

constants = YunmuConstants()
```

##### 主要属性

| 属性 | 类型 | 说明 | 示例值 |
| --- | --- | --- | --- |
| `I_APICAL` | str | 舌尖元音 | "-i" |
| `I_APICAL_REPLACEMENT` | str | 舌尖元音替换 | "ir" |
| `AO_FINAL` | str | ao韵母 | "ao" |
| `Y_NEAR_ROUNDED` | str | ü元音 | "ü" |
| `Y_REPLACEMENT` | str | ü替换 | "v" |
| `REQUIRED_FINALS` | List[str] | 必需韵母列表 | ["a", "o", "e", ...] |

##### 主要方法

###### `get_replacement_table() -> dict`

获取批量替换转换表。

**返回**：

- `dict`: maketrans 格式的替换表

**示例**：

```python
table = YunmuConstants.get_replacement_table()
# 可用于 str.translate() 方法
text = "ün".translate(table)
```

---

### 3. 拼音转换器 (PinyinConverter)

#### 类：`yime.pinyin_converter.PinyinConverter`

这是一个 legacy-compatible 转换器，主要服务旧 `数字标调拼音 -> 音元拼音` 数据库流。
当前主线 rebuild/runtime 不再依赖它；主线入口请改看 `docs/project/PINYIN_DATA_MIGRATION.md`。

处理数字标调拼音到音元拼音的转换。

##### 初始化

```python
from yime.pinyin_converter import PinyinConverter

# 这里的 pinyin_hanzi.db 指现有运行时/兼容数据库文件，不表示当前主线 rebuild 入口
converter = PinyinConverter(db_path="pinyin_hanzi.db")
```

**参数**：

- `db_path`: 数据库文件路径（默认: "pinyin_hanzi.db"，即现有运行时/兼容数据库文件）

##### 主要方法

###### `convert_all() -> int`

一键转换所有数字标调拼音到音元拼音。

**返回**：

- `int`: 成功转换的记录数

**示例**：

```python
converter = PinyinConverter()
count = converter.convert_all()
print(f"成功转换 {count} 条拼音记录")
```

---

### 4. 音节解码器 (SyllableDecoder)

#### 类：`yime.syllable_decoder.SyllableDecoder`

将编码音节解码为音元结构。

##### 初始化

```python
from yime.syllable_decoder import SyllableDecoder

decoder = SyllableDecoder(code_file="syllable_code.json")
```

**参数**：

- `code_file`: 编码映射文件路径（可选）

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

### 5. 音节结构 (SyllableStructure)

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

---

## 工具函数

### 1. 拼音解析

```python
from yime.pinyin_mapping import PinyinMapper

# 这里连接的是现有运行时数据库；若要重建数据，请改走 PINYIN_DATA_MIGRATION.md 中的主线链
mapper = PinyinMapper(db_path="pinyin_hanzi.db")

# 添加映射
mapper.add_mapping("zhong1", "zhong")

# 获取映射
result = mapper.get_mapping("zhong1")
print(result)  # 输出: zhong

# 批量添加
mappings = {
    "zhong1": "zhong",
    "guo2": "guo",
    "ren2": "ren"
}
count = mapper.batch_add_mappings(mappings)
```

---

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
from pinyin.yunmu_to_keys import YunmuConverter

converter = YunmuConverter()

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
