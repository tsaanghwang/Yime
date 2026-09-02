# 本机原生数据安全与回退补验

最新状态：2026-09-02 22:21 原生补验已完成，后续只读复核通过，详见[本机原生闭环验收](YIMECORE_NATIVE_LOCAL_CLOSURE_ACCEPTANCE_2026-09-02.md)。无需重复执行。下文保留执行说明和先前失败修正历史，不再表示当前仍待补验。

## 执行入口

保存并关闭 Word 和输入法设置/词库工具；执行期间暂勿输入或修改输入法数据。
从开始菜单或 Explorer 打开 **Windows PowerShell**，不要使用 Codex 内置终端，也不要更改默认输入法。运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\complete-local-trial-closure.ps1"
```

需要 UAC 时只允许当前 Windows 用户的管理员令牌；不要改用另一账户。入口验证 Explorer 来源、无打包应用祖先、SID、开发机范围和准备时锁定的脚本/包哈希。任何不符均停止，不绕过隔离保护。

该入口不是 `Upgrade-YimeCore-Trial.cmd`，不安装新的正常功能版本，也不主动重启 Windows。

## 实际步骤与保护

1. 系统 provider 只读检查 Run/卸载信息，采集真实 runtime/Broker PID、路径、父子关系、启动时间、SID 和注册快照。
2. 停写后新建完整状态与旧包备份，写入 `%USERPROFILE%\YimeCore Recovery Archives\native-closure-*\restore-backup`，不使用 AppData 内的归档作为独立恢复介质。
3. 对离线模型副本执行日志恢复；实际恢复原生用户模型、词库、黑名单、专业词库配置及设置。恢复前核对所有这些类别，包括新增/删除文件；发现备份后变化即拒绝覆盖。原始模型和设置另外保留，不删除。
4. 重新备份当前状态至同一归档的 `rollback-backup`；使用明确标记的故障专用包，让 x64 runtime 启动失败，执行真实安装事务的回退路径。
5. 完整比较机器 COM/TIP、用户 TIP、Run、卸载信息、默认输入法、语言配置及原始注册值类型；独立 `StdRegProv` 树快照必须一致。验证旧包、配置、实际运行进程和三种编码模式。再次核对学习/词库/设置及归档哈希和系统可见性。

本轮仅调用 x64 注册工具。x86/ARM64 原样继承经 manifest 核验的文件并记录来源，不重建、不执行冻结架构工具；生产 Rime/PIME 保留。故障包即使意外启动成功也必须回退，不能删除仍供冻结架构引用的旧安装根。

## 证据与停止条件

- 完整运行证据：`C:\dev\Yime\.tmp\yimecore-experiment\native-closure-*\`，最终 `summary.json` 或失败时 `failure.json`。
- 独立恢复介质：`C:\Users\tsaan\YimeCore Recovery Archives\native-closure-*\`，包含两份新备份、原件和成功摘要。
- 故障包：`.tmp/yimecore-experiment/native-closure-ready/failure-package`，仅用于本轮故障注入，绝不能用于正常升级。
- 初次准备产物 `native-closure-inputs` 保留为预检查记录，当前入口使用 `native-closure-ready/plan.json`；脚本哈希改变时拒绝使用旧计划。

此前 Word/记事本物理输入及生产版回退输入证据保留；本轮不以合成宿主代替物理输入，也不重新开启冻结机型测试。已通过的重启自启动记录仍保留；本轮维护后的手动运行不冒充新的登录自启动证据。

若出现失败，保留全部备份和失败证据，停止后续升级；先读 `failure.json` 的准确阶段及实际系统状态，不因状态文件写着 running 就宣告恢复。

签名证书正在申请，等候审批，暂缓相关事项。

## 本轮准备验证

- PowerShell 7 和 Windows PowerShell 5.1：24 项数据/进程/系统注册读取保护测试、持有写入句柄时的日志只读哈希测试、5 项 x64 专用演练约束均通过。
- 完整故障包 manifest、当前 staging 维护脚本一致性及冻结 payload 来源校验，两种 PowerShell 均通过；14 项入口依赖哈希已锁定并核对。
- 原有 packaged-context 防护 8 项、用户 TIP 嵌套 Enable/值类型回退回归和系统卸载信息 5 项事务测试通过。
- 两种 PowerShell 均成功只读采集完整系统注册树和实际进程；当前 runtime/Broker 仍为 PID 27424/27460。系统 Run 和卸载信息只读校验通过，manifest 仍为 `8d48953a...`。没有在准备过程中停止 runtime、安装包或改动生产注册。
- 当前 Codex 上下文实际调用补验入口被前置保护拒绝，未触发提权或维护写入。此项是环境保护验证，不是原生恢复/回退通过证据。

## 22:09 原生预检查失败及修正

用户反馈的 packaged-application 报错属于环境前置拒绝；实时进程链也能看到 Codex 子 PowerShell，不能在该窗口内再启动一个 PowerShell 充当原生上下文。另有 Explorer 直接启动的独立 PowerShell，已产生 `native-closure-20260902-220908-2e8dcce6` 记录。

该次原生运行停在 `preflight`：`System-visible uninstall metadata does not match installed package; no repair requested`。独立系统注册值本身正确，唯一差异是预期 DisplayName 被 Windows PowerShell 5.1 错读成乱码。安装器输出无 BOM 的 UTF-8 JSON，而检查器原先未指定读取编码。

现为卸载检查器的配置、manifest、安装元数据读取显式指定 UTF-8；新增无 BOM 中文元数据回归，PS7/PS5.1 均通过。PS5.1 对实际已安装包执行只读校验通过：`native-closure-ready/uninstall-utf8-ps5.json`。已更新本轮计划中该依赖的哈希，其余 13 项未变。未执行注册修复、恢复或安装回退，当前实际 runtime/Broker 仍为 27424/27460。

原失败记录和空恢复归档保留，不覆盖；下一次应在独立原生窗口重跑同一补验命令，产生全新运行目录。环境保护不应移除，预检查修正也不代表完整闭环已通过。

## 22:15 日志读取失败及全链编码修正

`native-closure-20260902-221453-aa7196e3` 已完成原生停写备份，随后在离线副本校验中失败。第一份模型恢复通过；第二份日志首行使用隐式 ANSI 解码，UTF-8 的“秋”被错误解码并破坏 JSON 字符串边界。错误出现在实时模型移动操作之前：没有生成 `pre-restore-user-model`、`pre-restore-settings` 或 `restore-evidence.json`，也没有进入失败升级回退。

这是验收脚本的读取问题，不是日志损坏。原生备份 150 个状态/包文件仍与 manifest 的长度和 SHA-256 全部匹配；6 项实时学习、词库和设置记录与备份一致。备份阶段已按流程停止并重启 runtime，本次观察到 runtime/Broker PID 为 700/24484；当前非提权观察无法读取其完整进程路径，不将此权限限制记成服务故障，也不以状态文件替代下一次原生窗口的完整身份验证。

此前只修正卸载元数据读取不足以覆盖整条维护链。本轮为 8 个相关脚本补上 25 处显式 UTF-8 读取；新增 `test-local-maintenance-encoding.ps1`，在维护前自动检查链内读取编码并运行中文、非 BMP 字符及引号/反斜杠样例。当前扫描 16 个脚本、53 处读取，全部显式 UTF-8，3 个 Unicode 样例通过；15 项入口依赖哈希已锁定。

PS5.1 和 PS7 使用失败运行的两份真实备份日志，在新的离线副本中完整恢复通过：

- installed-v1：485 条日志变更全部恢复，generation=485，165 条学习记录。
- 原始模型：335 条日志变更全部恢复，generation=335，97 条学习记录。
- 两者 truncated_tail_bytes、checkpoint_failures、compaction_failures 都为 0；原始归档未改变，测试没有修改实时用户模型。

证据分别在 `.tmp/yimecore-experiment/encoding-recovery-ps5-20260902/summary.json` 和 `encoding-recovery-ps7-final-20260902/summary.json`。原失败备份及副本保留。下一次仍须在独立原生终端重跑完整补验，不能把这些离线副本结果记为实际恢复或回退已通过。
