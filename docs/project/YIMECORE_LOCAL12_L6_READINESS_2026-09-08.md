# YimeCore local.12 L6 只读就绪审查

日期：2026-09-08。影响产品：YimeCore。范围仅 MYCOMPUTER 当前日用的 `0.1.0-local.12`、其仓外封存包和既有验收记录。本次没有从已安装目录复制文件，没有运行安装器、维护器或注册宿主，没有启动或停止产品，没有读取用户正文、设置、学习文件、事件或原始日志，也没有修改注册表、默认输入法或生产 Rime/PIME。

## 已完成

- 新增 `tools/yimecore/run-local-product-readiness.ps1` 及纯证据判定模块。门禁校验包内全部 74 个 manifest 成员的大小和 SHA-256，并分别输出 `local_product_ready` 与 `public_release_ready`。
- local.12 候选包、`source-snapshot.zip`、`working-tree.patch` 和构建摘要已从既有构包目录复制到 `C:\Users\tsaan\YimeCore Recovery Archives\local12-l6-sealed-20260908`。仓外包 manifest SHA-256 为 `9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e`；包内 74/74 文件和所需安装、维护、帮助、x64/x86 TSF、Runtime/Broker、源码 manifest 成员均通过。
- 门禁确认 local.12 的 L5 最终用户确认和使用后身份/保护检查、安装态 x64/x86 三模式注册宿主、重启与登录自启动均通过；local.11 的 Firefox/Notepad++ x86 实机验收记录和升级前完整恢复归档仍存在。
- PowerShell 5.1 与 PowerShell 7 回归覆盖三种关键状态：缺少当前恢复证据时失败关闭、完整合成证据时仅本机就绪、包成员被篡改时失败关闭。CI 已接入同一双版本回归。

结构化结果见 [2026-09-08-local12-readiness.json](../testing/l6/2026-09-08-local12-readiness.json)。当前各项除一项外均为 true。

## 尚未关闭的唯一 L6 门禁

`current_candidate_actual_restore_and_failed_upgrade_rollback=false`。2026-09-02 的真实恢复/失败升级回退和 local.8 的自身卸载重装仍是有效历史证据；但 local.12 包内 `Manage-YimeCoreTrial.ps1` 与 local.8 不同，因此门禁不把旧控制器的实际演练提升为当前候选通过。local.11 到 local.12 的实际成功升级与升级前备份也不能替代 local.12 控制器的故障回退路径。

关闭该项需要单独的同 SID 原生维护窗口，实际执行当前候选恢复与故障升级回退，并取得 `yimecore-local-product-current-candidate-recovery-v1` 证据。该动作会触碰当前安装，因本轮明确禁止触碰已安装 local.12，所以没有执行，也没有伪造结果。

因此当前结论保持：`L5_final_user_confirmation=true`、`L6_sealed=false`、`local_product_ready=false`、`public_release_ready=false`。签名、ARM64 原生安装/实机宿主和其他实体机验收继续作为公开发行或跨平台的独立 deferred 项，不影响上述唯一的本机 L6 阻塞判断。
