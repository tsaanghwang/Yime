# 本机独立产品：完整维护候选包

日期：2026-09-03。仅 MYCOMPUTER 原生 x64。

## 结论

已生成 `0.1.0-local.2` 完整候选包，从源码构建，不依赖已安装 Trial 或 Rime/PIME。71 项清单、23 个 x64 PE 全部审计通过；包内维护入口已在仓库外、带空格路径和无关当前目录执行只读 Plan。

`installable=true` 是候选包类型，不代表已经安装：`local_product_ready=false`，`public_release_ready=false`。当前安装、默认微软拼音、生产 Rime/PIME 和冻结 x86 注册未改变。新候选的实际安装/恢复、提权到普通用户启动、真实 Word 和回退未在本轮执行。

## 固定候选与来源

- 证据根：`C:\dev\Yime\.tmp\yimecore-local-product\20260903-000638-13644db3`
- 包目录：上述目录的 `package`
- 包 ID：`yimecore-local-0.1.0-local.2-779ef4dafe6b`
- manifest SHA256：`6bb1c10d24228c436ce6e77b4063c36bcc786fd5cabaa38a8efd690941e10e9d`
- source manifest SHA256：`779ef4dafe6bc8449aa25c1b3b0e774af24b74249b3ad2b7bf817c6bf933fa84`
- source ZIP SHA256：`b0789b7fad1f0a2422f57862677174da0c3964a053e0dd8747ae80bb99674b15`
- 654 项归档内容已重新逐项读取、计算哈希，并与 source manifest 一致，见 `source-archive-verification.json`。
- 新 x64 DLL SHA256：`35d517788ee034c68afd3835e2c38e2120fc2c9ddbf394987b08b2c605f16756`
- 新 runtime SHA256：`52e6de312cddea26e4c6d7fab3247cf541eab7ad7a54e81bf3e236d02442afb2`
- 包内共用维护器 SHA256：`7e4b6655382dc04d6a573c2b5e0558e5fa6b6b88143bae3e2f5edab37dcad437`

源码仍为未提交工作区，HEAD `45b389e530c02d12924beeadcc5b8fd9543a3821` 不能单独代表候选内容。保留 source ZIP、文件清单及二进制 Git diff，未重置用户改动。

## 本批实现

1. 新增严格契约 `yimecore-local-product-package-v1`。必需载荷为 55 项运行文件加 16 项维护/指南；拒绝未知或额外文件、缺失启动帮助程序、错误架构、间接路径、重复/越界路径及哈希不一致。旧 runtime-only 契约依然不可安装；旧 E6-C 多架构要求没有删减。
2. 包内 `Install-YimeCore-Local.cmd` 和 `Maintain-YimeCore-Local.cmd`。后者默认只读 Plan，支持 `-Action Upgrade/Uninstall/Backup/Restore/Verify`。安装/升级使用同一事务器，不再建第二套安装实现。
3. 同 SID、固定数据命名空间、x64-only、冻结引用目录保留、完整 staging、用户 TIP/Run/卸载回滚等保护继续生效。staging 审计使用完整且绑定 staging 当前路径的元数据，搬移后再次按目标路径核验，不跳过元数据校验。
4. 包内备份/安全恢复使用预编译 RecoveryProbe，无 Go 或仓库运行依赖。恢复后调用标准用户启动帮助程序，并验证 runtime/Broker 的真实映像、父子关系、启动时间、SID/会话和令牌。真实 elevated→medium 启动仍待原生验收。
5. 归档恢复前验证精确文件全集，拒绝清单外或重复文件；`data_files` 必须与实际归档的学习/词库/设置全集一致，先于克隆和实际数据移动。
6. 新 CMake 本机开关从产品 JSON 生成唯一显示名头文件。注册名称、语言栏提示和候选说明显示“Yime 独立开发版”；旧 Trial 构建保留旧文案，内部 GUID、状态目录、管道和学习 source ID 不变。

## 自动验证

