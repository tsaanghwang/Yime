# 开发与测试分支交接

## 2026-11-06 当前接续：ARM64 `.8` 固定候选与后续源码回归

[PR #113](https://github.com/tsaanghwang/Yime/pull/113) 的 ARM64 固定修复候选为 **`.8`**：源码 `ac326cbae438fc129e2e2a493b0342a8b8dbd479`，run `42185512418` **attempt 2**，artifact `13487852082`。[固定候选包](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13487852082)内层 `YimeCore-18u-0.2.0-18u-arm64.8-windows-arm64.zip` 的 SHA-256 为 `85191b5c9926c5090ddabc5117fe7e1d43e3981527903c68f3051906cfb50a6c`；同版本名的其他 CI 输出不替换这一固定身份。

后续源码接续包括 READY 启动合同回归，以及截至 `5400ec62` 的构建环境、输出路径和旧启动项检查修复，见[READY 本地验证](../../docs/testing/18u/2026-11-06/broker-ready-contract/RESULT.zh-CN.md)和[review 跟进](../../docs/testing/18u/2026-11-06/broker-ready-contract/REVIEW-FOLLOWUP.zh-CN.md)。这些源码与离线 CI 结果不表示上述固定 `.8` 包已包含后续修复，也不将新的同版本 CI 产物自动提升为交付候选。

ASUS `.8` 验收接续文档已获准合入，见[固定身份、前态重确认与现场接续范围](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)。文档区分包内只读 Check、安装后身份核验、共享前端/TIP 与独立 Broker 阶段及停止/恢复条件；旧 `.7` 路径、命令和默认回退假设不得继承，当前 ASUS 安装身份仍须将来在本机重新确认。本次批准仅提交文档，不授权安装、注册、卸载或现场测试，继续保留 ARM7-UI-01 暂不修改、不继续交互验收的决定。

**旧 `.7`（源码 `9636eaff`）是受已知 Broker 启动缺陷影响的历史交付，不再作为当前修复候选。** 下方 `.7` 的升级、检查及用户成功反馈保留原机器、原包和原观察范围，不改写或否定原记录，也不继承为 `.8` 或后续源码的现场验收。ARM7-UI-01 的历史反馈与暂不修改决定保持。

本轮只做源码、离线回归和交接文档更新，没有读取或改变当前安装状态，没有安装、注册、启动真实 TIP/宿主或修改默认输入法与用户数据。本节不发起新的安装或现场验收任务。下方各段中的“当前”“已安装”“未执行”均是各自阶段的历史快照，不能据此断言本机现在安装了哪个版本。


> 历史快照索引（2026-11-03）：当日主线 `64a785a7`、安装版 18u test.6/test.7、ARM64 候选及各机器结果见[项目现状](../../docs/YIME_PROJECT_ASSESSMENT.md)。其中候选与主线的区分、未完成项仅适用于当日记录，不覆盖下方 11 月 4—6 日的后续进展；各段结论仍绑定原机器、包和阶段，不跨版本继承验收。本次文档接续不新增执行任务。

2026-09-14 起恢复 Git 分支交接。本阶段开发分支 `codex/yimecore-replacement-experiment` 收尾后退役；后续从最新 `main` 创建按目标命名的 `codex/*` 开发分支；“计算机”测试分支：`perf/i7-7820x-local`。当前文档是唯一接续入口，共享目录中的旧指令停用。

## 历史任务快照（下列“当前”均为当时状态）

**2026-11-06 ASUS ARM64 `.7` 升级与本轮验证已归档。** 固定源码仍为 `9636eaff`，正常升级退出 0，安装后 14/14 核对和原生注册只读查询通过。记事本自动跟随、短文本输入、切页取消及设置返回恢复已有本轮现场证据；用户反馈浏览器可以输入。完整跨应用取消序列及完整手指／笔矩阵仍未完成。键盘高度几乎遮住笔记本焦点光标列为 **ARM7-UI-01 待处理**，用户要求暂不修改，当前不继续交互验收。详见[本轮升级与验证归档](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-UPGRADE-RESULT.zh-CN.md)。下方交付阶段的“未安装／未执行”保留为当时快照，不代表当前 `.7` 安装状态；不要重复已通过项目。

**2026-11-06 ARM64 `.7` 最终整合包已交付。** 源码 `9636eaff` 兼容合入 main `45be140e` 的字体/检查宿主修复，9 项 CI 全通过；完整包已下载核验 46 文件、39 载荷、六个 ARM64 PE 和 v2 配套，华硕包内只读 Check 通过。[固定 artifact、两层 SHA-256 与证据](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/INTEGRATED-DELIVERY.zh-CN.md)；[ASUS .7 现场步骤](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)。现有 `.5` 未升级，真实自动跟随、升级/回退和手指/笔均未执行；原 `.6` 未安装并保留历史身份。下方记录不相互继承运行或现场结果。

**2026-11-06 ARM64 共享前端 v2 完整包已交付。** 从固定 main `39bfc4a34566220af4aba5d7799d12432d8d4013` 接入原生 ARM64 前端、TIP v2、安装证明与完整制包，保持共享盘面和资源锁。源码 `cc6a8d18` 的 7 项 CI 全部成功；`.6` 配套包已实际下载核验 46 文件、39 载荷及六个 ARM64 PE，包内只读 Check 通过。固定 artifact、两层 SHA-256、原生测试和候选区分见[完整交付](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/DELIVERY.zh-CN.md)，后续顺序见[ASUS 现场步骤](../../docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)。当前已安装 `.5` 保持；实际升级、真实宿主自动跟随、手指/笔均未执行。下述 x64 包和同名旧候选不能替代本次固定 ARM 包。

**2026-11-06 test.13 本地修复候选。** 新分支修复原生宿主注册表实际长度处理和前端私有字体路径生命周期，补齐旧行为负对照并重建完整候选；源码、逐文件/ZIP 身份及验证边界见[修复与候选交付](../../docs/testing/18u/2026-11-06/test13-host-font-fixes/DELIVERY.zh-CN.md)。本地预览正常退出一次，仍不代表安装或 D1/D2 通过。既有符号链接夹具因普通权限未完成，须在 CI 补齐；当前未安装，安装另行执行。原 test.12 包和 D1 预检阻断、D2 未运行及前端退出崩溃证据原样保留，下方历史交付不被新候选覆盖。

**2026-11-06 main test.12 固定包已核验。** PR #100 已合并，main 源码 `36ca828b3531d6c61740e02b6835aa930442b97a` 的五项 CI 全部成功。固定 [run 41993377945 / artifact 13399696130](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130) 的完整包已下载，核验两层 ZIP、46 个文件、六个 AMD64 PE、同源 v2 前端/TIP 与资源。准确链接、SHA-256、到期时间及 PR 临时合并包区别见[main 交付记录](../../docs/testing/18u/2026-11-06/main-test12-delivery/DELIVERY.zh-CN.md)；MSI 后续引用[固定收包身份与范围](../../docs/testing/18u/2026-11-06/main-test12-delivery/MSI-HANDOFF.zh-CN.md)。本轮只补源码内交付记录，没有安装、注册、默认输入法或用户数据变更，也没有发起 MSI 安装/验收。以下 PR 阶段和旧包段落保留当时状态。

**2026-11-05 main 整合 PR。** 从最新 main `64a785a7` 合入准备分支 `862bf7f2`，包含 PR #99 及 `f3056aab` 的暂停模式偏好修复，保留 main 诊断改动和历史证据。制包工作流补齐 main PR/push，整合版使用 test.12；本地回归与尚待 CI 完成的符号链接用例见[整合审阅与交付门槛](../../docs/testing/18u/2026-11-05/main-integration/REVIEW.zh-CN.md)。当前只提交 PR，不安装、不变更注册或默认输入法；test.11 下述交付保持原版本范围，不代表 test.12 包或真实宿主/物理验收。

**2026-11-04 test.11 自动跟随完整包交付。** PR #99 已以 `c0e67e47` 合入 MSI 准备分支；其后继版本源码 `aed81162` 的三项 CI 均通过，同源 v2 前端与 TIP 完整包已下载并核验全部 46 个文件。见[固定下载、两层 ZIP SHA-256 与验证记录](../../docs/testing/18u/2026-11-04/auto-focus-test11/DELIVERY.zh-CN.md)。未安装、未改输入法注册或默认设置、未重复 test.8 实测；自动跟随真实宿主和物理验收仍未执行。下方旧版本交付保持历史范围。

**2026-11-04 test.10 翻页键对齐。** 按用户新要求将左右翻页键分别向内移动，与盘面各行首／末键的外沿对齐，继承 test.9 自动适配。前端现有回归、包装器与离屏绘制检查通过，见[本轮记录](../../docs/testing/18u/2026-11-04/pager-alignment/DEVELOPMENT.zh-CN.md)。源码 `853eb017` 的三项 CI 已通过，test.10 完整包已下载并核验；见[固定交付](../../docs/testing/18u/2026-11-04/pager-alignment/DELIVERY.zh-CN.md)。当前安装仍为 test.8。

**2026-11-04 当前交付：test.9 自动适应屏幕。** 用户确认 test.8 重启后选输入法、绑定和声音正常；剩余盘面默认尺寸问题已加入安装版自动适配工作区、等比放大与设置入口，保留独立毫米校准。见[开发与验证](../../docs/testing/18u/2026-11-04/screen-fit-development/DEVELOPMENT.zh-CN.md)。固定源码 `785724e8` 的三项 CI 已通过，完整 test.9 包已下载并核验；见[固定交付](../../docs/testing/18u/2026-11-04/screen-fit-development/DELIVERY.zh-CN.md)。当前安装仍是 test.8，尚未执行新包维护；不单独替换 EXE。

**2026-11-04 最新反馈：test.8 记事本重开后绑定与输入复测成功。** 已正常升级并核对完整包；用户退出 Notepad 后重新打开，切换到“18键宽”键盘，可以绑定和输入。此前同进程已有两条 `bound` 日志。今天最早失败时未选独立18u；昨天已选仍失败的记录及后续上下文未知的错误均保留，详见[最新反馈](../../docs/testing/18u/2026-11-04/msi-test8-upgrade/BINDING-FOLLOWUP.zh-CN.md)。这是用户报告的记事本复测结果，不扩展为全部触点、应用或持续稳定性验收；不要求重复安装、重启或重做该步骤。下方为历史开发交接。

**2026-11-04：test.8 记事本绑定修复接续。** 首次失败记录保留；普通应用真人触屏中文闭环尚未通过，Word只有绑定报告。已修复顶层／正文线程身份不一致的源码缺陷，加入持久绑定诊断、一次实测校准与居中缩放；本次没有证据将源码缺陷定为首次记事本失败根因。源码和本地验证见[开发记录](../../docs/testing/18u/2026-11-04/test8-development/DEVELOPMENT.zh-CN.md)，固定新包及CI见[本轮交付](../../docs/testing/18u/2026-11-04/test8-development/DELIVERY.zh-CN.md)。新包正常维护后仅按[最小复验](../../docs/testing/18u/2026-11-04/test8-development/RETEST.zh-CN.md)记录一次记事本绑定与手指中文提交；不重复已通过的安装、重启或自有宿主用例。下方test.7交付与结果均保留为历史。

> 历史证据边界（MSI test.7，2026-11-03）：[固定自有宿主脱敏回传 `ff7349be`](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/REVIEW.zh-CN.md)仅支持一次 CN/variable 实际激活、已安装 DLL 加载及提交/读回通过；原始证据留 MSI 本机。该记录未完成普通应用、指笔、其他模式及独立启动验收；此限定不否定后续 test.8 用户反馈，也不将其继承为 test.7 或 test.12 验收。不自动重复已通过用例。

**2026-11-03 22:50 +08:00：MSI test.7 自有宿主单次闭环通过，脱敏回传已固定。** MSI 本地 Codex 审阅确认：当前桌面用户与安装用户一致，以非管理员身份执行；固定包与 45 个安装文件核验通过，Windows 实际激活注册 profile、加载已安装 DLL，一次 CN/variable 提交为 `applied`，非空读回匹配，Runtime/host/Broker 正常退出。仅执行一次，无自动重试；默认输入法相关注册、受保护文件与机器注册比较未变。
已取得固定提交 `ff7349be` 的[脱敏审阅结果](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/REVIEW.zh-CN.md)及[证据索引](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/evidence-index.json)。原始报告和日志留在 MSI 本机；索引哈希用于固定本机证据，不代表原始内容已公开可取，本地路径也不是公开核验链接。本次仅覆盖自有宿主，不代表 Word／Edge、翻转、手指或笔通过；不重复已通过用例。

**2026-11-03：MSI 完整触控前端与普通应用 TSF 接入开发。** 分支 `codex/msi-18u-test-preparation-20261103`。
新增安装版前端、专用 TIP 线程内最终编辑端点、同源完整 test.7 制包路径及隔离回归。
本机完整前端三模式内存检查、Go 回归与原生内存 TSF 编辑回归通过；最终 `33b7113c` 的完整 MSVC/离线/制包 CI 已通过，完整 test.7 下载及哈希见[固定交付](../../docs/testing/18u/2026-11-03/msi-preparation/TEST7-DELIVERY.zh-CN.md)。
本段开发交付时 MSI `WIN-JTKUT7KBVN7` 仍保留 test.6、尚未新安装；这是历史状态，当前 test.7 自有宿主进展以上方 22:50 本地审阅记录为准，真人实测仍未完成。
当前实现、边界和验证入口见[前端开发交接](../../docs/testing/18u/2026-11-03/msi-preparation/FRONTEND-DEVELOPMENT.zh-CN.md)。
下方 MyComputer 记录仍仅属于该机器，不代表 MSI 或新版前端验收。

**2026-11-03：MyComputer 正常升级接续 PR #95。** 用户已授权修复、正常卸载、升级及重启；
test.2 仍完整，管理员独占打开及占用查询确认当前已释放。test.3 原失败未记录错误码，不能追认历史占用者。
test.5 正常卸载已越过文件占用点，但移除 TIP 后同进程 API 缓存导致最终检查失败，COM/旧文件保留。
已定位并修复为独立进程完成最终注销，test.6 同源 CI 和完整包交付通过。
10:21 本机已从部分卸载状态完成正常卸载续行和 test.6 安装，双退出码 0，载荷/注册及保护基线通过。
10:47 已核验 10:28:22 的实际重启，重启后载荷/注册及保护基线通过。
11:02 固定 test.6 已安装入口前台执行通过：实际 profile/DLL 激活、TSF 提交及非空读回一致，
runtime/host/Broker 正常退出，载荷及保护基线未变。本轮闭环完成，无需重测。
范围限 CN/variable 自有宿主，暂不分发其他三台；保留所有旧包、数据和证据，
后续状态与固定包见 [test.6 交付](../../docs/testing/18u/2026-11-03/upgrade/TEST6.zh-CN.md)。
阶段状态与验证见[升级交接](../../docs/testing/18u/2026-11-03/upgrade/HANDOFF.zh-CN.md)。此前逐键输入成功用例不重测。

**2026-11-03：独立 18u installed-host 的整段输入错误已修复，重启后的提交读回用例通过。** 开发分支 `codex/18u-installed-input-events-20261103`，修复提交 `6915f8b9fc1d0978c578f06363e65244b5fe7cd5`，[PR #95](https://github.com/tsaanghwang/Yime/pull/95)。用户于 08:14 +08:00 在前台执行一次修复宿主，实际激活 Windows 注册 profile、加载已安装 DLL、完成 TSF 编辑并读回匹配；host/Broker 均退出 0，安装载荷未改变。**通过组合为新开发检查宿主 + 原 test.2 DLL/Broker，不是 test.4 整包安装验收。** 没有重装、替换标准版或改变默认输入法；旧包内检查器仍未替换，不要重复旧失败命令。接续者先读[本轮交接与原始证据](../../docs/testing/18u/2026-11-03/installed-input-fix/HANDOFF.zh-CN.md)。当前无需重复该用例；后续包交付或真实应用/物理输入须明确范围，不能继承本轮结论。

**2026-11-02：开发机安装本分支构建 `0.1.0-local.14-pr88`（源 `fdd075cd`，PR #88 合并前验证）。** 连读准入、`build-local-product.ps1`、`Build-Package.ps1`、`Setup.ps1 -Action Check`、自提升安装与已安装 x64/x86 注册宿主矩阵 6/6 均通过，记录见 [S3c 恢复方案 §9](../../docs/project/18u-self-developed-integration/S3C_RECOVERY_DELIVERY_REVIEW.zh-CN.md)。用户确认开发测试使用新版本正常，**保留为日常使用，不回滚**；`0.1.0-local.13` 固定包仍在 `C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312` 备用。本次为开发机自建自装，不是测试端完整包交付，不改默认输入法。

两项构建链路说明：连读准入必须在**同一源码树**内运行后再构建——导出器把准入绑定到构建树的相对路径与哈希，跨工作树复用会被 `export evidence source changed` 拒绝，这是设计意图；测试夹具运行根已改为 `%LOCALAPPDATA%\YimeBuildFixtures\<id>` 并在测试后移回构建根 `t\<id>`，长路径工作树不再触发 `Test TEMP is too long`。

**PR #78 后续：** 已合入 main 的 `9adc3cdd`，保留双方原始证据规则；复查补强了 ARM 制包的原生 admission 前置和 Go 持久配置隔离，并保留旧 x64 兼容。固定 R2 包未重制，详见[冲突与复查记录](../../docs/testing/arm64/2026-10-26/PR78-REVIEW.md)。

**2026-10-26：YimeCore ARM64 R2 已安装，原生 Notepad 受控检查及用户回报的两项物理键盘检查通过，验收尚未封版。** registered-host 首轮 **8/9**，失败单格复测通过，首失败根因仍未知。候选代码注释显示问题待修；其他真实 x64/x86 应用、重启与日用稳定性待验证，不能据此宣称真实应用三模式通过。[固定 Release](https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-proart-20261026-r2) 的[完整 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-arm64-proart-20261026-r2/YimeCore-ARM64-20261026-r2.zip) SHA-256 为 `2c94d825c59bf768d8a00a13353d38fe65f3b67e2258d3fb9747014229049de1`；安装、来源、CI 与完整测试见[包与安装记录](../../docs/testing/arm64/2026-10-26/PACKAGE-AND-INSTALL-TEST.md)。下方源码阶段段落保留历史状态。

**2026-10-26：华硕 ProArt 创 16 RTX Spark 的 ARM64 原生源码验证。** 系统型号为 `HUASHUONOTEBOOK` / ASUS ProArt P16 H7607BA。设备和固定桌面原型包首轮结果见[实机报告](../../docs/testing/arm64/2026-10-26/TEST-RESULT.md)；已接续完成 ARM64 Go/MSVC 工具链、27 个当前身份产物、305 个 Go test/subtest、DLL/COM、32 项失焦取消及三模式直接 TSF，见[原生源码报告](../../docs/testing/arm64/2026-10-26/NATIVE-SOURCE-TEST.md)。本地分支 `codex/arm64-native-test-20261026` 的证据通过相同 Git tree 的连接器快照发布至 [PR #78](https://github.com/tsaanghwang/Yime/pull/78)。下一步是 ARM64 包契约和完整包交付；当前 x64 安装器不用于此机，尚无安装态 registered-host、真实应用或重启输入结论。旧 `perf/i7-7820x-local` 仍仅作既有 x64 测试报告分支，本轮不向它写入 ARM 结果。

**2026-09-28：touch-terminal KLE 模板导入与实屏基线开发中；测试端无安装任务。** 目标分支 `codex/touch-terminal-kle-baseline` 从已合并 PR #64 的当前主线 `af8ea73f` 创建，并接续 9 月 22 日隔离浏览器原型。范围仅为 KLE 触摸几何模板、离线生成/校验、浏览器交互与已连接触摸屏的本地基线；不连接或修改已安装输入法，不改变默认输入法、用户词库或桌面键位真源。接续入口为 [运行说明](../../prototypes/touch-terminal/README.md)，另见 [验证记录](../../prototypes/touch-terminal/VALIDATION.md)、[适配协议](../../prototypes/touch-terminal/PROTOCOL.md) 和 [硬件可行性](../../prototypes/touch-terminal/HARDWARE.md)。触摸屏已以复制显示模式连接，但在真实手指测试记录完成前，不宣称误触率、端到端延迟或宿主输入通过。

**2026-09-27：current-readiness 双产品完整包已重建并发布为开发预发布；测试端无安装任务。** 目标分支 `codex/current-readiness-delivery-20260927` 从当前 main `0ab86312` 创建，两套运行源码和安装器均固定于完整提交 `0ab8631266736775bf1386f456d4a1d53e8e2eb3`。来源提交 [CI 35418522827](https://github.com/tsaanghwang/Yime/actions/runs/35418522827) 成功；交付记录提交 `a274730fd3230ff22c04632be62ffe18397555ec` 的 [CI](https://github.com/tsaanghwang/Yime/actions/runs/36280832479) 全部成功后，发布固定资产；远端 size 与 SHA-256 digest 已逐项匹配本地。

完整包 `Yime-Current-Readiness-20260927.zip`：**256650784 字节**，SHA-256：`45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341`。本地目录：`C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312`。[Release 页面](https://github.com/tsaanghwang/Yime/releases/tag/test-current-readiness-20260927-0ab86312)；下载：[Yime-Current-Readiness-20260927.zip](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/Yime-Current-Readiness-20260927.zip)、[Yime-Current-Readiness-20260927-Evidence.zip](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/Yime-Current-Readiness-20260927-Evidence.zip)、[SHA256SUMS.txt](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/SHA256SUMS.txt)。Git 源码 checkout 和自动 Source code ZIP 不等于收到完整包。

已通过来源/清单/逐载荷哈希、PE 架构、PS5 包检查、隔离维护模拟和 ZIP 逐成员验证；YimeCore 65 文件、Rime/PIME 160 文件。来源证据与工具链保存在独立 Evidence ZIP。详见 [交付记录](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/DELIVERY.md)、[固定上传清单](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/UPLOAD.md) 和 [机器可读包身份](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/delivery.json)。

**本轮未安装、卸载、重启已安装产品进程，未修改默认输入法或用户数据；新包未做实机输入验收。** 不将 9 月 19 日旧包的本机结果继承到本包，不要求测试 PC 同步、安装或重复历史维护；任何后续实机任务另行交接。

## 历史文档交接（2026-09-16，当时状态）

**2026-09-16：工程文档更新，测试端无新增执行任务。** 开发分支 `codex/project-docs-refresh` 从当前主线 `76376080` 创建，统一项目首页、现状、架构、路线图、测试及工具说明。本轮只改文档，不制作安装包，不要求测试端同步、安装或重测。当前概览见[项目现状](../../docs/YIME_PROJECT_ASSESSMENT.md)与[文档导航](../../docs/README.md)。

此前的安装器修复已通过 [PR #57](https://github.com/tsaanghwang/Yime/pull/57) 合入主线 `76376080`，[合并后 CI 35041052421](https://github.com/tsaanghwang/Yime/actions/runs/35041052421) 成功。修复补齐 YimeCore 图标和三个必需工具的包校验；Windows 拒绝移除用户输入配置时，在 COM 注销、启动项清理和文件删除之前停止。新增的包完整性与配置移除失败隔离回归已纳入 `simple-installer` CI。

**包含 PR #57 修复的新完整包尚未交付，也没有该新包的实机安装或输入验收。** 下方已验收 ZIP 不包含这些修复。下一次需要实机测试时，另行发布具体范围、通过 CI 的源码提交、完整包 URL 与 SHA-256；不能因本轮文档更新重复执行历史步骤。

## 已完成阶段记录

**2026-09-15 本阶段已完成。** PR #55 的主线代码及 CI 已通过；测试端已同步主线 `86005b58`，回传 `1509b860` 已收取，见[同步报告](../../docs/testing/simple-maintenance/2026-09-15/main-sync/TEST-RESULT.md)和[阶段收尾复核](../../docs/testing/simple-maintenance/2026-09-15/main-sync/REVIEW.md)。测试端当前无待执行任务。同步执行单和下方安装步骤仅作历史记录，不因收尾文档合并再要求测试机同步、安装或重测。下一阶段另建开发分支并发布新的具体任务。

**本轮验收已完成，测试端无需再次安装或重测。** 已收取安装/重启报告 `85aec9c4` 和应用补充 `7ab9566f`，并补齐收包记录 `50f70a9c`。两套产品在“计算机”的 Codex 与记事本中重启前后均可输入，原始日志和 10 个证据文件校验通过，见 [开发端复核](../../docs/testing/simple-maintenance/2026-09-14/source-candidate-test/REVIEW.md)。保留两套安装，正常使用；下方下载和操作步骤作为本轮已执行记录，不是新任务。

清理后的两套程序现已从源码构建并在开发机替换安装，用户确认重启前后均可正常输入，见 [本轮源码候选包验收](../../docs/testing/simple-maintenance/2026-09-14/source-candidate/DEVELOPMENT.md)。YimeCore 首次注册遇到 `0x800700B7`，稍后重试成功，原始失败和重启处理建议保留在报告中。

本轮代码提交 `a4fa6f7616b41658361a9f5b14ea3c96311ed8b0` 的 [CI 34856928836](https://github.com/tsaanghwang/Yime/actions/runs/34856928836) 已成功。当时交付的完整包及安装、两套输入和重启确认现已完成。不重复历史维护矩阵。`5c9a5d77` 的已完成维护结果仍见 [验收汇总](VALIDATION.md) 与 [原始报告索引](../../docs/testing/simple-maintenance/2026-09-14/README.md)。

## 历史完整包与已完成操作（2026-09-14）

- [候选包发布页](https://github.com/tsaanghwang/Yime/releases/tag/test-simple-source-a4fa6f76)
- [下载完整安装包](https://github.com/tsaanghwang/Yime/releases/download/test-simple-source-a4fa6f76/Yime-Source-Candidate-20260914.zip)
- 文件：`Yime-Source-Candidate-20260914.zip`，256617810 字节。
- SHA-256：`8474875273b42404e8d1e6a29206216a329aca44e6b01499a0e749170ae3021d`。
- 安装器及应用源码均对应本轮已验收内容。包在提交前从工作区构建，包内 `BUILD-PROVENANCE.json` 保留当时基础提交 `58e360a5`、源码快照和两套产品清单哈希；构包时的 `pending` 不是当前验收状态，后续结果见本轮开发验收报告。此处交接更新仅为文档，不更换已验收 ZIP。

1. 按下节同步分支。下载上述 ZIP，核对文件大小和 SHA-256，完整解压至测试机本地新目录。不要使用 GitHub 自动生成的 Source code 压缩包，也不要从共享 `.tmp` 取包。
2. 保存工作，退出 Word 等输入法宿主，切换到英文键盘。运行解压目录中的 `Install-Uninstall.cmd`，Action 选 `1`，Product 选 `3`，允许 UAC，完成两套安装。无需预先手工删除目录、注册项或用户数据；如仍有旧安装，由包自身处理。
3. 分别选择两套输入法，在 Word 和测试机可用的另一常用应用输入并上屏。记录实际测试的应用；不为本轮专门安装额外宿主。
4. 保存工作、正常重启并登录，再分别确认两套输入法仍可输入。本轮结束保留两套安装，不再做最终卸载。
5. 在 `docs/testing/simple-maintenance/2026-09-14/source-candidate-test/TEST-RESULT.md` 记录包哈希、安装前状态、各步骤结果及真实应用名称，附本次安装父子日志，通过 `perf/i7-7820x-local` 提交推送。不要只回传“成功”而缺少包身份。

若显示文件占用，退出相关应用后重试，不能释放就取消并正常重启后重试。若发生与开发机相同的注册 `0x800700B7`，保留本次日志，正常重启后再运行同一完整包一次；不能把重试成功记成首次成功。重启后仍失败或出现其他错误，回传本次失败与日志，由开发端处理；不接续旧恢复脚本，不反复尝试。

## 下一阶段测试端接收

当前无需执行接收操作。下一阶段按新任务明确指定的主线或开发提交同步到 `perf/i7-7820x-local`；保留本地报告，普通合并后推送测试分支。具体分支、提交和测试范围由新交接给出，不继续拉取已结束的旧开发分支。出现分歧或冲突时保留现场并回报，不强制重置。

下一次需要实机验证时，开发端先完成本地构建、制包及相应验收，再推送并等待该提交 CI 成功；随后在本文件提供明确执行范围和包清单。完整包经 GitHub artifact/Release asset 下载，分支记录下载地址、大小、SHA-256、安装脚本提交和各运行载荷来源。拉取源码不等于收到安装包；缺包时反馈一次，由开发端补齐。

## 测试端回传

在 `docs/testing/simple-maintenance/<日期>/<本轮名称>/` 新建 `TEST-RESULT.md`，写明开发提交、包 SHA-256、机器/Windows、操作、实际结果和未测项。附本轮相关 `.user.log`、`.admin.log` 或小型 JSON 数据；不要提交用户词库、学习库、密码或无关应用数据。保持原报告不变，补充结论另写新报告。原始文件须按字节保留，参照已有 `raw` 目录属性和 SHA-256 索引。

只暂存本轮报告目录，提交并推送到 `perf/i7-7820x-local`，回报提交号。文档和测试结果不通过共享 `.tmp` 目录交回，也不在测试端改写安装器。

## 开发端收取

执行 `git fetch origin perf/i7-7820x-local`，先检查 `git log HEAD..origin/perf/i7-7820x-local` 及报告差异，再挑选报告提交合入当前开发分支。若报告与源码混在一个提交，按路径提取并注明来源，避免整分支回灌旧代码。将审阅结论写入同轮目录，更新本文的当前任务。

安装受阻时保留本次错误和父子日志即可；由开发端修复、验证、CI 成功后重新交付。测试端不接续历史恢复链。
