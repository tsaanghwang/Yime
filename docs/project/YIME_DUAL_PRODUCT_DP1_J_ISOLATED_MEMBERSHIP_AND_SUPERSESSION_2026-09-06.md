# DP1-J：隔离成员监测与 receipt supersession 协议首批

日期：2026-09-06。影响产品为独立的 Rime/PIME 开发线，但本批只实现并验证两个仓库内隔离夹具：连续 NSIS 目录成员监测，以及 receipt-v2 supersession 的内容寻址／原子 head／journal 协议。YimeCore 是另一独立产品，保持不变。本批没有执行 `makensis`、签名、安装器、卸载器或产品程序，没有访问注册表、默认输入法、生产 Rime/PIME、用户正文／学习数据或已安装 YimeCore local.12。

## 本批结论

[`rime-pime-nsis-membership-monitor-v1.ps1`](../../tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1)以异步 `ReadDirectoryChangesW` 监测全子树成员变化，使用随机完成哨兵、目录卷号／file ID 复核及有序取消清算。隔离测试覆盖同进程与独立同 SID 进程的瞬时文件、目录、嵌套子树及 rename 变化，并验证 overflow、重叠通知记录、异常取消和根目录替换前提会失败关闭。Windows PowerShell 5.1 与 PowerShell 7 各 15/15，结果逐字节一致。

这只证明“监测器可在夹具中发现受保护时间段内的成员变化”。它没有包围真实 `makensis`，也不物理阻止文件变化；因此 `makensis_interval_covered=false`、`active_same_sid_transient_tree_membership_interference_excluded=false`，non-OS/full toolchain closure 继续为 false。真实接线时还必须先把已知 NSIS 树复制到全新的 compiler stage，并让调用者在唯一完成哨兵出现前等待被保护的编译子进程退出。

[`rime-pime-receipt-v2-supersession.ps1`](../../tools/dual-product/rime-pime-receipt-v2-supersession.ps1)在全新的 `.tmp/dual-product/dp1-j-receipt-v2-supersession-*` 夹具内建立内容寻址 object、generation catalog、单一原子 head、独占 lock 和密封哈希链 journal。测试覆盖初次发布、CAS 拒绝、v2→v2 切换、同一进程模块重载 replay、未封存 object／未发布 head temp 修复、短 sidecar 尾部恢复、未决事务阻止后继、全 catalog 重读以及 journal 精确成员检查。两套 PowerShell 各 16/16，结果逐字节一致。

这个 supersession 夹具只用带 v2 schema marker 的合成 JSON；它没有调用实际严格 receipt-v2 reader，没有迁移 DP1-H 的非耐久 evidence，没有修改 canonical receipt，也没有验证跨进程崩溃／replay、真实断电、目录元数据耐久、hardlink 负例、对象物理不可变或并发内容替换排除。故 `canonical_receipt_mutated=false`、`cross_process_crash_or_replay_verified=false`、`directory_metadata_durability_verified=false`。

## 具体开发回归

本批只报告实现和复核中实际出现、现已修复并固定为负例的问题：

1. **DP1-MONITOR-MAXPATH-01（已关闭）**：最初的 overflow 负例使用过长文件名，在 Windows 路径限制处提前失败，未实际覆盖通知缓冲区 overflow。测试改用合法长度的多事件压力输入。
2. **DP1-MONITOR-CANCEL-02（已关闭）**：初版在 `CancelIoEx` 后等待事件便释放 OVERLAPPED 缓冲区，没有调用 `GetOverlappedResult` 完成清算。当前顺序固定为 cancel、wait、取得完成结果、再释放资源。
3. **DP1-MONITOR-ROOT-SHARE-03（已关闭）**：根目录句柄曾允许 delete-share，使根 rename／replacement 可能绕过监测前提。当前根句柄不共享删除，并验证根 identity。
4. **DP1-MONITOR-CLEANUP-04（已关闭）**：`Complete` 曾在清理失败时仍把状态标为 Closed。现在只有全部 native 资源释放后才进入 Closed，失败状态可重试清理。
5. **DP1-MONITOR-BARRIER-05（已关闭）**：完成哨兵的创建状态曾设置过晚，异常路径可能失去线性化边界。现在在哨兵成功创建时立即记录，并要求唯一哨兵。
6. **DP1-MONITOR-PARSER-06（已关闭）**：通知 parser 曾接受重叠 record offset。现在验证对齐、边界和非重叠布局，异常输入失败关闭。
7. **DP1-MONITOR-REPARSE-07（已关闭）**：初版只检查目标目录本身，未完整拒绝父链 reparse。当前逐级核对并限制到 fresh immediate fixture root。
8. **DP1-MONITOR-CLOCK-08（已关闭）**：超时最初依赖可回拨的 wall clock；现在使用单调 `Stopwatch`。
9. **DP1-SUPERSESSION-MODULE-01（已关闭）**：测试按完整 module 路径查询 `Get-Module`，在一套 shell 下得不到预期模块。现按实际加载身份核验固定导出面。
10. **DP1-SUPERSESSION-JSON-02（已关闭）**：PS5／PS7 结果格式最初不同。结果改为稳定压缩 JSON，两套 shell 的结果 SHA-256 一致。
11. **DP1-SUPERSESSION-CATALOG-03（已关闭）**：generation reader 最初只验证 receipt object，没有重读 catalog 中每个 object。当前逐项核对长度和摘要，并加入篡改负例。
12. **DP1-SUPERSESSION-PARTIAL-04（已关闭）**：sidecar、object data 与 head temp 的半写状态最初不能安全恢复。现在只从已绑定 intent 重建明确未封存／未发布材料。
13. **DP1-SUPERSESSION-JOURNAL-05（已关闭）**：journal reader 曾忽略额外目录成员。现在要求 exact membership，任何未列文件或目录均拒绝。
14. **DP1-SUPERSESSION-INTERLEAVE-06（已关闭）**：处于 prepared 或已切 head 未 terminal 的事务最初可被后继越过。现在任何先前未决事务都会阻止新事务。
15. **DP1-SUPERSESSION-SEAL-07（已关闭）**：任意 sidecar mismatch 曾可能被误当成可修复 torn tail。现在只有明确短于规范长度的 sidecar 才作为半写恢复；完整长度但内容错误一律失败关闭。
16. **DP1-BASELINE-ESCAPE-08（已关闭）**：新增 CI 锚点字符串中的 Python 反斜杠转义触发警告；现使用有效的字面量。
17. **DP1-BASELINE-COUNT-09（已关闭）**：新增 7 个来源后，测试仍固定旧 source count。期望已更新为 121 个 contract source path、128 个最终 hash source。
18. **DP1-BASELINE-PROMOTION-10（已关闭）**：最初只替换一处 supersession false 时，基线未拒绝伪造的 true 提升。现扫描全部相关来源并覆盖单点篡改。

