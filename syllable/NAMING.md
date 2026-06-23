# syllable 代码命名约定

概念定义与中英翻译见 **[docs/TERMINOLOGY_INDEX.md](../docs/TERMINOLOGY_INDEX.md)** 与 **[docs/YINYUAN_TERMINOLOGY.md](../docs/YINYUAN_TERMINOLOGY.md)**。
本文只规定 **Python 模块、类名、文件名** 的唯一用法，供维护者与 AI 遵守。

---

## 层次与目录

| 目录                 | 职责                                           | 应用层命名后缀                  |
| -------------------- | ---------------------------------------------- | ------------------------------- |
| `syllable/pianyin/`  | 片音（phonic slice）模型                       | `*Pianyin`                      |
| `syllable/analysis/` | 音系分析、首音/干音组件、试验脚本              | 见下表                          |
| `syllable/codec/`    | 编解码、CLI、`yinjie_code.json`                | `Yinjie*`、`*Encoder`（结构向） |
| `syllable/yinyuan/`  | **JSON 数据**（码点/序列映射），不是 Python 包 | `*.json`                        |

**依赖方向：** `codec` → `analysis` →（必要时）`pianyin`；片音层不应 import 音元编码实现。

---

## 概念 → 唯一代码标识

| 中文概念                | 唯一类 / 模块                                      | 禁止混淆                                                               |
| ----------------------- | -------------------------------------------------- | ---------------------------------------------------------------------- |
| 乐音片音（简单模型）    | `syllable.pianyin.PitchedPianyin`                  | ≠ `analysis.pitched_pianyin.PitchedPianyin`                            |
| 噪音片音（简单模型）    | `syllable.pianyin.UnpitchedPianyin`                |                                                                        |
| 共享类别轴              | `analysis.yinyuan_categories.YinyuanCategory`      | 贯穿片音 / 音元两层；≠ 结构段                                          |
| 乐音片音（试验/切片链） | `analysis.pitched_pianyin.YueyinPianyin`           | 仅 `tools/syllable_analysis/ganyin_slicer.py` 等试验链；**非**主链默认 |
| 乐音音元                | `analysis.yueyin_yinyuan.YueyinYinyuan`            | 继承 `MusicalYinyuan`；**不**表示「干音」                              |
| 乐音音元基类            | `analysis.pitched_yinyuan.MusicalYinyuan`          |                                                                        |
| 乐音归并器              | `analysis.yueyin_mapper.YueyinMapper`              | 片音 → 乐音音元；调号样式转换；**不是**音元对象                        |
| 音节结构                | `syllable.codec.yinjie.Yinjie`                     | 内部分解：呼/韵/主/末                                                  |
| 首音音段                | `syllable.analysis.syllable.Syllable.shouyin`      | 声母 + `shoudiao`；通俗即声母/辅音；≠ `Zaoyin*` 类别                   |
| 干音音段                | `syllable.analysis.syllable.Ganyin`                | 韵母 + `gandiao`；≠ `YueyinYinyuan`                                    |
| 干音结构编码            | `analysis.ganyin_encoder.GanyinEncoder`            | 输入如 `i1`；内部可用 `YueyinYinyuan` 作乐音材料                       |
| 首音结构编码            | `analysis.shouyin_encoder.ShouyinEncoder`          | 输入为声母键；零声母等见码表                                           |
| 首音段切分              | `analysis.segment_split.SegmentSplitResult`        | 首音段 / 干音段标签 + ``Syllable`` / ``Ganyin``                        |
| 干音三槽编码            | `analysis.ganyin_yinyuan_slots.GanyinYinyuanSlots` | 呼 / 主 / 末音元字符                                                   |
| 结构化编码结果          | `codec.yinjie_encoder.EncodedYinjieResult`         | ``encode_yinjie_structured``                                           |
| 批量音节编码            | `syllable.codec.yinjie_encoder.YinjieEncoder`      | ``encode_single_yinjie`` → `codec/yinjie_code.json`                    |

### 跨层桥接（允许的唯一位置）

- `YueyinYinyuan.from_pianyin(pianyin)` — **乐音片音对象** → **乐音音元对象**
- `YueyinMapper.normalize_pianyin_text(text)` — **片音字符串** → **乐音音元符号**
- 不要在其它模块新增第二个 `from_pianyin`、第二个归并器，或平行桥接类。

---

## 禁止（AI 与贡献者）

| 禁止行为                                                    | 原因                                                                         |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 新建 `analysis/pianyin.py` 或复制 `pianyin/pianyin.py`      | 旧重复副本已删除；请只使用 canonical 模块                                    |
| 新建第二个「乐音片音」类名如 `MusicalPianyin`               | 用上表已有类                                                                 |
| 将 `Ganyin*` 类重命名为 `Yueyin*`                           | 干音 ≠ 乐音                                                                  |
| 改写 `Yinjie` 层级或新建平行音节类（如「首音+乐音」两分支） | 真源为 `codec/yinjie.py` + [TERMINOLOGY_INDEX](../docs/TERMINOLOGY_INDEX.md) |
| 在说明文字里写「干音=乐音」或省略干音/韵音中间层            | 历史 AI 篡改模式，禁止传播                                                   |
| 将 `yueyin_yinyuan_enhanced.json` 理解为「干音表」          | 文件名含 yueyin = 乐音 **音元** 增强映射                                     |
| 用英文单词替代 numeric 拼音作为码表键                       | 运行时约定为 `zhong1` 等                                                     |

---

## 历史遗留（勿盲目删除）

完整处置原则见 **[LEGACY_ANALYSIS.md](LEGACY_ANALYSIS.md)**。摘要：**零 import ≠ 可删**；须区分重复副本、试验链与 `tools/syllable_analysis/` 思想成果。

| 路径                                                      | 状态                                             |
| --------------------------------------------------------- | ------------------------------------------------ |
| `analysis/pitched_pianyin.py`                             | **试验链**（`ganyin_slicer`）；**保留**          |
| `pitched_yinyuan.py` 末尾空壳 `class YueyinYinyuan: pass` | 兼容占位；真类在 `yueyin_yinyuan.py`；**勿扩展** |

---

## 相关入口

- 包结构与 CLI：[README.md](README.md)
- 遗留模块处置：[LEGACY_ANALYSIS.md](LEGACY_ANALYSIS.md)
- 文档总索引：[docs/TERMINOLOGY_INDEX.md](../docs/TERMINOLOGY_INDEX.md)
- 重构流程图：[docs/project/YINYUAN_REFACTOR_FLOW.md](../docs/project/YINYUAN_REFACTOR_FLOW.md)
