# 开发与测试分支交接

2026-09-14 起恢复 Git 分支交接。本阶段开发分支 `codex/yimecore-replacement-experiment` 收尾后退役；后续从最新 `main` 创建按目标命名的 `codex/*` 开发分支；“计算机”测试分支：`perf/i7-7820x-local`。当前文档是唯一接续入口，共享目录中的旧指令停用。

## 当前任务

**2026-11-04 当前开发：test.9 自动适应屏幕。** 用户确认 test.8 重启后选输入法、绑定和声音正常；剩余盘面默认尺寸问题已加入安装版自动适配工作区、等比放大与设置入口，保留独立毫米校准。见[开发与验证](../../docs/testing/18u/2026-11-04/screen-fit-development/DEVELOPMENT.zh-CN.md)。当前安装仍是 test.8，新包须待固定提交 CI 完整制包；不单独替换 EXE。

**2026-11-04 最新反馈：test.8 记事本重开后绑定与输入复测成功。** 已正常升级并核对完整包；用户退出 Notepad 后重新打开，切换到“18键宽”键盘，可以绑定和输入。此前同进程已有两条 `bound` 日志。今天最早失败时未选独立18u；昨天已选仍失败的记录及后续上下文未知的错误均保留，详见[最新反馈](../../docs/testing/18u/2026-11-04/msi-test8-upgrade/BINDING-FOLLOWUP.zh-CN.md)。这是用户报告的记事本复测结果，不扩展为全部触点、应用或持续稳定性验收；不要求重复安装、重启或重做该步骤。下方为历史开发交接。

**2026-11-04：test.8 记事本绑定修复接续。** 首次失败记录保留；普通应用真人触屏中文闭环尚未通过，Word只有绑定报告。已修复顶层／正文线程身份不一致的源码缺陷，加入持久绑定诊断、一次实测校准与居中缩放；本次没有证据将源码缺陷定为首次记事本失败根因。源码和本地验证见[开发记录](../../docs/testing/18u/2026-11-04/test8-development/DEVELOPMENT.zh-CN.md)，固定新包及CI见[本轮交付](../../docs/testing/18u/2026-11-04/test8-development/DELIVERY.zh-CN.md)。新包正常维护后仅按[最小复验](../../docs/testing/18u/2026-11-04/test8-development/RETEST.zh-CN.md)记录一次记事本绑定与手指中文提交；不重复已通过的安装、重启或自有宿主用例。下方test.7交付与结果均保留为历史。

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
