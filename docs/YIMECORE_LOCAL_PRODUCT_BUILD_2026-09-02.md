# 本机独立产品第一批源码构包验收

2026-09-02。结论：**L1 完成；L2 的独立源码 x64 运行包通过，完整安装维护尚未交付。** 本次未升级当前安装，没有新的已安装 Word/物理任务栏验收结论。

## 对应产物

- 构建证据根：`C:\dev\Yime\.tmp\yimecore-local-product\20260902-231416-b6e0cf49`
- 包目录：上述根下 `package`；ID `yimecore-local-0.1.0-local.1-be6e13ec3b38`。
- manifest SHA-256：`f1b9a64b80973f1eb690f024e85fe229ed0190c5b2f99f9ae54fe8e3b4facb94`。
- source manifest SHA-256：`be6e13ec3b38c5809409e49a21f2b01527778d9033f6b9ded414cc48d867de4c`。
- `source-snapshot.zip` SHA-256：`a291a23c0fa1919963d0d2b4cc6059ae26b220ab2ae974ff8c67d01186090398`。只含构建源/数据，不含用户学习数据；独立重读 ZIP 的 643 项内容哈希全部与清单吻合。
- 源码：HEAD `45b389e530c02d12924beeadcc5b8fd9543a3821` 加明确归档的 dirty/untracked 内容；不是仅靠 HEAD 标识当前程序。事后新增本报告及文档进度不改变包的源码身份。
- 工具链：Go 1.26.4，windows/amd64、GOAMD64=v1、CGO_ENABLED=0；CMake 4.3.1；MSVC 19.44.35225.0，原生 x64。

## 实际通过项目

| 项目 | 证据与结果 |
| --- | --- |
| 从空目录独立构包 | 不读旧包、不读已安装 runtime-config；20 个 Go 程序、x64 DLL/注册工具/宿主测试载荷源建，共 55 项文件、23 项 PE |
| 新清单审计 | `independence-audit.json` 和 `independence-after-tests.json` PASS；全部 PE 为 x64，Rime/PIME 构件/导入缺席，测试未改包内容 |
| 旧 E6-C 未放宽 | 新审计器只读审计已安装 `8d48953a` 包，`legacy-installed-audit.json` PASS；旧多架构文件仍被要求。未运行冻结架构程序 |
| 构包回归 | PS7 `contract-7d7aaf5208864c9ebb051ad41d5ba028`、PS5.1 `contract-0975cc5d62884361a7d274e69373e0c9`：各 37 项 PASS；Go 新旧清单回归另以 `-count=1` 通过 |
| 核心测试 | `go-tests.txt`：independence-audit、trial-runtime、yimecore、yimebroker 通过；原生 `native-contract.txt` 通过 |
| 三模式新索引 | full/variable/shorthand 各 1,166,753 条；每模式构建两次，哈希一致，见 `index-*.json` / `rebuild-*.json` |
| 可重建性抽查 | 与上一成功输出 `20260902-231203-3a6e5c5d` 比较，全部 20 个 Go 程序逐字节相同；不强称 C++ PE 时间戳及归档元数据相同 |
| 仓库外运行 | `runtime-verification/relocated-audit.json` PASS；副本在唯一 Temp 子目录，runtime 显式使用其中 data/indexes 和全新状态，不需要 Go/CMake/旧安装帮助运行 |
| 整句与学习 | 12 个整句用例 PASS；3 模式学习、journal 恢复、索引切换/回退 PASS；包内 RecoveryProbe 对临时模型恢复 generation=12、records=11 |
| 直接 TSF | 64 类英文 Shift 组合、裸数字及 Shift 候选契约、组合提交、候选点击、标点、失焦/上下文隔离、中英语言栏状态等 PASS |
| runtime 异常恢复 | 对本次独立 runtime 的已验证子 Broker 注入退出；PID 更换、重启计数增加、路径/父进程复核通过，测试 runtime 已停止 |
| 现有系统不变 | `protection-before.json` / `protection-after.json` 的独立 StdRegProv 系统视图一致；生产/试验 COM/TIP、用户 TIP、Run、卸载和默认语言设置保留 |

最终 `summary.json` 为 `passed=true`、`registration_and_default_preserved=true`，同时明确 `installable=false`、`local_product_ready=false`、`public_release_ready=false`。

测试后只读进程核对仍是原维护后的 runtime PID 13132 / Broker PID 3536，创建时间 22:21:34；没有把它们重启成新包。当前上下文对这两个既有提权进程的 ExecutablePath 不可见，不能据此称其失效；既有原生维护/系统注册证据继续有效。

## 证据边界与下一批

- 直接 TSF 测试通过不是注册宿主或 Word 物理点击验收。其 `text_extent_anchor=false` 是本隔离测试返回的原始状态，本次不把它写为已验证的真实 Word 光标定位。
- Temp 副本和临时模型只是可丢弃测试材料，不是独立原生上下文的恢复介质；此前用户原生备份/实际恢复/安装回退 PASS 未被替代。
- 首批开发中间出现过 PowerShell 续行、旧边界脚本严格模式调用兼容、以及误将工具 Win32 UI 纳入核心禁用范围的问题；均修复并重新从空目录构包。失败目录保留，不作为通过证据。
- 没有新增真实宿主阻塞；目前未交付的是工程实现：正常 x64 安装维护、自包含备份/恢复、同 SID 权限分离、显示名接线，以及这些改变对应的新 RC 验收。
- 不要用旧 E6-C 维护器安装此运行包。L3 将收拢共享事务实现，保护冻结注册引用的旧根，补齐包内入口；到完整 RC 后才安排原生安装窗口和必要重启。
- ARM64、x86、老旧 x64、其他实体机/模拟仍冻结。生产 Rime/PIME 不卸载，默认输入法不切换。

签名证书正在申请，等候审批，暂缓相关事项。
