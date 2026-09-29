# YimeCore 首次注册查询修复交付（2026-09-29）

影响产品：**YimeCore**。状态：独立代码变更已提交、全部 CI 通过；新完整包及独立证据包已发布，远端大小和 SHA-256 均与本地一致。新包尚未执行实机安装或输入验收。

## 源码与原始证据

- 目标分支：`codex/yimecore-registration-fix-20260929`，从刷新后的 main `7ae18035a7bde9e2cb23e7eeaaaf94fdfd4c2948` 创建。
- 源码、安装器和制包脚本提交：[`2ffee43242af9981c462aeabb0d5b26c4f99286c`](https://github.com/tsaanghwang/Yime/commit/2ffee43242af9981c462aeabb0d5b26c4f99286c)。构建时工作区干净，源码 manifest、原始源码快照和工具链随 Evidence ZIP 交付。
- [源码 CI 36503447392](https://github.com/tsaanghwang/Yime/actions/runs/36503447392) 全部通过；[原始 CI 元数据](raw/source-ci.json) 与 [原生 CI 日志](raw/source-native-ci.log) 记录本轮 x64/x86 注册查询测试实际执行并通过。
- 原工作区中的修复、CMake 和查询测试迁入独立工作树；终端设置、首页/概览改动及其他未提交输出未纳入。原工作区保持原样。
- 原始 current-issues 报告及 29 份 raw 共 30 文件按字节保留，Git 索引亦逐项复核。历史日志所记 6 项哈希全部匹配。参见 [证据复核](REVIEW.md) 和 [完整索引](original-evidence-index.json)。原报告中的“未提交/未交付”保留其 9 月 28 日时间语义。

## 实现与验证

`profileRegistrationExists` 查询当前架构视图中的精确机器级 CTF TIP CLSID/语言/profile 键。不存在的键返回 absent，其他注册表错误传播；禁用 profile 仍算持久化注册。保留 COM/profile/category 真实重复拒绝和原有注册路径，新增分步 HRESULT 日志，不增加自动重试或任意注册项清理。

x64/Win32 Release 测试覆盖空状态、未启用的新 profile、相邻 CLSID/语言/profile 排除、立即删除/重建、空输出参数、HKLM 根与显式 WOW64 视图、FILE/PATH_NOT_FOUND、ACCESS_DENIED 和其他错误传播。CI `native-build` 与完整产品构建都实际执行两架构测试。查询测试没有调用真实 TSF 注册；重复 guard 的支撑是未改变的条件复核及历史受控诊断，不冒充本轮新实机结果。

完整构建通过 x64/x86 原生契约、焦点取消 mock、查询回归、五组 Go 测试、三模式索引双构建一致性、两次独立性审计。本轮语流准入和导出通过；准入在源码提交前执行，其 source inventory 与构包时源码匹配并由 exporter 再验证，不将准入运行时的旧 HEAD 误当新包来源。

PS5 的包完整性、profile 移除失败、单/双产品调度、进程等待隔离回归和实际新包 `Read-Package` 通过。包内 **65 个载荷、25 个 PE** 的精确集合、大小、SHA-256、架构以及 native Release/资源来源全部匹配；x64/x86 注册工具均来自本轮新构建。封包前再次核验，完整 ZIP **71 个文件成员**及 Evidence ZIP 的 CRC、重复项、集合、大小和逐成员 SHA-256 全部通过。

构建前后和制包验证后，经进程外系统视图读取的 COM/TSF 注册、语言/默认输入及启动项哈希一致，见 [保护比较](raw/registration-preservation.json)。本轮没有安装、卸载、停止/重启已安装产品进程、变更默认输入法或用户数据。未执行真实 Setup Check、Test-Startup、Test-Logging、注册宿主、实机输入或系统重启验收；隔离日志里的 Install/Uninstall 是 synthetic fixture 调度。未重新构建或交付 Rime/PIME，未使用它的安装作为依赖。

## 固定交付资产

[开发预发布](https://github.com/tsaanghwang/Yime/releases/tag/test-yimecore-registration-20260929-2ffee432)。单产品完整包直接提供 `Setup.cmd`，不需要另一个产品或双产品选择器。包版本 `0.1.0-local.13-registration-fix-20260929`；payload descriptor 的产品版本保持 `0.1.0-local.13`。

| 资产 | 字节 | SHA-256 |
| --- | ---: | --- |
| [完整包](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/YimeCore-Registration-Fix-20260929.zip) | 187973541 | `849bfc21fa9222dec3948f88c5652bcf404960f82e84f72175865293e7a3c073` |
| [Evidence ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/YimeCore-Registration-Fix-20260929-Evidence.zip) | 107938755 | `8c2a9abfb2c3ea89c1017be2e53a04397d1e9d6ed9f09c04d0a66c5bb3d845ec` |
| [SHA256SUMS.txt](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/SHA256SUMS.txt) | 219 | `c1f28d201da3dfcc929b7e26d0964da016ec0aa5a6e88686e748f2c8ac7ec10a` |

[逐载荷清单](raw/product-package.json)、[完整 ZIP 清单](raw/package-zip-verification.json)、[来源绑定](raw/BUILD-PROVENANCE.json)、[封包前复核](raw/sealing-verification.json)、[远端发布核验](raw/publication-verification.json) 和 [机器可读交付记录](delivery.json) 均保存在分支。大体积源码快照、准入索引、测试二进制与完整构建证据保存在独立 Evidence ZIP；源码 checkout 与 GitHub 自动 Source code ZIP 不等于安装包。

本地归档：`C:\dev\Yime-deliveries\registration-fix-20260929`。此路径仅为构建证据位置；交付使用上面的固定 Release URL，不使用共享 `.tmp`。

9 月 27 日 `Yime-Current-Readiness-20260927.zip` 的 SHA-256 仍是 `45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341`，它不含本修复；原包恢复、输入及重启验收仍归原包。没有替换或重新标记旧资产。

后续安排只在提交 CI 成功且以上新包可交付后写入 [HANDOFF](../../../../../installer/simple/HANDOFF.md)；测试报告须另建本轮目录，不能继承历史通过结果。
