# 音元输入法编辑器 (Yinyuan Input Method Editor)

[![Use: Non-Commercial](https://img.shields.io/badge/Use-Non--Commercial-success.svg)](LICENSE)
[![Commercial: Separate License](https://img.shields.io/badge/Commercial-Separate%20Authorization-orange.svg)](COMMERCIAL_LICENSE.md)
[![GitHub Release](https://img.shields.io/github/release/tsaanghwang/YIME)](https://github.com/tsaanghwang/YIME/releases)
[![Python Version](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)

## 概述

音元输入法编辑器(YIME)，简称音元输入法，是以音元为码元的
汉语音码输入系统。当前仓库的重点不是完整展开这套理论，而是维护
Windows 桌面输入法原型、相关生成链，以及一组已经可重复生成的
效率基线。

当前主线已经能稳定给出几类可验证结果：

- 带调全拼音节在当前主线下统一为 4 码编码。
- 运行时候选以 SQLite `pinyin_hanzi.db` 为主路径查词。
- 音元全拼 / 简拼 / 标准全拼的结构码长可以在同语料上并列比较。
- 单字排序与首屏命中率仍是当前优化重点；当前单字需求权重真源是
    BCC 字频频道 `external_data/char_freq/merged_char_freq.txt`，并在
    runtime 中先经动态定标的 5 档分层骨架，再叠加真单字频率与轻量
    修正项。

数据 rebuild 与运行时消费见 [docs/project/PINYIN_DATA_MIGRATION.md](docs/project/PINYIN_DATA_MIGRATION.md)。

当前可重复生成的第一版指标表见 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md)。

## 实现范围说明

README 中提到的简拼、双拼、并击、动态组词和更强的编码转换能力，
很多仍属于理论能力、设计方向或长期可能性，不应默认理解为当前
仓库都已实现。

当前实际主线仍是 Windows 桌面输入法原型，优先处理全拼输入、候选显示、选字回贴、手动输入路径和基础稳定性。

## 重要设计约束

**改代码、写 `syllable/`、或使用 AI 生成补丁前，请先读
[术语总入口](docs/TERMINOLOGY_INDEX.md)**
（含干音 ≠ 乐音等易混概念与代码命名禁令）。

实现、测试、键盘布局和数据库相关改动，还应遵守
[码点与中间层策略](docs/CODEPOINT_POLICY.md)。
当前最重要的约束只有三条：

- `N01-N24` 与 `M01-M33` 是语义槽位层，不是可随意删除的中间产物。
- `PUA-B` 是长期规范承载层，`BMP PUA` 只是当前平台投影层。
- 如果实现结果与约束冲突，应先回查链路，而不是直接改库或跳过语义层修补结果。

## 特性

本仓库里的“特性”分成两层理解：理论层描述音元系统本身的结构
能力，工程层只指当前已经落到代码和 Windows 输入法原型里的主线。

当前真正可运行、可验证的主线主要包括：

- 全拼输入、候选显示、选字回贴和基础交互
- 运行时数据导出与效率基线统计
- 键盘布局生成、MSKLC 打包与安装链

更完整的理论背景、术语和桥接说明请从
[docs/README.md](docs/README.md) 进入；当前实现边界与指标则分别看
[docs/project/INPUT_METHOD_SOLUTION.md](docs/project/INPUT_METHOD_SOLUTION.md)
和 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md)。

## 快速开始

当前根目录 README 只保留最短导航。

1. 安装环境与依赖：看
    [docs/install/INSTALLATION_GUIDE.md](docs/install/INSTALLATION_GUIDE.md)
    或 [docs/install/QUICKSTART_PY312.md](docs/install/QUICKSTART_PY312.md)。
2. 启动当前原型：使用 `python -m yime.input_method.app` 或 `python run_input_method.py`。
3. 了解边界与细分文档：先读
    [docs/project/INPUT_METHOD_SOLUTION.md](docs/project/INPUT_METHOD_SOLUTION.md)，
    再进 [docs/README.md](docs/README.md)。

## 项目结构

```text
YIME/
├── yime/                 # 输入法主线
├── syllable/             # 音节编码与分析
├── internal_data/        # 词库 / rebuild 真源
├── external_data/        # 外部数据与 Unihan 构建链
├── docs/                 # 文档与约束
├── tests/                # 测试
├── tools/                # 维护脚本
├── scripts/              # 一键入口（测试、发布等）
├── config/               # finals 分类等工具配置
├── fonts/                # 文档预览用字体
└── run_input_method.py   # IME 启动入口
```

## 文档入口

根目录 README 只保留三组导航：

- 安装与启动：
    [docs/install/INSTALLATION_GUIDE.md](docs/install/INSTALLATION_GUIDE.md)、
    [docs/install/QUICKSTART_PY312.md](docs/install/QUICKSTART_PY312.md)
- 当前实现边界：
    [docs/project/INPUT_METHOD_SOLUTION.md](docs/project/INPUT_METHOD_SOLUTION.md)
- 文档入口： [docs/README.md](docs/README.md)、
    [docs/TERMINOLOGY_INDEX.md](docs/TERMINOLOGY_INDEX.md)、
    [docs/CODEPOINT_POLICY.md](docs/CODEPOINT_POLICY.md)、
    [docs/SOURCE_AND_ARTIFACTS.md](docs/SOURCE_AND_ARTIFACTS.md)、
    [docs/project/PINYIN_DATA_MIGRATION.md](docs/project/PINYIN_DATA_MIGRATION.md)

## 授权说明

本项目采用“默认放开非商用使用，商用必须另行取得商业许可证”的策略：

- 个人学习、研究、非营利性质的试用与改写，默认可在 [LICENSE](LICENSE) 约束下进行。
- 任何与销售、收费服务、商业交付或营利性业务流程相关的使用，都必须先取得单独商业许可证。
- 英文许可原文见 [LICENSE](LICENSE)，中文参考译文见 [LICENSE.zh-CN.md](LICENSE.zh-CN.md)。
- 商业许可证说明见 [COMMERCIAL_LICENSE.md](COMMERCIAL_LICENSE.md)，
    合同模板见
    [COMMERCIAL_LICENSE_TEMPLATE.md](COMMERCIAL_LICENSE_TEMPLATE.md)。
- 授权文档总览见 [docs/LICENSING_INDEX.md](docs/LICENSING_INDEX.md)，
    法务审阅问卷见
    [docs/LEGAL_REVIEW_CHECKLIST.md](docs/LEGAL_REVIEW_CHECKLIST.md)。
- 文本策略说明见
    [docs/LICENSING_STRATEGY_CN_PRIORITY.md](docs/LICENSING_STRATEGY_CN_PRIORITY.md)
    与
    [docs/LICENSING_STRATEGY_INTL_PRIORITY.md](docs/LICENSING_STRATEGY_INTL_PRIORITY.md)。

- 协议与协作： [LICENSE](LICENSE)、 [NOTICE.md](NOTICE.md)、
    [COMMERCIAL_LICENSE.md](COMMERCIAL_LICENSE.md)、
    [CONTRIBUTING.md](CONTRIBUTING.md)
- 仓库与反馈： [tsaanghwang/YIME](https://github.com/tsaanghwang/YIME)、 [Issues](https://github.com/tsaanghwang/YIME/issues)