| 证据/测试 | 结果和界限 |
|---|---|
| `summary.json`、`independence-audit.json`、`independence-after-tests.json` | 完整候选与前后审计通过，71 项/23 PE；生产/试验注册和默认配置的独立系统视图保持一致 |
| `package-verification/summary.json` | Windows PowerShell 5.1：35 项通过 |
| `package-verification-ps7/summary.json` | PowerShell 7：35 项通过，包含真实 CMD 调用链 |
| 两组 `relocated-cmd-plan.json` | 仓库外带空格包路径，从 Windows 目录调用真实 CMD；只读，不改变调用方模块环境 |
| `runtime-verification/summary.json` | 唯一管道、全新临时状态；直接 TSF、Broker 自恢复及停机通过，不是 registered-host/物理任务栏验收 |
| `runtime-verification/sentence-regression.json` | 新索引 12 项整句用例通过 |
| `runtime-verification/multimode.json`、`packaged-recovery.json` | 三模式、学习与克隆恢复通过；generation=12、records=11；不是当前用户学习数据 |
| `runtime-verification/tsf-composition.txt` | 64 组英文 Shift、组合/提交、数字键契约、鼠标选词、标点原子提交、失焦/跨上下文/终止恢复等通过；`text_extent_anchor=false` 如实保留，夹具没有实际 Word 文本区域 |
| `native-contract.txt` | 本机产品名称和原有语言栏/候选回归通过 |
| `.tmp/yimecore-local-product/legacy-native-20260903` | 同一源码以旧 Trial 显示开关构建 x64 DLL 和契约测试通过；不是冻结的老旧机型性能评测，无 x86/ARM64 构建或执行 |

38 项构包回归在 PS5.1/PS7 通过；共用维护器 55 项在 PS5.1/PS7 通过。旧 E6-C 安装契约、用户 TIP Enable/值类型、5 项故障演练保护、5+3 项上下文保护、24 项数据安全、12 项自启动和 5 项系统卸载事务回归亦通过。编码回归为 54 处显式读取、3 个 Unicode 夹具。本轮未重跑真实旧包回退。

三模式各 1,166,753 项索引双构一致，哈希与先前源码构包一致；不声称 ZIP/C++ 时间戳等整体字节可复现。

## 构包中定位并修复的两个问题

- PS5.1 的 `Get-Content` 文本携带 PSDrive/Provider 属性。证据深度序列化将其展开，内存异常增长。只停止本轮所启动且已核对命令行的构建进程；输出 `20260902-235914-c64e24a8` 原样保留，不是合格候选。新增纯文本规范化和回归后，完整 PS5 构包通过。
- PS7→CMD→PS5 与直接 PS7→PS5 的模块搜索环境不同，真实 CMD 曾报 `Get-FileHash` 不存在。CMD 通过 `setlocal` 为该子进程限定 Windows 原生模块目录，未修改用户/系统环境。`20260903-000316-acaf616b` 是发现该缺陷前的中间候选，已被本文固定候选取代；不应安装它。

## 现有安装保护和仍待完成的事项

本轮结束时仍是旧安装根 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-45b389e530c0-8d48953a`，runtime 文件哈希仍为 `415ef8b09b26ca884cff935c8b61b5b970a4e28f6d1e2603df62514b5592fff4`。现有 runtime PID 13132、Broker PID 3536 及 2026-09-02 22:21:34 启动时间未改变；当前低权限 CIM 不提供它们的映像路径，不将空路径误报为崩溃或新候选已运行。

冻结 x86 COM 仍引用旧根，包内 Plan 将它标为必须保留的目录；不注销、不删除、不安排重启删除。保留不等于 x86 已通过新候选验收。

2026-09-03 原生维护预检已发现 `Duplicate linked primary token` 失败，发生在停写和安装之前；候选完整安装暂停。当前下一步为只读 `-LaunchProbeOnly`，捕获真实 Windows 错误码与令牌类型，见[原生窗口记录](YIMECORE_LOCAL_PRODUCT_NATIVE_INSTALL_WINDOW_2026-09-03.md)。候选封存文件不原地修改；修复并验证后才重新安排安装、普通权限 runtime/Broker、数据/系统注册核对、备份恢复、失败回退和自身重装、真实宿主及最终登录启动。此过程不能从 Codex 的打包祖先进程绕过上下文保护。

当前 Restore 有明确限制：仅支持新鲜归档安全恢复演练，任何较新学习/词库/设置变化都会拒绝覆盖；无持久化日志的空白配置不报告恢复通过。它不等价于任意历史/灾难恢复，也不提供静默强制覆盖。候选的这些边界须在日常就绪前继续评估，不把旧基线闭环结果复制为新候选已通过。

不需再运行旧 `Upgrade-YimeCore-Trial.cmd`。本轮没有请求重启，也没有将人工输入法选择/自动化任务栏限制重新作为产品阻塞。

签名证书正在申请，等候审批，暂缓相关事项。ARM64、x86、其他机型/模拟及联网同步、新语境音变规则均未启动。
