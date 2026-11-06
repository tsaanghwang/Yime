# 开发与测试分支交接

**2026-11-06 08:56：ASUS 已实际升级 `.5 / 636cef68`，20/20 项载荷与固定完整包一致。** 正常重启后单次标准安装返回 0，管理员日志确认注销/注册完成，Runtime/Broker/GUI 三进程均以普通用户身份运行。标准 YimeCore、Rime/PIME、默认输入覆盖项和原校准保持不变，两次 RunOnce 已消费，原失败记录保留。见[安装成功与复测交接](../../docs/testing/arm64/2026-11-06/binding-fix-package/installed-success/README.zh-CN.md)。本对话的升级工作完成；按用户确定的分工，由“继续工作”对话接续真实记事本绑定和中文输入。本轮尚未进行该项验收，不再重复安装。

**2026-11-06 08:41：真实重启已完成，第一次登录安装停在 Windows 提升未完成，仍是完整 `.4`。** 旧 DLL 随后又被 Explorer 与当前 Codex 加载。用户已准备处理 Windows 确认；已登记独立的第二次单次登录入口，保留首次记录及所有占用保护，正在等待本次正常重启的保存确认。见[明确重试 01](../../docs/testing/arm64/2026-11-06/binding-fix-package/explicit-retry-01/README.zh-CN.md)及[重启后只读证据](../../docs/testing/arm64/2026-11-06/binding-fix-package/post-reboot-0832/README.zh-CN.md)。本对话唯一执行升级；实际安装核验成功后，由“继续工作”对话接续记事本绑定和中文输入，暂不启动 GUI 复测。

**2026-11-06 08:05：已登记下次登录的一次性 `.5` 安装入口，用户确认已保存工作并允许正常重启。** 当前用户 RunOnce 的唯一值经 `StdRegProv` 写入和回读；不自动重试，不改默认或产品持久自启，旧文件占用检查保持。见[重启交接](../../docs/testing/arm64/2026-11-06/binding-fix-package/next-logon-handoff/README.zh-CN.md)。实际重启请求和随后安装仍须读本地独立日志，不能把准备完成当作升级成功；确认 `.5` 全载荷后才做真实记事本测试。

**2026-11-06：ASUS 同源 ARM64 `.5` 完整包已发布，安装尚未启动。** 固定源码 `636cef68`，全部产品程序重新构建，1156 个完整包文件及 20 个产品载荷逐项核验，最终本地目录原生 Check 通过，远端六附件摘要一致。完整交付及 SHA-256 见[交付记录](../../docs/testing/arm64/2026-11-06/binding-fix-package/DELIVERY.zh-CN.md)。当前仍安装 `.4`：旧 DLL 被资源管理器、当前 Codex 和含未保存文档的 Notepad 加载。未发起已知会在停止后台后失败的 Install，未强制关闭宿主；三产品文件/注册/启动项/进程、默认输入覆盖值和校准保持。已准备 `C:\dev\Yime-deliveries\18u-binding-636cef68-20261106\Install-18u-ARM64.cmd`，用户保存文档并正常重启后、重开 Codex/记事本前可走标准安装入口。安装授权继续有效；新版真实记事本绑定、中文正文和真人触摸均未验收，必须在安装身份核验后继续。

**2026-11-05 固定修复源码 CI 已通过。** `636cef68` 的四条工作流均成功，21 个任务成功、3 个手动任务按既有门控跳过，见[CI 回执](../../docs/testing/18u/2026-11-05/arm64-binding-focus/ci-receipt.json)。本次为源码交付；尚未发布完整安装包、执行升级或 ASUS 真实记事本复测。CI 预览包与测试证据不能替代同源完整安装包。

**2026-11-05：ASUS Broker 接入的正文焦点线程源码修复。** 独立分支修正 TIP、最终编辑与 Broker 三层把顶层线程当正文线程的限制，同时保留精确正文焦点、进程、祖先、TSF context 和世代校验；GUI 保留已返回的绑定错误。357 项 Go 测试/子测试通过、3 项完整资源用例跳过；ARM64 异步17组、标准失焦36项及专用激活替身检查通过。见[源码修复与验证](../../docs/testing/18u/2026-11-05/arm64-binding-focus/README.zh-CN.md)。未安装或真实记事本复测，ASUS 历史失败不改写。已同步主线 `36ca828b` 的状态：MSI test.8 重开记事本后已获用户绑定/输入成功反馈，不再沿用下方历史“两机均失败”作为 MSI 当前状态。新增 `focus` 协议必须随同源完整包交付，禁止单换组件。

**2026-11-04 最新真人回报：ASUS 参考线实测 100 mm，长度检查通过；记事本仍不能绑定，手指正文输入未通过。用户同时报告微星也不能绑定。** 两机分别保留安装身份与证据，汇总见[真实应用绑定问题](../../docs/testing/18u/2026-11-04/cross-machine-binding/README.zh-CN.md)。下方“待复测/待回填”属于此次回报前的阶段记录，不能继续作为当前结论。

