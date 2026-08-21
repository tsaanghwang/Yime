# syllable 包说明

`syllable/` 是 Yime 仓库中的 **汉语音节音系分析与音元编解码** Python 子包（与 `yime*` 一起在 `pyproject.toml` 中打包）。它覆盖从「带调拼音 → 音节结构分解 → 4 码音元编码 → 解码还原」的技术链，**不包含**输入法运行时（`yime/`）与词库 rebuild（`internal_data/pinyin_source_db/`）。

**命名与概念请先读：** [片音分析与音元表示：工程阅读概要](../docs/PIANYIN_ANALYSIS_OVERVIEW.md)、[docs/TERMINOLOGY_INDEX.md](../docs/TERMINOLOGY_INDEX.md)、[NAMING.md](NAMING.md)（含 **片音 ≠ 等长平顶音段**、**Yinyuan ID ≠ 实际音值**、**干音 ≠ 乐音** 等易混说明）。

当前整条工程链见 [docs/CURRENT_ARCHITECTURE.md](../docs/CURRENT_ARCHITECTURE.md)，
音节规则依据见 [docs/SYLLABLE_ENCODING_RULES.md](../docs/SYLLABLE_ENCODING_RULES.md)。
码点/语义分层约束见 [docs/CODEPOINT_POLICY.md](../docs/CODEPOINT_POLICY.md)；
生成物归属见 [docs/SOURCE_AND_ARTIFACTS.md](../docs/SOURCE_AND_ARTIFACTS.md)。

---

## 目录结构

```text
syllable/
├── codec/          生产编解码：模型全码、变长音元模型、输入省键、CLI、运行时 JSON
├── analysis/       音节切分、首音/干音组件、编码流水线依赖模块
├── yinyuan/        首音/干音/音元映射 JSON（编码链消费的数据面）
├── pianyin/        片音模型与调值/statistics 试验（偏理论，非 IME 主链）
└── README.md       本文件
```

进入 `analysis/` 前请读 [`analysis/README.md`](analysis/README.md)。该目录当前处理符号化音节分析，
没有实现从语音波形自动切分片音或通过插值合成连续语音。

### 职责边界

| 子目录          | 做什么                                                                                                     | 典型入口                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **`codec/`**    | 音节 `Yinjie` 模型；批量/交互编码；从 `yinjie_code.json` 解码；输出 `yinjie_code.json`、`key_to_code.json` | `model_full_code/`、`variable_length_yinyuan/`、`input_shorthand/`、`yinjie_encoder.py`、`yinjie_decoder.py` |
| **`analysis/`** | 拼音切分、首音/干音编码器、片音/乐音/噪音分析组件；被 `codec/yinjie_encoder.py` 调用                       | `syllable_encoding_pipeline.py`、`shouyin_encoder.py`、`ganyin_encoder.py` |
| **`yinyuan/`**  | 存首音码点、干音定长序列、增强映射等 JSON；由 `ShouyinEncoder` / `GanyinEncoder` 读写                      | 见下文「数据文件」                                                         |
| **`pianyin/`**  | 片音（Pianyin）抽象类与调值统计脚本；`yueyin_yinyuan` 等试验会 import 此处                                 | `pianyin/pianyin.py`                                                       |

**不要与仓库根目录 `tools/syllable_analysis/` 混淆**：后者是一组 **命令行 orchestration / 验证脚本**（生成 zaoyin/yueyin 增强 JSON、切片分析等），逻辑上服务 `syllable/analysis` 与 `syllable/yinyuan`，但不是 Python 包内的库模块。

---

## 编解码数据流

```text
带调拼音 (zhong1)
    │
    ▼
analysis: SyllableEncodingPipeline 切分 → 首音段 / 干音段标签
    ├── ShouyinEncoder  → 首音 Yinyuan ID
    └── GanyinEncoder   → 干音三个乐音 Yinyuan ID
    │
    ▼
codec: YinjieEncoder.encode_single_yinjie()
    │
    ▼
syllable/codec/yinjie_code.json    （numeric_syllable → 4 个 ID 的字符投影）

音元串 / 编码键
    │
    ▼
codec: YinjieDecoder
    ├── 还原 Yinjie 结构（首音 + 呼/主/末乐音）
    └── 可选导出 yinyuan_dict、key_to_code 映射
```

