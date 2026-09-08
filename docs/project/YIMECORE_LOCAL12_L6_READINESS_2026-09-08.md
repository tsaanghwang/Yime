# YimeCore local.12 L6 只读就绪审查

## 2026-09-08 复审纠正（当前判定）

下方初版 v1 仅校验了部分公共包成员，报告布尔值存在 PowerShell 类型强制转换问题，x86 文档存在性也不能替代原始证据核验。初版 JSON 原样保留，不再用“除一项外均通过”证明当前就绪。

修复后的 v2 使用受审查的路径和 SHA-256 索引绑定候选、目标、日期及原始 registered/x86 记录，拒绝字符串真值、错误包身份、缺失原始文件和路径逃逸。实际核验还逐项读取源码 ZIP，验证 seal、补丁及构建摘要，并重新检查仓外上一 local.11 公共包的完整清单。此过程只验证历史验收与现存公共工件，不是新一轮安装态或真实宿主验收。

PS5/PS7 最终各 43/43 回归通过；新的[PS5 只读结果](../testing/l6/2026-09-08-local12-readiness-v2-ps5.json)与[PS7 只读结果](../testing/l6/2026-09-08-local12-readiness-v2-ps7.json)均为九项证据检查通过、原生恢复未通过，最终代码的只读复跑结论相同。十份原始 registered/x86 JSON 连同来源路径和摘要进入专用证据目录；Git 属性保留原始换行字节，避免跨机器检出时改变摘要。

恢复门禁不再接受手写 all-true JSON。可信原生恢复证据生产入口尚未接入，`L6_sealed`、`local_product_ready`、`public_release_ready` 继续为 false。原有 `CurrentCandidateRecoveryEvidence` 参数仅记录未核验提交的摘要，不能授权或关闭门禁。

[最小维护补验方案](YIMECORE_LOCAL12_MINIMAL_MAINTENANCE_RETEST_2026-09-08.md)核实了 local.11/local.12 控制器同字节以及 local.6 的实际恢复/失败回退证据。需要定向补验的是新增 NativeDesktop 双架构回退、注销及卸载重装路径；不能只因 local.8/.12 控制器哈希不同要求整套重测，也不能复用只支持历史单架构的故障脚本。既有 L5 用户确认保持有效。

## 初版过程记录（由上方纠正限定，不作为新版核验结果）

日期：2026-09-08。影响产品：YimeCore。范围仅 MYCOMPUTER 当前日用的 `0.1.0-local.12`、其仓外封存包和既有验收记录。本次没有从已安装目录复制文件，没有运行安装器、维护器或注册宿主，没有启动或停止产品，没有读取用户正文、设置、学习文件、事件或原始日志，也没有修改注册表、默认输入法或生产 Rime/PIME。

### 初版记录的已完成项

- 新增 `tools/yimecore/run-local-product-readiness.ps1` 及纯证据判定模块。门禁校验包内全部 74 个 manifest 成员的大小和 SHA-256，并分别输出 `local_product_ready` 与 `public_release_ready`。
- local.12 候选包、`source-snapshot.zip`、`working-tree.patch` 和构建摘要已从既有构包目录复制到 `C:\Users\tsaan\YimeCore Recovery Archives\local12-l6-sealed-20260908`。仓外包 manifest SHA-256 为 `9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e`；包内 74/74 文件和所需安装、维护、帮助、x64/x86 TSF、Runtime/Broker、源码 manifest 成员均通过。
- 门禁确认 local.12 的 L5 最终用户确认和使用后身份/保护检查、安装态 x64/x86 三模式注册宿主、重启与登录自启动均通过；local.11 的 Firefox/Notepad++ x86 实机验收记录和升级前完整恢复归档仍存在。
- PowerShell 5.1 与 PowerShell 7 回归覆盖三种关键状态：缺少当前恢复证据时失败关闭、完整合成证据时仅本机就绪、包成员被篡改时失败关闭。CI 已接入同一双版本回归。

结构化结果见 [2026-09-08-local12-readiness.json](../testing/l6/2026-09-08-local12-readiness.json)。当前各项除一项外均为 true。

### 初版记录的待办（以复审纠正为准）

`current_candidate_actual_restore_and_failed_upgrade_rollback=false`。2026-09-02 的真实恢复/失败升级回退和 local.8 的自身卸载重装仍是有效历史证据；但 local.12 包内 `Manage-YimeCoreTrial.ps1` 与 local.8 不同，因此门禁不把旧控制器的实际演练提升为当前候选通过。local.11 到 local.12 的实际成功升级与升级前备份也不能替代 local.12 控制器的故障回退路径。

关闭该项需要单独的同 SID 原生维护窗口，实际执行当前候选恢复与故障升级回退，并取得 `yimecore-local-product-current-candidate-recovery-v1` 证据。该动作会触碰当前安装，因本轮明确禁止触碰已安装 local.12，所以没有执行，也没有伪造结果。

因此当前结论保持：`L5_final_user_confirmation=true`、`L6_sealed=false`、`local_product_ready=false`、`public_release_ready=false`。签名、ARM64 原生安装/实机宿主和其他实体机验收继续作为公开发行或跨平台的独立 deferred 项，不影响上述唯一的本机 L6 阻塞判断。
