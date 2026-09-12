# Lockfix 恢复在精确载荷移除阶段停止

影响产品：Rime/PIME 回滚、YimeCore TIP 恢复。源码 `1814a63ffdbc12cfd4a0d00e9305509e5eb3904a`；目标事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`，复用原 fae6c1d4 恢复授权及独立载荷。未重新准备或启动旧 EXE。

验证 UTC 2026-09-12 04:09:54.354174 至 04:10:18.336611，退出 0、VALIDATED。Apply 一次，UTC 04:10:18.339074 至 04:13:41.004327，退出 1。原错误时间 04:13:40.8997568Z，PID 18924，defaultstring-recovery：`Exact removal is pending or incomplete; no completion decision published.`。

调用栈为 Remove-MaintenanceInstalledFiles 第 398 行 → Complete-MaintenanceRemoval 第 367 行 → recover-defaultstring-transaction.ps1 第 84 行。该位置在 worker 返回、候选注册 Absent 检查、peer 和默认输入检查之后，支持本次已越过此前 worker journal 锁阻断；这是调用路径证据，不冒称已在事后重新独立采集注册状态。

## 当前文件观察

只读按此前 192 项载荷观察逐项检查路径和当前 SHA-256：7 项不存在，185 项存在。清单见 payload-observations.json。未删除或重试任何文件。不存在只接受 FileNotFoundError；其他读取错误不会被当作缺失。本次只核对文件大小和摘要，没有重新核对文件身份。

移除器返回结果中至少一项 Removed 为假，调用方因此在完成终态发布之前抛错。现有实现只在内存变量 outcomes 中检查这些结果，没有保存每项移除状态或错误码。故不能确定是锁占用、权限、删除挂起或其他原因，更不能推定具体 DLL 或进程负责。请开发端保留逐文件移除结果并核对执行期间的载荷读取租约；不要以弱化精确身份检查或强制删除替代定位。

TIP 修复在 Complete-MaintenanceRemoval 返回之后，本次尚未到达。原事务仍不能认定闭合；本轮未重新解析 journal 或采集当前系统注册，也没有 RECOVERED/成功 peer-repair result。由于部分文件已移除，下一轮验证是否支持该实际状态必须由新交接明确，不能直接再跑当前入口。

未重试 Apply、未杀进程、未清理锁文件、未补写终态或手工修复 TIP。保留原错误、授权、载荷副本与全部既有证据，等待开发端限定后续步骤。

[复核结果](../testing/platform/2026-09-12-recovery-exact-removal-stop/verified-result.json)、[原错误](../testing/platform/2026-09-12-recovery-exact-removal-stop/failure.json)、[当前载荷观察](../testing/platform/2026-09-12-recovery-exact-removal-stop/payload-observations.json)、[外部索引](../testing/platform/2026-09-12-recovery-exact-removal-stop/external-index.json)、[仓库索引](../testing/platform/2026-09-12-recovery-exact-removal-stop/index.json)。原控制台为 Git 外 recovery-lockfix-1814a63f-once，原诊断为 failure-642b55542e354dac8f5f557a0b83459d.json。授权及用户数据未提交。
