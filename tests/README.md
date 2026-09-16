# 离线 Python 测试

`tests/` 覆盖共同源的离线拼音、音节编码、词库生成与输入模型研究工具，不是 YimeCore 或 Rime/PIME 的完整运行时测试集。产品测试层级、CI 范围及实机验收入口见[测试与验收指南](../docs/YIME_TESTING_GUIDE.md)；当前安装结果见[简版维护验证](../installer/simple/VALIDATION.md)。

## 当前目录

| 目录 | 职责 |
| --- | --- |
| 顶层 `test_*.py` | 拼音规范化、数字声调、音节解码、资产路径等跨模块基础检查 |
| `yinjie/` | 音节编码与解码、阶段结构、双向校验、轻声及入口清单 |
| `syllable_analysis/` | 条件音值、片音/音元来源、声母/干音分析、儿化分类与审查 |
| `yime/` | 规范映射、三模式、布局锁、来源与词库选择、运行资产导出及可重现性 |
| `lexicon_bundle/` | 词库构建、音节准入、PSC 审查、正音覆盖和字符分级 |
| `pinyin_source_db/` | 拼音来源次序、规范库存导出和物化音节清单 |
| `input_model/` | 组合输入路径、候选覆盖、排序证据、构式组件及试验导出 |
| `tools/` | 人工布局源解析等离线辅助工具 |

新增测试放入最贴近其职责的目录；运行时用例放入对应产品源码测试目录，不在这里建立第二套输入法实现。

## 运行

从仓库根目录、Python 3.14 环境运行：

```text
python -m pip install -e "tools/lexicon[test]"
python tools/powershell/run_checked.py --script tools/lexicon/test.ps1 --edition ps7
```

统一入口依次检查仓库数据边界、`tools/lexicon/tests`、目标锁，再运行本目录 pytest。单个离线用例也可直接运行，例如：

```text
python -m pytest -q tests/yinjie/test_yinjie_encoder.py
```

数据依赖、解释器选择和来源级重建说明见[离线词库工具](../tools/lexicon/README.md)。外部大型来源只从 `YIME_LEXICON_EXTERNAL_ROOT` 指定的独立内容锁定目录读取；不得添加原型仓、其他 Git 仓库或父目录搜索回退。普通回归不等于来源级完整重建。

## 其他测试入口

- Go 引擎、Broker、Rime 适配和工具：`go-backend/` 各包测试，由 [test-go.ps1](../tools/test-go.ps1)、[test-real-rime.ps1](../tools/test-real-rime.ps1)、[test-go-race.ps1](../tools/test-go-race.ps1) 分别编排。
- YimeCore 原生契约与宿主：[YimeTextServiceExperiment/tests](../YimeTextServiceExperiment/tests/)；构建和隔离执行见[源码工具入口](../tools/yimecore/README.md)。
- Rime/PIME 原生回归：[PIMETextService](../PIMETextService/) 与 [PIMELauncher](../PIMELauncher/)，CI 分别验证 C++ 与固定 i686 host Rust 工具链。
- 安装维护：[installer/simple](../installer/simple/README.md) 的 `Test-*.ps1`；隔离检查不能代替完整包安装、真实输入和重启确认。
- 工作流权威定义：[.github/workflows/ci.yaml](../.github/workflows/ci.yaml)。