由于没有运行候选、产品宿主或用户输入流程，本批没有产生新的 daily-use、installed、registered 或 live-host 产品回归结论。

## 回归证据

| 检查 | Windows PowerShell 5.1 | PowerShell 7 |
| --- | --- | --- |
| 隔离 NSIS membership monitor | 15/15 | 15/15 |
| 隔离 receipt-v2 supersession protocol | 16/16 | 16/16 |
| receipt-v2 严格合同（保留回归） | 26/26 | 26/26 |
| receipt no-downgrade（保留回归） | 7/7 | 7/7 |
| DP1-I journal（保留回归） | 114/114 | 114/114 |
| replay reference model（保留回归） | 16/16 | 16/16 |

membership 两份结果 SHA-256 均为 `4b6da068ea02aeb7cc920c17f6174596e2fb03da73ec3eaeac366074df65463f`；supersession 两份结果 SHA-256 均为 `7b6ab62bb4d4e0cf16b04073e379677079d94916acb89da6ee43c542a37a64f0`。按最终源码生成的全局基线固定 121 个 contract source path、128 个 hash source，49/49 项 Python 合同通过并保留原 5 项真实待办；结果为 `.tmp/dual-product/dp1-j-baseline-root-final-20260906-a1/baseline.json`，SHA-256 `8890332604fa46f630d83a5a178df8c112920fa2f125f20f0118b8bd499e7acf`。

本批新增源码摘要：

- membership helper：`0794976f48e9d4103d1d93327ae5b200f87eab58eaee0b4fa7f8657377c24d82`
- membership module：`2c4204192bbbf313e15eb3e8db4b832f69057c455da045ed97d1e23c794b7a63`
- independent fixture writer：`3bc792ee3ee576423a3fe763ae953204232864c3cc910d46b80b097bd98a38e4`
- membership test：`0b7ef3dbf8604acf0b1839ed878d61c879f19af01550216d5ce6a9b4927f9812`
- supersession helper：`4329b0c0ad43e4305e529445ec4ea4723997ab65173d8ede61c3f53c4d605610`
- supersession module：`72ba89e560995422fc7f062a4f7144ef3f30dd8d3ba6f31a3b422648d9e6ee5e`
- supersession test：`a8186f4edf5fc34e120898ad9ca21d333066089124620cd94c1a44a415efae99`

精确结果路径、边界字段与来源摘要见[结构化记录](../testing/dual-product/2026-09-06-dp1-j.json)。`.tmp` 结果不是耐久恢复介质；DP1-H canonical v2 的 SHA-256 仍为 `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be`，本批没有改写它。

## 下一工作顺序

1. 将已知 NSIS 树复制到全新的 compiler stage，在真实但仍默认禁用的 `makensis` 子进程完整生命周期外层接入 membership monitor、现有文件 lease 和 seal；随后只做静态解包核对，不执行候选。
2. 为内容寻址 evidence root 接入实际严格 receipt-v2 reader，补跨进程 lock／replay、目录 flush／耐久边界、hardlink 与并发替换负例；在此之前不称 durable。
3. 只有上述证据成立后，才在真实 publication lock 内完成 canonical v2→v2 supersession；不得用夹具 head 替换 canonical receipt。
4. 再接入受限真实 transaction adapter，并完成注册收敛、逐维 rollback／cleanup、子进程硬崩溃和 installed exact removal。
5. 另行交接后才进入签名、installed／registered／live-host、必要重启、单装与两种共存顺序验收。

安装器、卸载器与 tagged release 的硬阻断继续保留。当前候选仍未签名、默认禁用、不可交付且未执行；DP1、DP2、DP3、L5 和 L6 均未完成。