运行时输入法默认 **读取** 已生成的 `yinjie_code.json`；`python run_input_method.py` **不会**自动重建码表。
该文件是正式编码器的生成产物，不得用手工补码或布局试验直接修改。

---

## CLI 入口（`codec/`）

在仓库根目录、已激活虚拟环境的前提下：

```bash
# 批量编码：读拼音列表，写 yinjie_code.json
python syllable/codec/yinjie_encoder.py

# 交互式：逐条输入拼音看编码结果
python syllable/codec/interactive_yinjie_session.py

# 解码：从 yinjie_code.json 解码并导出辅助 JSON
python syllable/codec/yinjie_decoder.py
```

路径常量见 `syllable/codec/paths.py`：

- `YINJIE_CODE_PATH` → `syllable/codec/yinjie_code.json`
- `KEY_TO_CODE_PATH` → `syllable/codec/key_to_code.json`

---

## 与词库 rebuild 的关系

词库 rebuild（`internal_data/pinyin_source_db/rebuild_pinyin_assets.py`）与音节 **编码表** rebuild 是 **两条 Phase**，不要混用：

| Phase                           | 做什么                                                                         | 典型命令                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| **Phase 1 — 词库 + 音节表导出** | `source_lexicon.sqlite3` → `pinyin_normalized.json`；**默认不**改 `yinjie_code.json` | `python internal_data/pinyin_source_db/rebuild_pinyin_assets.py` 或 `scripts/run_tests.cmd` 前置步骤 |
| **Phase 2 — 编码表**            | 首音/干音 JSON → `yinjie_code.json` → `yime/code_pinyin.json`                  | `python tools/rebuild_encoding_assets.py` 或 `scripts/apply_syllable_codebook.cmd`                   |

Phase 2 仅在 Phase 1 测试通过、且你 **有意刷新编码层** 时执行。详见 [internal_data/pinyin_source_db/README.md](../internal_data/pinyin_source_db/README.md) 与 [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)「编码资产重建」一节。

`tools/rebuild_encoding_assets.py` 顺序：

1. `ShouyinEncoder().generate_encoding_files()` → `yinyuan/shouyin_codepoint.json`，以及兼容导出 `internal_data/yinyuan_derived/zaoyin_yinyuan.json`
2. `GanyinEncoder().generate_encoding_files()` → `yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json`，以及 `internal_data/yinyuan_derived/` 下若干兼容 JSON
3. `YinjieEncoder().generate_encoding_files()` → `codec/yinjie_code.json`
4. （可选）`reverse_key_value_pairs` → `yime/code_pinyin.json`

仅刷新码表、跳过反查 JSON：

```bash
python tools/rebuild_encoding_assets.py --skip-code-pinyin
```

---

## 主要数据文件

### `codec/`（运行时消费）

| 文件               | 说明                                             |
| ------------------ | ------------------------------------------------ |
| `yinjie_code.json` | 带调 numeric 音节 → 4 码音元串；IME 与解码器主读 |
| `key_to_code.json` | Yinyuan ID → 字符映射；解码器写键位映射时用        |

### `yinyuan/`（编码链中间/映射层）

| 文件                                           | 说明                                              |
| ---------------------------------------------- | ------------------------------------------------- |
| `zaoyin_yinyuan_enhanced.json`                 | 噪音（首音）音元增强映射源                        |
| `yueyin_yinyuan_enhanced.json`                 | 干音/乐音增强映射源                               |
| `shouyin_codepoint.json`                       | 首音 runtime 码点映射（由 `ShouyinEncoder` 生成） |
| `ganyin_to_fixed_length_yinyuan_sequence.json` | 干音定长音元序列（由 `GanyinEncoder` 生成）       |
| `yinyuan_codepoint.json`                       | 音元码点表                                        |

两份 `*_enhanced.json` 是当前音元语义来源；其余码点、定长序列和运行时 JSON
属于受控生成物。完整归属见 [docs/SOURCE_AND_ARTIFACTS.md](../docs/SOURCE_AND_ARTIFACTS.md)
与 [docs/CODEPOINT_POLICY.md](../docs/CODEPOINT_POLICY.md)。

