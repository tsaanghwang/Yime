# 双产品 DP1 只读基线与隔离合同

影响面：共存安装合同／两版源码基线。当前已完成首批基线、定向退出、`TargetUserSid`、Rime/PIME 注册所有权／状态接线、纯事务参考模型、全量密封 stage、stage-only NSIS 构建、只读静态归档核对、canonical v2 静态证据绑定，以及 fixture-only journal／replay／类型化合成快照／精确 removal、连续 tree-membership monitor 和 supersession 协议；证据限于源码、构建接线、隔离文件系统、合成快照、纯内存事件及未执行候选的归档字节。**未运行 native probe、真实维护、安装器、卸载器、注册表或真实产品进程**，不是完整 DP1 或 DP2 单装／共存实机验收。

- `contract.json` 固定产品选择、无相互运行依赖、无共享可写状态及此次读取的源码清单。
- `baseline.py` 从真实源码提取 CLSID/Profile、安装和状态根、端点、Run／卸载归属及进程名，交叉校验来源；只对明确列出的生成数据计算哈希。
- `test_baseline.py` 以源码提取结果建立纯内存模型，验证对方缺失、各自资源归属、错误路径／SID、跨产品写入／停进程拒绝以及批次拒绝不部分写入。这个模型是下一步安装器接入的合同，不能证明现有安装器已经执行它。
- `rime-pime-ownership.ps1` 与 `invoke-rime-pime-maintenance.ps1` 是本版独立维护保护：验证已标记的明确根、SID 和精确进程，并把已验证运行树交给定向退出合同；不发全局退出事件、不强杀。
- `test-rime-maintenance.ps1 -OutputRoot <全新 .tmp/dual-product/dp1-rime-maint-* 根>` 覆盖真实 helper 和从卸载源码提取的三个函数分支；进程、SID 和删除全为合成／mock。PS 5.1、PS 7 各 31 项通过，不执行安装／卸载入口。
- `rime-pime-target-user.ps1` 是定义式 SID／一次性关联信封／精确 HKU 路径合同；`invoke-rime-pime-target-user.ps1` 是 NSIS 和开发入口使用的窄 CLI。NSIS 先以非提升引导器捕获发起 SID，再以短时、所有者绑定且验证后删除的关联信封准入同 SID 提升 worker；直接构造 worker 参数没有有效信封时拒绝。
- `test-rime-pime-target-user.ps1 -OutputRoot <全新 .tmp/dual-product/dp1-target-user-* 根>` 只做纯 SID／信封模型和源码接线检查。这里的 Profile API 仍由同 SID 的提升 worker 调用，不是非提升回调；绿灯不能替代 UAC／注册实机验收。
- `transaction-isolation.ps1` 是只定义函数的下一阶段合同：要求发起、提升、维护和普通运行令牌保持同一 SID；注册、Run、卸载项、进程、包根和状态根严格归属所选产品；升级须先完整暂存，失败须还原注册值类型、配置和运行状态，同时保持另一产品与默认输入法快照不变。它尚未接入安装器。
- `test-transaction-isolation.ps1 -OutputRoot <全新 .tmp/dual-product/dp1-transaction-* 根>` 只读取源码并运行早期合成事件序列。它的历史收据把当时已有的 YimeCore 接缝、Rime/PIME 目标 SID 源码链和当时尚缺的注册根所有权／完整事务接线分开记录；当前注册源码状态以 DP1-D 专项收据为准。该测试通过从未表示 DP1 完成。
- `rime-pime-ownership.ps1` 的注册部分和 `PIMERegistrationStatus`／NSIS 接线现提供精确根、架构、目标 SID、系统视图、COM shadow、fresh orphan、Profile／类别闭集与命令失败传播合同。`test-rime-pime-registration-ownership.ps1`、`test-rime-pime-registration-completeness.ps1` 和 `test-rime-pime-native-user-cleanup.ps1` 只使用合成对象、fake provider 或源码扫描；它们不读取真实注册表，也不运行状态工具或安装／卸载入口。
- `rime-pime-transaction-engine.ps1` 和 `test-rime-pime-transaction-faults.ps1` 固定纯内存的 24 阶段、10 个回滚维度以及 96 个 before／after 故障例（两套合成架构状态 × 24 × 2）。原 fault matrix 验证提交边界、完整回滚、逐维回滚失败和非目标摘要不变；`test-rime-pime-transaction-replay-model.ps1` 另固定 no-mutation／rollback／cleanup／noop replay 判定及 mutation 幂等冲突。engine 尚未接入安装器，也不直接做真实文件、注册、进程或崩溃恢复。
- `rime-pime-fixture-transaction-journal.ps1` 与 `.psm1` 只在全新的仓内 `.tmp/dual-product/dp1-i-journal-*` fixture 中建立 prepared／step／commit／terminal 哈希链、独占 lock anchor、case-local recovery material 绑定和 torn-tail 判定。`test-rime-pime-fixture-transaction-journal.ps1` 会实际创建、封存和删除隔离夹具文件；不操作产品文件系统。`Resume` 只删除唯一未封存尾记录并返回 disposition，不执行 rollback／cleanup adapter。模块重载仍在同一进程，类型化 registry JSON 不是真实注册表快照，跨进程 replay／lock、子进程硬崩溃、真实断电／目录耐久及 hash-check→delete 并发替换均未证明。
- `rime-pime-nsis-stage.ps1` 从密封 stage manifest 生成六个分调用点宏；`installer.nsi` 只消费生成 include，不保留仓库相对或递归产品 `File` 输入。`test-rime-pime-nsis-stage.ps1` 在 PS5／PS7 各 20/20，仅运行合成文件夹合同。
- `rime-pime-staged-installer-build.ps1` 与根 `tools/build-rime-pime-installer.ps1` 在导入前锁定构建逻辑、持有输入租约、复核 stage PE，并以互斥且 receipt-sidecar-last 的可恢复提交发布默认禁用候选。真实 `makensis` 会执行；安装器、卸载器和签名 hook 不执行。`test-rime-pime-staged-installer-build.ps1` 当前在 PS5／PS7 各 12/12，并覆盖 v2／未知／残缺 canonical 状态的无降级拒绝。
- `rime-pime-postbuild-extraction.ps1` 固定实际 `7z.exe`／`7z.dll`，逐项从 stdout 取得归档原始字节并在父进程持锁快照上与 stage 核对。`test-rime-pime-postbuild-extraction.ps1` 在 PS5／PS7 各 50/50；真实只读核对每轮检查外层 181 项、内嵌卸载器 11 项，安装器和卸载器均不执行。
- `rime-pime-nsis-toolchain-closure.ps1` 根据仓内 v2 lock 固定本机 NSIS 分发树的 303 个文件／17 个目录，持有 303 个文件读租约、19 个目录 identity 租约和 2 个控制文件租约跨越 `makensis`。它阻止已知文件写入、删除和替换，并在打开与 seal 时验证 exact tree；但 Windows 目录租约不冻结子项成员关系，实测同一 SID 仍可瞬时创建并删除未列插件，所以 non-OS/full toolchain closure 必须保持 false。
- `rime-pime-nsis-membership-monitor-v1.ps1` 与 `.psm1` 是 DP1-J 的 fixture-only 连续目录成员监测协议；独立 writer 负例覆盖同一 SID 瞬时增删。PS5／PS7 各 15/15。DP1-J 当时尚未包围真实 `makensis`；这一历史限制已由下一项 DP1-K 检测并拒绝接线取代，但物理防止、non-OS/full toolchain closure 仍未关闭。
- `rime-pime-nsis-compiler-interval.ps1` 在 fresh compiler stage 中把连续 monitor 包围同步 `makensis` 全区间，并在候选首次读取和 publication 前完成 barrier／post-snapshot。真实最小编译覆盖 clean、瞬时 file／directory／rename／root-file 及 compiler-error；当前只证明检测并拒绝，不证明恶意同 SID 写入被物理排除，也没有刷新完整产品候选或 canonical receipt。
- `rime-pime-package-receipt-v2.ps1` 与显式 finalizer 把一个候选的 v1 predecessor、stage、生成 include、build-result、固定 toolchain 和 postbuild-result 绑定成 canonical v2。`test-rime-pime-package-receipt-v2.ps1` 在 PS5／PS7 各 26/26，`test-rime-pime-receipt-no-downgrade.ps1` 各 7/7。旧 canonical 仍明确 `evidence_artifacts_durable=false`；发布 v2 后旧 v1 builder／签名流程拒绝降级。
- `rime-pime-receipt-v2-store.ps1` 把严格 reader 所需证据按 SHA-256 保留，并提供共享 publication lock 下显式的 v2→v2 receipt-only supersession 与 persistent-intent recovery。该源码接线未自动迁移 actual canonical；硬件断电／目录元数据耐久、installer identity 替换和真实事务 adapter 仍待验收。
- `rime-pime-receipt-v2-supersession.ps1` 与 `.psm1` 是另一套 fixture-only 协议：在 fresh `.tmp` 根中验证内容寻址 object／generation、单一原子 head、CAS、独占 lock、sealed journal 和限定 replay。PS5／PS7 各 16/16。它只使用带 v2 marker 的合成 JSON，没有调用严格 receipt-v2 reader、迁移耐久 evidence 或修改 canonical receipt，也不证明跨进程、断电、目录耐久、hardlink 或并发替换安全。