2026-09-14 起恢复 Git 分支交接。本阶段开发分支 `codex/yimecore-replacement-experiment` 收尾后退役；后续从最新 `main` 创建按目标命名的 `codex/*` 开发分支；“计算机”测试分支：`perf/i7-7820x-local`。当前文档是唯一接续入口，共享目录中的旧指令停用。

## 当前任务

**2026-11-04：ASUS 18u `.4` 安装成功。结束快照为 `0.2.0-18u-arm64.4`，20/20 项载荷匹配。其他两产品及默认输入覆盖值保持未变。随后已依据 100 mm 参考线实测 57.5 mm 保存校准，已安装前端的软件检查 18/18 通过，测试 Job 已清空并重新核验恢复后的三个普通用户进程。** 当前固定源码 `6cea24bc665a4ded31e083a42bebd5d2d039832d`，版本 `0.2.0-18u-arm64.4`；软件校准保存与受控 TSF 检查不代表实体尺复测、真实记事本正文或真人手指输入通过；这些仍须单独记录。历史 `.2`/`.3` 首失败保留，未据 `.4` 的结果追认 `.3` 的锁来源。 继续读取[本轮记录](../../docs/testing/arm64/2026-11-04/binding-calibration/README.md)，不重复旧失败安装命令。

**2026-11-04 12:21（UTC+08）：ASUS `.3` 运行中升级仍未通过，原 `.1` 文件完整。** `cb77b675` 的固定 CI、完整包及新停止回归均通过，单次恢复原三进程后升级已越过 `GetOwnerSid` 竞态；随后旧 Broker EXE 的文件独占门禁返回 sharing violation 32，RM 未列使用者，因此在卸注册/复制前停止。原三进程已停止，标准两产品与默认输入覆盖值未变。私有原生夹具随后证实退出码与退出句柄完成之间存在时间差，正在用 `.4` 候选补齐强等待；尚不能认定历史锁来源。继续读取[本次记录](../../docs/testing/arm64/2026-11-04/binding-calibration/README.md)，不重复旧失败命令，不将候选包或源码 CI 写为已安装/真人通过。

**2026-11-04 11:42（UTC+08）：ASUS 18u 校准升级失败，正在修复安装器退出竞态。** 真人首测中 100 mm 线实测 57.5 mm，记事本绑定失败；记事本已证实为原生 ARM64。`c9676d17 / 0.2.0-18u-arm64.2` 源码 CI 与完整包交付通过，但对运行中的 `.1` 升级在查询已退出 Broker 的 `GetOwnerSid` 时失败，尚未卸注册或复制文件。当前仍保留 `.1` 的完整 20 项载荷，18u 三进程已停止；标准 YimeCore、Rime/PIME 和默认输入覆盖值未变，未重置用户数据。后续 `.3` 修复须经新固定提交、CI、完整包交付后才安装；不得重复 `.2` 失败命令或把旧 18/18 记为真人通过。当前接续见[本次记录](../../docs/testing/arm64/2026-11-04/binding-calibration/README.md)。下段三产品安装完成为此次升级前的历史状态。

**2026-11-04：本机 ARM64 三产品安装完成，准备真人实测。** 标准 YimeCore maint.1、独立 Rime/PIME 与 18u 触摸前端均已安装；默认输入和既有数据保留。标准注册宿主验证通过，Rime 最终普通父进程双架构 profile 验证通过后启动，18u 已安装完整 TSF 通路 18/18 通过。各自固定包与来源见[当前结果](../../docs/testing/arm64/2026-11-03/full-input/INSTALLED-RESULT.md)及[交付索引](../../docs/testing/arm64/2026-11-03/full-input/FINAL-DELIVERY.md)。真人手指/笔、100 mm 尺标、重启和日用仍分别待验；18u 当前只确认原生 ARM64 宿主。保留失败证据，不再将历史候选包作为当前安装入口。

**2026-11-03：本机 ARM64 全套输入准备。** 用户明确选择标准键盘 YimeCore + Rime/PIME 两个独立产品，并补齐完整 YimeCore 输入链和 18u 触摸前端。当前分支 `codex/arm64-complete-input-20261103`，从主线 `64a785a7` 整合 18u ARM 候选后开发；原工作树及 17u 历史材料保持。接续入口为[本机完整输入准备](../../docs/project/ARM64_COMPLETE_INPUT_INSTALL_2026-11-03.md)。安装要使用本任务同源 CI 通过后的固定完整包及 SHA-256；鼠标/受控 TSF 测试与真人手指、笔验收分开。下方 MyComputer 交接属于另一台机器，不能直接套用到 ASUS ARM64 本机。

**2026-11-03：MyComputer 正常升级接续 PR #95。** 用户已授权修复、正常卸载、升级及重启；
test.2 仍完整，管理员独占打开及占用查询确认当前已释放。test.3 原失败未记录错误码，不能追认历史占用者。
test.5 正常卸载已越过文件占用点，但移除 TIP 后同进程 API 缓存导致最终检查失败，COM/旧文件保留。
已定位并修复为独立进程完成最终注销，test.6 待同源 CI/交付后续行正常卸载、安装和重启；保留所有旧包、数据和证据。
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
