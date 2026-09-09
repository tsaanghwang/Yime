# contract-tests 控制器源码许可修复

影响范围：YimeCore 准备工具的已审核源码列表、合成回归及共享 CI 前置调度。
不更改控制器、已安装产品或实际维护执行权限。

## 失败与复现

提交 `388ad7a7decc21dcecce116297a8b7e0066233fc` 的
[contract-tests](https://github.com/tsaanghwang/Yime/actions/runs/34324647044/job/102382134095)
在 `test-local13-maintenance-preparation.ps1` 的首个正例失败：
`Controller is not approved for guarded NativeDesktop rehearsal.`
同一运行的 Go race、native-build 和六项长矩阵全部通过；后续打包没有执行。

该测试将工作树中的维护控制器复制为只读夹具数据，并独立计算其哈希。先前
`f21fff0f2` 接入启动健康门禁后，控制器变成
`c4585051463c18b1164a4bf5eeb624f232fcc4b2c4177180feebe2e3c4448d75`；
准备模块仍只接受两个旧审核值。因此失败是独立许可列表正确拒绝了尚未纳入的字节，
不是 PS5 特有故障。本地修复前 PS5/PS7 均复现相同错误并退出 1。

## 修复边界

本轮独立复审确认，新增启动门禁和 NoLaunch 提前拒绝未削弱 NativeDesktop
强制回滚屏障、旧安装根保留或 finalizer。共享准备模块只追加上述精确哈希；
保留原 `e65ea013…` 和 `9f69d9ab…` 两个值，不按当前文件动态生成许可。

固定候选入口 `prepare-local13-maintenance.ps1`、`local13-maintenance-inputs.psm1`
中的候选、归档控制器和归档准备模块哈希均未改动。这项源码许可只表示具有已审核的
保护逻辑，`execution_authorized`、`ready_to_execute`、实际产品执行与最终验收字段
继续为 false。旧候选不继承新控制器，也没有重构或替换任何历史归档。

回归增加新精确值的正例，以及对真实控制器追加注释后同步重算清单、合同哈希的反例。
后者必须命中独立源码许可错误，不能用一般文件哈希不匹配来冒充拒绝成功。
修复后 PS5/PS7 各 **59/59 通过**。

完整的这项双 shell 回归前移至 `build-contract`，从后续循环中移除重复项。
原有其余 16 项双 shell 回归继续执行；丢失任一 shell 调用或 PS5 退出检查会被
调度回归拒绝。这样源码许可漂移会在昂贵构建和长矩阵之前失败。

## 验证记录

原始 CI 日志、修前双 shell 失败、本轮正反回归保留在
`.tmp/ci-contract-failure-20260909/`。调度回归 **8/8 通过**，actionlint 和
构建合同检查通过。新来源基线收录 **235 个来源**，夹具 **72/72 通过**，
记录后逐一复算哈希无漂移；8 项待验收项及 DP1/DP2 最终闭合字段保持未通过。
基线位于 `.tmp/dual-product/dp1-controller-policy-ci-20260909/baseline.json`。

从当前 CI 步骤原样提取剩余 16 项维护脚本，在同一 PS7 父进程中依次执行每项的
PS5 子进程和 PS7 调用，**32/32 脚本执行通过**。结果位于
`.tmp/native-maintenance-ci-5f321c0435d348819d60fd78f63ad3c6/`；包括旧候选输入
固定哈希、回滚观察、恢复证据及启动健康回归。

后续 26 项合约在 PS5/PS7 各执行一次，**52/52 脚本执行通过**，包括载荷、暂存、
NSIS 树成员、收据、DP1-S/T/U 合成路径、私有 hive、精确删除、PE 导入及静态安装器
检查；工具链闭包明确使用 `-SyntheticOnly`。汇总、逐项日志与来源哈希保留在
`.tmp/contract-after7-20260909-da2648c6/`。这些是本地隔离回归结果；新提交的远端
`contract-tests` 仍须独立验证，不借用旧提交的通过记录。

所有新增或重跑操作只使用源码与私有测试夹具；没有运行安装器、实际维护事务、
已安装 Runtime，也未触碰 local.12、生产 Rime/PIME、默认输入法及实际用户数据。
