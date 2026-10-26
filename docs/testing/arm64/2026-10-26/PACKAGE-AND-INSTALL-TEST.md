# ARM64 完整产品包与安装验收

本轮接续用户“请继续”的授权，在 HUASHUONOTEBOOK / 华硕 ProArt 创 16 RTX Spark 上推进 **YimeCore**。Rime/PIME 保持独立 x64 产品；本轮没有将其移植为 ARM64，也不修改 CN134/18u 键盘实验室的数据或几何。

R2 已完成固定包交付、本机安装和原生 ARM64 现代 Notepad 的受控 UI 输入检查，用户另回报两项物理键盘检查正常。安装态 registered-host 首轮为 **8/9**；失败的 x86 shorthand 在诊断开启、关闭时各复测一次通过，现有 9 格均有通过证据，但首失败根因未明，不能记为首轮 9/9 或稳定性封版。重启自启、其他真实 x64/x86 应用及日用稳定性仍待验收。

后续 PR #78 已合入 main 并补强 ARM 制包的原生 admission 前置及 Go 持久配置隔离，见[冲突与复查记录](PR78-REVIEW.md)。以下 R2 的包、CI 和实机证据保持其原始绑定，不将新源码状态倒填为 R2 已验证内容。

## 平台合同

Windows on Arm 的 ARM64 与 x64 进程共用 64 位 COM 注册视图；两份 DLL 先后注册会覆盖同一 `InprocServer32`。本包采用单个合并 ARM64X DLL，x86 仍有独立 DLL 与 Registry32 注册。Runtime、Broker、工具及主注册器均为原生 ARM64。

| 使用者 | 载荷 | 注册 |
| --- | --- | --- |
| ARM64 原生应用 | `arm64/YimeTextServiceExperiment.dll` 的 ARM64 视图 | 原生注册器一次注册 Registry64 |
| x64 / ARM64EC 应用 | 同一 ARM64X DLL 的兼容视图 | 共用上述 Registry64 |
| x86 模拟应用 | `x86/YimeTextServiceExperiment.dll` | x86 注册器仅 register-com |

