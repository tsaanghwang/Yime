# YIME 文档中心

欢迎来到 YIME（音元输入法编辑器）文档中心！

说明：本文档中心优先组织当前 Windows 桌面输入法原型直接相关的主线材料；理论、术语和音系分析类文档主要作为背景与长期参考，不等于当前仓库均已实现。

补充说明：仓库内旧的 `docs/*.html` 静态文档站已外置到单独的 `Yime-docs-html-site` 仓库；当前主仓库以本目录下的 Markdown 文档作为维护中的文档主线。

---

## 📚 文档导航

建议阅读顺序：先看 [../README.md](../README.md) 了解项目边界，再看 [project/INPUT_METHOD_SOLUTION.md](project/INPUT_METHOD_SOLUTION.md) 确认当前输入法主线，最后再按需要进入理论、术语和生成链文档。

### 重要设计约束

- **[码点与中间层策略](CODEPOINT_POLICY.md)** - 说明 `N01-N24`、`M01-M33` 的语义层地位，以及 canonical 与 projection 的分工
- **[真源文件与生成产物清单](SOURCE_AND_ARTIFACTS.md)** - 区分哪些文件是设计真源，哪些文件只是可重建产物
- **[音元系统术语说明](YINYUAN_TERMINOLOGY.md)** - 说明“时段”“片音”“音元”等核心术语的中英文定义与相互关系
- **[Terminology of the Yinyuan System](YINYUAN_TERMINOLOGY_EN.md)** - The English counterpart of the terminology note for external readers
- **[片音与语音技术单位的对应关系](PIANYIN_TECH_BRIDGE.md)** - 说明片音如何与语音识别、语音合成中的技术单位建立对应关系
- **[Correspondence Between Pianyin and Speech-Technology Units](PIANYIN_TECH_BRIDGE_EN.md)** - English note on how pianyin relates to units used in speech recognition and synthesis

### 快速开始

- **[安装指南](install/INSTALLATION_GUIDE.md)** - 当前 Windows 桌面输入法原型的主安装入口
- **[便携版发布指南](install/PORTABLE_RELEASE_GUIDE.md)** - 用 PyInstaller 打成无需 Python 的 Windows 独立目录
- **[MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)** - 最短的 Windows 键盘生成、打包、安装、回滚路径
- **[Python 3.12 快速开始](install/QUICKSTART_PY312.md)** - 最短启动路径，适合已理解当前主线后快速跑起原型
- **[无管理员权限安装](install/PORTABLE_PYTHON_GUIDE.md)** - 使用便携版 Python 3.12 的无管理员权限安装路径
- **[使用说明](USAGE.md)** - 基本使用方法和示例
- **[状态反馈速记](STATUS_FEEDBACK.md)** - 说明状态栏、弹窗、诊断脚本各自负责显示什么
- **[跨窗口稳定性手工回归清单](CROSS_WINDOW_REGRESSION_CHECKLIST.md)** - 只保留当前最值钱的真实 Windows 跨窗口回贴回归场景
- **[反查编码与用户词库操作说明](REVERSE_LOOKUP_AND_USER_LEXICON.md)** - 说明如何反查字词编码、查询用户频率、备份/迁移用户词库以及使用 seed 初始化词库
- **[反查编码与用户词库速查](REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md)** - 一页看完最常用的反查、加词、备份和调序诊断操作
- **[快速入门](../README.md)** - 项目概述和快速开始

补充说明：上面这一组链接应理解为当前推荐入口；如果某份文档只是保存试验经过、旧机器现象或历史调查，请不要把它直接当成当前操作手册。

KLC 文档分工：

- `MSKLC_RELEASE_QUICKSTART.md` 是当前键盘布局链的主入口。
- `MSKLC_PRECOMPILE_CHECKLIST.md` 只负责打包前检查。
- `KEYBOARD_LAYOUT_PIPELINE.md` 解释生成链分层与职责。
- `REBUILD_KEYBOARD.md` 只补充速记页之外的检查、验证和排错说明。
- `windows-klc-workflow.md` 保留同口径的流程备忘，不再作为优先入口。

### 核心文档

- **[输入法实现方案](project/INPUT_METHOD_SOLUTION.md)** - 当前 Windows 桌面输入法原型的实现状态、边界和后续方向
- **[效率基线报告](EFFICIENCY_BASELINE.md)** - 基于现有运行时候选导出生成的第一版效率指标表
- **[API 参考手册](API.md)** - 完整的 API 文档和示例
- **[开发者指南](DEVELOPMENT.md)** - 开发环境配置和最佳实践
- **[常见问题](FAQ.md)** - 常见问题解答

### 技术文档

- **[音元理论](THEORY.md)** - 音元系统理论基础
- **[理论索引](THEORY_INDEX.md)** - 理论文档总入口与实现约束入口
- **[架构设计](ARCHITECTURE.md)** - 系统架构和设计说明
- **[数据库设计](DATABASE.md)** - 数据库结构和设计

### 项目管理

- **[路线图](project/ROADMAP.md)** - 项目发展路线图
- **[更新日志](../CHANGELOG.md)** - 版本更新历史
- **[贡献指南](../CONTRIBUTING.md)** - 如何贡献代码

### 历史记录与归档

- **[MSKLC 编译与安装历史记录](../internal_data/msklc_compile_install_report.md)** - 2026-04 的本机调查记录，仅供追溯当时的编译/安装现象，不代表当前推荐流程

---

## 只保留三种用法

### 1. 我只想按当前主线操作

1. 看 [安装指南](install/INSTALLATION_GUIDE.md) 或 [Python 3.12 快速开始](install/QUICKSTART_PY312.md)
2. 涉及 Windows 键盘布局时，从 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md) 进入
3. 遇到问题时，再回看 [FAQ.md](FAQ.md) 与 [DEVELOPMENT.md](DEVELOPMENT.md)

### 2. 我想理解文件和生成链

1. 先看 [SOURCE_AND_ARTIFACTS.md](SOURCE_AND_ARTIFACTS.md)
2. 再看 [KEYBOARD_LAYOUT_PIPELINE.md](KEYBOARD_LAYOUT_PIPELINE.md)
3. 需要术语背景时，再看 [YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md) 与 [THEORY_INDEX.md](THEORY_INDEX.md)

### 3. 我只是在追旧记录

1. 先确认目标文档是否被明确标成“历史记录”“归档”或“调查记录”
2. 不要把这类文档直接当成当前操作手册
3. 当前流程仍以本页“快速开始”和上面的 KLC 主入口说明为准

## 获取帮助

1. 先查 [FAQ.md](FAQ.md)
2. 再看 [DEVELOPMENT.md](DEVELOPMENT.md) 或仓库根目录的 [README.md](../README.md)
3. 需要外部反馈时，再去 GitHub Issues 或 Discussions

---

**最后更新**: 2026-04-11
**文档版本**: 1.0.0
