# YIME 文档中心

欢迎来到 YIME（音元输入法编辑器）文档中心！

说明：本文档中心优先组织当前 Windows
桌面输入法原型直接相关的主线材料；理论、术语和音系分析类文档
主要作为背景与长期参考，不等于当前仓库均已实现。

补充说明：仓库内旧的 `docs/*.html` 静态文档站已外置到单独的
`Yime-docs-html-site` 仓库；当前主仓库以本目录下的 Markdown
文档作为维护中的文档主线。

---

## 📚 文档导航

建议阅读顺序：先看 [../README.md](../README.md) 了解项目边界，
**改 `syllable/` 或用 AI 前读
[TERMINOLOGY_INDEX.md](TERMINOLOGY_INDEX.md)**，再看
[project/INPUT_METHOD_SOLUTION.md](project/INPUT_METHOD_SOLUTION.md)
确认当前输入法主线，最后再按需要进入理论、术语和生成链文档。

### 重要设计约束

- **[术语总入口（请先读）](TERMINOLOGY_INDEX.md)** -
  音元/片音/干音/乐音命名索引、常见误解、AI 提醒；
  链到中英文专题文档与 [syllable/NAMING.md](../syllable/NAMING.md)
- **[码点与中间层策略](CODEPOINT_POLICY.md)** -
  说明 `N01-N24`、`M01-M33` 的语义层地位，以及 canonical 与
  projection 的分工
- **[真源文件与生成产物清单](SOURCE_AND_ARTIFACTS.md)** -
  区分哪些文件是设计真源，哪些文件只是可重建产物
- **[音元系统术语说明](YINYUAN_TERMINOLOGY.md)** -
  「时段」「片音」「音元」及音节结构术语的中英文定义（专题正文）
- **[Terminology of the Yinyuan System](YINYUAN_TERMINOLOGY_EN.md)** -
  English counterpart
- **[片音与语音技术单位的对应关系](PIANYIN_TECH_BRIDGE.md)** -
  片音与 ASR/TTS 技术单位的衔接
- **[Correspondence Between Pianyin and
  Speech-Technology Units](PIANYIN_TECH_BRIDGE_EN.md)** -
  English bridge note

### 快速开始

- **[安装指南](install/INSTALLATION_GUIDE.md)** -
  当前 Windows 桌面输入法原型的主安装入口
- **[普通用户帮助](help/README.md)** -
  面向试用者的帮助总入口，包含快速开始、菜单与词库、
  故障排查几个子页
- **[便携版发布指南](install/PORTABLE_RELEASE_GUIDE.md)** -
  用 PyInstaller 打成无需 Python 的 Windows 独立目录
- **[安装包发布指南](install/SETUP_RELEASE_GUIDE.md)** -
  用 Inno Setup 打成可分发的 `Setup.exe`
- **[最小试用交付方案](install/MINIMAL_TRIAL_DELIVERY.md)** -
  把 `Setup.exe`、试用说明、验收清单和反馈模板收成一个
  默认交付目录
- **[朋友试装前最小验收清单](install/friend-trial-checklist.md)** -
  发给外部试装前，先用 10 分钟做一轮最小风险检查
- **[发给朋友的说明模板](install/friend-trial-message-template.md)** -
  发安装包时可直接复制改写的一段短说明
- **[试用者一页说明与最小键位对照](install/friend-trial-one-page.md)** -
  给外部试用者看的单页版：怎么唤起、怎么上屏、键位大致怎么看
- **[MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)** -
  最短的 Windows 键盘生成、打包、安装、回滚路径
- **[Python 3.12 快速开始](install/QUICKSTART_PY312.md)** -
  最短启动路径，适合已理解当前主线后快速跑起原型
- **[无管理员权限安装](install/PORTABLE_PYTHON_GUIDE.md)** -
  使用便携版 Python 3.12 的无管理员权限安装路径
- **[使用说明](USAGE.md)** - 基本使用方法和示例
- **[状态反馈速记](STATUS_FEEDBACK.md)** -
  说明状态栏、弹窗、诊断脚本各自负责显示什么
- **[跨窗口稳定性手工回归清单](CROSS_WINDOW_REGRESSION_CHECKLIST.md)** -
  只保留当前最值钱的真实 Windows 跨窗口回贴回归场景
- **[反查编码与用户词库操作说明](REVERSE_LOOKUP_AND_USER_LEXICON.md)** -
  说明如何反查字词编码、查询用户频率、备份/迁移用户词库，
  以及使用 seed 初始化词库
- **[反查编码与用户词库速查](REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md)** -
  一页看完最常用的反查、加词、备份和调序诊断操作
- **[词语调序规则说明](LOCAL_PHRASE_PRIORITY_RULES.md)** -
  说明当前局部词语优先规则何时触发、规则文件从哪里来，
  以及当前边界
- **[快速入门](../README.md)** - 项目概述和快速开始

补充说明：上面这一组链接应理解为当前推荐入口；如果某份文档
只是保存试验经过、旧机器现象或历史调查，请不要把它直接当成
当前操作手册。

KLC 文档分工：

