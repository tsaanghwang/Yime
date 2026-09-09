# DP1-U 私有 hive 与精确文件删除的原生持久事务

影响产品：Rime/PIME。本批把 [application hive 类型恢复](YIME_DUAL_PRODUCT_DP1_U_APPLICATION_HIVE_2026-09-09.md)
与 [按句柄删除普通文件](YIME_DUAL_PRODUCT_DP1_U_EXACT_FILE_REMOVAL_2026-09-09.md)
接入可在新进程中恢复的事务协议。实际操作对象仍是仓内自有 hive 和普通文件夹具；
它不是已经完成的原生产品安装、注册、回滚或卸载事务，也未接入 NSIS 执行入口。
当前源码的事务回归已在 PS5/PS7 各通过 45 项，私有 hive 类型恢复分别通过 53 项；
下文绑定这两组独立证据，不据此关闭产品维护验收。

## 对象与入口

源码为 `tools/dual-product/rime-pime-dp1u-native-transaction.cs` 与同名 `.psm1`。
模块同时持有自身及 application hive、精确文件删除两组实现的六份源码读取租约；
原生帮助源码按固定哈希核对，并编译到本模块私有随机命名空间。准备记录绑定全部
六份源码哈希，恢复时任何来源变化都拒绝。依赖模块不使用 `Import-Module -Force`。

调用方预先创建三个同级、普通目录，名称必须使用同一个小写 32 位十六进制 GUID：

```text
<repo>\.tmp\dual-product\dp1-u-native-transaction-<guid>\
<repo>\.tmp\dual-product\dp1-u-app-hive-<guid>\private.hiv
<repo>\.tmp\dual-product\dp1-u-exact-removal-<guid>\payload\
```

入口不能指定其他 hive、系统 HKEY、任意载荷根或提供程序。事务只处理 hive 根上的
固定六个逻辑值，以及 payload 根下明确列出的 1 至 64 个普通文件；文件名必须是
受限的单层名称，不递归删除子树。未列明载荷、目录、hive 文件和事务记录均保留。
各根及祖先以原生目录身份租约固定，拒绝间接路径和不符合文件边界的对象。

| 入口 | 行为 |
| --- | --- |
| `New-RimePimeDp1UNativeTransaction` | 接收 `TransactionRoot`、已关闭 hive 的 `ExpectedHiveFile`、完整六值 `DesiredValues` 及带文件 ID/大小/SHA-256 的 `ExpectedFiles`；验证后发布准备记录，返回 ticket。此阶段不改 hive 值、不删除载荷。 |
| `Invoke-RimePimeDp1UNativeTransaction` | 接收 `TransactionRoot` 与外部保留的 `PreparedSha256`，只对尚无决定的事务执行首次 apply。 |
| `Resume-RimePimeDp1UNativeTransaction` | 使用相同两项输入读取持久决定，按提交前/提交后规则恢复或核验终态；不重新猜测执行方向。 |

`PreparedSha256` 是准备记录中 JSON 载荷的 SHA-256，不是整个二进制封装文件的哈希。
调用方须把 ticket 中该值作为独立绑定保存并传回，不能从待恢复目录重新计算一个
哈希便称其可信。它绑定本次准备内容，不认证调用者、代码执行环境或恶意同 SID 的身份。
ticket 的 `execution_authorized=false` 保持不变。

## 先保存旧、新值，再改变状态

准备时先完整核对指定文件，并通过既有删除原语打开全部批准成员用于预检；hive
必须由单独 Existing 入口按文件 ID、长度和哈希重开。原快照导出固定六值的深复制
数据，旧值和新值均经过完整类型、字段、字节长度和终止符准入，之后才发布 `prepared.bin`。
导出的历史值不是当前状态证明，也不是跨进程可复用的内存快照令牌。

准备记录保存事务 ID、绝对根、三个目录身份、六份源码哈希、hive 文件 ID、文件
身份集合及旧/新类型值。原始字节按规范 Base64 保存，保留 Absent 与零字节现存值、
值类型、顺序及受支持字符串终止符的区别；不展开环境变量或修补不支持的历史畸形值。
这里持久保存的是本次自有夹具的原始值，不能描述为仅保存哈希，也不是生产用户数据备份。