依据：[Microsoft ARM64X COM 场景](https://learn.microsoft.com/en-us/windows/arm/arm64x-pe)、[ARM64EC 互操作](https://learn.microsoft.com/en-us/windows/arm/arm64ec)、[ARM64X 构建方法](https://learn.microsoft.com/en-us/windows/arm/arm64x-build)。本机双架构加载验证补充这些部署约定，不代替安装态验收。

新增简单包合同为 `yime-simple-package-2 / windows-arm64`，必须声明原生宿主 `arm64` 与共享 TSF `arm64x`。旧 format1 仍解释为 x64 包。检查依据 Windows 原生架构 API，不能用继承为 AMD64 的环境变量把 x64 包安装到 ARM。安装/卸载仅维护本产品的 arm64 与 x86 工具，保留 StdRegProv 启动项读回及产品归属边界。

ARM 源包从唯一标准 `tools/yimecore/local-product.json` 派生平台描述，不修改原 x64 描述、标准布局或词典。所有标准资产、三模式索引、11 项连读资源和构建清单都必须存在；ARM64X 验证包含真实 PE 结构及双视图导入检查，不能用普通 AA64 文件头冒充。

## 构包与隔离验证（安装前）

- 单个实际 ARM64X DLL 已由本机 ARM64、x64 测试进程分别加载，通过 DLL/COM 契约；保护注册摘要保持。
- 简版安装器新增 37 项包、架构、宿主、注册顺序与卸载工具检查，PowerShell 7 和 Windows PowerShell 5.1 均通过，包括实际调用系统架构 API。其余旧包、选择调度、配置移除失败保护回归保持。
- Go 独立性审计已在原生 ARM64 运行：121 项 test/subtest 通过、5 项既有平台/符号链接项目跳过；x64 仿真运行 125 项通过、1 项符号链接项目跳过。仿真运行不计为 x64 硬件验收。兼容视图中混入 `rime.dll` 的反例被拒绝。
- 正式 ARM64 连读准入通过：512 项 test/subtest 通过、3 项跳过，7 个自有 Broker 阶段完成，624 项来源前后相同，注册、默认选择及进程环境保护保持。
- R2 完整包构建通过：19 个原生 Go 程序及 6 个本机组件共 25 个 PE；25 项标准资产、11 项连读资源及三模式索引齐全。每种模式含 1,166,753 项，重复生成逐字节相同；原始载荷和简单包载荷分别通过独立性审计。
- R2 包内 `Setup.ps1 -Action Check` 经 checked Windows PowerShell 5 在此 ARM64 实机执行，退出码 0。真实载荷在独立目录完成 12 项复制、文件归属、字体占用、破损修复、重新安装和清理检查；这不是安装态测试。
- R2 的 ARM64、x64 仿真、x86 仿真宿主分别对 full/variable/shorthand 执行直接 TSF，共 9 组通过；9 个自有 Broker 均停止，注册及默认选择前后相同。各组保留 `text_extent_anchor=false`，不将其解释为真实应用候选位置通过。

R1 曾完整构包，但实际交付脚本的 PS5 Check 遇到 `[ushort]` 类型别名不可用。修复为 `[System.UInt16]` 后增加实际架构 API 回归，并从新目录重建 R2；没有原地替换 R1。R1 ZIP、原日志及禁止安装状态保存在独立证据索引中，不能使用 R2 的成功结论覆盖它。

原始证据索引：[工具链与准入](package-validation/evidence-index.json)、[R1 失败候选](package-validation/product-r1/evidence-index.json)、[R2 完整候选](package-validation/product-r2/evidence-index.json)。

## R2 包身份与来源

- 文件：`YimeCore-ARM64-20261026-r2.zip`，168,171,619 字节；73 个 ZIP 成员已逐项核对解压内容 SHA-256。
- SHA-256：`2c94d825c59bf768d8a00a13353d38fe65f3b67e2258d3fb9747014229049de1`。
- 本地保留：`C:\dev\Yime-deliveries\arm64-proart-20261026-r2`；[固定 Release](https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-proart-20261026-r2)、[完整 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-arm64-proart-20261026-r2/YimeCore-ARM64-20261026-r2.zip) 已发布，服务器 size 与 SHA-256 digest 均和本地一致。
- 包内 source-manifest SHA-256：`9283c3f60d2e04b669e27198b98b5381d7470ad1a371d503669ca0f7213ff2e7`；product-package SHA-256：`2615facbb83553e5a49cf2d7a6730bb51dc17e25dba9ef8e2d12fe3bec2543d1`。
- 构建基础提交为 `d6a03c9e31cecb2d973c94252a4171d19755dbb7`，工作区含本轮改动；逐文件来源以包内清单为准。构包后更新 HANDOFF/README 状态，并仅修复 Test-Manage 的临时模块 BOM，checked PS5 重跑通过；运行与安装实现未变。逐文件核对见[构包后来源对照](package-validation/postbuild-source-comparison.json)，不把构建时的基础提交冒充完整来源提交。
- 连读准入 summary SHA-256：`b1423ab265d78bcfb2e3b0e366f019381a00245c15d8be1854244fd9d29cff4e`；source inventory SHA-256：`d52f43b5d6ec5a9c088aa616a85e3927dc2f4291dce638e43e91126eaa00709e`。

## 可重复构包入口

使用 checked PS7 调用 `tools/yimecore/run-connected-speech-admission.ps1`，显式传 `ExperimentTarget=arm64`、本机 Python 和原生 `GoExecutable`；完成后固定 summary 与 source inventory 两个 SHA-256。

再使用 checked PS7 调用 `tools/yimecore/run-platform-experiment.ps1`，传 `Target=arm64`、`Action=Package`、`NativeGenerator`、`GoExecutable`、`SpeechAdmissionRoot` 与两个完整 SHA-256。入口创建新的隔离目录，经 ARM64/ARM64EC 合并、x86 构建、实际 DLL 加载、重新索引、独立连读导出和双重包审计，生成单产品 `YimeCore-ARM64` 目录。

安装端运行完整包自带的 CMD 入口，不需要 Python、Go、CMake、Git 或另一套输入法。构建目录中的 x64 测试宿主是验收工具，不进入安装载荷。

## 交付与 CI

本地实现提交 `f855867d2cd048de1b74bc97ba92921b481fc82e` 通过相同 Git tree `71fef246d310baf49c7b37f5819aca13c5642811` 发布为 `0d5d7808e47e43d6f13d9232e3427fa747471b22`。[Build CI](https://github.com/tsaanghwang/Yime/actions/runs/40328189798) 与[原型 CI](https://github.com/tsaanghwang/Yime/actions/runs/40328189734) 共 13 项全部通过。

用户完成 GitHub CLI 网页授权后，完整 ZIP 与 SHA256SUMS 已发布并核对远端 digest；[发布与哈希记录](package-validation/publication/release.json)、[CI 检查记录](package-validation/publication/ci-checks.json) 已归档。构包后来源对照对应上述实现提交。以下安装和输入检查使用这一固定 R2 包；后续状态与证据更新没有替换包内运行载荷、安装脚本或上述通过 CI 的源码 tree。

## 本机安装与保护检查

用户从完整包入口启动并确认 UAC 后，安装日志 `e3d2f95ca1274c46ba7f8496dc9da645` 的父入口记录提权子进程退出码 0；对应[用户日志](installed-validation/install/manual-uac.user.log)和[管理员日志](installed-validation/install/manual-uac.admin.log)均保留。更早的自动提权尝试被取消，未观察到对应管理员日志，见[原始记录](installed-validation/install/automatic-uac-cancelled.user.log)；不把它改写成安装成功或产品故障。

- 已安装的 68 项载荷逐项匹配固定包清单。Registry64 指向 `C:\Program Files\YimeCore\arm64\YimeTextServiceExperiment.dll`，为 ARM64/x64 共用 ARM64X；Registry32 指向 `C:\Program Files\YimeCore\x86\YimeTextServiceExperiment.dll`。
- 当次只读诊断确认 Runtime PID `6720`、Broker PID `20436` 的安装路径及 Broker 管道身份，用户启动项指向安装根与独立 state 根。PID 和持久化状态仅为当次运行诊断，不代替输入或重启验收。
- [安装前基线](installed-validation/baseline/preinstall-baseline.json)与[安装后观察](installed-validation/baseline/postinstall-observation.json)中的默认输入选择及 Rime/PIME 产品观察一致。Rime/PIME 在本机仍未安装，不据此声称两产品同时安装的共存验收；未读取或复制新建学习库、用户词库内容。

分阶段对照见[安装观察](installed-validation/stage1-observations.json)。该文件保留生成时的阶段状态，后续 registered-host 与真实应用结果如下。

## 安装态 registered-host

首次实际矩阵 `acc00c7b` 执行 ARM64、x64 仿真、x86 仿真各 full/variable/shorthand，共 9 格：**8 格通过，x86 shorthand 失败**，原错误为 `registered key sink did not claim KeyDown`。该次 DLL 路径与哈希已确认，但没有当时的前台采样或按键诊断，不能据此断定是焦点问题。保留[首次矩阵](installed-validation/registered-host/matrix-first-run/summary.json)及[失败单格](installed-validation/registered-host/matrix-first-run/x86-shorthand/result.json)。

随后只针对 x86 shorthand，分别在[按键诊断开启](installed-validation/registered-host/retry-key-diagnostics-on/summary.json)、[按键诊断关闭](installed-validation/registered-host/retry-key-diagnostics-off/summary.json)时各执行一次，均通过。因此 **9 格各有通过证据，11 次宿主尝试中 10 次通过、1 次失败**；这不等于首轮 9/9，也不足以确认间歇问题已修复。首失败根因仍待查，见[阶段观察](installed-validation/stage2-observations.json)。

矩阵开始前还保留了 CIM 无法读取已提权进程映像、时间戳时区解释导致的观察器前置失败；这些尝试尚未进入任何宿主单格，不计为产品输入失败，也没有覆盖原日志。

## 原生 ARM64 现代 Notepad

实际宿主为 Windows Notepad `11.2607.14.0`，PID `29208`，PE 为 `0xaa64`，`IsWow64Process2` 返回 process `0x0000`、native `0xaa64`，见[宿主身份](installed-validation/live-host/notepad/host-identity.json)。已确认该进程加载当前安装的 ARM64X DLL，其 SHA-256 为 `f84a30f265e5c4e7d09d7588b06a9d95180e653b44697a23d010931490ab803b`。以下 8 项通过真实应用 UI 自动化逐键或鼠标操作观察，属于安装态真实应用证据；不冒充用户物理键盘操作或触摸/笔验收。

本次仅验证当时激活 profile 的当前模式，没有另行观测模式名称、读取真实设置或分别切换三模式；不能将这些结果称为真实应用三模式均已通过。

| 操作 | 观察结果 |
| --- | --- |
| 从无 composition 状态输入裸 `2` | 开始编码 composition `2`，没有直接提交数字或选择候选。 |
| 逐键输入 `2jru`，再按 `Shift+1` | 首候选“秋”提交到文档。 |
| 已有“秋”时输入 `2`，再按 `Esc` | 仅取消 preedit，保留已提交的“秋”。 |
| 已有“秋”时输入 `2`，切到新开的 Explorer，再返回 | 失焦仅取消原 preedit，保留“秋”，未自动提交原始码或候选。 |
| 对未提交的 `2` 按 `Backspace` | preedit 清除，已提交文本保留。 |
| 鼠标选择首候选“其” | “其”提交，文档成为“秋其”。 |
| `2jru` 候选显示时单按裸 `2` | composition 有效延长为 `2jru2`，没有触发第二候选选择。 |
| 继续输入 `jfa`，形成 `2jru2jfa`，再按 `Space` | “秋千”提交；最终文档为“秋其秋千”，共 4 个字符。 |

原始步骤观察与截图保存在 `C:\dev\Yime\.tmp\arm64-notepad-live-20261026`，归档入口为[真实应用证据](installed-validation/live-host/notepad/)。重复裸 `2` 的早期 `2 → 22` 操作没有延长 composition：标准三模式字典没有 `22` 前缀，无候选新码会回退；因此上表使用有词典依据的 `2jru → 2jru2` 验证裸数字编码，不把早期观察当成数字选词。

用户随后以物理键盘在当前 Notepad 末尾执行两项检查，并回报“**两项均正常**”：输入 `2jru` 后按 `Shift+1` 新增“秋”；再输入 `2` 后按 `Esc`，只取消新编码并保留已提交文字。这两项按**用户回报 PASS**记录，范围仅限当前宿主和当时激活模式，不扩大为完整人工验收、真实应用三模式、日用稳定性或重启验证。

## 待修问题与未完成验收

- **候选代码注释显示问题：** 本次可见 `2j...` 省略显示。源码保留完整注释并测量其宽度，绘制层有省略号兜底；边框占宽不足只是待验证假设，具体触发原因尚未确认。此项按显示问题待修复，不描述为正常紧凑策略，也没有证据称其 ARM 特有。当前输入结果不能替代完整代码显示与候选位置验收。
- **CUA 工具限制：** 先前恢复已最小化 Explorer 时，工具观察出现 stale 状态与窗口最小化状态矛盾。改用新 Explorer 后，实际失焦取消检查通过；这一观察限制与 x86 shorthand 首失败、候选显示问题分开记录。
- **后续验收：** 两项物理键盘检查已有用户回报通过；尚未完成重启后自启、重启后输入、其他真实 x64/x86 应用和日用稳定性验证。现有结果不替代这些结论，报告继续更新，不宣布稳定性封版。
