# DP1-I：隔离夹具事务 journal 与幂等重放模型

日期：2026-09-06。影响产品为独立的 Rime/PIME 开发线，但本批只在当前仓库下全新的 `.tmp/dual-product/dp1-i-journal-*` 隔离夹具中验证事务证据格式、重放判定、类型化合成注册快照和精确删除顺序。YimeCore 是另一独立产品，必须保持不变。本批没有运行安装器或卸载器，没有读取或修改真实注册表、产品进程、用户数据、默认输入法、生产 Rime/PIME 或已安装 YimeCore local.12，也没有把夹具接入真实 transaction engine 或 installer。

## 本批结论

[`rime-pime-fixture-transaction-journal.ps1`](../../tools/dual-product/rime-pime-fixture-transaction-journal.ps1)和[显式导出模块](../../tools/dual-product/rime-pime-fixture-transaction-journal.psm1)建立了仅限隔离夹具的 prepared／step／commit／terminal 持久 journal。记录使用封闭 schema、连续序号、前一记录摘要和事务／受保护状态绑定；step 的 operation ID 从事务及阶段身份重新计算，case-local 的类型化合成注册快照与 removal manifest 也在开始和恢复时重新验证。

夹具写入使用新建文件、独占句柄、write-through、`Flush(true)` 和 sidecar-last；这只证明本测试进程在隔离文件系统中实际创建、封存、验证和删除了夹具文件。它不证明真实安装目录、真实恢复档案、NTFS 目录元数据或突然断电后的耐久性。

[`rime-pime-transaction-engine.ps1`](../../tools/dual-product/rime-pime-transaction-engine.ps1)新增的纯模型把无 journal、prepared、committed 和 terminal 映射为 no-mutation、rollback、cleanup 和 noop 判定，并固定重复 mutation 的幂等／冲突语义。[replay model 测试](../../tools/dual-product/test-rime-pime-transaction-replay-model.ps1)在 Windows PowerShell 5.1 与 PowerShell 7 各 16/16；原有 fault matrix 同时保持各 9/9、24 个阶段和 96 个 before／after 故障例。

`Resume` 当前只验证 journal、在唯一且确认为末尾的 torn JSON 记录上删除该未封存尾部，并返回 replay disposition。它不调用 rollback 或 cleanup adapter，不恢复真实注册或文件，也不启动／停止产品进程。测试中的模块重新导入发生在同一进程内，不能称为真实进程崩溃恢复；本批没有执行子进程硬崩溃、跨进程 replay／lock、真实断电或目录耐久试验。

## 类型化合成恢复材料

固定 synthetic registry catalog 覆盖 absent、string、expand-string、DWORD 十进制文本和 multi-string 等类型，并使用合成 SID 与固定坐标。它只验证类型、坐标闭集、规范 JSON 和事务绑定，不访问注册表 provider，也不保存任何用户正文、真实路径值或私人设置。因此“类型化快照通过”不能改写为“真实注册表导出／恢复通过”。

manifest removal 在夹具内按普通文件叶到根删除，将已安装 manifest 排在倒数第二、`Uninstall.exe` 排在文件最后，并以最深目录优先、根目录最后的非递归顺序处理目录。内容或身份已变化的项目及外来项目会保留，结果只记录数量，不披露意外文件名。

这仍不是生产级并发精确删除：从摘要／身份检查到删除之间的并发替换没有排除，`concurrent_replacement_excluded=false`。真实安装所有权、并发攻击面、reparse／hardlink 及提升边界仍须在实际 maintenance transaction 中另行关闭。

## 具体开发回归

本批只报告构建夹具和跨 shell 执行中实际观察到的问题；全部在形成当前证据前修复并加入回归覆盖：

