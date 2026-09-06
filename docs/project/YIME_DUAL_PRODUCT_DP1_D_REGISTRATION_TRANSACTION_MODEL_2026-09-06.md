# DP1-D：Rime/PIME 注册接线与纯事务模型收口

日期：2026-09-06。影响面为 Rime/PIME 产品源码及双产品维护合同；YimeCore 已安装产品不在本批变更范围。本批只收口注册／反注册的源码与构建接线、目标用户清理的源码合同，以及不接触操作系统的纯合成事务模型。

## 结论和证据等级

当前源码已增加或加固下列接缝：注册失败传播、明确的机器级 COM 归属、完整 Profile／类别闭集的只读状态工具、x64／WOW64 x86／ARM64 架构互斥与 PE 身份接线、发起 SID 绑定、系统视图注册读取、目标用户清理顺序，以及安装器中的逐命令失败检查。缺失判断同时覆盖每个所选视图的 COM 与 machine TIP 整树；Profile 的 `IconFile`、`IconIndex` 及值类型也绑定到所选根和既有 Windows 版本规则。x86／x64 状态工具已进入 CI 构建、交接 artifact、签名验证与 manifest 清单，ARM64 项仅按 ARM64 DLL 是否存在作成对接线。对应检查只读取源码、构建脚本和合成对象；它们没有调用状态工具查询真实 TSF，也没有运行安装器、卸载器、`regsvr32`、`InstallLayoutOrTip`、注册表、真实进程或提升流程。

[`rime-pime-transaction-engine.ps1`](../../tools/dual-product/rime-pime-transaction-engine.ps1) 是纯内存参考模型，不是安装器事务实现。它和独立硬编码预期的 [`test-rime-pime-transaction-faults.ps1`](../../tools/dual-product/test-rime-pime-transaction-faults.ps1) 在 PowerShell 5.1／7 上各通过 9／9 项：

- 阶段目录固定为 24 项，从根／清单／架构验证、完整暂存、哈希验证和双快照开始，经 prepared journal、定向停机、静止验证、旧根隔离、新根激活、逐架构反注册／注册及读回、目标用户 Profile、产品注册、非提升 Runtime 启动／readiness、非目标状态保护，最后写 activation commit、清理隔离根并结束 journal。
- 回滚目录固定为 10 维：package、registration、registry kinds、Run、uninstall、target-user TIP、Runtime、shortcut、font 和 pending reboot。
- 96 个前向故障例来自两套合成架构集合（`x64,x86` 与 `arm64,x86`）× 24 阶段 × before／after 两个边界。模型分别要求：首项活动变更前失败不产生变更；提交前且已变更的失败完整回滚；提交后的失败只标记 cleanup pending，不能倒退为已回滚。
- 另逐维验证回滚成功的完整顺序、回滚自身失败时只恢复到失败维度之前的前缀、失败维度和事件不被隐藏，以及另一产品、设置、学习和默认输入法的合成摘要不变。

这 24／10／96 是合成状态机覆盖数，不是 24 次真实安装、10 次真实恢复或 96 次系统故障注入。模型不会复制／替换文件、写持久 journal、修改注册表、启动或停止进程，也不会跨崩溃或重启重放。

## 当前收据

| 门禁 | 结果 | 证据边界 |
| --- | --- | --- |
| 注册完整性与构建接线 | PS 5.1、PS 7 各 25／25 | 源码与构建／签名／manifest 接线扫描；`actual_registration_probe_executed=false`，未读真实注册表 |
| 注册根所有权与 fresh-orphan 合同 | PS 5.1、PS 7 各 21／21 | 文件夹夹具、合成注册快照和 fake provider；含 native／x86 空 TIP 壳键及 IconIndex 值／类型负例；未读写系统注册表、未提升 |
| 原生注册函数的跨 SID 禁止与目标用户清理接线 | PS 5.1、PS 7 各 11／11 | 源码和合成分类；未运行 DLL 注册入口或卸载器 |
| 24 阶段／10 维／96 故障纯事务模型 | PS 5.1、PS 7 各 9／9，0 失败 | 纯内存对象和事件；`actual_filesystem_registry_process_or_elevation_executed=false` |

纯事务模型收据：

