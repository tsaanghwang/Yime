# ARM64 完整产品包与安装验收

本轮接续用户“请继续”的授权，在 HUASHUONOTEBOOK / 华硕 ProArt 创 16 RTX Spark 上推进 **YimeCore**。Rime/PIME 保持独立 x64 产品；本轮没有将其移植为 ARM64，也不修改 CN134/18u 键盘实验室的数据或几何。

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

## 当前验证

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

## 安装与交付状态

目前尚未安装、卸载或重启输入法产品，默认输入法和用户数据未变。安装态 registered-host、真实应用输入、候选位置、重启后输入及日用均为待验收；原有源码测试和鼠标/模拟输入不能继承为这些结果。

本地实现提交 `f855867d2cd048de1b74bc97ba92921b481fc82e` 通过相同 Git tree `71fef246d310baf49c7b37f5819aca13c5642811` 发布为 `0d5d7808e47e43d6f13d9232e3427fa747471b22`。[Build CI](https://github.com/tsaanghwang/Yime/actions/runs/40328189798) 与[原型 CI](https://github.com/tsaanghwang/Yime/actions/runs/40328189734) 共 13 项全部通过。

用户完成 GitHub CLI 网页授权后，完整 ZIP 与 SHA256SUMS 已发布并核对远端 digest；[发布与哈希记录](package-validation/publication/release.json)、[CI 检查记录](package-validation/publication/ci-checks.json) 已归档。构包后来源对照对应上述实现提交；本次交付状态更新仅为文档和证据。安装前置交付已完成，下一步为本机安装、三架构 registered-host 和真实应用验收。
