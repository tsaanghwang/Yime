# 本机完整输入链交付与验证

**最新状态（2026-11-04）：ASUS 18u `.4` 安装成功。结束快照为 `0.2.0-18u-arm64.4`，20/20 项载荷匹配。其他两产品及默认输入覆盖值保持未变。随后已依据 100 mm 参考线实测 57.5 mm 保存校准，已安装前端的软件检查 18/18 通过，测试 Job 已清空并重新核验恢复后的三个普通用户进程。** 固定 `.4` 来源与实际结果见[本轮记录](../../2026-11-04/binding-calibration/README.md)。软件校准保存与受控 TSF 检查不代表实体尺复测、真实记事本正文或真人手指输入通过；这些仍须单独记录。历史 `.2`/`.3` 首失败保留，未据 `.4` 的结果追认 `.3` 的锁来源。

以下保留本次更新之前的实施、安装或交付记录，不作为旧包重装指令。

用户指定范围：标准键盘 YimeCore 与 Rime/PIME 两个独立产品、完整 YimeCore 输入链、18u 触摸键盘。
测试机为 HUASHUONOTEBOOK / ASUS ProArt P16 H7607BA / Windows ARM64 build 28000。
本目录只记录本轮实际完成的工作；安装和真实输入结果随执行另行追加。

最终完整包、固定来源、远端 SHA-256 与 CI 见 [最终交付](FINAL-DELIVERY.md)。下文首次标准包和启动问题保留为历史执行记录。

实际安装、普通权限运行及失败定位见 [本机安装执行记录](INSTALLED-RESULT.md)。当前三套均已安装：标准 maint.1 为 6c1c0122，18u 为 46dd5896（真实 TSF 18/18），Rime 为 defbf9f8（普通父进程双架构严格验证通过后启动）。前两次 Rime 失败和 18u 控制器首失败均保留。

## 标准 YimeCore 固定来源

源码：`64a785a7ede5fb2a53e2560b873075950160668b`，来自独立干净主线工作树。
源 CI：[Build 41585633667](https://github.com/tsaanghwang/Yime/actions/runs/41585633667)。
完整验证汇总见 `standard-arm64-report.json`：69 个载荷、73 个 ZIP 成员，原生 ARM64 runtime/Broker、ARM64X 与 x86 TSF。
三模式 × ARM64/x64/x86 共 9 组直接 TSF 测试通过；这不是安装态注册宿主结果。
连读准入有 3 个既有符号链接权限用例跳过，报告保留原状态，未改系统开发者模式。

包 `YimeCore-0.1.0-local.13-main64a785a7-arm64-20261103.zip`：168189960 bytes。
SHA-256：`7a8cff04fcc09f8a9908257c1f8ac7b8f5a37f123c192eebea62089f39a45e25`。
证据 ZIP：`standard-arm64-evidence-64a785a7-20261103.zip`，172241 bytes，SHA-256 `9cc864673ce27bb5297f09de82dd65fd16e7345c4c6e23f2d6d0dd8ab6358613`。
固定[测试发行版](https://github.com/tsaanghwang/Yime/releases/tag/test-standard-arm64-64a785a7-20261103)已发布；[完整安装包](https://github.com/tsaanghwang/Yime/releases/download/test-standard-arm64-64a785a7-20261103/YimeCore-0.1.0-local.13-main64a785a7-arm64-20261103.zip)和[证据包](https://github.com/tsaanghwang/Yime/releases/download/test-standard-arm64-64a785a7-20261103/standard-arm64-evidence-64a785a7-20261103.zip)的远端大小、SHA-256 与本地完全匹配，见 `standard-release.json`。

## 新的 Rime/PIME 与 18u

标准 Rime/PIME 的 ARM64 完整构建、真实 Rime 三模式、Launcher 和三架构 DLL 加载证据位于 `tools/rime-pime/evidence/2026-11-03/`。
18u 使用独立 CN134 布局、固定三模式词典和 v2 前端清单，保留原标准产品的字典、注册与状态边界。
18u 前端当前 TSF 为原生 ARM64，未由该构建证明 x64/x86/ARM64EC 应用兼容性。
两个新包使用各自编译绑定的原生维护入口和完整固定 ARM64 PowerShell 依赖；草稿证据不构成正式交付。

## 实机结果边界

### 标准版首次安装与启动问题

固定主线包已在本机安装，安装器返回 0；安装后 69 个载荷全部匹配。
已安装 ARM64/x64(ARM64X)/x86 × 三模式共 9 组注册宿主检查全部通过，见 `standard-registered-host/evidence.json`。
这些用例使用独立普通用户 Broker；不依赖常驻 Runtime，也不把它们视为真人日用结论。

本轮同时发现旧安装器会从提升子进程启动常驻 Runtime/Broker/Toolbar。Win32 实际令牌查询确认它们为 High 完整性；
普通 CIM/Process.Path 查询隐藏了这些提升进程路径，最早快照的“进程 0”是观测假阴性。
随后普通用户启动因已有单实例而退出 0，不能据此宣称普通权限启动成功。
保留原始日志及令牌证据，修复为提升子进程只安装、原普通用户父进程核验载荷后启动。
最终重制标准包需要分别声明不变的主线运行时来源与新安装器来源，不能把混合组件来源写成单一提交。

仅安装后才记录已安装逐载荷、注册身份、普通用户运行时、真实宿主读回结果。
触摸前端自动化与鼠标检查不是实际手指/触笔验收；不把旧主线包、旧机器或旧受控宿主结论继承到新包。
Windows 默认输入法和已有学习/用户词库保持，不自动重启或关闭用户文档。
