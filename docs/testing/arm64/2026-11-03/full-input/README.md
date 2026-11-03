# 本机完整输入链交付与验证

用户指定范围：标准键盘 YimeCore 与 Rime/PIME 两个独立产品、完整 YimeCore 输入链、18u 触摸键盘。
测试机为 HUASHUONOTEBOOK / ASUS ProArt P16 H7607BA / Windows ARM64 build 28000。
本目录只记录本轮实际完成的工作；安装和真实输入结果随执行另行追加。

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

仅安装后才记录已安装逐载荷、注册身份、普通用户运行时、真实宿主读回结果。
触摸前端自动化与鼠标检查不是实际手指/触笔验收；不把旧主线包、旧机器或旧受控宿主结论继承到新包。
Windows 默认输入法和已有学习/用户词库保持，不自动重启或关闭用户文档。
