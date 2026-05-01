[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![GitHub Release](https://img.shields.io/github/release/tsaanghwang/YIME)](https://github.com/tsaanghwang/YIME/releases)
[![Python Version](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)

# 音元输入法编辑器 (Yinyuan Input Method Editor)

## 概述

音元输入法编辑器(YIME)，简称音元输入法，是以音元为码元的汉语音码输入系统。这套系统通过 52 个音元组织汉语音节编码，当前仓库已经能先用现有运行时数据证明一部分效率相关事实：

- **固定长度音节编码**：当前全拼主线下，每个带调音节对应 4 码。
- **词语重码控制已可量化**：当前运行时导出数据中，同码词语最大碰撞数为 5，全部词语编码桶都能落在默认首屏 5 个候选内。
- **频率加权命中率可先内部追踪**：按当前运行时 `sort_weight` 口径，词语加权首选命中率约为 96.59%，词语加权首屏可见率为 100.00%。
- **单字分级可以按规范字表同等数量对齐**：基线报告现在已经拆出一级 3500 字、二级前 6500 字、三级前 8105 字和全量四档，便于对齐常用字层的首屏命中改善。
- **同语料码长对照已可生成**：基线报告现在可在同一批运行时语料上并列计算音元全拼、音元简拼、标准全拼和抽象双拼的结构码长；当前总体上音元简拼平均码长约为 5.61 键，较音元全拼的 6.68 键减少约 1.07 键。
- **按带数字调号全拼口径，音元简拼平均码长更短**：在当前同语料结构码长基线下，若以带数字调号的标准全拼作为对照，音元简拼总体平均码长约少 1.30 键。这个结论只在显式标调的比较口径下成立，不直接外推到省调现行拼音输入。
- **单字仍是主要翻页压力**：当前运行时导出数据中，同码单字最大碰撞数为 513，后续优化重点应继续放在单字排序和首屏命中率上。
- **更精的音系表达**：音元系统与已有各种类型的语音系统相比，主要是在和音位系统对比时，能更准确地表达汉语语音系统的特征。

当前可重复生成的第一版指标表见 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md)。

## 实现范围说明

README 中涉及简拼、双拼、并击、动态组词、智能编码转换等表述，更多是在描述音元输入体系下的理论能力、设计方向或长期可能性，不等于当前仓库已经完整实现，或后续一定会全部进入开发。

当前项目的实际主线仍以 Windows 桌面输入法原型为主，优先处理全拼输入、候选显示、选字回贴、手动输入路径和基础稳定性。对于实现复杂度较高、超出当前个人精力或能力边界的功能，后续可能只保留为设计设想、研究记录或文档说明，而不承诺实际落地。

## 重要设计约束

在阅读实现、测试、键盘布局或数据库相关代码前，建议先阅读 [码点与中间层策略](docs/CODEPOINT_POLICY.md)。

该文档明确规定：

- `N01-N24` 与 `M01-M33` 是系统的语义槽位层，不是可删的临时中间产物。
- `PUA-B` 是长期规范承载层，`BMP PUA` 主要是当前平台投影层。
- 测试、重构、数据库调整和键盘布局生成不应绕过语义层直接修改字符结果。

如果后续实现与该策略冲突，应先审查实现链路，而不是先删除中间层或直接改库。

## 特性

这里区分两层信息：

- 第一层是音元输入体系本身的理论结构与长期设计方向。
- 第二层是当前仓库已经落到代码、数据基线和 Windows 输入法原型里的可运行主线。

阅读本仓库时，应优先以后者判断当前状态，不要把理论能力默认当成已经实现的功能。

### 理论与长期方向

音元系统用 52 个音元组织带调音节编码，强调首音/干音的结构分层，以及与现有拼音体系之间的精确对应关系。简拼、双拼、并击、更强的编码转换和更完整的输入模式，仍主要属于理论能力、设计方向或长期目标。

如果你想看这些理论细节、键盘布局示意、音符系统和术语说明，请从 [docs/README.md](docs/README.md) 进入，再看 [docs/THEORY_INDEX.md](docs/THEORY_INDEX.md)、 [docs/YINYUAN_TERMINOLOGY.md](docs/YINYUAN_TERMINOLOGY.md) 和 [docs/PIANYIN_TECH_BRIDGE.md](docs/PIANYIN_TECH_BRIDGE.md)。

### 当前可运行主线

当前真正进入可运行主线的，仍是 Windows 桌面输入法原型及其相关生成链：

- 全拼输入、候选显示、选字回贴和基础交互
- 运行时数据导出与效率基线统计
- 键盘布局生成、MSKLC 打包与安装链

当前指标和限制以 [docs/EFFICIENCY_BASELINE.md](docs/EFFICIENCY_BASELINE.md) 和 [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md) 为准。

## 快速开始

### 环境要求

- Windows 10 / 11
- Python 3.12.x
- 可选：Miniconda / conda
- 可选：Git LFS

### 安装步骤

```bash
# 克隆仓库
git clone https://github.com/tsaanghwang/YIME.git
cd YIME

# 推荐：创建并激活 Python 3.12 conda 环境
conda create -n yime_env python=3.12
conda activate yime_env

# 安装当前 Windows 输入法原型依赖
pip install -r requirements_py312.txt

# 启动输入法原型
python -m yime.input_method.app
```

### 使用说明

1. 优先阅读 [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) 完成 Python 3.12 环境配置。
2. 使用 `python -m yime.input_method.app` 或 `python run_input_method.py` 启动当前 Windows 桌面输入法原型。
3. 先看 [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md) 了解当前实现边界，再从 [docs/README.md](docs/README.md) 进入细分文档。

## 项目结构

```text
YIME/
├── yime/                 # Python 核心引擎
├── pinyin/               # 拼音处理模块
├── syllable/             # 音节分析模块
├── src/                  # 历史前端代码与实验性界面资源
├── docs/                 # 文档
├── scripts/              # 辅助脚本目录
├── tests/                # 测试文件
└── external_data/        # 外部数据源
```

## 文档入口

根目录 README 只负责项目边界、当前主线和最短启动路径；更细的文档导航统一从 [docs/README.md](docs/README.md) 进入。

- 当前实现边界： [INPUT_METHOD_SOLUTION.md](INPUT_METHOD_SOLUTION.md)
- 当前安装入口： [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md)
- 最短启动路径： [QUICKSTART_PY312.md](QUICKSTART_PY312.md)
- 无管理员权限安装： [PORTABLE_PYTHON_GUIDE.md](PORTABLE_PYTHON_GUIDE.md)
- 设计约束与产物边界： [docs/CODEPOINT_POLICY.md](docs/CODEPOINT_POLICY.md)、 [docs/SOURCE_AND_ARTIFACTS.md](docs/SOURCE_AND_ARTIFACTS.md)
- 其余背景、术语、开发和 KLC 文档：统一看 [docs/README.md](docs/README.md)

## 使用许可

本项目代码默认采用 [MIT 许可证](LICENSE)。如涉及商业授权或其他额外说明，请同时查看仓库中的相关许可证与说明文件。

## 技术支持

- GitHub 仓库： [tsaanghwang/YIME](https://github.com/tsaanghwang/YIME)
- Issues： [tsaanghwang/YIME/issues](https://github.com/tsaanghwang/YIME/issues)
- Discussions： [tsaanghwang/YIME/discussions](https://github.com/tsaanghwang/YIME/discussions)
- 贡献入口： [CONTRIBUTING.md](CONTRIBUTING.md)

## 核心团队

- Huang Chang (黄畅) - [yinyuanxitong@foxmail.com](mailto:yinyuanxitong@foxmail.com)
- 其他贡献者见 [CONTRIBUTORS.md](CONTRIBUTORS.md)
