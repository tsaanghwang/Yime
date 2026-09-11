# exit 51 原事务恢复方案（待执行确认）

> **已被单次 Resume 失败复核取代：原恢复方案已执行并再次返回 51，禁止重复执行本页历史命令。当前只交回现有证据，见 [开发端复核与补证交接](YIME_RIME_PIME_EXIT51_RESUME_REVIEW_2026-09-11.md)。**

影响产品：只完成 Rime/PIME 失败安装的回滚；YimeCore 为保护对象。本次请求是审阅和制定方案，尚未执行恢复。测试端不得把本文或 CI 成功自行解释为执行指令。

## 审阅结论与限制

已审阅测试分支 `b2e21d9d3` 的只读报告及 evidence-index.json。报告与索引的 191 项载荷、零错误/零不匹配、注册缺失、进程为空、默认输入匹配等摘要一致。原件前后清单的摘要相同。开发端没有访问 Golde 用户目录中的原始证据，故这属于对提交报告、索引和原恢复代码的审阅，不冒称独立复测原始文件。

当前状态符合“安装未提交、移除意图已提交、两边 terminal 均缺失”。恢复目标是完成 `rolled-back`，不是继续安装。191 项载荷仍在且身份一致，提供了原精确删除算法所需的候选对象；这不授予按目录递归删除的权利。

## 固定绑定

- 原事务：`84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`。
- 交付：`test-delivery/rime-pime-coexistence-20260911-empty`，index SHA-256 `b45f350998f85bfd19b1c450ae2e7aa9ca630fcd89325771ad4baa2389e7cf63`。
- 安装器 SHA-256 `0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617`。
- 原票据 SHA-256 `05352e3da345967e3e71fb5b6551f1db5739473f46a36ce3b311c46313d2b039`，路径见准备参数文件。原 approval SHA-256 `89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab`。
- PreparedSha256 必须读取这个已核验的原票据。索引中 prepared.bin 的文件 SHA-256 不是可直接替代票据摘要的数值。

不得换诊断包、替换旧包维护脚本、编辑旧授权或票据。新源码增加的诊断功能没有进入原包；本方案不声称能补回历史异常。

## 执行前检查（确认执行后进行）

1. 使用同一“计算机”、同一 Windows 用户，从资源管理器普通启动原生 PS5，进入本机仓库根目录。记录本次控制台输出至新的仓库外证据目录；不得在 Codex/带包身份的终端中启动维护。
2. 再验证固定交付六份文件及原票据、原 approval 的上述摘要。复制原 journal 及授权证据到新的外部备份，逐项比较摘要；仅在副本上进行会取得 ReadWrite 锁的解析。保留原目录身份和原件。
3. 重做只读报告中的状态检查：安装仍没有 commit/terminal，原 remove-requested 关联有效且无 terminal；191 项已列文件仍全部匹配文件身份/大小/哈希；原注册、uninstall、指定 Run 值仍缺失；原候选进程仍不存在；默认输入三字段仍匹配。任何变化都停止本方案，不自行适配或重试。
4. 用现有准备工具的 `Mode=Resume` 和原票据产生一份**新授权**，保持原 install/state/recovery 根及包身份。工具会重新取得完整 peer 快照和原生上下文证据。不得改旧授权的过期时间。生成后核对新执行参数的 Mode 必须是 Resume、包 SHA 必须等于上述值、PreparedSha256 必须与原票据一致，所有产品根路径必须还是原事务。

准备参数已提供为 `docs/testing/platform/2026-09-11-exit51-readonly/resume-preparation.json`。该文件仅用于准备，不是执行参数，不能交给安装器；不要双击根目录默认 Install 准备入口。

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file docs/testing/platform/2026-09-11-exit51-readonly/resume-preparation.json
```

## 单次恢复操作

全部前置检查通过且用户已确认执行本方案后，使用刚生成的 execute-parameters.json，通过现有执行入口运行**一次 Resume**。接受同 SID 的 UAC 提升。

```text
python tools/powershell/run_checked.py --script tools/dual-product/execute-rime-pime-coexistence-test.ps1 --edition ps5 --params-file <本次新生成的execute-parameters.json绝对路径>
```

原 `6321067de` 控制器仅在存在安装 commit 且没有 removal 时进入前向 Runtime 恢复；本事务不满足该分支，会进入 Complete-MaintenanceRemoval。其顺序为保持已提交的移除意图、确认/停止原计划拥有的 Runtime、委托原 worker 处理移除、验证注册缺失、比较 peer/默认输入、按原计划文件身份精确删除，再写移除和安装回滚终态。

预期 worker 观察到注册缺失后无需重放注册器；如执行前状态变化导致该预期不成立，应由前置检查阻止本方案。状态目录、学习、未列文件、目录本身、恢复 EXE、原票据和 journal 按原策略保留。根目录仍存在是允许结果，不以目录消失判定成功。

## 成功与停止判据

成功必须同时满足：退出码为零；原安装 commit 仍缺失，安装 terminal 合法关联原 PreparedSha256 且 disposition=rolled-back；原移除 commit 保留且 terminal=remove-complete；191 项原已列载荷观察为缺失；注册和指定 Run/uninstall 仍缺失；没有原候选进程；恢复前后完整 peer 比较未变；默认输入三字段仍匹配。

归档新的原始结果与哈希，记录未列文件/用户状态/恢复材料仍保留，提交报告到测试分支。此结果只证明这一次事务回滚，不提升共存安装、宿主或重启验收。

若任何检查失败或再次退出 51：停止，不自动重试，不新 Install、不手工清理、不补写 terminal。保留本次新授权、完整控制台输出和原 journal，重复只读补证。控制台记录无法保证捕获原包隐藏提升 worker 的 stderr；若仍缺详细错误，需要另行制定诊断桥接或专项恢复方案，不能修改固定包后继续。

## 开发端验证

新增隔离回归构造“注册失败且移除 worker 失败”的准备态：无安装 commit/terminal、有 remove-requested、全部计划载荷保留。更换新授权 run 后 Resume 返回 rolled-back，未重新注册或启动 Runtime，精确移除计划载荷并补齐两个 terminal。PS5/PS7 各 16 项维护检查通过。注册/进程部分使用夹具，并非测试机真实提升恢复；原包决策分支另经源码审阅，现阶段不宣称原机恢复已经成功。
