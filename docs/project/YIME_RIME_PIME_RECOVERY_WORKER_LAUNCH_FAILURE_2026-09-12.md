# logfix 恢复：验证通过，Apply 在提权进程启动前失败

影响产品：Rime/PIME 限定回滚、YimeCore TIP 恢复。使用 `88dc856a0ea749ee9e35ea28f86ff9c742a791fc`、新 logfix 策略及已有 fae6c1d4 恢复授权，目标仍为事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`。未再次准备授权、复制载荷或启动旧 EXE。

验证 UTC 2026-09-12 02:32:16.835941 至 02:32:41.558681，退出 0 并打印 VALIDATED。Apply 随后执行一次，UTC 02:32:41.559811 至 02:33:04.957717，退出 1。没有 RECOVERED，不标记恢复成功。

原始 failure JSON 的中文完整，控制台乱码应以原记录为准：

> 无法将“System.Object[]”转换为参数“FilePath”所需的类型“System.String”。不支持所指定的方法。

类型为 System.Management.Automation.ParameterBindingException，Error ID 为 CannotConvertArgument,Microsoft.PowerShell.Commands.StartProcessCommand。调用栈：defaultstring-recovery-adapter.ps1 的 Invoke-MaintenanceWorker 第 23 行 → Complete-MaintenanceRemoval 第 362 行 → recover-defaultstring-transaction.ps1 第 83 行。

适配器第 22 行取 `(Get-Command python -CommandType Application -ErrorAction Stop).Source`，第 23 行直接把结果传给 Start-Process -FilePath。当解析出多个 Application 时，Source 为数组。另以 run_checked.py 在当前 Codex PS5 子进程只读查询，返回 `C:\Program Files\Python314\python.exe` 及 `%USERPROFILE%\AppData\Local\Microsoft\WindowsApps\python.exe` 两个路径。此查询并非失败时 Explorer 的完全相同 PATH；原调用的 Object[] 参数错误本身已证明启动参数不为标量，不将补查的具体列表冒充失败现场列表。

参数绑定失败发生在 Start-Process 执行前，因此本次没有由该调用启动提权 Remove worker，也尚未到达后续 Restore-DefaultstringPeerTip。适配器此前可能已写入 recovery-worker/recovery-entry 请求文件，包含授权及委托材料，继续留在外部授权目录，不提交 Git。未重试、未自行选取 Python 覆盖固定恢复代码、未修改策略摘要。原事务终态和产品状态本轮没有重新采集，不能声称已闭合或恢复。

请开发端修正可验证的单个 Python 可执行路径选择，并覆盖多 Application 命中及实际参数类型；按新策略和交接继续，测试端暂停。此前诊断日志分类修正已通过验证入口，不等于恢复完成。

[复核结果](../testing/platform/2026-09-12-recovery-worker-launch-failure/verified-result.json)、[原始错误副本](../testing/platform/2026-09-12-recovery-worker-launch-failure/failure.json)、[外部索引](../testing/platform/2026-09-12-recovery-worker-launch-failure/external-index.json)、[仓库索引](../testing/platform/2026-09-12-recovery-worker-launch-failure/index.json)。控制台原件位于 Git 外 recovery-logfix-88dc856a-once；原错误为 diagnostics/failure-9b66f5e96eb847d5ab2a0ee55fb02963.json。未上传授权或用户数据。
