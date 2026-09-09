# YimeCore 恢复证据准入修复

影响产品：YimeCore 源码。`restore-local-trial-state.ps1` 原来用 PowerShell 真值判断
备份结果，字符串 `"false"` 可能通过；RecoveryProbe 退出为 0 后直接接受 JSON，
没有确认结果属于本次 clone 和 source。错误证据可能因此进入停止写入者、移动当前
模型的后续路径。

本次在原脚本中修复，入口参数保持不变：

- `passed`、`writers_stopped`、`native_context_verified` 必须为布尔值 true。
- JSON 必须为对象，拒绝重复键，保留 PS5 对单元素数组的类型边界。
- RecoveryProbe 必须实际返回整数退出码 0，并生成新的结果文件；结果 `passed`
  必须为布尔值 true，`clone` 和 `source_id` 必须与本次请求完全相同。
- 按现有 Go 程序的六个顶层字段和 `DurableUserModelStats` 校验计数及可选诊断。
  原生协议没有 `schema_version`，没有增加该要求。计数逐字段校验原值，避免
  PowerShell 管道将非法数组展开成合法整数。
- 所有结果校验均位于停止产品写入者、移动或替换实际状态之前；不改变原恢复流程。

## 回归证据

新 `tools/yimecore/test-local-restore-evidence.ps1` 在 PS5.1 和 PS7 均 **107/107**
通过。除纯证据拒绝外，测试抽取原生产 AST 中的准入调用块，使用私有 probe/stop
替身及新建的模型目录，验证成功路径可继续、错误路径不会停止或移动。
源码生产者字段也与实际 `model-recovery-probe.go` 及 `usermodel_store.go` 核对。

| 证据 | 仓内路径 / SHA-256 |
| --- | --- |
| PS5 | `.tmp/local-restore-evidence-20260909/ps5-final.json`；`f84c1548326fb99aaacb4b49d5a70507bc42d3f87b05cbad45ebf28ebf0edaad` |
| PS7 | `.tmp/local-restore-evidence-20260909/ps7-final.json`；`cafc0cba081d290d99f8c72f873cf7c345385d69eb065f6507d3d31be8246be4` |
| 恢复脚本 | `d94eaddfe4b613c22f984fd4720c692814bc2a1bf708f29977088e132f994f10` |
| 回归脚本 | `310e8527b59585736ee6b5ed0816738d022d5fd8afffbf0c8baffdec97202be5` |

CI 在现有 YimeCore 合约步骤分别调用两个 shell；两份脚本及实际 Go 协议来源加入
双产品来源闭包。本轮未执行完整 restore 入口或原生 RecoveryProbe，没有读取生产
状态或改动已安装 local.12。候选包、安装版本、L5 既有结论和历史 raw 均保留；
L6、local/public release、DP1-U/DP2/DP3 实际验收不因源码回归提升。

后续 YimeCore 维护仍需把支持新协议的候选健康检查接入启动成功/旧根清理前的
事务门禁，并完成原生上下文下真实维护验证；历史 local.12 不能强制新增健康协议。
