# DP1-H：canonical v2 与 NSIS 已知输入边界

日期：2026-09-06。影响产品仅为独立的 Rime/PIME；YimeCore 是另一独立产品，必须保持不变。本批构建了两个默认禁用、未签名、不可交付的 `x86,x64` 静态候选，执行了固定工具链下的只读归档核对，并把其中 PS7 候选的证据显式封存为 canonical v2 package receipt。安装器、卸载器、签名器和任何产品进程均未运行；没有读取或修改注册表、默认输入法、生产 Rime/PIME、用户正文、设置、学习数据、恢复档案或已安装 YimeCore local.12。

## 本批结论

[`rime-pime-nsis-toolchain-closure.ps1`](../../tools/dual-product/rime-pime-nsis-toolchain-closure.ps1)把本机仓库固定的 NSIS 分发输入扩展为 5 个根、17 个目录和 303 个文件，canonical tree SHA-256 为 `a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352`。v2 toolchain lock SHA-256 为 `01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45`；其中包括 `makensis.exe`、其固定 runtime、实际 include／locale／resource／stub，以及 x86-unicode 插件扫描集。

构建期间持续持有 303 个文件 read/no-delete 租约、17 个 scoped directory 加 2 个 anchor directory identity 租约，以及 lock JSON／sidecar 的 2 个 control 租约。打开、`makensis` 前、编译后和 seal 前的精确树快照一致；已知文件的写入、删除和同 SID 替换均被阻止。因此 `nsis_known_input_file_replacement_closure=true` 与 `nsis_distribution_tree_exact_at_open_and_test=true` 有实际证据。

但这不是完整 NSIS 工具链闭包。Windows 上的目录 identity handle 不冻结子项成员关系：合成负例已经在租约存活期间成功创建并删除一个未列插件。两次离散快照可能看不见这种瞬时成员，因此必须保持：

- `active_same_sid_transient_tree_membership_interference_excluded=false`
- `nsis_non_os_compiler_input_closure=false`
- `full_nsis_toolchain_input_closure=false`

Windows loader DLL、环境、调度及其他 OS 输入也不在本批 `repository-pinned-nsis-distribution-non-os-v1` scope 内。这里的“已知输入文件替换闭包”不得简称为“完整 compiler/toolchain closure”。

## canonical v2

[`rime-pime-package-receipt-v2.ps1`](../../tools/dual-product/rime-pime-package-receipt-v2.ps1)及[显式 finalizer](../../tools/dual-product/finalize-rime-pime-package-receipt-v2.ps1)把下列对象绑定到同一候选身份：

- package plan、175 项复制 stage、166 个持久 payload、9 个 bootstrap 文件；
- 6 个 stage 宏生成的 payload include 及其 receipt；
- 原 canonical v1 的原始摘要、字节数、候选摘要和 package-plan 身份；
- disabled build-result v2 的固定 NSIS tree、租约计数和诚实闭包字段；
- postbuild-result 的外层 181 项、内嵌卸载器 11 项及逐项原始字节来源；
- 仓内 canonical installer 的摘要、长度及 `installer.nsi` 源摘要。

当前 canonical receipt schema 为 `yime-rime-pime-package-build-receipt-v2`，SHA-256 为 `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be`。PS5 与 PS7 的严格 reader 均验证通过。它的状态是 `canonical-static-closure-disabled`，不是 release receipt：`unsigned_disabled_build=true`，而 signing、可信生成卸载器、final payload closure 和 delivery admission 均为 false。

收据绑定的 build／postbuild 文件仍在 `.tmp`，没有嵌入仓内，也没有转存到耐久证据根，因此 `evidence_artifacts_embedded=false`、`evidence_artifacts_durable=false`。严格 reader 会在这些证据消失或变化时失败。v2 发布后，旧 v1 builder 与签名入口按设计拒绝静默降级；真实 preflight 已在创建输出或执行 `makensis` 前拒绝。当前尚未实现显式、同等级的 v2→v2 supersession，所以这是有意的单向保护门，不是可持续发布流程。

## 两套真实静态构建

| 宿主 | build-result SHA-256 | 候选 SHA-256／字节数 | 构建后 v1 receipt SHA-256 | postbuild-result SHA-256 |
| --- | --- | --- | --- | --- |
| Windows PowerShell 5.1 | `c1c91c07b596e00a66bd4f3a56b552e65ce0a1bc3b35da174804de22763935c2` | `4657267f8e0017ad668a91f44b5f7dcb9331b1cce3a08200809b5141aa9e49c3`／41,452,870 | `137b927845ef4789c368ddbd3d42bdff19fd43038cf9b0ffd7389a4a75046437` | `2b018dd88485f020a1b417fc14d5360c1eec98348d405793b14b2ecc5d8f0384` |
| PowerShell 7 | `c1845b1dcb6b2ac49e8d4127d5ea8a6032c56646bcfac7c78da0574f3f7e6a49` | `32a7d66e06284d512675e40495b6e244a23630d2e368ac2cf73ce652e623efe2`／41,456,428 | `d8570876b1fe5208011ce52252b261f37ef263ffce161de44560e63c3a9d1450` | `c1ea171de99485ba6771c5b7e6fd9a1e4ec8a62a1d48ed9d4b5979fffc4d0a01` |