## 分解与遗漏审计

```bash
python tools/export_syllable_decomposition.py
```

该入口生成三张便于逐项观察的表：

- `internal_data/yime_syllable_decomposition.tsv`：1725 个规范带调音节的分解与编码；
- `internal_data/yime_syllable_encoding_provenance.tsv`：每条编码的来源和规则依据；
- `internal_data/yime_syllable_omissions.tsv`：理论集合、技术拼写与当前字典清单的差异。

遗漏表中的条目不能直接补入 `yinjie_code.json`；先确认它是表层拼写差异、
技术别名、未见字典实例的理论形式，还是编码器故障，再从对应上游规则修复。

---

## Python API 示例

```python
# 编码
from syllable.codec.yinjie_encoder import YinjieEncoder

encoder = YinjieEncoder()
code = encoder.encode_single_yinjie("zhong1")

# 解码
from syllable.codec.yinjie_decoder import YinjieDecoder

decoder = YinjieDecoder()
yinjie = decoder.decode("zhong1")

# 音节结构分析（包根 re-export）
from syllable import Syllable, SyllableCategorizer, YinjieAnalyzer
```

**结构真源：** `syllable/codec/yinjie.py`（``Yinjie``）。

**旧 import 路径：** `yime/syllable_decoder.py`（``SyllableDecoder``，继承 ``YinjieDecoder``）。

已删除：`yime/syllable_structure.py`、`yime/utils/syllable_compat/`；早期宽松切分和
独立的缩写草稿兼容入口也已清退。当前变长/省键模式由正式三模式编码链实现，
不依赖这些旧入口。正式链从四元等长码出发，保留首音边界，并通过合并组成干音的相邻相同音元生成
变长码。等长模式下，首音后的干音固定由呼音、主音、末音三个音元组成：三者不同时保持不变；只有
前两者相同时合并前两者；只有后两者相同时合并后两者；三者相同时合并为一个音元。随后再从变长码
省略符合高—中—低或低—中—高条件的干音中调生成省键码；虚首音不再省略。

---

## 片音模块说明（`pianyin/` vs `analysis/`）

完整约定见 **[NAMING.md](NAMING.md)**。摘要：

- **`syllable/pianyin/`**：片音 canonical 模块；主链使用 `YueyinPianyin` / `ZaoyinPianyin`。
- **已删除 `syllable/analysis/pianyin.py`**：原为与 `pianyin/pianyin.py` 重复的旧副本；请统一使用 canonical 的 `syllable/pianyin/`。
- **`syllable/analysis/pitched_pianyin.py`**：历史试验模块；公共类型以 `syllable.pianyin` 为准。

## 测试

音节相关测试分散在：

```bash
python -m pytest tests/yinjie/ tests/syllable_analysis/
python -m unittest tests.test_yinjie_legacy_helpers
```

完整门禁（含词库 rebuild + 上述测试）：

```bash
scripts/run_tests.cmd
```

编码表变更后，至少跑：

```bash
python -m pytest tests/yinjie/test_yinjie_encoder.py tests/yinjie/test_yinjie_roundtrip.py tests/yinjie/test_pinyin_bidirectional_validation.py
```

---

## 进一步阅读

- [docs/PIANYIN_ANALYSIS_OVERVIEW.md](../docs/PIANYIN_ANALYSIS_OVERVIEW.md) — 片音/音元代码阅读约束与实验边界
- [docs/TERMINOLOGY_INDEX.md](../docs/TERMINOLOGY_INDEX.md) — 术语总入口
- [docs/CURRENT_ARCHITECTURE.md](../docs/CURRENT_ARCHITECTURE.md) — 当前能力、真源和改动边界
- [docs/SYLLABLE_ENCODING_RULES.md](../docs/SYLLABLE_ENCODING_RULES.md) — 音节规则来源与遗漏分类
- [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md) — 编码资产重建与 pytest 门禁
- [docs/DATAFILES.md](../docs/DATAFILES.md) — `key_to_code.json` 等数据文件说明
- [docs/project/PINYIN_DATA_MIGRATION.md](../docs/project/PINYIN_DATA_MIGRATION.md) — 词库/runtime 与编码层边界
