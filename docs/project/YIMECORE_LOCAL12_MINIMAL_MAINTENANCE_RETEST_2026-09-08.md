# local.12 最小维护补验准备

日期：2026-09-08。影响产品：YimeCore。状态：只读差异审查及补验规格已准备，实际维护未执行。本文件不授予安装、停写、恢复用户状态、注册、卸载或重启权限；也不把历史通过改记为 local.12 通过。

## 审查结论

不能仅因 local.8 与 local.12 的维护控制器哈希不同，就要求重新做整套恢复验收。已核实 local.11 与 local.12 的事务控制器和产品维护入口完全相同；local.6、local.8、local.11、local.12 的备份、恢复、运行身份、安全检查及恢复探针也相同。真正新增而尚缺实机故障证据的是 **NativeDesktop 的 x64/x86 双架构注册回退和卸载**。

最近的实际数据恢复和失败升级回退证据是 **local.6，2026-09-03**，不是只有 2026-09-02 的旧 E6-C 记录。local.8 补齐了自身完整卸载重装；local.11 有升级前新鲜原生 Backup；local.12 有成功升级及普通 Runtime、注册宿主、重启与 L5。应分别保留这些结果，不要求重做已经成立的日用报告。

本轮只读取明确路径内的公开产品包、必要归档元数据及仓内报告。重新核对 public package manifest 中列出的全部文件 SHA-256：local.6 为 71/71，local.8 为 71/71，local.11 与 local.12 各 74/74，无哈希不匹配。没有读取或重新哈希归档的 state、user-model、settings、journal、用户正文或原始维护日志。用户状态完整性只沿用原生维护记录的历史结论，没有声称本轮重新验证。

## 候选及恢复介质身份

| 用途 | 精确版本与 manifest SHA-256 | 已核实 public package 根 |
| --- | --- | --- |
| 当前待封存候选 | `0.1.0-local.12`；`9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e` | `C:\Users\tsaan\YimeCore Recovery Archives\local12-l6-sealed-20260908\package` |
| 上一日用版本包 | `0.1.0-local.11`；`5a3f847a3136fd2198f7dc9aba22dc017ed7439d8447435e8752eb379a4a5cd8` | `C:\Users\tsaan\YimeCore Recovery Archives\local-product-20260905-135008-38219e5a\previous-package` |
| 已通过卸载重装的历史包 | `0.1.0-local.8`；`0354fd33fcae9171004ecd7c9a33f2e56bcf27c2cc99e58fbf857bc67e8e1fc2` | `C:\Users\tsaan\YimeCore Recovery Archives\local8-uninstall-reinstall-20260903-171745-7fffaaf1\preuninstall-backup\previous-package` |
| 已通过实际数据恢复的历史包 | `0.1.0-local.6`；`42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087` | `C:\Users\tsaan\YimeCore Recovery Archives\local6-backup-restore-20260903-110006-133432a3\previous-package` |

local.12 的仓外 `seal.json` 固定源码快照 `4c5b89fa5088aed016ebb2905ec6409f2688cde8054100756fdbdb1b6897ac74`、源码清单见包内 `build/source-manifest.json`（`2f31f6d278a7fa46e2b7ae2118df88649cefd02ec7a6c3b017d3a5eb099f2c57`）。本文件引用封存元数据；源码 zip 的完整核验由 L6 只读门禁负责，不能用本文件替代它。

上一版本备份的 `backup-manifest.json` 本轮重算为 `317b3bc99d033c5ddf94ea88bda36c1b6922510de5c0a541c3512313ec5ba933`，与 [09-05 原生备份记录](../testing/l5/2026-09-05-local12-native-backup.json) 一致。它属于 local.11，不能在将来直接覆盖已经继续使用的 local.12 数据；实际维护必须另取新鲜备份。

计划目标为 `MYCOMPUTER`，AMD64 Windows，原生 x64 Runtime/Broker 和当前身份 x64/x86 WOW64 TSF。候选描述仍将本地产品维护锁定到该机，不支持把它直接当作另一台电脑的安装包。09-05 [安装元数据](../testing/l5/2026-09-05-local12-installed-metadata.json) 记录：

- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-62af8b507c91-9b3366b3`。
- 发起 SID：`S-1-5-21-2783006668-770716121-2150155084-1001`。
- 活动 CLSID：`{E40FA752-BB96-461D-A51D-F40EB437EC65}`；Profile：`{126F54C6-E9B1-4E22-8652-03224CBD49F9}`。

以上是已记录的预期身份，未来维护窗口必须重新核对实际安装与发起 SID；本次没有读取当前用户状态来作新证明。新维护窗口时间、授权引用、运行 ID、新备份路径和故障候选 manifest 均未确定。

## 已核验的维护差异

| 文件或路径 | 实际变化 | 对补验的影响 |
| --- | --- | --- |
| `Manage-YimeCoreTrial.ps1`：local.11 → local.12 | 完全相同，SHA-256 `ff3a563bf58999683f34e9c6fb73656ea6790b120e48fd322b71f97c99818cca` | 不为这一步虚构新事务变化。 |
| `manage-local-product.ps1`：local.11 → local.12 | 完全相同，SHA-256 `b0d85e48d43cf3b8f04f32c3b713fc7cab094e7811001086277f30be9860af06` | 已有 local.11 Backup 与 local.12 成功安装经过同一入口。 |
| `backup-local-trial-state.ps1` | local.6/.8/.11/.12 相同；`3e1bc247dec0283f3d0f0dcaee91bd18ec2c41ac005792f478e63d6c121da3e8` | 停写、复制稳定性、完整归档和启动恢复的历史行为证据可继承。 |
| `restore-local-trial-state.ps1` | 四版本相同；`52950c81b66776877da83078b4b8923d052557a5c1a25662870c0be777b59bd1` | 备份新鲜度、离线恢复、原件保留、恢复失败退回原件路径没有新增实现变化。 |
| `local-maintenance-safety.ps1`、`local-package-contract.ps1`、`local-product-runtime.ps1`、`local-runtime-launcher.cs`、`start-e6c-trial-runtime.ps1`、`stop-e6c-trial-runtime.ps1`、`verify-e6c-trial-runtime.ps1` | 四版本各自同字节 | 相应代码路径无需仅因版本递增而重复全部测试；新 Runtime/Broker 的集成结果仍应绑定实际版本。 |
| `bin/YimeCoreRecoveryProbe.exe` | 四版本相同；`e3b37e3a26c36ff17b4b2df7a856bc2fc12380e51393f82168c326173326ec48` | 不存在“本版换了恢复探针”这一重测理由。 |
| local.6 → local.8 控制器 | 完成卸载后删除活动用户 TIP；只有真实旧安装才恢复原 TIP，否则显式 DWORD `Enable=1`；语言列表操作前保护旧身份用户 TIP | local.8 自身卸载重装已实际覆盖这些修正；local.6 的旧卸载假 PASS 不可继承。 |
| local.8 → local.11 控制器/入口 | `NativeDesktop` 取代入口的 `NativeX64Only`；新增 x86 `register-com`；按旧包 descriptor 判断恢复架构；精确寻找当前身份注销工具；UAC 与卸载命令透传 `NativeDesktop` | 双架构失败回退、完整卸载间隙和重装仍需定向实机补验。 |
| local.11 → local.12 scope | 增加获准平台实验入口和目标，修改 scope ID；本地 `MYCOMPUTER`、AMD64、x64/x86 和 64 位 PowerShell 限制保留 | 需 scope 兼容性回归；这不是 ARM64 或另一实体机实际维护证据。 |

## 历史证据的继承边界

| 历史证据 | 可继承的结论 | 不得提升为 |
| --- | --- | --- |
| local.6 `acceptance-summary.json`，SHA-256 `8ed2e5a3ae0f014a3fefd8e97bd664a9bb67146148676fe4e1de3bd9dd98a829`；同目录 `restore-evidence.json`，`fda347a01ffb5a8b52a51a572d740b97a33131a8564145773f82c81adef5d368` | 原生停写备份、实际 Restore、原件保留、数据哈希保持、注册不变、普通 Runtime 的 local.6 原始通过；结合上述字节等同性作为恢复实现的依据 | local.12 本次实际 Restore、未来数据内容兼容性或全新故障恢复通过 |
| local.6 `local6-failed-upgrade-rollback-20260903-110721-19d95018/corrected-postacceptance.json`，`20733201aa6c9f14b173feafc01d4a1e63a0b92306bad25f1e7c81bac7e4c09b` | 原退出码 1、权威启动失败关联、local.6 包/注册/数据/普通 Runtime 回退通过；保留原假阴性摘要 | 当前双架构回退通过；原控制器只运行当前 x64 注册工具 |
| local.8 `local8-uninstall-reinstall-20260903-171745-7fffaaf1/summary.json`，`b1371135966d57b13b01e1f9cc2b96cab0be23cefb2c583b95626213a9b06a86` | 自身卸载重装、活动 TIP 子树消失后重新 DWORD 1、生产与默认项保持 | 当前 x86 COM 注销/重装通过；原活动架构只有 x64 |
| local.11 原生 Backup 与 local.12 成功升级记录 | 当前双架构入口成功路径、旧包介质、数据与保护项保持 | 失败事务自动回退、完整卸载间隙或新鲜 local.12 Restore |
| local.12 L5、注册宿主、重启证据 | 已完成的本机日用和对应精确包的运行证据 | 维护后的新进程身份、故障回退、卸载或新登录启动 |

以上归档根均位于 `C:\Users\tsaan\YimeCore Recovery Archives`。没有重读 `data-before.json` 等用户数据记录；历史聚合布尔值用于确定原报告范围，不独立构成本轮实际验收。

## 最小补验序列与停止条件

先完成准备与孤立回归，再安排一次经明确授权的同 SID 原生维护窗口。准备阶段不启动产品、不修改安装，不需要用户重新完成 L5。

1. **锁定完整执行计划。**固定 local.12 public 包、实际安装 manifest、所有执行脚本、故障运行时、故障 manifest、独立系统视图采集器及恢复介质验证器的 SHA-256。计划关联发起 SID、目标机、准许的动作、有效期和唯一运行 ID。预检失败就停止；不临时替换脚本、不把 .13 源码当作 .12 包内入口。
2. **新鲜 Backup。**在原生普通 PowerShell 5.1 中，用当前安装包的受控 Backup 路径短暂停写并恢复运行，保存新建仓外包/状态归档。只向审查方导出白名单布尔、版本、哈希、数量和运行元数据；实际原生备份需要读取并复制用户状态，须包含在维护窗口授权范围。无新鲜备份、系统不可见、复制不稳定或 Runtime 恢复失败均不得继续。
3. **当前候选最小 Restore。**若 L6 继续要求“当前候选实际恢复”，只需从本窗口刚生成且未产生新写入的备份做一次原样 round trip，核验原件保留、恢复后字节、系统注册未变及普通 Runtime。无需重复 local.6 的所有编码故障或要求用户重新造数据。任何备份后新增、修改或删除的数据都拒绝覆盖；不使用 `Force`，也不拿 local.11 的旧学习状态回填。此项关闭精确候选执行证据，原因不是恢复算法发生变化。
4. **双架构启动失败回退。**从封存 local.12 的独立副本准备故障专用包，只替换 Runtime 为确定退出码 86 的无状态探针，重新锁定全包 manifest；不能原地修改正常候选。实际失败必须发生在新 x64/x86 注册之后和旧根删除之前，取证关联故障进程、包、运行 ID、时间和安装器实际退出码。回退后核验两个 COM 视图、机器及用户 TIP 的完整值/类型、Run/卸载项、runtime config、旧根、普通 Runtime/Broker 及全部保护项。数据只比较原生白名单指纹，不导出正文。退出码 1 单独不能证明回退；超时、未触发预期故障、注册/数据差异或错误阶段不明立即终止后续卸载。
5. **一次双架构卸载重装。**仅前面全部通过后，取新鲜保护快照和恢复包，执行保留数据的精确卸载。检查当前身份 x64/x86 COM/TIP、用户 TIP 子树、Run、卸载项、Runtime/Broker 和活动配置消失，旧身份及 Rime/PIME、默认设置、用户数据和仓外包保留；之后从已验证的同版 public 包重装，核验 DWORD `Enable=1`、双架构注册和普通权限运行。残留或数据变化时保留现场并停止，不能强删 DLL、杀 Explorer 或清空用户目录来获得 PASS。
6. **最小人工确认和独立复核。**用户只需保存/关闭受影响宿主、从 Explorer 打开普通 Windows PowerShell、以同一账户确认 UAC，以及维护后实际选择“音元拼音”完成一次短输入确认。若该次维护改变了 Run/安装根并要求新的登录启动证据，由用户自行决定真实重启时间；手动启动不能冒充重启证据。无需重新报告既有 L5 时长或做额外两天日用。

**当前尚不能发出可执行维护命令。**上述第 4 步缺少已审查的 local.12 双架构故障候选与取证执行计划。现有 `invoke-local6-failed-upgrade-rollback.ps1` 锁定 local.6 manifest、SID 和旧故障包；`complete-local-trial-closure.ps1` 使用历史 E6-C 准备计划；两者均不能原样用于 local.12。不得去掉哈希/SID/范围检查来使旧命令运行。

还需解决一个明确的故障边界：local.12 控制器拒绝把 `NativeDesktop` 与 `NativeX64Rehearsal` 混用，且“故障包意外启动成功也强制回退”的分支只属于后者。因此新双架构演练执行器必须证明注入只会失败，并处理意外成功时的安全停止/恢复；单写 `rehearsal_only=true` 不能提供该保证。不得在尚未解决时运行故障包，也不得修改已封存 local.12 控制器然后继续声称测试的是原包。

## 完成条件

本文件只关闭“比较具体变化并准备最小补验范围”。当前 `current_candidate_actual_restore_and_failed_upgrade_rollback`、当前双架构完整卸载实机结果、`L6_sealed`、`local_product_ready`、`public_release_ready` 均不因此置为 true。

后续关闭维护门禁需要精确绑定候选与新鲜归档的原生证据，而非本文件、历史汇总布尔值或 PS5/PS7 合成 PASS。实际执行仍受 [AGENTS.md](../../AGENTS.md) 的安装、同 SID、原生上下文和数据边界约束，以及本轮“不触碰已安装 local.12”的明确范围限制。没有用户数据访问和实际维护窗口的明确授权时，继续实现和验证准备工具即可，不能以“完成尚待工作”代替真实运行证据。