- PS 5.1：`.tmp/dual-product/dp1-transaction-faults-final2-ps5-20260906-a1/result.json`，SHA-256 `342ef7807957f1706b88cb4e17a2bb0799a397a2ddf72fbe424d58b936a2a31d`。
- PS 7：`.tmp/dual-product/dp1-transaction-faults-final2-ps7-20260906-a1/result.json`，SHA-256 `f67cf1e32e80b5095f8b993c1a7a3def46cc30e42e2b4fcfa0a72c54969ba0c9`。
- 两份收据固定同一 engine SHA-256 `000804999698ec4235924ccb3c46996ee0afa4f5a41a8f88349f324524a93cfa` 和 test SHA-256 `75a4bbab120d9d245d7d543381fdc90bd1c0983e68a605bfcccdb6955bdccdc9`。

注册源码收据以 [结构化记录](../testing/dual-product/2026-09-06-dp1-d.json)列明；PS 5.1 和 PS 7 路径、计数及收据哈希分别记录，不以任一 shell 的结果代替另一 shell。

同一最终源码还在 PS 5.1／7 各通过目标 SID 25／25、维护 31／31、定向退出 17／17 和通用事务隔离 52／52；Python 基线固定 68 个来源并通过 35／35。x86、x64、ARM64 的 `PIMETextService.dll` 和 `PIMERegistrationStatus.exe` 均完成源码构建，7 个 PE 身份检查匹配；ARM64 仍只是本机交叉构建。x86／x64 CTest 各 4／4。`makensis` 仅生成未签名、未运行的 `installer/YIME-1.4.0-dev-setup.exe`，大小 39,836,691 字节，SHA-256 `3b95adb3f37e9e2dcc5bd6223b03aaa80527276ee31abf78237843c49d0b7183`。

## 本批发现并关闭的具体源码回归

1. 检查命令宏最初在 NSIS 展开后把命令行拆成三个参数，`makensis` 明确报 `ExecWait expects 1-2 parameters, got 3`；宏改为把完整命令作为一个引用参数后，最终构包退出码为 0。
2. 新状态工具最初未进入 CI 的 x64 target、x86／x64 artifact、签名验证和 manifest 清单，恢复 artifact 后构包会缺必需文件；当前这些交接清单已闭合。
3. 原缺失验证只查 COM，可能把遗留的 native／x86 machine TIP 空壳误判为已完全移除；现在每个所选视图同时要求 COM 和 machine TIP 整树缺失，并有两个空壳负例。
4. `DllEntry.cpp` 原来计算 Win8+ `iconIndex=1`，却未传给 `LangProfileInfo`，实际仍为值初始化的 0；当前已传入，并以 `IconIndex` DWORD 的错误值和错误类型负例保护。

以上都是当前源码／构建链中发现并修复的回归，不是对已安装 local.12 或用户日用行为的异常报告。

## 尚未完成的真实产品工作

以下全部仍是待办，不能由源码扫描或合成模型推定通过：

1. 把完整私有暂存、逐文件哈希、旧根隔离、注册收敛、持久 prepared／commit journal、恢复归档、逐维真实回滚和清理接入 Rime/PIME 安装／升级／卸载事务。
2. 在进程被终止、机器崩溃或重启后读取持久状态，安全重放或完成回滚；证明失败中的回滚失败仍保留可继续恢复的介质和准确状态。
3. 用发起用户的非提升令牌启动 Runtime，并对精确 PID、映像、SID、完整性级别和 readiness 做读回；源码中出现启动命令不等于 Runtime 已就绪。
4. 在获准隔离目标执行真实 UAC、COM／TIP／Profile／类别、用户语言列表、注册值类型、安装／升级／卸载／恢复和另一产品不变验证。
5. 完成 x64／WOW64 x86 registered-host 与真实应用验证；ARM64 当前最多只有交叉构建、构建交接接线和合成 `arm64,x86` 状态，没有 ARM64 原生安装、注册、进程或 live-host 证据。
6. 为 legacy PIME/YIME 注册和载荷建立明确、可恢复、逐身份审查的迁移事务。当前源码拒绝含糊 legacy 状态；这不是 legacy migration 已实现。

因此 `dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`。DP1、DP2、L5 最终确认和 L6 均未完成；DP3 三选一入口也未开始验收。

## 对当前已安装产品的影响

本批没有安装 `local.13`，也没有重建或替换当前日用安装。已安装、用于日常观察的 YimeCore 仍是 `local.12`，其设置、学习、进程、注册和默认输入法均未被本批读取或修改。生产 Rime/PIME、历史冻结载荷及用户正文同样未被读取、启动或更改。
