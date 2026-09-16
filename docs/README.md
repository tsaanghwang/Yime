# Yime 文档导航

更新：2026-09-16。项目按 YimeCore 与 Rime/PIME 两个独立产品开发。先阅读当前概览，再按产品和任务进入专项资料。

## 当前工程入口

| 文档 | 回答的问题 |
|---|---|
| [项目现状](YIME_PROJECT_ASSESSMENT.md) | 哪些已实现、已交付或实测，哪些仍未完成？ |
| [开发路线图](YIME_DEVELOPMENT_ROADMAP.md) | 下一步按什么优先级推进，怎样判定完成？ |
| [系统架构](YIME_ARCHITECTURE.md) | 两套产品及共同数据链如何分工？ |
| [测试指南](YIME_TESTING_GUIDE.md) | 当前 CI 检查什么，哪些必须单独做原生与实机验收？ |
| [构建、交付与签名](YIME_RELEASE_AND_SIGNING.md) | 源码如何形成可追溯的开发包，正式发行还缺什么？ |
| [用户指南](YIME_USER_INSTALL_GUIDE.md) | 如何安装和使用，Rime/PIME 的工具怎样操作？ |
| [安装器](../installer/simple/README.md) | 单套/双套安装、卸载、重装、日志和数据重置 |
| [当前交接](../installer/simple/HANDOFF.md) | 测试机是否有新任务，具体接收哪一个包？ |
| [安装验证范围](../installer/simple/VALIDATION.md) | 各次包验证的产品、应用、成功条件和未测项 |

## 开发与专项资料

| 范围 | 入口 |
|---|---|
| 产品边界 | [双产品计划](project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md) |
| YimeCore 源码与平台实验 | [工具入口](../tools/yimecore/README.md)、[TSF 源码](../YimeTextServiceExperiment/README.md) |
| Rime/PIME | [Go 后端](../go-backend/README.md)、[Rime 集成](YIME_RIME_INTEGRATION.md) |
| 离线词库和编码 | [离线工具](../tools/lexicon/README.md)、[资料边界](lexicon/README.md)、[数据格式](YIME_DATA_FORMAT_REFERENCE.md) |
| 布局与候选评估 | [评估入口](../tools/evaluation/README.md) |
| 语流音变 | [规则与准入计划](project/MANDARIN_CONNECTED_SPEECH_PLAN.md) |
| 原生工具 UI | [开发指南](YIME_TOOL_DEVELOPMENT_GUIDE.md)、[UI 规范](YIME_NATIVE_UI_GUIDELINES.md) |
| 仓库维护 | [贡献指南](../CONTRIBUTING.md)、[工程约束](../AGENTS.md)、[PowerShell 入口](../tools/powershell/README.md) |

## 历史材料的使用

`docs/testing/`、带日期的验收报告和专项阶段记录保留当时的源码、包身份及结论。某份旧报告中“待执行”“未回传”或旧绝对路径不自动成为当前任务；当前状态由上述概览及同轮后续复核解释，原始文件不追改。

旧 NSIS、固定事务恢复链、Python 桌面原型及冻结身份的实验包不属于现行安装入口。当前源码通过 CI、旧包在实机通过、正式签名发行完成是不同结论，引用时必须保留这种区别。
