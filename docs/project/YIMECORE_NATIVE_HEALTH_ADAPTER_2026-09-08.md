# YimeCore 原进程引用与健康观察器集成（2026-09-08）

受影响产品：YimeCore。本轮补齐真实候选的 `Open-YimeCoreNativeMaintenanceProcesses` → `Get-YimeCoreNativeMaintenanceHealth` → 原租约复核/关闭调用链，PS5/PS7 均通过。使用新增的显式 `References` 参数集，直接传入本次 Runtime/Broker 的 `Process` 对象；没有替换私有提供程序、扫描已安装产品或直接绕过 PowerShell 观察器调用 C# 客户端。

本轮复用 [上一轮健康候选](YIMECORE_LOCAL13_HEALTH_CANDIDATES_2026-09-08.md)，没有重构或安装产品。普通包仍为 `yimecore-local-0.1.0-local.13-7f86b4384fef`，manifest SHA256 为 `8f7e44ab9097a99d938891b507d0a07b753ffa66dbbec887cb0576286470f2cc`，85 个载荷成员；来源仍是干净 `e2d9d4222b09c548f978101668940262b895e4fc` 的 818 项源码 ZIP。已有 188 文件的仓外归档、故障包及历史原始证据保持原样。本轮工具是随后修改的仓内源码，不能声称已进入这份候选或归档。

结构化证据及精确来源见 [本轮 JSON](../testing/l6/2026-09-08-native-health-adapter.json)。已安装 local.12、Rime/PIME、默认输入法和实际用户状态未改动；未执行安装、备份、回滚、恢复或卸载。

## 原引用的边界

`Open-YimeCoreNativeMaintenanceProcesses` 和便利读取入口保留默认 `Discovery` 参数集，仍要求全局恰有一个 Runtime 和一个 Broker，不因隔离测试存在而放宽。新增 `References` 参数集要求两个真实且不同的 `System.Diagnostics.Process` 对象，没有公开 PID、发现器或脚本块覆盖参数。它不调用全局枚举，也不在引用失效时退回按 PID 打开进程。

每个引用在短暂的 `DangerousAddRef` 保护下，经 `DuplicateHandle` 复制原句柄，只请求 `SYNCHRONIZE | QUERY_LIMITED_INFORMATION` (`0x00101000`)；复制句柄指向同一内核进程对象。随后立即释放原 SafeHandle 的临时引用。租约保留原 Process/SafeHandle 对象关联，并在每次观察前后核对关闭状态、PID、原生创建时间、路径、父子关系、SID、普通权限、架构及预期映像哈希。关闭租约只关闭私有句柄和文件读取句柄，不关闭或停止调用者的进程。

真实回归发现，长期持有 `DangerousAddRef` 时，调用者对原 SafeHandle 执行 `Dispose` 的状态可能被保留引用掩盖，单看 `IsClosed`、对象关联及缓存 StartTime 仍可通过。因此最终实现采用上述短暂保留与私有复制方式，并验证直接关闭 SafeHandle 后拒绝继续观察。另有“原目标仍存活，但同一 Process 对象已 Close/Start 指向新子进程”的反例，避免把原目标恰好退出误当成对象关联检查有效。

这证明收到的引用与观察对象绑定，不证明调用者最初如何取得 Process 对象。`process_start_origin_authenticated=false` 保留；本次候选确由测试脚本启动的事实，另通过其原始进程句柄、父子身份和退出记录绑定。`discovery_scope` 明确区分 `global_exact_pair` 与 `explicit_process_references`，显式一对进程不等于系统中不存在其他同名进程。

## 来源与清理

进程模块不再复用调用方预装的全局 `Facts`/`ProcessPin` 类型。两个原生辅助源码由固定 SHA256、同一读取流校验后，编译到该模块的私有 GUID 命名空间，并保留返回的 Type。模块及辅助源码读取句柄跨整个观察租约保留，后续核对同一文件身份与哈希。预装同名假类型在独立子进程内测试，不能污染后续同进程 PS7 检查。

初始化或部分打开失败时释放已取得的来源、映像、令牌及进程句柄。单项 Dispose 抛错后仍尝试释放其余资源，模块移除也遍历其余租约，最后报告首个清理错误。导入健康模块不用 `Force`，模块内部租约集合及原对象身份保持有效。

固定来源：