1. **DP1-JOURNAL-DATE-01（已关闭）**：PowerShell 7 的 `ConvertFrom-Json` 自动把 UTC 字符串转换成日期对象，规范序列化时触发递归／数字处理失败。reader 现按能力使用 string date 解析，并显式拒绝 `DateTime`／`DateTimeOffset` 混入规范记录。
2. **DP1-JOURNAL-PS5-PATH-02（已关闭）**：一处路径 API 重载在 Windows PowerShell 5.1 不兼容；已改为两套 shell 共有的路径判定，并由 PS5／PS7 同批验证。
3. **DP1-JOURNAL-PS5-LIST-03（已关闭）**：generic list 作为参数传递时在 PS5 发生绑定差异；已消除该依赖并固定跨 shell 结果一致。
4. **DP1-JOURNAL-CONTEXT-04（已关闭）**：早期 context 可自报 repo root 和 case 路径，存在把夹具范围伪造成其他位置的可能。现以 helper 的脚本位置锚定仓库根，重新计算全部 case 路径并限制到当前仓库下的 fresh immediate DP1-I fixture。
5. **DP1-JOURNAL-CASE-BINDING-05（已关闭）**：早期测试可引用另一 case 的 registry／removal 恢复材料。现要求 case-local 密封材料，并在 `Start` 与 `Resume` 两条路径重新校验。
6. **DP1-JOURNAL-PROTECTED-STATE-06（已关闭）**：早期 step writer 漏写 reader 已要求的 `protected_state_sha256`，导致自产记录不能按闭合 schema 重读。现每条 step 都与同一受保护状态摘要绑定，并由篡改负例覆盖。
7. **DP1-JOURNAL-OPERATION-ID-07（已关闭）**：早期 reader 没有从 transaction ID 与 stage ID 重新计算 step operation ID。现重新计算并绑定，篡改负例会失败关闭。
8. **DP1-JOURNAL-EXPORT-08（已关闭）**：通配导出曾暴露低层写入 helper。模块现只公开固定的 26 个 API，底层 raw／sealed writer 不导出。
9. **DP1-JOURNAL-STATIC-SCAN-09（已关闭）**：静态安全扫描最初把测试文件自身纳入扫描，因其中的禁止模式断言而自触发。扫描范围现限定为 helper 与 module，仍拒绝真实注册表、进程、安装目录和递归删除接口。
10. **DP1-JOURNAL-RESULT-SCHEMA-10（已关闭）**：早期结果缺少稳定 schema 和 `fixture_only` 边界字段。当前 PS5／PS7 结果逐字节一致，并显式保留所有未验证能力为 false。
11. **DP1-BASELINE-FLUSH-11（已关闭）**：基线首版只要求两处 `Flush(true)` 锚点中的任一处存在，单独弱化其中一处时未能失败关闭。现要求至少两处并加入单点篡改负例；46/46 项 Python 合同随后通过。

这些是本批观察到并修正的具体开发回归。由于没有运行候选或产品宿主，本批没有产生新的日用、installed、registered 或 live-host 产品回归结论。

## 回归证据

| 检查 | Windows PowerShell 5.1 | PowerShell 7 |
| --- | --- | --- |
| fixture journal／replay／typed snapshot／exact removal | 114/114 | 114/114 |
| replay reference model | 16/16 | 16/16 |
| 原 fault matrix | 9/9；24 stages；96 cases | 9/9；24 stages；96 cases |

PS5 与 PS7 的 fixture result SHA-256 均为 `a9a44e449b93313ba1248ab08645bf19e1544c8fee3fdf5a26d1abc823066d45`。本批源码摘要为：

- journal helper：`8360763160873b6252b6253254bfaaedfb717f814cd9b831e34eaf22a8800e1b`
- module：`92ebd2043e2cd987cc4131bcf90d79b59aadfa883c1be56265f79c62bbcf2c1b`
- fixture test：`1c9c48cd7cd990ae770bb415f8fb47a9699eebc9bdf8dd7d7a062114c764dcdd`
- transaction engine：`7e3e565981b8b5a2d695855597dc201ebd863e35809095cd301f97304e3cd68b`
- replay model test：`5559035b60270dc12f08b71cc08e41e4ae09459fcc1a41e305707c351b811daf`

按最终源码重跑的全局基线固定 121 个哈希输入，46/46 项 Python 合同测试通过，并继续保留 5 项真实待办；独立复跑结果为 `.tmp/dual-product/dp1-i-baseline-root-review-a1/baseline.json`，SHA-256 `f6d172759bcd3361d406c6559f7224b0175a3fa53d6d0b054bee4efbfa4b5295`。其中 journal／replay 只按源码和 CI 锚点核对，Python 基线没有执行 PowerShell 夹具，也没有把 pending 提升为通过。

精确临时证据路径、字段与边界见[结构化记录](../testing/dual-product/2026-09-06-dp1-i.json)。`.tmp` 结果不是耐久恢复介质；DP1-H 及更早记录保持各自历史结论，不以本批夹具结果改写。

## 下一工作顺序

1. 先关闭 DP1-H 留下的同一 SID 瞬时 NSIS tree-membership 干扰，把 canonical v2 所需证据迁入耐久内容寻址根，并完成锁内、失败可恢复的 v2→v2 supersession。
2. 在上述先决条件成立后，为真实维护事务增加受限 adapter；让 `Resume` 在独立进程重启后实际执行并验证 rollback／cleanup，同时保持另一产品、默认输入法和非目标状态不变。
3. 增加子进程硬终止、跨进程 journal lock／replay、torn write 以及明确文件系统 flush／目录元数据耐久边界的测试；在没有真实断电证据时继续保持 power-loss durability 为 false。
4. 把 manifest-driven removal 接入受保护的 staged／installed 所有权链，并关闭检查到删除间的并发替换、reparse／hardlink 和提升后身份边界。
5. 只有事务、可信签名和既有硬门均完成且另行交接后，才进入 installed／registered／live-host、必要重启、单装与两种共存顺序验收。

安装器、卸载器与 tagged release 的硬阻断继续保留。当前候选仍未签名、默认禁用、不可交付且未执行；YimeCore local.12、生产 Rime/PIME、默认输入法与用户数据均未触碰。DP1、DP2、DP3、L5 和 L6 均未完成。
