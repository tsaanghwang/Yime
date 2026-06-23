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

### 实现层补充

当前主线实现把“噪音 / 乐音”明确成 **片音层与音元层共享的类别轴**，并把“片音到音元的归并规则”从音元对象本身拆出：

- 片音对象：`syllable.pianyin.*`
- 音元对象：`syllable.analysis.yinyuan.*`、`syllable.analysis.yueyin_yinyuan.YueyinYinyuan`
- 共享类别轴：`syllable.analysis.yinyuan_categories.YinyuanCategory`
- 乐音归并器：`syllable.analysis.yueyin_mapper.YueyinMapper`

流程图见 [project/YINYUAN_REFACTOR_FLOW.md](project/YINYUAN_REFACTOR_FLOW.md)。

---

## 核心模块

原 `pinyin.*` helper 包与根目录 `legacy/` 归档树已移除，不再属于当前公开 API 或打包面。
当前主线请改看 `internal_data/pinyin_source_db/*` 与 `yime/*` 相关入口；下面开始列出现行仍保留的 API。

### 1. 音节解码器

#### 主链：`syllable.codec.yinjie_decoder.YinjieDecoder`

带调拼音 → 四码 → ``Yinjie`` 的编解码真源。常用方法：

| 方法                            | 说明                                 |
| ------------------------------- | ------------------------------------ |
| `decode(pinyin)`                | 按 ``yinjie_code.json`` 解码单个音节 |
| `decode_all()`                  | 解码码表全部条目                     |
| `resolve_code(key)`             | 按拼音键或四码值反查                 |
| `split_encoded_string(encoded)` | 切分四码或 legacy 宽松编码串         |
| `run()` / `run_example()`       | 批量导出音元分类与键位映射           |

```python
from syllable.codec.yinjie_decoder import YinjieDecoder

decoder = YinjieDecoder()
yinjie = decoder.decode("ma1")
```

#### 兼容入口：`yime.syllable_decoder.SyllableDecoder`

继承 ``YinjieDecoder``，并 re-export ``YinjieDecoder`` / ``YinjieDecoderRunResult``。
仅额外提供：码表缺失时返回空映射、旧方法名 ``split_encoded_syllable`` / ``_get_code``。
新代码请优先 import 主链。

##### 初始化（Yinjie）

```python
from yime.syllable_decoder import SyllableDecoder, YinjieDecoder

decoder = SyllableDecoder()
# 等价于主链，但码表文件缺失时不抛错
```

**参数**：

- `code_file`: 编码映射文件路径（可选，默认 ``syllable/codec/yinjie_code.json``）

##### 主要方法

###### `split_encoded_syllable(encoded: str) -> Yinjie`

兼容旧名；行为同主链 ``YinjieDecoder.split_encoded_string``。

**参数**：

- `encoded`: 音元编码字符串（生产语义为 4 字符；宽松切分仅 compat）

**返回**：

- `Yinjie`: 音节结构对象（``syllable.codec.yinjie``）

**异常**：

- `ValueError`: 输入为空

**示例**：

```python
from syllable.codec.yinjie import Yinjie

# 生产四码（与 yinjie_code.json 一致）
result = decoder.split_encoded_syllable("NABC")
print(result.shouyin)     # 首音槽
print(result.ganyin_code) # 干音三槽拼接字符串

# legacy 宽松切分（非四码语义，勿用于 IME 查词）
from syllable.codec.yinjie_loose_split import split_loose_encoded_string
legacy = split_loose_encoded_string("zhong")
```

---

### 2. 音节结构 (`Yinjie`)

#### 类：`syllable.codec.yinjie.Yinjie`

四音元位层递归结构树；编解码与 IME 全拼主链的真源。术语见 [TERMINOLOGY_INDEX.md](TERMINOLOGY_INDEX.md)。

##### 初始化

```python
from syllable.codec.yinjie import Yinjie

# 四码构造（推荐）
yinjie = Yinjie.from_code("NABC")

# 或按四项音元赋值
yinjie = Yinjie(initial="N", ascender="A", peak="B", descender="C")
```

**参数**（历史英文字段名，
编解码 JSON 顺序不变）：

- `initial`: 首音槽（噪音类音元）
- `ascender`: 呼音槽
    （乐音，峰前段）
- `peak`: 主音槽
    （乐音，峰段）
- `descender`: 末音槽
    （乐音，峰后段）

##### 主要属性

| 属性                  | 类型          | 说明                 |
| --------------------- | ------------- | -------------------- |
| `initial` / `shouyin` | str           | 首音槽               |
| `ascender` / `huyin`  | str           | 呼音槽               |
| `peak` / `zhuyin`     | str           | 主音槽               |
| `descender` / `moyin` | str           | 末音槽               |
| `ganyin`              | `GanyinSlots` | 干音递归结构（对象） |
| `ganyin_code`         | str           | 干音三槽字符拼接     |
| `rime`                | dict          | 韵音兼容 dict        |

##### 主要方法（Yinjie）

| 方法 | 说明 |
| ---- | ---- |
| `from_code(code)` / `to_code()` | 四字符编解码 |
| `classify_phonemes()` / `classify_codes()` | 噪音 / 乐音分类 |
| `get_ganyin_code()` / `get_jianyin_code()` / `get_yunyin_code()` | 区段字符串 |

**示例**：

```python
yinjie = Yinjie.from_code("NABC")
noise, musical = yinjie.classify_phonemes()
print(f"噪音: {noise}")    # ['N']
print(f"乐音: {musical}")  # ['A', 'B', 'C']
```

##### 辅助模块（非 IME 主链）

| 模块 | 说明 |
| ---- | ---- |
| `syllable.codec.yinjie_loose_split` | 早期可变长切分；`split_loose_encoded_string` |
| `syllable.codec.yinjie_jianpin_draft` | 简拼草稿（仅干音去重）；完整规则待实现 |
| `yime.syllable_decoder.SyllableDecoder` | 旧 import 路径；继承 `YinjieDecoder` |

---

## 数据库 API

### 1. 当前主线数据入口

当前主线没有把 `db_manager.py` 作为默认数据库 API 入口；
该模块已于 2026-06 Phase E 删除。
如果你的目标是重建当前拼音数据链，请优先使用：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `internal_data/pinyin_source_db/validate_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
    （兼容入口；真实实现位于
    `yime/utils/prototype_single_char_import.py`）
- `yime/import_duozi_into_prototype_tables.py`
    （兼容入口；真实实现位于
    `yime/utils/prototype_phrase_import.py`）
- `yime/refresh_runtime_yime_codes.py`
    （兼容入口；真实实现位于
    `yime/utils/runtime_codes_refresh.py`）

---

### 2. Legacy-compatible 数据库管理器（已删除）

`yime.db_manager` 与 `run_db_setup` 已于 2026-06 Phase E 删除。
历史 API 说明保留在 git 历史中；
当前主线请改看 `docs/project/PINYIN_DATA_MIGRATION.md`。

---

## 工具函数

## 异常处理

所有 API 方法都可能抛出以下异常：

| 异常类型            | 说明         | 处理建议                |
| ------------------- | ------------ | ----------------------- |
| `ValueError`        | 输入参数无效 | 检查输入格式和内容      |
| `TypeError`         | 类型错误     | 检查参数类型            |
| `sqlite3.Error`     | 数据库错误   | 检查数据库连接和SQL语句 |
| `FileNotFoundError` | 文件不存在   | 检查文件路径            |

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