| 文件 | SHA256 |
| --- | --- |
| `native-maintenance-processes.psm1` | `2d15b76b555e68b550865508dd6b489ad26541f99fcc42c9f013e8c1a28c4132` |
| `native-maintenance-process-facts.cs` | `55e81dc42c9280aed1f054a816534d9961d5e52b99e2a098d89a5be0392b2370` |
| `test-native-maintenance-processes.ps1` | `af10c54fa1bfa81f339260fd9eb3582388c09ed3a133d3e22aa821f898fea215` |
| `test-local-product-health.ps1` | `4c9bc8d3f34fabe2d5448a2752a761176c2db71ff0ef1b7aa83337362ed5cb9a` |

## 本轮验证

| 检查范围 | PS5 | PS7 |
| --- | --- | --- |
| 进程模块默认回归 | 89 通过 | 89 通过 |
| 显式自建 Runtime/Broker 夹具完整回归 | 100 通过 | 100 通过 |
| 候选包装器纯契约/自有文件检查 | 65 通过 | 65 通过 |
| 合并后实际维护 CI 的 15 脚本组合 | 1,555 通过 | 1,555 通过 |
| 合并后 Rime/PIME 载荷闭包隔离回归 | 29 通过 | 29 通过 |
| 实际普通候选完整适配器链 | 两轮、每轮两角色通过 | 两轮、每轮两角色通过 |

100 项包含默认检查，不能与 89 项作为互不重叠覆盖相加。默认进程检查已包含自有 PowerShell/cmd 进程的原生句柄、类型与关联回归；显式开关另增加编译的同名 Runtime/Broker 父子夹具，均不读取已安装产品。CI 用独立 PS5 和同进程 PS7 执行，30 份结果全通过；这些是本机执行实际 CI 检查体的结果，不是远端 CI 结果。双产品基线 220 项来源及 68 项测试通过，8 项待办保持。

提交期间合并了远端 `610e19e4e`、`51631e1f0`、`912322b4e` 的子进程退出竞争、显式释放信号及载荷回归作用域修复，没有冲突。合并前各 1,552 项 CI 原始结果保留；合并后重新执行整组检查，子进程回归由 71 增至 74 项，各版合计 1,555 项，并另跑各 29 项载荷回归及新来源基线。PS5 载荷回归第一次被默认执行策略阻止，脚本未启动；重试仅对子进程传入 `-ExecutionPolicy Bypass` 后通过，没有修改系统策略。上述远端改动不在真实候选健康调用链中，本轮候选原始结果仍对应相同的固定来源。

真实候选测试分别使用新 `.tmp` 状态、私有环境和随机管道。打开原进程租约后再导入健康模块，核对原租约未变；拒绝序列化副本，调用者修改公开 evidence 也不能替代原生事实。两轮均实际经过 PowerShell 健康接口，nonce、管道服务端身份与调用前后保留句柄检查成功，没有未完成客户端 IO。测试结束通过该私有 Runtime 的停止入口退出，随后确认失效及已关闭租约都被拒绝。

两版测试脚本退出码都是 0，stopper/Runtime/Broker 的实际退出码分别是 0/0/1。Broker 的 1 与 Runtime 常规停止源码使用终止操作相符，如实保留；测试脚本没有强制终止，清理错误为零。`production_lease_adapter_integrated=true` 只表示这次显式引用适配器与隔离候选的真实组合通过，`production_process_discovery_used=false`、`private_provider_replacements_used=false`、`collector_integrated=false` 保持。

## 尚未关闭的验收

健康观察证明协议响应及身份绑定，不证明引擎执行、配置已被消费、真实登录启动、注册或完整维护事务。collector v2 前后仍观察固定旧 local.12 及其备份配置，不能强制要求它提供后来加入的健康协议。Runtime/config 观察器的提示已限定为本次没有请求健康观察，不再笼统说所有当前 Broker 都没有该协议；未增加版本字符串推断或把探测失败当成旧版不支持的回退逻辑。

本轮没有执行故障包、安装器或实际用户状态维护。原生桌面维护上下文、真实备份/故障升级回滚/正常升级/卸载重装、引擎及配置采用、重启登录和宿主验收仍需各自证据。连续目录成员保护、内存代码身份、E7/L6、local/public readiness、DP1 完整验收、DP2 物理矩阵及 DP3 安装入口不因本轮适配器集成自动关闭。上一轮历史脚本和辅助源码哈希不同，旧原始记录继续描述当时的字节与范围。
