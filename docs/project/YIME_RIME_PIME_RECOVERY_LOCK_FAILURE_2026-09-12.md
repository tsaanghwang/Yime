# Pythonfix 恢复：worker 启动后遇到事务锁冲突

影响产品：Rime/PIME 限定恢复、YimeCore TIP 修复。执行源码 `04a46d6178005f65a767dcd558770591b8864e0b`，固定事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`，继续使用 fae6c1d4 原恢复授权和 pythonfix 策略。没有重新准备或启动旧包。

验证 UTC 2026-09-12 03:17:40.535924 至 03:18:03.983946，退出 0、VALIDATED。Apply 一次，UTC 03:18:03.984948 至 03:19:04.104444，退出 1。无 RECOVERED，恢复未完成。

## 首个错误与调用链

03:18:59.0657109Z，worker PID 29076 的 worker-original-Remove 保留原始 IOException：打开 `recovery-9fe7f28d-0889-4828-85b5-1f481431b43a/install-9fe7f28d-0889-4828-85b5-1f481431b43a/transaction.lock` 时报告文件被另一进程占用。调用栈为 Open-CandidateJournal 第 229 行 → Read-MaintenancePreparedPlan 第 254 行 → Invoke-RimePimeCandidateWorker 第 513 行 → 专用恢复入口第 52 行。

03:19:03.9627038Z，同一 worker 的 defaultstring-recovery-worker 再次保留相同异常链；03:19:04.0280491Z，控制器 PID 26544 记录 `Recovery worker failed: 1`，位置为适配器第 39 行。三个记录是同一失败传播链，不能计为三次重试。本轮已有实际 worker 错误，说明已越过上一轮 Python FilePath 数组绑定失败点。

源码中控制器 recover-defaultstring-transaction.ps1 第 66 行打开 ticket.store，到第 83 行调用 Complete-MaintenanceRemoval 时仍保留，最终第 95 行才释放；Complete-MaintenanceRemoval 第 362 行等待 worker，worker 第 513 行又调用 Read-MaintenancePreparedPlan 打开同一安装 journal。该调用关系支持父子进程事务存储持有冲突的定位，但本轮未采集系统锁持有者，不冒称已直接识别持锁 PID，也不认定是上轮进程残留。

worker 在读取计划阶段失败，未到其后注册移除动作；控制器未到 TIP 修复。入口此前已执行协调、Request-MaintenanceRemoval、运行时停止检查及档案写入，不能概括为整个 Apply 完全没有作用。未重新采集当前注册、载荷或 journal 终态，恢复状态不能提升为成功。

保留全部证据与锁文件；不删除 transaction.lock、不强杀进程、不弱化互斥、不重复 Apply。请开发端修正父子进程事务存储的持有与交接，并用真正分进程回归覆盖后交付新策略。本次错误不是上一轮的 Python 选择错误，未恢复 YimeCore 用户 TIP，旧候选继续停用。

## 证据

[三份脱敏错误](../testing/platform/2026-09-12-recovery-lock-failure/failure-details.json)、[复核结果](../testing/platform/2026-09-12-recovery-lock-failure/verified-result.json)、[外部索引](../testing/platform/2026-09-12-recovery-lock-failure/external-index.json)、[仓库索引](../testing/platform/2026-09-12-recovery-lock-failure/index.json)。原控制台为 Git 外 recovery-pythonfix-04a46d61-once；diagnostics 原件为 failure-33c10c3c1bc04e1caa06ebdd960c63f6.json、failure-ebee678450024080b48a213925c9877c.json、failure-f0c4586d164b4aabaafb77e2c2cd20ae.json。原件与脱敏副本各自计算摘要，授权及委托请求留在 Git 外。
