# Partial 恢复：字体移除返回 native_error=5

影响产品：Rime/PIME 回滚、YimeCore TIP 恢复。源码 `cdeb9a428696356e29619b4b1b939bb51ac7152b`；固定事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`，原恢复授权和 original-bundle 继续复用，未重新准备。

验证 UTC 2026-09-12 05:06:02.251813 至 05:06:36.780894，输出剩余 185 项、VALIDATED，退出 0。Apply 一次，UTC 05:06:36.781891 至 05:08:13.450191，再次核验 185 项，退出 1。无 RECOVERED，TIP 修复未到达，整体恢复仍未完成。

## 本轮新增的精确移除结果

控制器 PID 5712 于 05:08:13.3415907Z 保存 exact-removal JSON，outcomes_available=true，initially_absent_count=7。185 项结果中：

- 第一项 `go-backend\input_methods\yime\data\fonts\YinYuan-Regular.ttf`：status=`preserved-error`，native_error=`5`（访问被拒绝），marked_for_deletion=false，removed=false。
- 后续 184 项全部 status=`not-attempted`，均未删除；其 native_error=0 不表示删除成功，因为根本未尝试。
- 本调用没有新增成功移除项。与前轮已有 7 项缺失分开记录；不是 185 项均遇到占用，也不是删除挂起已确认。

05:08:13.3813840Z 的 defaultstring-recovery 错误明确引用上述证据文件。栈位于 Remove-MaintenanceInstalledFiles 第 411 行，经 Complete-MaintenanceRemoval 第 367 行、专用恢复入口第 85 行。当前错误码不能确定 ACL、字体映射或具体持有进程；未进行这些归因所需的额外探测。

验证已接受部分缺失并要求候选注册 Absent；这是本轮工具验证证据，不代替事后独立注册采集。本轮未重新解析原 journal 或当前系统注册，不声明终态已发布。没有强制删除字体、操作字体注册、修改权限、杀进程、重启或自动重试。请开发端基于精确结果制定下一步限定诊断或恢复，不跳过保护或手写完成状态。

## 证据

[完整脱敏移除结果](../testing/platform/2026-09-12-recovery-font-access-denied/exact-removal-redacted.json)、[错误](../testing/platform/2026-09-12-recovery-font-access-denied/failure-redacted.json)、[复核摘要](../testing/platform/2026-09-12-recovery-font-access-denied/verified-result.json)、[外部索引](../testing/platform/2026-09-12-recovery-font-access-denied/external-index.json)、[仓库索引](../testing/platform/2026-09-12-recovery-font-access-denied/index.json)。

原控制台为 Git 外 recovery-partial-cdeb9a42-once。原移除明细为 fae6c1d4 授权目录的 exact-removal-2316d4a452724ae4b9f0a07186ed46b6.json，原错误为 diagnostics/failure-7ffc594c2d664f9c88493c6aaecbd5aa.json。用户主目录已脱敏；原件与仓库副本分别计算大小和 SHA-256，授权和私人数据不提交。