恢复会重新准入持久化值，取得新的原始当前快照，再通过原 application hive Set
路径写入；不能把反序列化对象直接当作原生快照。外来 hive 值保持不变。

## 持久决定与恢复方向

每次操作由零长度 `transaction.lock` 的独占文件句柄串行化。正式记录只有
`prepared.bin`、`commit.bin`、`terminal.bin`；每个记录包含魔数、精确长度、JSON
载荷摘要及载荷。读取拒绝截断、额外内容、摘要不符、重复或大小写重复 JSON 键、
错误字段类型及与本次根/准备摘要不符的决定。

发布先用 `CreateNew` 写唯一 `.pending-<guid>` 文件，使用 WriteThrough 和
`Flush(true)`，关闭后通过 `MoveFileExW` 的 WRITE_THROUGH 标志、不替换既有目标
发布正式名称，再从正式文件严格读回。正式记录只发布一次；遗留 pending 文件
可以保留，但永远不是提交或终态决定。正式决定不可读、损坏或相互矛盾时失败关闭，
不能当作“记录不存在”选择另一条恢复路径。

| 已读到的完整决定 | 当前状态要求与恢复行为 |
| --- | --- |
| 尚无 commit/terminal，首次 Invoke | 文件必须全部仍是准备时的批准对象，六值必须完整等于旧值。写入新值、flush 并精确读回后，才发布 `commit.bin`。 |
| 尚无 commit，Resume | 文件仍须完整保留；每个当前值只能等于该值的旧值或新值。恢复全部旧值，核对文件未变，再发布 `rolled-back` 终态。 |
| 已有 commit、尚无 terminal | 六值必须完整等于新值。只继续完成批准文件的目标缺失状态；不能回滚成旧值。 |
| 已有 `rolled-back` 或 `commit-complete` 终态 | 重新核对与决定相符的值和文件状态；不因已有终态文字便跳过验证。 |

提交边界是完整、绑定正确且可严格读回的 `commit.bin`。在新值写入后、提交决定
发布前进程中断，Resume 走恢复旧值；提交后中断，Resume 只向前完成文件清理。
出现旧/新集合之外的值或文件身份变化，拒绝继续并保留现场，不覆盖未知状态。

每个仍存在的批准文件由原删除原语按同一已打开文件句柄核对身份、大小和哈希后
删除。提交后遇到文件已经缺失，只记录 `desired-absence-observed`，并保持
`removed_this_invocation=false`；无法归因于本次进程。删除等待其他句柄释放、
路径不可访问或最终状态不明时不发布完成终态，保留 commit 供之后 Resume。
最终逐项确认文件缺失、六值仍为新值，才发布 `commit-complete`。

Invoke 发生异常时释放本次租约，保留可能已改变的 hive、所有决定及载荷现场；
不会在 catch 中猜测应回滚还是继续。后续恢复仍须使用原外部准备摘要读取正式决定。
事务目录、日志、锁文件、pending 临时文件及三个根都不会被自动递归清理。

日志目录句柄共享读取和写入，保留 DELETE 拒绝，以便在固定目录对象下发布记录。
只共享读取会让 Windows 的同目录 `MoveFileExW` 返回错误 32，已在自有目录中实测；
这项调整仅用于新日志存储，原 hive 和精确删除的目录租约不变。

## 验证与声明限制

事务专属回归在 Windows PowerShell 5.1.26100.9278、PowerShell 7.6.5 顺序执行，
各 45/45、退出码 0。每个宿主启动 15 个自有子进程：8 个在精确故障点以 73 退出，
7 个由新进程恢复并自然退出 0，无强制清理。检查实际 hive 类型/原始字节、文件身份
和状态，不仅检查返回值。覆盖写前、写后提交前、提交后、首个文件删除后、终态后
中断，以及真正只写前三个值并 flush 后中断、回滚完成但终态发布前再次中断。