从仓库根目录运行，输出必须是尚不存在的 `dp1-*` 目录：

```powershell
$dp1RunId = [Guid]::NewGuid().ToString('N')
$dp1Receipt = Join-Path (Get-Location) ".tmp/dual-product/dp1-$dp1RunId/baseline.json"
& 'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B tools/dual-product/baseline.py --output $dp1Receipt
```

该 Python 路径是本机当前配置的捆绑工具链，不是输入法的安装依赖；其他开发机使用已有 Python 3.11+，不依赖 Codex。程序不启动子进程、不执行 Rime、安装或维护命令、不访问系统注册及生产／用户数据。只读取当前仓库中列明的源码和锁定数据，并新建一份 `.tmp` 结果收据；拒绝输出覆盖、越界及 reparse 路径。它不更改默认输入法。

成功收据中的 `source_baseline_passed` 与 `fixture_contract.passed` 仅表示对应检查通过。`known_pending` 来自当前维护源码的实际命中，`dp1_full_implementation_passed=false` 和 `dp2_physical_acceptance_passed=false` 继续保留。纯夹具的间接路径标记和模拟 reparse 属性不补足此前真实 Windows 符号链接负例。

历史结果见 [DP1-B 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_B_2026-09-05.md)：当时固定 26 个来源、23 项基线测试；该收据只代表当时源码，不用当前源码重新标注。自动定向退出和目标 SID 已完成源码接线／合成合同，注册根所有权也已达到源码／合成层；所有安装态验收及完整持久包事务仍待实现。此前 [DP1 首批记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_2026-09-05.md)同样保持历史结果。总体顺序见[双产品开发计划](../../docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，DP1-C 历史审计见[原记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_C_TRANSACTION_AUDIT_2026-09-05.md)，当前收口见 [DP1-D 注册接线与纯事务模型](../../docs/project/YIME_DUAL_PRODUCT_DP1_D_REGISTRATION_TRANSACTION_MODEL_2026-09-06.md)。

按定向退出最终源码重跑的目标 SID 专项批次在 PS 5.1／PS 7 各 24/24：`.tmp/dual-product/dp1-target-user-current-ps5-20260905-a2/result.json`（SHA-256 `921ec50a170355551dbc19bd2909f32a9509f6af7a2d060ed130b1b723eee8a5`）和 `.tmp/dual-product/dp1-target-user-current-ps7-20260905-a2/result.json`（SHA-256 `9e896ec01579827ad18ee86eb1905b37642ec87cd90a7638aff25f04cb7510b5`）。事务合同合成回归各 41/41；全局基线固定 59 个哈希输入、28 项 Python 合同测试通过，见 `.tmp/dual-product/dp1-target-user-current-baseline-20260905-a2/baseline.json`（SHA-256 `499da30aa00401da9cb9d6906a4a5ca9683942658b4807d7cbc9904acef5f616`）。收据均明确 `dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`；未执行提升、注册、安装、恢复、真实停进程或读取用户数据。

该批次确认 Rime/PIME 源码已把发起 SID 贯穿 NSIS／提升 worker 和开发维护入口，并把用户清理限定到明确的 `HKU\<TargetUserSid>`。DP1-D 又固定了注册根、读回和事务状态机的源码／合成合同，但仍须在获准隔离目标验证真实 UAC、一次性信封、Profile API、注册收敛、其他 SID 不变、完整暂存、持久回滚／崩溃重放及 Runtime readiness。单装、两种共存顺序、升级／卸载／恢复／重启和 ARM64 原生目标均须另行授权执行；ARM64 当前只有交叉构建／接线及合成状态。

DP1-D 纯事务模型的 PS 5.1／PS 7 收据各为 9／9，固定 24 阶段、10 维和 96 个故障例；精确路径与哈希见 [结构化记录](../../docs/testing/dual-product/2026-09-06-dp1-d.json)。完整事务、persistent rollback／crash replay、registered/live host 和 legacy migration 都仍是 pending。

DP1-E 又把 Rime/PIME 的签名、验签、NSIS 构建、receipt、manifest 和 StaticOnly smoke 绑定到同一密封 package plan；当前 plan 只接受 `x86,x64`，且其 `closure_scope=declared-packaged-product-pe-inputs-only-not-installed-payload` 只代表声明的产品 PE 构建输入，不是完整安装 payload。`rime-pime-payload-closure.ps1` 的闭树、特殊卸载器、reparse／hardlink／ADS 和二次扫描拒绝目前只在隔离文件夹夹具上通过，尚未接入实际 staged／installed tree。

安装器与卸载器在各自 `.onInit` 第一项及 Section 入口继续无条件中止；tagged release 也在构包前阻断。任何 unsigned disabled package 都不可交付或运行。ARM64 仅有交叉构建和显式成对静态 PE 验证，没有进入当前 package plan，也没有 ARM64 包、原生注册或宿主证据。build manifest schema 3 先要求环境提交与当前 `HEAD` 一致；当前 dirty tree 上只可写 `sourceIdentity.kind=working-tree` 且 `commitIsCompleteSourceIdentity=false`，其中的 commit 不是完整源码身份。`signedRelease` 还必须与受保护流程中独立 Authenticode 验签的成功证据配对，不能由 manifest 单独证明。

DP1-E 的准确证据边界、PS 5.1／PS 7 收据和剩余阻塞见 [构建输入闭集记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_E_BUILD_INPUT_CLOSURE_2026-09-06.md)及[结构化索引](../../docs/testing/dual-product/2026-09-06-dp1-e.json)。当前已安装日用 YimeCore local.12 未变，local.13 未安装；DP1、DP2、DP3、L5、L6 均未完成。

DP1-F 新增 `rime-pime-package-staging.ps1`、`test-rime-pime-package-staging.ps1` 和 `run-rime-pime-package-staging.ps1`。它们把完整复制输入封成显式 spec，在全新 `.tmp` 树中复制 166 个持久安装文件和 9 个 bootstrap helper，并分离跨复制稳定的 content digest 与本机 file-ID observation；PS 5.1／PS 7 各 21/21，真实两棵 stage 的 spec、manifest 和 content digest 一致。`Uninstall.exe` 在这一阶段必须缺席，NSIS 仍未读取 stage，故它是“生成特殊文件前”的前置闭包，不是最终 payload、安装或签名通过。具体结果及接下来移除 `File /r`、静态解包比较和可信 uninstaller 的顺序见 [DP1-F 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_F_PREPACKAGE_STAGING_2026-09-06.md)与[结构化证据](../../docs/testing/dual-product/2026-09-06-dp1-f.json)。

DP1-G 已完成 DP1-F 指定的下一层接线：当前 175 个复制输入生成 6 个宏／176 个显式 `File` 引用，PS5／PS7 真实禁用构建均在 200 个 prebuild 输入租约及 20 个唯一 PE／22 个路径绑定复核下通过；随后用固定并持锁的 `7z.exe`／`7z.dll` 对 181 个外层成员和 11 个内嵌卸载器成员逐项读取原始字节，与 stage exact-set／hash 核对。生成卸载器目前只通过静态成员核对，仍为未签名、不可信、不可交付；builder 尚未自动调用 postbuild，canonical receipt 尚未绑定其证据，完整 compiler-input 闭包和持久事务未完成。结果见 [DP1-G 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_G_STAGE_ONLY_NSIS_2026-09-06.md)与[结构化证据](../../docs/testing/dual-product/2026-09-06-dp1-g.json)。DP1-F 的 21/21 保持历史原值；当前 staging 加强版另在 PS5／PS7 各 31/31。

DP1-H 已在 PS5／PS7 真实禁用构建中固定 303 个已知 NSIS 文件和 17 个目录，并把 PS7 候选、stage、include、build-result 与静态 postbuild-result 发布为 canonical v2 receipt。严格 reader 在两套 shell 均通过；安装器、卸载器与签名器未执行。该收据不是 release receipt：生成卸载器不可信，完整 toolchain closure、证据耐久性、v2→v2 supersession、持久事务及 installed/live 均为 false／pending。目录 identity lease 不能阻止瞬时新增再删除未列插件是本批保留的具体回归；另有两处 PowerShell 模块导入顺序回归已修复并加入合同测试。当前全局基线固定 117 个哈希输入，42/42 项 Python 合同通过并保留 5 项真实待办。结果见 [DP1-H 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_H_CANONICAL_V2_NSIS_INPUT_BOUNDARY_2026-09-06.md)与[结构化证据](../../docs/testing/dual-product/2026-09-06-dp1-h.json)。

DP1-I 阶段曾在隔离夹具层固定持久 hash-chain journal、幂等 replay 判定、类型化合成 registry snapshot 和 manifest-driven leaf-first exact removal。PS5／PS7 journal 各 114/114，结果 SHA-256 均为 `a9a44e449b93313ba1248ab08645bf19e1544c8fee3fdf5a26d1abc823066d45`；replay model 各 16/16，原 fault matrix 各 9/9、24 stages／96 cases。当时全局基线固定 121 个哈希输入，46/46 项 Python 合同通过，5 项真实待办保持。实现过程中修正并锁定日期自动转换、PS5 路径 API、generic list 参数、context 伪造、跨 case 材料绑定、operation ID、低层导出、静态扫描／结果 schema，以及基线只验证单一 `Flush(true)` 的负例盲点。准确历史边界见 [DP1-I 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_I_FIXTURE_TRANSACTION_JOURNAL_2026-09-06.md)与[结构化证据](../../docs/testing/dual-product/2026-09-06-dp1-i.json)。其未接入 engine／installer、且 DP1-H 尚待处理的描述保留为当时事实；后续状态由 DP1-H 至 DP1-L 记录更新。

DP1-J 首批把连续 NSIS membership monitor 和 receipt-v2 supersession protocol 固定在隔离夹具层：PS5／PS7 分别为 15/15 和 16/16；当时全局基线固定 121 个 contract source path、128 个 hash source，49/49 项 Python 合同通过。准确历史边界见 [DP1-J 记录](../../docs/project/YIME_DUAL_PRODUCT_DP1_J_ISOLATED_MEMBERSHIP_AND_SUPERSESSION_2026-09-06.md)与[结构化证据](../../docs/testing/dual-product/2026-09-06-dp1-j.json)。其“尚未包围真实 makensis／尚未接入严格 reader”是当时结论，不代表当前源码状态。

DP1-K 已把 fresh compiler stage 和真实最小 `makensis` 全区间监测接入 builder；DP1-L 又接入严格 reader 的内容寻址证据保留及 receipt-only v2→v2 supersession／恢复 API。当前 contract source path 为 125 个、hash source 为 132 个，Python 合同 51/51；actual canonical 未迁移，完整产品构包未刷新，interval 尚未成为新 canonical receipt 的强制语义字段。断电／目录耐久、恶意同 SID 并发替换和真实 transaction adapter 均待办。安装／卸载、tagged release、installed／registered／live-host 硬门不变，DP1、DP2、DP3、L5、L6 均未完成。
