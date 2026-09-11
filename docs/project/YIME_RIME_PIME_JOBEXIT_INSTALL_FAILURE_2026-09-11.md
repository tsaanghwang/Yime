# 计算机：jobexit 新候选安装失败，自动回滚完成

影响产品：Rime/PIME；YimeCore 为共存保护对象。按 `d4552abc93b599acc48bd205ad474aa1687e6203` 新安装交接，以 Golde 从资源管理器启动一次新事务，未重试。安装失败，**本机安装验收未通过**；该新事务自身的自动回滚已完成。原事务 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0` 未被重新执行。

- 包：`test-delivery/rime-pime-coexistence-20260911-jobexit`，版本 `1.4.0-dev.1`，完整性交付校验 `integrity_passed=true, artifact_count=6`。
- 安装器 SHA-256：`ffdd6f380a9fe7518f9c6db6d54c100f526201989d268a8638c6c6a603d3eacd`。
- 新事务：`80f6a615-c0c6-407f-8ed3-b2a021605d2c`；Mode=Install，PreparedSha256 为空，使用新 install/state/recovery 路径和新授权。
- 执行 UTC：2026-09-11 15:19:01.146626 至 15:23:03.633320（北京时间 23:19 至 23:23）。安装器返回 51，Python 执行进程返回 1，attempts=1。
- integrity、prepare、before、after、collect 的退出码均为 0。安装后取证成功不代表安装成功。

## 直接失败证据

15:20:22.9382346Z，PID 38656，`elevated-Register` 报 `Machine registration not complete: com-x64`，位于包内 `rime-pime-dp1u-candidate-registration.psm1` 的 `Assert-CandidateMachineRegistration` 第 178 行，调用路径经过第 274 行。随后 install-original 记录 elevated worker 返回 51；15:23:02.8583456Z 的 controller-Install 明确记录安装失败且原生事务已回滚。

这是当前证据能定位的失败断言；尚不能断言 x64 COM 注册缺失或不匹配的底层原因。本轮三份 failure JSON 未报告此前的 Job 活动后代错误，也不能仅凭总退出码 51 将两轮归为同一原因。脱敏错误及完整调用栈见[失败详情](../testing/platform/2026-09-11-jobexit-install-failure/failure-details-redacted.json)。

## 回滚与共存保护复核

只读采集复制日志后使用当前严格解析器读取副本，未打开原事务存储进行维护。prepared、授权、票据及事务绑定通过；安装 commit 缺失，install terminal 为 `rolled-back`；removal commit 为 `remove-requested`，removal terminal 为 `remove-complete`。这两份 removal 决定属于安装器自动回滚，测试端没有另行执行 Remove。

192 个计划载荷均不存在，并用 `os.lstat` 独立复核，仅把 FileNotFoundError 认定为不存在。通用采集 summary 的 `payload_errors=192` 是回滚后按“应存在载荷”检查产生的缺失记录，不是 192 个新增安装故障。37 项注册/Run 观察无错误且全不存在，候选 Launcher/server 当前进程为空；因此没有已安装运行时可进行 native Rime readiness 验收。

安装前后默认输入比较一致。控制器三组 YimeCore peer 比较均 unchanged=true，前后摘要均为 `9fbcf26fc7b557f6393b4a8ae890048e0231a708591ad66fa044cf7e5f12b447`。独立 before/after peer JSON 结构也完全一致。辅助脚本的 `independent-peer-comparison.json` 是空文件：断言函数成功时没有返回对象；保留原文件，不将其作为 JSON 通过凭据，采用完整快照比较及三份控制器结果佐证。

取证前后原证据文件哈希保持一致。新旧恢复材料与目录保留，不清理、不重放。真实宿主输入、重启登录、自启和升级/卸载矩阵均保持未验，等待开发端审阅本轮失败后给出下一步。

## 证据

[复核结果](../testing/platform/2026-09-11-jobexit-install-failure/verified-result.json)、[事务决定](../testing/platform/2026-09-11-jobexit-install-failure/decisions.json)、[执行记录](../testing/platform/2026-09-11-jobexit-install-failure/execute-process.json)、[仓库副本索引](../testing/platform/2026-09-11-jobexit-install-failure/index.json)、[外部证据 SHA-256 索引](../testing/platform/2026-09-11-jobexit-install-failure/external-evidence-index.json)。

原始控制台、授权、边界、完整 peer 和注册观察均保留于 Git 外 `%USERPROFILE%\Yime Rime-PIME Test Archives`，包括 `jobexit-install-d4552abc-once`、本轮 `approval-80f6a615-...`、`readonly-80f6a615-c0c6-407f-8ed3-b2a021605d2c-5884e03a4fd34644bf235115162ae659` 和 diagnostics 下本次三份错误。授权和用户数据原文未提交；外部索引将用户主目录替换为 `%USERPROFILE%`。

## 开发端审阅及暂停点

已接收 `167c5906e`，七份仓库证据副本的长度和 SHA-256 全部匹配索引。接受本轮“安装失败、自动回滚完成、peer 与默认输入未变”的报告结论；外部原始文件未在开发端重新读取。无需再次收尾，不重放任何新旧事务。

源码路径表明，`RegisterNative` 在 x64 regsvr32 的受控子进程检查通过后，才调用机器注册断言；该断言对 com-x64 的匹配项数量、键存在性、值数量和子键数量使用同一个错误文本。预期该键有一个默认字符串值及一个 InprocServer32 子键。当前提交没有失败瞬间的这些实际数量，不能判定是哪一项不符，也不能由进程退出 0 推定注册结果完整。DLL 的源码写入 HKLM Classes，不能未经证据改写为防火墙问题、HKCU 重定向问题或 Windows 安全策略问题。

下一步由开发端补足这条注册断言的失败观测，并核对注册写入与系统视图读取的对应关系；在有可审阅的定位或新诊断候选前，测试端保持现状，不重装来补截图，不关闭安全软件。若已有执行期原始日志含注册前后快照，可另交非敏感摘要；没有就记录缺失，不以回滚后快照替代。宿主输入、重启与维护矩阵继续未验。