两次构建共同绑定同一 package plan、stage content tree、payload include、NSIS tree 和 `makensis.exe` 摘要；NSIS 输出本身含构建差异，因此不宣称候选逐字节可复现。PS7 行是本次 canonical v2 的候选来源。两个候选都只做静态读取，从未执行。

## 具体回归

1. **DP1-NSIS-MEMBERSHIP-05（本记录时未关闭；后续见 [DP1-K](YIME_DUAL_PRODUCT_DP1_K_NSIS_COMPILER_INTERVAL_2026-09-06.md)）**：目录 identity lease 不能阻止同一 SID 在租约期间创建并删除未列插件；前后 exact snapshot 都可能仍一致。合成回归 `same-sid-transient-unlisted-child-is-not-excluded-by-directory-leases` 固定了该事实。继续把 transient/non-OS/full closure 保持为 false；本记录的后续要求不以放宽门限或把离散快照改名为连续闭包来满足。DP1-K 按本次用户授权的全编译区间检测并拒绝边界关闭此项，不改写本记录原始 receipt 或物理防止结论。
2. **DP1-NSIS-PSMODULE-06（已关闭）**：Windows PowerShell 5.1 中最后导入 toolchain module 会因嵌套 `Import-Module -Force` 使全局 staging 导出消失，真实 builder 在任何候选、canonical 或系统变更前报找不到 `Get-YimePimePayloadFileRecord`。builder 现固定为 toolchain → staging → nsis-stage → staged-build，并由 baseline 锁定顺序；随后 PS5 真实构建通过。
3. **DP1-RECEIPT-PSMODULE-07（已关闭）**：v2 finalizer 导入 receipt module 后不能依赖嵌套模块重新导出 staging helper，首次封存于 canonical 写入前退出。runner 现显式在 receipt module 后重新导入已持租约的 staging module，并加入 PS5／PS7 合成回归；第二次封存成功。

这些是本批观察到的构建／证据链回归。由于候选从未执行，本批没有产生新的日用、已安装或 live-host 产品回归结论。

## 回归证据

- NSIS toolchain closure：PS5／PS7 各 15/15，包括真实最小 `.nsi` 在全部已知输入租约下编译，以及瞬时未列成员不能排除的负例。
- package receipt v2：PS5／PS7 各 26/26；包括字段篡改、重新封存、候选／stage／toolchain 不一致、发布回滚、陈旧 predecessor、无进程启动面和 finalizer staging re-import。
- no-downgrade：PS5／PS7 各 7/7；完整 v1 可升级，v2、未知 schema、六种残缺组合和内容失配均在写入前原字节拒绝。
- staged publication：PS5／PS7 各 12/12；postbuild synthetic：各 50/50。
- 真实 PS5／PS7 disabled build 与静态归档 exact-set 比对均通过；实际安装器、卸载器及签名器执行数为 0。

精确路径、摘要、基线计数和边界见[结构化证据](../testing/dual-product/2026-09-06-dp1-h.json)。DP1-G 及更早记录保持当时结论，不用 v2 结果回写或重标历史证据。

## 下一工作顺序

1. 关闭整个 `makensis` 区间内的瞬时 tree-membership 干扰，并同时明确 Windows loader／环境／调度边界；未取得证据前不提升 full closure。
2. 把 v2 所需证据转入耐久、内容寻址的受控根，并实现锁内、失败可恢复的 v2→v2 supersession；不能删除 v2 或回退到 v1 绕过。
3. 建立持久 prepared／commit 哈希链 journal、flush／独占锁／幂等 replay、隐私安全的合成恢复归档及子进程硬崩溃测试。
4. 用 manifest 驱动的叶到根精确 removal 替换递归删除；意外文件必须拒绝或保留。随后关闭提升后 helper 身份、版本化 side-by-side TSF 根、注册切换及由非提升发起用户令牌启动 Runtime 的边界。
5. 上述条件与可信签名完成并另行交接后，才进入 installed／registered／live-host、必要重启、单装和两种共存顺序验收。

安装器、卸载器与 tagged release 硬阻断继续保留。当前日用 YimeCore local.12 未变，local.13 未安装；生产 Rime/PIME、默认输入法和用户数据未触碰。ARM64 仍须在独立原生目标取得自己的 Runtime、Broker、包装事务及 registered/live 证据。本批不宣称 DP1、DP2、DP3、L5 或 L6 完成。
