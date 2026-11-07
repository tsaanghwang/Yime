# Yime 文档导航

更新：2026-11-03。项目保持 YimeCore 与 Rime/PIME 独立产品边界，同时推进隔离的 18u/CN134 输入链。主线、候选分支、固定包与实机结果以[项目现状](YIME_PROJECT_ASSESSMENT.md)统一索引，再按产品和任务进入专项资料。

## 当前工程入口

| 文档 | 回答的问题 |
|---|---|
| [项目现状](YIME_PROJECT_ASSESSMENT.md) | 哪些已实现、已交付或实测，哪些仍未完成？ |
| [开发路线图](YIME_DEVELOPMENT_ROADMAP.md) | 下一步按什么优先级推进，怎样判定完成？ |
| [系统架构](YIME_ARCHITECTURE.md) | 两套产品及共同数据链如何分工？ |
| [测试指南](YIME_TESTING_GUIDE.md) | 当前 CI 检查什么，哪些必须单独做原生与实机验收？ |
| [人工交互验收惯例](testing/INTERACTIVE_ACCEPTANCE_CONVENTION.zh-CN.md) | 各机器怎样统一分组操作、点选回报，并避免聊天后的输入法/焦点切换误判？ |
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

## 18u 与 ARM64 接续入口

| 范围 | 入口与证据边界 |
|---|---|
| 18u 便携原型 | [桌面交接](../prototypes/touch-terminal/desktop/HANDOFF.md)、[验收指南](../prototypes/touch-terminal/desktop/ACCEPTANCE_18U.zh-CN.md)；步骤绑定具体视图和包 |
| 18u 自研 TSF 主线 | [集成计划](project/18u-self-developed-integration/PLAN.zh-CN.md)、[异步与诊断记录](project/18u-self-developed-integration/S3C_NATIVE_ASYNC_GATES_HANDOFF.zh-CN.md)；历史编译/自有宿主不等于普通应用验收 |
| 18u 安装版候选 | [现状页来源表](YIME_PROJECT_ASSESSMENT.md#主线与候选来源)固定 test.6/test.7、验证分支及 task-results；分支合并不等于 main 合并 |
| 标准 ARM64 | [10 月 R2 包及安装报告](testing/arm64/2026-10-26/PACKAGE-AND-INSTALL-TEST.md)、[11 月候选汇总](YIME_PROJECT_ASSESSMENT.md#已有交付与实机证据)；标准产品、Rime/PIME 与 18u 候选分别判断 |

## 历史材料的使用

`docs/testing/`、带日期的验收报告和专项阶段记录保留当时的源码、包身份及结论。某份旧报告中“待执行”“未回传”或旧绝对路径不自动成为当前任务；当前状态由上述概览及同轮后续复核解释，原始文件不追改。

旧 NSIS、固定事务恢复链、Python 桌面原型及冻结身份的实验包不属于现行安装入口。当前源码通过 CI、旧包在实机通过、正式签名发行完成是不同结论，引用时必须保留这种区别。
