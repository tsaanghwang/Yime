# exit 51 原事务只读补证报告

影响产品：Rime/PIME 候选；YimeCore 为保护对象。对应开发端交接 `5cb8e5a7`，原失败报告 `02297f82` 保留不变。

## 结论

本机由用户从资源管理器普通启动原生 PS5，经 `run_checked.py` 完成只读采集。未执行 Install、Remove、Resume、注册写入、产品启停或清理。

当前仍为**安装失败、回滚完成未证实**。预期注册及 Run 值已缺失、候选进程未观察到、默认输入与原计划一致，但 191 项计划载荷仍全部存在，且安装和移除 terminal 均缺失。不得据此报告干净环境或恢复完成。

## 固定对象与解析方式

- 原事务：`84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`。
- 原候选：`rime-pime-coexistence-20260911-empty`，安装器 SHA-256 `0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617`。
- 读取器来自原编译提交 `6321067de503463a71262a84239b8f5c3064f10d`，隔离展开到 `.tmp/exit51-original-6321067d`；没有复制新模块进旧安装或恢复目录。
- 原 transaction store 即使打开既有事务，也会对锁文件取得 ReadWrite 句柄并调用 Flush(true)。为避免对原件执行此操作，先清点并核验复制哈希，再只在新证据目录的 journal 副本上调用原 Open-CandidateJournal、Read-CandidateJournal、Get-MaintenanceDecision。
- 原解析器验证记录魔数、长度、嵌入摘要和严格 JSON。安装 prepared 匹配外部原票据摘要；计划与 approval 的根路径、机器/用户绑定、包摘要、原 approval 摘要和事务路径一致。按原算法重建移除 intent 摘要并核验 prepared/commit 关联。
- 这是副本上的决策关联验证，不是完整恢复入口重演；未声称重新验证所有目录身份或全部原计划 schema 不变量。

## 实际观察

| 项目 | 结果 |
| --- | --- |
| 原票据、approval、boundary、执行参数及两个 journal 文件 | 采集前后名称、长度、SHA-256 与修改时间一致；报告生成时再次读取原件核验大小和 SHA-256 |
| 安装 prepared | 外部摘要绑定通过 |
| 安装 commit / terminal | 均缺失 |
| 移除 prepared / commit | 关联通过，commit 为 `remove-requested` |
| 移除 terminal | 缺失 |
| 原计划已列载荷 | 191/191 存在，大小、SHA-256、文件身份全部匹配，无读取错误 |
| 注册及 uninstall | 原布局 36 个节点全部缺失，无读取错误 |
| 指定 Run 值 | HKLM Registry64 `SOFTWARE\Microsoft\Windows\CurrentVersion\Run` 的 `PIMELauncher` 不存在 |
| 读取方式 | 原 StdRegProv 读取器；未回退进程注册视图。原封装校验 provider 返回状态并检查存在值的类型；本轮值均缺失，不赋造类型。逐次原始 ReturnValue 数字未另行记录 |
| 默认输入 | override、first_language、first_tip 与 retained plan 原始基线一致；此结论仅覆盖这三个字段 |
| 候选进程 | 对原计划 Launcher/server 映像路径筛选，结果为空，未出现同名进程路径不可读记录；因此无当前匹配 PID 或启动时间 |
| 现存日志 | 原 state 根及产品 logs 根范围内未找到目标日志文件；不代表全机所有日志位置均为空 |
| 原生错误输出 | 原控制器与隐藏 worker 未持久化 stderr，具体原始错误仍缺失；未重跑安装补造 |

三份既有 peer unchanged 结果仍仅代表此前的观察时点。本次没有生成新的完整 YimeCore peer 快照，不扩大其时间覆盖范围。

## 证据与采集器错误

完整成功采集目录：`C:\Users\Golde\Yime Rime-PIME Test Archives\readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-ce41cbffd5e14fdca76af1fb6dbfc6b0`。

前一次采集目录后缀 `9e78a0da7282440f9dcdaedbb2ef0891` 原样保留。其错误发生在采集器 Save 序列化空进程集合时，属于本机采集工具错误，不是新的安装失败。修复显式保留空数组/null 后，PS5 空数组、null、单元素数组回归通过；用户重新启动采集，成功结果使用新目录，未覆盖前次证据。

[证据索引](../../testing/platform/2026-09-11-exit51-readonly/evidence-index.json) 提供原件名称、长度、时间和 SHA-256，以及各外部结果文件和采集脚本的哈希。原授权内容、SID、MachineGuid、恢复材料及注册值内容均未提交到 Git；payload 只采集文件元数据与哈希，没有发布设置或学习内容。

## 交回开发端

请基于原包、原票据和当前移除决策制定恢复方案。保留原件及载荷，不把未来的新诊断包视为自动获准接管旧事务。当前没有原始 worker 异常，故障根因仍未确定；所有安装、移除、恢复操作继续暂停。
