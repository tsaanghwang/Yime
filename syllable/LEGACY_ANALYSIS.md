# 分析链遗留模块处置说明

改 `syllable/` 或清理文件前请先读本页。**不要** 因「零 import」就删除下列 artifact——其中不少是一次性分析工具或思想成果的代码化载体，删掉会导致后续分析无据可循。

## 处置原则

| 类别                                   | 做法                                                                              |
| -------------------------------------- | --------------------------------------------------------------------------------- |
| **生产编解码主链**                     | 只保留 [NAMING.md](NAMING.md) 登记的 canonical 模块                               |
| **重复副本**（与 canonical 逐字同源）  | 标记 deprecated，不扩展；合并前须 diff 确认无独有注释/试验逻辑                    |
| **试验 / 一次性分析脚本**              | 保留在 `tools/syllable_analysis/`，或把结论写入 `docs/project/syllable_analysis/` |
| **思想成果代码**（命名旧但含领域注释） | 优先 **归档说明 + 指向 canonical**，而非物理删除                                  |

## 当前清单

| 路径                                                        | 引用情况                                   | 建议处置                                                      |
| ----------------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------- |
| `syllable/pianyin/pianyin.py`                               | 主链 / 试验                                | **Canonical** 片音简单模型                                    |
| `syllable/analysis/pianyin.py`                              | 已删除                                     | 原为与 `syllable/pianyin/pianyin.py` 重复的旧副本；后续勿恢复 |
| `syllable/pianyin/indeterminate_pitch_pianyin.py`           | pianyin 包                                 | **Canonical** 无调片音                                        |
| `syllable/analysis/pitched_pianyin.py`                      | `tools/syllable_analysis/ganyin_slicer.py` | **试验链**；`YueyinPianyin` 非主链默认，**保留**              |
| `syllable/analysis/yueyin_yinyuan.py`                       | `GanyinEncoder` 等                         | **生产** 乐音音元                                             |
| `syllable/analysis/pitched_yinyuan.py`                      | 被 yueyin 继承                             | **生产**；末尾空壳 `YueyinYinyuan: pass` 勿扩展               |
| `tools/syllable_analysis/*`                                 | 手工 orchestration                         | **工具箱**；生成/验证 JSON，见各脚本头注释                    |
| `docs/project/syllable_analysis/sound_variable_analysis.md` | 文档                                       | **思想成果** 文字版；与 TERMINOLOGY_INDEX 峰位填充表一致      |

## 与编解码重构的关系

分步改造优先打通：

1. `syllable/analysis/syllable.py` — 声韵母 **音段层**
2. `syllable/analysis/segment_split.py` — 首音段 / 干音段切分
3. `syllable/codec/yinjie.py` — 四槽 **音元层**
4. `syllable/codec/yinjie_encoder.py` — `encode_yinjie_structured`

**清理重复 `.py` 文件不在重构关键路径上**；须单独开 issue，按上表逐文件审查。

## 相关入口

- [NAMING.md](NAMING.md) — 代码唯一类名
- [docs/TERMINOLOGY_INDEX.md](../docs/TERMINOLOGY_INDEX.md) — 术语树
- [README.md](README.md) — 编解码数据流