- `MSKLC_RELEASE_QUICKSTART.md` 是当前键盘布局链的主入口。
- `MSKLC_PRECOMPILE_CHECKLIST.md` 只负责打包前检查。
- `KEYBOARD_LAYOUT_PIPELINE.md` 解释生成链分层与职责。
- `REBUILD_KEYBOARD.md` 只补充速记页之外的检查、验证和排错说明。
- `windows-klc-workflow.md` 保留同口径的流程备忘，
  不再作为优先入口。

### 核心文档

- **[输入法实现方案](project/INPUT_METHOD_SOLUTION.md)** -
  当前 Windows 桌面输入法原型的实现状态、边界和后续方向
- **[拼音数据迁移与运行时查词](project/PINYIN_DATA_MIGRATION.md)** -
  rebuild 链、SQLite 主路径、已删除 legacy 脚本
- **[连续输入候选组织草案](project/CONTINUOUS_INPUT_CANDIDATE_ORGANIZATION_DRAFT.md)** -
  说明连续输入阶段如何划分状态、组织候选，
  以及叠加现有单字兜底与词语优先
- **[效率基线报告](EFFICIENCY_BASELINE.md)** -
  基于现有运行时候选导出生成的第一版效率指标表
- **[API 参考手册](API.md)** - 完整的 API 文档和示例
- **[开发者指南](DEVELOPMENT.md)** - 开发环境配置和最佳实践
- **[常见问题](FAQ.md)** - 常见问题解答

### 技术文档

- **[音元理论](THEORY.md)** - 音元系统理论基础
- **[理论索引](THEORY_INDEX.md)** - 理论文档总入口与实现约束入口
- **[真源文件与生成产物清单](SOURCE_AND_ARTIFACTS.md)** -
  当前主线的结构边界、生成链分层与关键资产归属
- **[数据文件结构说明](DATAFILES.md)** -
  数据文件、导入产物与目录层次说明
- **[syllable 包说明](../syllable/README.md)** -
  音节分析、编解码目录、CLI 与 Phase 1/2 rebuild 边界

### 项目管理

- **[路线图](project/ROADMAP.md)** - 项目发展路线图
- **[更新日志](../CHANGELOG.md)** - 版本更新历史
- **[贡献指南](../CONTRIBUTING.md)** - 如何贡献代码
- **[授权文档索引](LICENSING_INDEX.md)** -
  统一查看许可文本、商业许可证说明、合同模板与法务审阅入口

### 历史记录与归档

- **[MSKLC 编译与安装历史记录](../internal_data/msklc_compile_install_report.md)** -
  2026-04 的本机调查记录，仅供追溯当时的编译/安装现象，
  不代表当前推荐流程

---

## 只保留三种用法

### 1. 我只想按当前主线操作

1. 看 [安装指南](install/INSTALLATION_GUIDE.md) 或
   [Python 3.12 快速开始](install/QUICKSTART_PY312.md)
2. 涉及 Windows 键盘布局时，
   从 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md) 进入
3. 遇到问题时，再回看 [FAQ.md](FAQ.md) 与
   [DEVELOPMENT.md](DEVELOPMENT.md)

### 2. 我想理解文件和生成链

1. 先看 [SOURCE_AND_ARTIFACTS.md](SOURCE_AND_ARTIFACTS.md)
2. 再看 [KEYBOARD_LAYOUT_PIPELINE.md](KEYBOARD_LAYOUT_PIPELINE.md)
3. 需要术语背景时，再看
   [YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md) 与
   [THEORY_INDEX.md](THEORY_INDEX.md)

### 3. 我只是在追旧记录

1. 先确认目标文档是否被明确标成“历史记录”“归档”或
   “调查记录”
2. 不要把这类文档直接当成当前操作手册
3. 当前流程仍以本页“快速开始”和上面的 KLC 主入口说明为准

## 2026-06 主线更新（维护摘要）

近期仓库清理与文档对齐要点：

- **数据 rebuild**：`source_pinyin.db` → prototype 导入 →
  `refresh_runtime_yime_codes`
- **运行时查词**：**SQLite** `pinyin_hanzi.db` /
  `runtime_candidates` 为主；JSON 导出可选
- **已删除**：`db_manager`、`run_db_setup`、`legacy_pinyin_tables`、
  `yime/legacy/`、`windows_candidate_box`、
  `yime/syllable_structure.py`、`yime/utils/syllable_compat/`
- **兼容保留**：`yime/syllable_decoder.py`
  （旧 import 路径；结构真源在 `syllable/codec/yinjie.py`）
- **静态兜底**：`pinyin_hanzi.json` 已 gitignore，缺失不影响主链
- **本地验证**：`scripts/run_tests.cmd`
  （unittest + pytest input_method）

细节与历史删除清单见
[PINYIN_DATA_MIGRATION.md](project/PINYIN_DATA_MIGRATION.md)、
[SOURCE_AND_ARTIFACTS.md](SOURCE_AND_ARTIFACTS.md)
（§6D 起为归档摘要，逐项清单查 `git log`）。

## 获取帮助

1. 先查 [FAQ.md](FAQ.md)
2. 再看 [DEVELOPMENT.md](DEVELOPMENT.md) 或仓库根目录的
   [README.md](../README.md)
3. 需要外部反馈时，再去 GitHub Issues 或 Discussions

---

**最后更新**: 2026-06-17
**文档版本**: 1.1.0
