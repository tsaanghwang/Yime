[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![GitHub Release](https://img.shields.io/github/release/tsaanghwang/YIME)](https://github.com/tsaanghwang/YIME/releases)
[![Python Version](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)

# 音元输入法编辑器 (Yinyuan Input Method Editor)

## 概述

音元输入法编辑器(YIME)，简称音元输入法，是以音元为码元的汉语音码输入系统。当前仓库的重点不是完整展开这套理论，而是维护 Windows 桌面输入法原型、相关生成链，以及一组已经可重复生成的效率基线。

当前主线已经能稳定给出几类可验证结果：

- 带调全拼音节在当前主线下统一为 4 码编码。
- 运行时候选与重码情况已经可以用基线报告量化。
- 音元全拼 / 简拼 / 标准全拼的结构码长可以在同语料上并列比较。
- 单字排序与首屏命中率仍是当前优化重点。

当前可重复生成的第一版指标表见 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md)。

## 实现范围说明

README 中提到的简拼、双拼、并击、动态组词和更强的编码转换能力，很多仍属于理论能力、设计方向或长期可能性，不应默认理解为当前仓库都已实现。

当前实际主线仍是 Windows 桌面输入法原型，优先处理全拼输入、候选显示、选字回贴、手动输入路径和基础稳定性。

## 重要设计约束

实现、测试、键盘布局和数据库相关改动，都应先遵守 [码点与中间层策略](docs/CODEPOINT_POLICY.md)。当前最重要的约束只有三条：

- `N01-N24` 与 `M01-M33` 是语义槽位层，不是可随意删除的中间产物。
- `PUA-B` 是长期规范承载层，`BMP PUA` 只是当前平台投影层。
- 如果实现结果与约束冲突，应先回查链路，而不是直接改库或跳过语义层修补结果。

## 特性

本仓库里的“特性”分成两层理解：理论层描述音元系统本身的结构能力，工程层只指当前已经落到代码和 Windows 输入法原型里的主线。

当前真正可运行、可验证的主线主要包括：

- 全拼输入、候选显示、选字回贴和基础交互
- 运行时数据导出与效率基线统计
- 键盘布局生成、MSKLC 打包与安装链

更完整的理论背景、术语和桥接说明请从 [docs/README.md](docs/README.md) 进入；当前实现边界与指标则分别看 [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md) 和 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md)。

## 快速开始

当前根目录 README 只保留最短入口。

1. 环境与安装：看 [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md)；如果只想走 Python 3.12 快速路径，再看 [QUICKSTART_PY312.md](QUICKSTART_PY312.md)。
2. 启动当前 Windows 输入法原型：使用 `python -m yime.input_method.app` 或 `python run_input_method.py`。
3. 判断当前实现边界：看 [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md)。
4. 进入细分文档：从 [docs/README.md](docs/README.md) 开始。

## 项目结构

```text
YIME/
├── yime/                 # 当前输入法主线代码
├── docs/                 # 文档入口与约束说明
├── tests/                # 自动化测试
├── pinyin/               # 拼音相关处理
├── syllable/             # 音节分析与中间层
├── scripts/              # 辅助生成脚本
└── external_data/        # 外部数据源
```

## 文档入口

根目录 README 只保留入口导航；细分文档统一从 [docs/README.md](docs/README.md) 进入。

- 当前实现边界： [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md)
- 安装与启动： [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md)、 [QUICKSTART_PY312.md](QUICKSTART_PY312.md)
- 设计约束与清理边界： [docs/CODEPOINT_POLICY.md](docs/CODEPOINT_POLICY.md)、 [docs/SOURCE_AND_ARTIFACTS.md](docs/SOURCE_AND_ARTIFACTS.md)

## 进一步信息

- 协议与协作： [LICENSE](LICENSE)、 [NOTICE.md](NOTICE.md)、 [COMMERCIAL_LICENSE.md](COMMERCIAL_LICENSE.md)、 [CONTRIBUTING.md](CONTRIBUTING.md)
- 仓库与反馈： [tsaanghwang/YIME](https://github.com/tsaanghwang/YIME)、 [Issues](https://github.com/tsaanghwang/YIME/issues)