其他回归包括原值 Absent 的恢复、外来 Binary 值保留、未知第三值/文件替换拒绝、
旧值不符合恢复接口类型时禁止发布准备记录、22 种损坏或错误绑定的正式决定、
遗留 pending、合作锁冲突、日志目录移动拒绝、等待删除时禁止完成终态，以及终态
之后状态变化拒绝。坏决定既有外层损坏，也有重新计算合法摘要的内部 JSON/类型/
绑定错误。此前构造参数解包错误和目录租约导致发布错误 32 的原始失败记录保留，
44 项中间通过记录也保留；以最后 45 项和实际子进程记录判定本批结果。

证据索引为 `.tmp/tx-fixture-20260909-1788948935302/summary-final45.json`，
SHA-256 `f251c511085d31f4783b3d2078f0361aa619313f9334b1a96d577c10c9db9035`，10,366 字节。
索引逐项绑定七份当前实现/测试来源、两份主结果及 14 份成功的新进程恢复结果，
主结果进一步保留各子进程的来源绑定、精确中断点、退出码和原始输出引用。

| 来源或原始结果 | SHA-256 |
| --- | --- |
| `rime-pime-dp1u-native-transaction.cs` | `4859d2abcd3f8eafd17053f10b6063944572796fc81b853606d1ce0da34431b8` |
| `rime-pime-dp1u-native-transaction.psm1` | `55271a8fc38d2e750b2fe5b431ec8862d8e96f43006119b3ec08421be9f6a50d` |
| `test-rime-pime-dp1u-native-transaction.ps1` | `4b1eb8379725f6649d6d22a9ecf06b46083232313edeb2d4a173c0ef2909ee95` |
| `.tmp/dual-product/dp1-u-native-transaction-test-ps5-tx-fixture-20260909-1788948935302-final45/result.json` | `24dfd2efebafde6622a9b162c4b16ee893706c528781a0c13731be87a6d09c30` |
| `.tmp/dual-product/dp1-u-native-transaction-test-ps7-tx-fixture-20260909-1788948935302-final45/result.json` | `89361402874b0f1b934e08a097a137ba96a32532ca2474d183eb5e666eb6565e` |

独立 hive API 的 53/53 结果见其[类型恢复说明](YIME_DUAL_PRODUCT_DP1_U_APPLICATION_HIVE_2026-09-09.md)。
事务回归已接入现有 CI `contract-tests`，顺序运行 PS5/PS7，不增加构建矩阵腿。
Python 基线只验证来源与接线，不执行这些原生 PowerShell 回归；
`process_interruption_protocol_wired=true` 也不是硬件断电证据。

这次协议只处理进程中断后的持久记录和目标状态。`Flush(true)`、WRITE_THROUGH、
内容摘要与进程重启不能证明目录 metadata 耐久或实际断电恢复。目录租约不证明
瞬时子成员完全不变；application hive 加载前哈希到加载后的同文件 ID 检查仍有
内容竞争窗口。均不声称恶意同 SID 物理防止、连续成员保护、原子多值更新或原子
文件与注册表联合提交。

没有访问真实 HKCU/HKLM 注册视图、启动产品 Runtime、运行安装器/卸载器、改变
默认输入法、读写生产用户状态或触碰已安装 local.12。保持
`full_native_product_transaction_complete=false`、`dp1_u_acceptance_passed=false`，
硬件断电、目录耐久、调用者认证等字段也继续为 false。

## 下一步

本协议的真实私有夹具回归与来源绑定已完成。下一步把受控操作扩展到真正产品维护所需的
提供程序：32/64 位 COM/TIP 注册与独立系统视图核对、发起 SID/UAC、Run/卸载项、
快捷方式/私有字体/延期删除，以及非提升 Runtime/后端当前身份和响应就绪。每一类
动作都要接入可恢复的计划、持久决定、冲突处理及另一产品/默认设置保护。

Rime/PIME 现有 NSIS 仍有安装与卸载硬阻断，现有 v2 receipt 只表示 disabled 静态
工件。必须完成上述适配及可信生成卸载器/可执行候选准入，并在指定独立目标执行
注册、失败回滚、卸载和 Runtime 验收，才能关闭 DP1-U；不是仅等待用户批准。
之后才推进 DP2 两种安装顺序矩阵及 DP3 三选一入口。本批不改变这些先后关系。
