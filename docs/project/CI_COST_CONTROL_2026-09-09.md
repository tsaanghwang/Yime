# CI 分阶段执行与费用控制（2026-09-09）

影响范围：共享 CI 调度、Rime/PIME 合成合约和 YimeCore 合成合约。产品实现、
签名发布门禁、已安装产品和验收结论没有改变。

## 已核对的基线

提交 `39c6b068d2cc41ac135f1d1c806b8335391485ca` 的
[run 34290238585 attempt 2](https://github.com/tsaanghwang/Yime/actions/runs/34290238585/attempts/2)
耗时 1 小时 58 分 14 秒。页面上超过三小时的总跨度包括前一次失败/取消和重跑。

| 原执行位置 | 耗时 |
| --- | ---: |
| `native-build` 全 job | 106 分 18 秒 |
| 其中 DP1-N installer/receipt transaction，PS5 后 PS7 | 55 分 18 秒 |
| retained receipt publication/crash recovery，PS5 后 PS7 | 15 分 09 秒 |
| DP1-Q evidence archive，PS5 后 PS7 | 13 分 34 秒 |
| Win32 + x64 编译步骤 | 2 分 55 秒 |

三个长回归合计 84 分 01 秒，是原生 job 的约 79%。不能把这些完整性、
崩溃恢复和失败拒绝测试删除，或者把过滤后的子集写成完整通过。

## 执行顺序

1. `build-contract` 首先检查调度图及其拒绝回归、工具链锁、仓外数据锁、
   双产品源码合约和 libIME2 修改边界。失败后不会启动后续 Windows 构建/回归。
2. 原生编译、Go/Rust/Rime/词典检查、`nsis-preflight` 并行执行。
   NSIS 准备和编译区间的 PS5/PS7 回归在这里提前完成。
   `native-build` 保留真实 PE 依赖的 staged-installer-build 回归，并立即保存
   `yime-native-<SHA>` 工件。
3. 上述检查全部成功后，普通 `contract-tests` 与 `dp1-long-contracts` 并行。
   长回归为三个完整套件乘两个真实 PowerShell host，共六个 job，最多同时运行两个。
   DP1-N 两个 host 优先排入矩阵；不会用 `CheckPattern` 切掉用例。
4. 全部回归成功后才生成、验证和上传 installer payload，随后编译禁用执行的测试安装包。
   打包 runner 再次验证自己的固定 NSIS 分发；不复用另一个 runner 的可变工具目录。
5. `core-build` 明确要求新增 job 和原有检查全部 `success`。
   `installer-package` 保留原有普通/标签构建的结果约束。

独立 job 的 `.tmp` 根保留原有短路径预算，PS5 和 PS7 不共享夹具。长回归的三个
结果 JSON（以及原有 sidecar）按 suite、shell、SHA、run attempt 命名上传，保留 14 天。
失败或取消过早可能没有 JSON；上传步骤的 `warn` 不会把测试 job 改判成功。
GitHub job 日志保留实际步骤输出，不上传庞大的合成安装树。

## 失败和重跑

- 三组长回归属于一个 `fail-fast: true` 矩阵：任何一腿失败就取消该矩阵尚未完成的腿。
  已取消/跳过的腿没有通过证据，最终门禁仍失败。其他已经开始的独立 job 不受这个
  matrix 设置控制；其后续依赖会停止。此处不是全工作流暂停功能。
- 每个 job 有明确超时；完整长套件每腿最多 60 分钟。超时是失败，不允许忽略错误继续发布。
- 同一自动分支/PR 的新运行取消已被替代的旧运行。手动运行和标签运行使用独立组，
  不被普通 push 取消。PR 的合并提交与分支提交仍各自验证，不把两者去重为同一结果。
- 原提交的偶发失败：打开 Actions 对应 run，使用 **Re-run failed jobs**。
  已成功 job 的结果保留，失败/取消及其受影响的后续 job 重跑；单个 job 内没有步骤检查点。
- 修复并产生新提交：先在本地运行下面的便宜检查，再集中一次推送。
  GitHub 的普通 Re-run 使用原 SHA，不会采用新代码。
  `workflow_dispatch` 仍提供手动启动完整验证入口。没有新增跨提交复用旧 PASS 的功能。

## 本地提交前检查

在仓库根目录运行；`python` 使用本机已有的 Python 解释器：

```powershell
python tools/ci/test_workflow_contract.py
python -m unittest discover -s tools/dual-product -p test_baseline.py
python tools/verify_toolchain_lock.py
.\tools\validate-build-contract.ps1
git diff --check
```

涉及工作流结构时，还应使用 actionlint 校验 GitHub YAML/表达式。本次使用官方
actionlint 1.7.7 发布包，并核对官方 SHA-256。已有原生构建产物时，在 PS5 和 PS7
分别运行 `tools/test-build-guards.ps1 -SkipPackagedRime`；该检查有真实 PE 输入依赖，
不应为了执行它重新安装产品。长套件调用仅改变调度时，不在本地和云端重复全跑；
首次新工作流的云端运行负责确认新 runner 分配和实际耗时。

## 节省范围与验收

并行缩短等待时间，但不会按相同比例减少成功运行的 runner 总分钟数；新增 runner
初始化和一次 NSIS 准备还会带来小额固定开销。主要费用收益来自提前失败、取消过期运行、
独立 job 重试和避免连续推送/重复验证。不要把 Actions 分钟数等同于 AI 平台的调用费用。
代理等待 CI 时应避免反复读取相同日志和复述无变化状态。

按上述历史步骤耗时估算，拆分后完整流程约 55–65 分钟，取决于 Windows runner 排队和
各 PowerShell host 的实际耗时。该数值是估算；新的远程运行通过和计时才是优化验收证据。
本记录不宣布签名发布、真实安装、卸载/回滚或完整 NSIS 输入闭包已经通过。

2026-09-09 远程验收补记：提交 `d5d0670473ef6df540dd10f00e37a2b2c4da6c9d` 的
[运行 34307751867](https://github.com/tsaanghwang/Yime/actions/runs/34307751867)
最终为 `success`，UTC 03:36:04 至 04:24:06，耗时 **48 分 02 秒**。六个长回归
矩阵项、普通合约、原生构建和 unsigned 包均通过，三个仅标签发布 job 正常跳过。
相比前述成功运行的 118 分 14 秒，墙钟时间减少约 59%；这不代表 runner 总分钟或
AI 费用按相同比例下降。本地原始验证记录中的远程未通过字段保留为写入时的状态。

2026-09-09 后续失败核对：`cf427cdc82a8a50f8bda5a87af65224061890ad1` 的
[运行 34317346502](https://github.com/tsaanghwang/Yime/actions/runs/34317346502)
中，`native-build` 成功（06:03:46–06:09:58 UTC），失败源是
[`go-race-msys2` 的 GDI 绘图测试](https://github.com/tsaanghwang/Yime/actions/runs/34317346502/job/102356443425)：
`TestLanguageIconsRenderDistinctNonEmptyGDIInk` 得到中文 0、英文 64 个着色像素；
日志没有报告 Go data race。快速前置失败后，普通合约、六项长矩阵及安装包构建未启动，
两个汇总门禁按设计失败。不能把这次失败归到原生编译，也不能借用上一提交的全绿。
原始日志保留在 `.tmp/ci-race-gdi-20260909/prior-run-34317346502-job-102356443425.log`。

本轮对 `go-backend/cmd/input-toolbar/main_test.go` 作局部修复。生产 `app.run` 已锁定
OS 线程，绘图夹具原来没有；新增受控线程让出回归在修复前实际记录 owner=42892、
resumed=1516、holder=42892 并失败，证明夹具违反了 GDI 线程合同。现在锁定范围覆盖
GetDC 到 ReleaseDC 及全部清理，绘图后检查 GdiFlush，并拒绝 GetPixel 的无效返回值。
字体、生产绘图实现、非空与图形差异断言均未改动。依据是微软的
[同线程释放 DC 要求](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-releasedc)、
[按线程存储的 GDI 批处理](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-gdiflush)
及 Go 的 [LockOSThread](https://pkg.go.dev/runtime#LockOSThread) 约束。

四项绘图/线程回归修后普通与 race 各重复 100 次，分别 **400/400 通过**；修前仅重复
原三项测试也曾通过，因此不声称已证明远端单次空白的唯一历史原因。修复的是实际
复现的线程合同缺口，远端结果仍需由新 SHA 的 CI 验证。原失败日志、迁移反例以及
本地输出均保留，不用重跑旧 SHA 或取消断言来消除失败。

完整 `input-toolbar` 包的普通/race 回归各 **33/33 通过**，无 race 报告。源码固定为
`fc5d71b9df1bf9ac8df09072da65d0f433f3062cf6d8968c4d414b4e320ec316`；最终摘要
`.tmp/toolbar-gdi-fix-20260909/summary-final.json` 的 SHA-256 为
`87a44c525a0311ff7827f300432bb2ae688aabe008669a5132d725f3ce303072`，逐项绑定九份原始
日志，包括早期本机 cgo 编译退出 2 及同一工具链在沙箱外普通用户下成功的结果。
本轮只编译/运行该测试包，未启动安装器、实际工具栏或修改已安装产品。

2026-09-09 第二次失败核对：`222f2d5f6411df1a942b12d0a11735a7205fe7df` 的
[`go-race-msys2` 日志](https://github.com/tsaanghwang/Yime/actions/runs/34320910054/job/102367315120)
确认工具栏包已通过（1.331 秒），本次失败转为
`TestConnectedSpeechReconnectBrokerBundleDurableLifecycle/full` 的候选选择超时。
该语义测试使用真实临时 journal，选择路径包含 `Write`、`Sync` 和确认；测试 helper
原来的 `Config{}` 同时继承了生产的 50ms 交互期限。在 race 插桩、共享 runner 和真实
磁盘操作中，这不能作为普通生命周期测试的固定时延假设。日志没有报告 data race，
也没有足够分段计时证明具体是哪一次 Sync 或调度延迟造成超时。

修复只将 `connected_speech_reconnect_test.go` 的 `newReconnectSession` 明确配置为
有限的 5 秒夹具预算；生产默认、journal Sync、严格 JSON 解码和原有 5ms/2ms 超时
驱逐测试不变。新增反例在原 writer 外层延迟 150ms，仍调用真实 `store.persist` 和
`store.commit`：修前实际得到同一 select timeout，修后核对单次 journal/model
generation、明确提交、学习记录及 Close/reopen 一致性。五组定向测试在普通与 race
模式各重复 10 次通过，独立复审未发现阻断。原始日志及源文件哈希摘要保留在
`.tmp/ci-race-second-failure-20260909/`。

这是持久化生命周期与交互时延测试的职责修正，不是生产 50ms 目标的性能验收。
生产超时停止等待、迟到持久化仍可能完成的既有语义未由本批改变或关闭。

本地完整验证使用与 CI 相同的 `tools/test-go-race.ps1`，Go 1.26.4、MSYS2 UCRT64
GCC 16.1.0，实际退出码为 0；49 个测试包通过，缓存结果 0 个，另 29 个包无测试文件，
未报告 data race。定向普通/race 各有 100 个测试 PASS 事件（含子测试，顶层各 50 次）。
源码 SHA-256 为 `4db2f6d4f1cf4509ef9c1feca3aa414b30d8325b69baadb3c592874242e028d2`；
`summary.json` 为 `b36c17568eb856e1e4589cbb220c3c8993d60b2d8f66b14d72bc97543660b523`，
绑定修前反例、定向回归及完整日志。记录形成时新 SHA 尚未推送，远端字段保留 false；
没有运行安装器或访问已安装 local.12、生产用户状态。

参考：[GitHub 并发控制](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)、
[矩阵失败处理](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations)、
[重跑工作流与 job](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)。
