# Yime 双独立产品开发计划

2026-09-07 DP1-N 增量：[isolated installer＋receipt identity transaction](YIME_DUAL_PRODUCT_DP1_N_INSTALLER_RECEIPT_TRANSACTION_2026-09-07.md) 已在 fresh `.tmp` case-local repository 中固定联合身份替换合同：新 installer 先形成 deterministic durable stage，durable intent 之后只 roll-forward；四个允许的公开状态／瞬态覆盖 stage、物理 installer、receipt-first mixed pair 和 new canonical pair，所有 ownership move 均用 flags=`8` no-replace。旧 installer 保留，successor 必须通过 strict reader 并携带当前 membership-interval evidence。此增量没有迁移 actual canonical、刷新完整构包或接入真实安装事务 adapter，也不证明硬件断电、目录 metadata durability 或恶意同 SID 物理防止；两版同时可装、各自独立、互不依赖的产品关系不变。

2026-09-06 DP1-M 增量：[build evidence membership-interval admission](YIME_DUAL_PRODUCT_DP1_M_BUILD_EVIDENCE_ADMISSION_2026-09-06.md) 已把 DP1-K 区间对象、fresh compiler stage 租约和 16 项执行源码闭集固定为新 build evidence／receipt preparation 的强制语义。新 schema 名故意不匹配旧版开放的 `result-vN` 正则，使旧工具失败关闭；历史 build-result-v2 仅保留严格读取及同收据 retention-only 转换。Publish 与 Resume 均拒绝改变过的 legacy successor。actual canonical、installer identity 和产品安装态均未改变；完整构包、原子 installer＋receipt 迁移、断电／目录耐久及真实事务 adapter 仍待完成，不据此提升 DP1 或产品验收结论。

2026-09-06 DP1-L 增量：[retained receipt publication](YIME_DUAL_PRODUCT_DP1_L_RETAINED_RECEIPT_PUBLICATION_2026-09-06.md) 已实现严格 v2 reader 的内容寻址证据保留，以及共享 publication lock 内的 v2→v2 receipt-only supersession／持久 intent 恢复 API。下文 DP1-J／K 中“尚未接入严格 reader／canonical supersession”的实现状态由此更新；实际 canonical receipt 迁移、硬件断电／目录耐久验收、安装器身份替换和真实事务 adapter 仍待完成，不据此提升 DP1 或产品验收结论。

决策日期：2026-09-05。用户已批准按本计划调整开发过程，并明确：“共存是指两个输入法可以同时安装，各自独立，互不依赖。”本次批准开发方向和工作顺序，不等于批准改动当前生产安装、默认输入法或用户数据，也不代表新增验收已经通过。

本文是当前双产品开发过程入口；[本机实施计划](YIMECORE_LOCAL_PRODUCT_IMPLEMENTATION_PLAN.md)继续管理 YimeCore L1–L6，[发布保留方案](YIMECORE_INDEPENDENT_RELEASE_RETENTION_PLAN.md)管理独立发布、备份及回退。旧“替换／退役”路线中的阶段性退出预期由本决策替代，历史证据和回退载荷不删除、不改判。

## 1. 产品关系：可同时安装，但没有相互依赖

向用户提供三个最终安装选择：只装 Rime/PIME 版、只装 YimeCore 自研版、同时安装两版。它们是两个完整输入法产品，不是一个输入法中的双内核开关。

| 边界 | Rime/PIME 版 | YimeCore 自研版 | 必须保持的关系 |
| --- | --- | --- | --- |
| 输入运行链 | 本版宿主、中层与 Rime/PIME 组件 | 本版 TSF、Runtime、Broker、YimeCore 及静态数据 | 对方未安装、未运行或已卸载时，本版仍可工作；不跨产品调用或自动回退 |
| 注册与运行资源 | 本版产品身份、注册、端点、自启动和进程 | 本版产品身份、注册、端点、自启动和进程 | 分别归属；不能靠另一版启动、注册或修复自己 |
| 安装和维护 | 本版自包含包、升级、卸载和恢复入口 | 本版自包含包、升级、卸载和恢复入口 | 不要求安装对方；维护一版不得停止、升级、覆盖或卸载另一版 |
| 可写数据 | 本版设置、学习、用户词库、日志及备份 | 本版设置、学习、用户词库、日志及备份 | 分开保存、独立读写；不共享学习文件，不自动迁移或同步 |
| 版本与发布 | 独立候选包、来源清单和验收记录 | 独立候选包、来源清单和验收记录 | 不要求版本号相同、同步升级或绑定发布 |

“共存”不要求两版同时处理同一次输入。用户在应用中自行选择一个已安装的输入法；安装器和测试不自动替用户修改默认输入法。产品列表、诊断及帮助最终须能清楚区分两版，但本次不改现有名称、GUID 或安装路径；涉及身份或显示变更仍须先审查迁移和精确宿主回归。

两版可以各自使用正常的 Windows 系统能力及各自声明的依赖；“互不依赖”禁止的是产品之间的安装、运行、维护和数据依赖，不是要求重复实现操作系统。Rime/PIME 版使用自己的 Rime/PIME 组件，与自研版完全脱离 Rime/PIME 运行并不矛盾。

历史封存的 YimeCore 旧 CLSID/Profile 不是 Rime/PIME 版，也不是第三条恢复开发的产品线；继续只读保护，不执行或重新标记其旧载荷。

## 2. 开发分工与共享边界

- YimeCore 是主要开发线：继续当前语流音变接入、受影响宿主复验、L5 最终日用确认及 L6 封存。不因双产品方向重做已通过的核心研究或把所有旧门禁从头执行。
- Rime/PIME 是独立可选、持续维护的产品线：固定可复现基线，维护安装可用性，处理具体缺陷、安全问题及必要的共同规则适配。不是默认等待退役的临时回退资产，也不要求与自研版等量、同期开发全部新功能。
- 每项开发任务先标明“共同源／Rime/PIME 版／YimeCore 版／共存安装”影响面，再列出受影响产品的构建和回归出口。单版功能未实施不伪称另一版已支持；一个产品通过不代替另一个产品验收。
- 可共享仓库内规范词典、音节编码规则、唯一布局源、离线生成器和无私密文本的合成测试规格。仍遵守独立外部数据边界；不得从另一 Git 仓库或另一版的安装目录获取隐式构包输入。
- 共享发生在源码、离线生成及测试规格层。每个安装包必须带齐自己的运行所需产物，固定自身来源与哈希；不得依靠另一版已部署的词典、DLL、工具或可写目录。共享维护器源码也必须随各包完整交付，不能变成需先安装另一版的共享运行服务。
- 规范读音与音元编码仍是共同上游，不能反向以 Rime 生成词典定义自研内核语义。语流音变按[既定规则计划](MANDARIN_CONNECTED_SPEECH_PLAN.md)准入，不扩大规则、改写规范读音或增加别名长度。

## 3. 验证与对照分开

YimeCore 的包依赖审计、核心／Broker／TSF 回归和独立运行验收必须能在没有 Rime/PIME 产品的环境完成。Rime/PIME 版相应验收也不能要求安装或启动 YimeCore。

开发排查时可以在明确选择的隔离环境中对照 Rime/PIME：固定源码／包／数据版本、三模式及相关设置，使用同一合成样本，分别记录结果。差异只说明行为不同；只有违反已确认契约或出现有证据的回归才判缺陷。对照不是自研输入运行的依赖，也不是要求两版候选排序完全一致的通用判据。

“可选对照”不取消受影响产品的必需回归：例如共同语流别名或 Rime 适配发生变化时，既有三模式真实 Rime 回归要求继续有效，在隔离 Rime 测试链中执行；它证明 Rime 产物兼容性，不证明 YimeCore 的无 Rime 运行或安装宿主已经通过。只修改自研实现且没有影响共同规则／Rime 产物时，不把额外 Rime 行为对照设为普遍前置条件。

人工日用仍采用隐私安全流程：只记录产品／包身份、模式、页号／序号、候选数、操作类别、耗时区间、通过／失败及脱敏复现步骤；不读取或记录用户正文、真实编码、候选文本、学习内容或私人观察文件。合成夹具须明确标识，不能伪称真实日用。对照操作也不授权访问生产 Rime/PIME 用户数据。

## 4. 调整后的工作顺序

| 阶段 | 本阶段工作与交付 | 验收出口／当前状态 |
| --- | --- | --- |
| DP0 决策与契约 | 明确两版关系、开发优先级、数据／安装所有权和验证边界，同步开发入口 | 本次完成文档调整；不声称程序已经实现全部契约 |
| DP1 双产品基线与隔离夹具 | 从当前源码核对两版身份、进程、注册、目录、构包输入及卸载所有权；固定各自来源清单；区分独立发布与旧 E7 可选跨产品切换证据；补“另一版不存在”与跨产品写入拒绝的隔离合同测试 | [DP1-J 历史记录](YIME_DUAL_PRODUCT_DP1_J_ISOLATED_MEMBERSHIP_AND_SUPERSESSION_2026-09-06.md)固定了两套隔离协议；[DP1-K](YIME_DUAL_PRODUCT_DP1_K_NSIS_COMPILER_INTERVAL_2026-09-06.md)已接入 fresh compiler stage 全编译区间检测；[DP1-L](YIME_DUAL_PRODUCT_DP1_L_RETAINED_RECEIPT_PUBLICATION_2026-09-06.md)已接入严格 reader 的内容寻址 evidence 和 receipt-only supersession／恢复 API；[DP1-M](YIME_DUAL_PRODUCT_DP1_M_BUILD_EVIDENCE_ADMISSION_2026-09-06.md)已将 interval 固定为新 build／receipt admission 的强制语义；[DP1-N](YIME_DUAL_PRODUCT_DP1_N_INSTALLER_RECEIPT_TRANSACTION_2026-09-07.md)又固定 `.tmp` 隔离的 installer＋receipt identity replacement 与恢复合同。actual canonical 尚未迁移，完整构包、断电／目录耐久、恶意同 SID 并发替换及真实事务 adapter 均未通过，因此 DP1 未完成 |
| DP2 独立维护与共存验收 | 分别构建新候选包；在明确获准的隔离环境覆盖下表的单装、两种顺序、升级、卸载、恢复和失败回退 | 待执行；任何生产安装操作须另行明确授权 |
| DP3 三选一安装入口 | 在各自安装器通过后增加薄选择入口，只调用所选产品的独立安装器；明确显示每版状态和结果 | 待实现；不复制安装事务，不强制装配套产品；两版选择中一版失败不破坏已安装的另一版 |
| DP4 分别封存与维护 | 每版固定包、源码、数据、功能范围、架构／宿主覆盖与恢复介质；按受影响产品维护 | 各自门禁通过才分别发布；默认切换、公开发行或退役均不由本计划自动批准 |

近期实施顺序：YimeCore 当前源码已同步重构未安装的 local.13；DP1-D 固定注册所有权和纯内存事务要求，DP1-E 封存声明 PE 输入，DP1-F 建立全量复制 stage，DP1-G 让真实 NSIS 只消费该 stage并完成静态归档核对，DP1-H 又把 stage、include、禁用构建和 postbuild 写入 canonical v2 receipt，并固定 303 个已知 NSIS 输入。DP1-I 在完全隔离的文件系统夹具中固定了 journal、replay 判定、类型化合成快照和精确 removal 语义；DP1-J 首批又固定连续 tree-membership 检测和内容寻址／原子 head／journal supersession 协议。DP1-K 已完成 fresh compiler stage 与全 makensis 区间检测接线；DP1-L 已把严格 receipt-v2 reader、内容寻址 evidence、跨进程 replay／lock 接入 receipt-only supersession；DP1-M 又保留历史 build-result-v2 读取并把 tagged membership interval 固定为新 preparation 和 changed-supersession 的强制语义；DP1-N 已固定 `.tmp` 隔离的 installer＋receipt identity replacement、pre-intent durable stage 和 intent 后 roll-forward 合同。下一项是在不削弱当前 canonical-v2 无降级保护的隔离路径完成新候选构包和静态复核，再另行审查 actual canonical 迁移，并做目录／断电耐久验收。只有这些先决条件成立后才接入真实 adapter，并补注册收敛、逐维回滚、并发安全 removal 和非提升 Runtime readiness。在另行交接前，安装／卸载及 tagged-release 硬阻断不得解除。之后才按候选包变更范围安排 registered/live host、必要重启和 legacy migration。取得用户 L5 最终确认后才完成 L6；DP1、DP2、DP3 均不能借当前 local.12、静态构包或合成协议提前记为完成。

2026-09-06 历史增量：[DP1-J 隔离成员监测与 receipt supersession 协议首批](YIME_DUAL_PRODUCT_DP1_J_ISOLATED_MEMBERSHIP_AND_SUPERSESSION_2026-09-06.md)完成。membership monitor 在 PS5／PS7 各 15/15，能检测同进程和独立同 SID 进程的瞬时文件／目录／rename 变化并对 overflow、异常取消和根替换前提失败关闭；supersession fixture 各 16/16，覆盖内容寻址 generation、单一原子 head、CAS、密封 journal、未决事务互斥及限定半写恢复。两者均只操作 fresh `.tmp` 夹具。该段“未包围真实 makensis／未使用严格 reader”保留为当时事实，后续状态分别由 DP1-K／DP1-L 更新；未触碰安装器、产品进程、真实注册表、用户数据、默认输入法、生产 Rime/PIME 或 local.12，全部硬阻断保持。

2026-09-06 当前增量：[DP1-I 隔离夹具事务 journal 与幂等重放模型](YIME_DUAL_PRODUCT_DP1_I_FIXTURE_TRANSACTION_JOURNAL_2026-09-06.md)完成。PS5／PS7 的 journal 夹具各 114/114，结果摘要一致；replay 纯模型各 16/16，原 fault matrix 各 9/9、24 stages／96 cases 保持。测试实际创建、封存和删除的仅为当前仓库新建 `.tmp` 夹具；类型化 registry JSON 不是注册表导出，模块重载不是进程崩溃，`Resume` 只清理唯一 torn tail 并返回 disposition，不执行 rollback／cleanup adapter。子进程硬崩溃、跨进程 replay／lock、真实断电／目录耐久以及 hash-check→delete 并发替换均未排除。未触碰 installer／uninstaller、真实注册表、产品进程、用户数据、默认输入法、生产 Rime/PIME 或 local.12，也未接入 engine／installer。DP1-H 的瞬时 NSIS tree-membership、耐久 evidence 和 v2→v2 supersession 仍须先处理；全部硬阻断保持，DP1、DP2、DP3、L5、L6 均未完成。

2026-09-06 当前增量：[DP1-H canonical v2 与 NSIS 已知输入边界](YIME_DUAL_PRODUCT_DP1_H_CANONICAL_V2_NSIS_INPUT_BOUNDARY_2026-09-06.md)完成。PS5／PS7 均用同一个 303 文件／17 目录的固定 NSIS 树完成禁用构建与静态归档核对；canonical v2 receipt 严格绑定 PS7 候选、stage、include、v1 predecessor、build-result 和 postbuild-result。已知文件替换闭包成立，但实测目录 identity lease 不冻结子项成员关系，未列插件可在租约期间创建再删除，所以 `active_same_sid_transient_tree_membership_interference_excluded=false`、non-OS/full closure=false。收据依赖 `.tmp` 中的非耐久证据且尚无 v2→v2 supersession；生成卸载器仍不可信，候选未签名、未执行、不可交付。日用 local.12、生产 Rime/PIME、默认输入法和用户数据均未触碰。

2026-09-06 当前增量：[DP1-G 密封 stage 驱动 NSIS 与逐项静态归档核对](YIME_DUAL_PRODUCT_DP1_G_STAGE_ONLY_NSIS_2026-09-06.md)完成。当前 175 个复制输入生成 6 个宏／176 个显式 `File` 引用，`installer.nsi` 不再直接读取仓库相对载荷或 `File /r`。PS5／PS7 真实构建都在 200 个 prebuild 输入租约和 20 个唯一 PE／22 个路径绑定复核下通过；候选默认禁用、未签名、不可交付且从未执行。外层 181 项与内嵌卸载器 11 项均由固定 `7z.exe`／`7z.dll` 逐项原始字节读取并与 stage exact-set 比对。当前只证明生成卸载器是静态归档成员；其可信发布身份、完整 NSIS toolchain、canonical v2 receipt、持久事务和 installed/live 证据仍待办。日用 local.12 未变，local.13 未安装；DP1、DP2、DP3、L5、L6 均未完成。

2026-09-06 当前进度：[DP1-E 构建输入闭包](YIME_DUAL_PRODUCT_DP1_E_BUILD_INPUT_CLOSURE_2026-09-06.md)完成源码、构建接线、编译产物静态分析、隔离文件系统夹具和纯内存事务层收口。当前 Rime/PIME 构包 profile 精确为 `x86,x64`，20 个声明产品 PE 输入已封存；ARM64 仅有单独交叉构建和显式静态验证，不在本安装包中，也不是原生运行证据。schema 3 manifest 将本地脏树明确标为 `working-tree`，并拒绝环境提交与当前 `HEAD` 不一致；因此 commit 字段不被误写成完整源码身份。未签名安装器不可交付，安装／卸载入口保持最早硬阻断且从未运行；完整非 PE 载荷、不可变 staging、打包后解包比对、持久事务及 installed/live 验证仍待办。日用 local.12 未变，local.13 未安装；DP1、DP2／DP3、L5、L6 均未完成。

2026-09-06 当前增量：[DP1-F 全量构包前复制暂存](YIME_DUAL_PRODUCT_DP1_F_PREPACKAGE_STAGING_2026-09-06.md)把当前 166 个持久安装源和 9 个 bootstrap helper 变成显式、密封的 source→destination 映射；PS 5.1／PS 7 各 21/21，两个真实隔离 stage 的 spec、manifest 与 content-tree digest 完全一致。本批关闭了 PS5 参数默认路径和跨 shell JSON 非确定性回归，并发现／限定了构建副本传播 `Zone.Identifier` 的问题。此 stage 明确停在可信 `Uninstall.exe` 生成之前，当前 NSIS 尚未消费它，完整根构建也未因这一增量重跑；因此 `File /r`、构包后解包比对、签名／uninstaller、持久事务与 installed/live gate 仍待办，所有硬阻断保持。

2026-09-06 历史阶段：[DP1-D 注册接线与纯事务模型](YIME_DUAL_PRODUCT_DP1_D_REGISTRATION_TRANSACTION_MODEL_2026-09-06.md)完成文档收口。注册完整性、注册根归属、fresh orphan、目标用户清理和架构互斥只取得源码／构建接线及合成快照证据；纯事务模型在 `x64,x86` 与 `arm64,x86` 两套合成状态上覆盖 24 阶段、10 个回滚维度和 96 个 before／after 故障例。没有执行 native probe、安装／卸载、真实注册表、提升或真实进程。ARM64 仅有交叉构建／接线和合成状态，不是原生证据；完整事务、持久回滚／崩溃重放、Runtime readiness、registered/live host 和 legacy migration 仍待办。

2026-09-05 23:58 当前进度：[DP1-C 注册、SID 与事务隔离审计](YIME_DUAL_PRODUCT_DP1_C_TRANSACTION_AUDIT_2026-09-05.md)已把 Rime/PIME 定向退出及目标用户链接入源码。stdin EOF 未关闭已跟踪服务的红灯已修复；临时 Rime 用户目录中 checked `RimeDestroySession` 后不调用 `Finalize` 的跨进程学习保持连续两次通过。目标 SID 合同 PS5／PS7 各 24／24、定向退出各 17／17、事务合成各 41／41；当前基线 59 个来源、28／28，仍明确保留 3 项待办。NSIS 仅构建未运行。安装态进程树、真实 UAC／注册、完整事务和 DP2 均未通过。

2026-09-05 23:55 当前进度：[SR4-B4 当前源码同步重构](YIMECORE_SPEECH_SR4B4_SOURCE_SYNC_2026-09-05.md)已完成。由于 DP1 修复改动了 Stage5C 锁定的共享源码集合，B3 包转为历史证据；新鲜准入仍为 498 PASS／3 SKIP，构包仍为 478 PASS／4 SKIP、两版 PowerShell 各 38 项和私有 Runtime 七阶段。当前未安装 local.13 package ID 为 `yimecore-local-0.1.0-local.13-dbfab0b45dd2`；日用 local.12 未变。

2026-09-05 23:02 过程记录：[SR4-B3 维护配置闭合与 local.13 重构包](YIMECORE_SPEECH_SR4B3_MAINTENANCE_2026-09-05.md)修复了 `learning.json` 未进入维护新鲜度／恢复映射的具体缺口，并由红灯 PS5／PS7 各 5 项失败闭合到各 12／12；第一次重构又由独立固定来源清单拒绝，补齐清单守卫后新鲜准入 498 PASS／3 SKIP、重构包 478 PASS／4 SKIP、两版 PowerShell 各 38 项和私有 Runtime 七阶段通过。该时点未安装 package ID `yimecore-local-0.1.0-local.13-6fa24332928d` 已由 B4 当前源码包取代，保留为历史证据；日用 local.12 未变。

2026-09-05 22:24 当前进度：[SR4-B2 默认关闭的正常候选包与私有进程验证](YIMECORE_SPEECH_SR4B_PACKAGE_2026-09-05.md)已完成：local.13 新构包 85 文件、477 个定向 Go 节点通过／4 SKIP、PS5／PS7 各 26 项，x64／x86 直接 TSF 与仓外正常 Runtime 七阶段通过。没有安装，日用仍是 local.12。下一步先补维护配置覆盖、定向退出及完整注册／SID／事务门槛，再交接明确获准的安装／真实宿主及必要重启；不提前标记 DP1 全部完成、DP2／DP3、SR4、L5 最终确认或 L6。两版可以同时安装、各自独立、互不依赖的契约不变。

2026-09-05 21:23 过程记录：[SR4-B1 正常产品接口／Runtime／显式设置](YIMECORE_SPEECH_SR4B_SOURCE_2026-09-05.md)源码接入及隔离回归完成，641 个命名 Go 节点通过、2 个真实符号链接权限 SKIP，三个正常程序仅编译。补修了新接入别名把表层读音显示为标准拼音的源码接缝，不改变规范读音或规则。DP1-B 维护保护同步完成。下一批为 SR4-B2 精确资源导出、可选包描述／审计和正常 Runtime 私有进程／维护门槛；DP1 继续定向退出、完整注册／SID 与事务验证，之后才进入获准的安装／宿主和 DP2，不提前组合三选一安装器。

2026-09-05 20:03 过程记录：[SR4-A 自包含试验包与仓外运行](YIMECORE_SPEECH_SR4_PACKAGE_2026-09-05.md)完成，69 个固定载荷、默认关闭、不可安装；仓外私有 Broker 的七阶段验证通过。DP1 首批同步完成。该时点证据保留，不因 B1 源码更新而重新标记其工具或结果。

最新安装证据仍是 `local.12`；[24 条 Stage5C 准入与隔离源码接入](YIMECORE_SPEECH_ADMISSION_ISOLATED_SOURCE_2026-09-05.md)及 SR4 各源码／构包批次均未构成新的安装／产品 UI 人工验收／实机通过证据。B1 历史批次有 2 项真实符号链接权限 SKIP，当前 B4 构包收据为 4 项；这些负例均仍待补证据，不因方向调整或其他检查通过改判。

## 5. 共存验收矩阵（待执行，不是通过记录）

以下每项均固定测试产品身份、包 manifest、测试账户／目标、隔离数据根和前后保护快照。真正的“单装”证据要求环境中没有另一版可用载荷、注册或启动入口；仅停止另一版进程不足以证明独立。不得为此卸载当前开发机的生产输入法。

| 场景 | 必须取得的证据 |
| --- | --- |
| 仅 Rime/PIME 版；仅 YimeCore 版 | 分别首装、启动、三模式输入、设置和学习跨本版重启保持；构包和运行均不寻找另一版 |
| 先 Rime/PIME 后 YimeCore；反向顺序 | 两个独立可辨认的产品条目，各自能在测试宿主中选用；先装产品和既有默认输入法未被后装产品改写 |
| 共存时分别升级，包括失败回退 | 升级目标可恢复；非目标版进程、注册、文件、设置及学习不受写入／停止影响 |
| 共存时分别卸载，随后重装 | 只移除所选产品拥有的资源，默认保留其用户数据；留下的另一版可独立输入，保留数据重装可恢复本版状态 |
| 分别备份／恢复与重启 | 只操作目标版状态及恢复介质；另一版不被覆盖、清除或作为恢复前提；按各自启动策略核对真实 PID／映像及新开机证据 |
| 只选一版；选择两版；取消／部分失败 | 薄入口不调用未选产品的安装事务；每版结果独立准确，无自动默认切换或跨产品清理 |

测试只有模拟事务／源码／跨编译时，必须按其实际级别报告；不能计作真实安装、注册宿主或物理机器通过。涉及系统共有语言设置的合法变更必须精确限定、保持非目标产品与用户默认选择，不能靠整棵覆盖完成。

目标范围继续遵守 [development-scope.json](../../tools/yimecore/development-scope.json) 与 [开发主机范围](YIMECORE_DEVELOPMENT_HOST_SCOPE.md)：MYCOMPUTER x64／WOW64 x86、已批准的主流 x86-64 和 Windows ARM64 独立试验；x86 是 WOW64 应用表面，不是单独的 32 位 Windows 产品线。每个产品／架构需要自己的证据，不能继承另一版或跨编译结果。未列目标、云机器采购和硬件配额不由本计划新增授权。

## 6. 每次任务的最小记录

开发任务和交接记录均注明：影响哪一版或共同源；该版候选包／源码身份；另一版保护边界；完成的测试级别；尚需的安装、宿主、重启或用户确认。只记录具体回归与所需证据，不把正常行为差异、自动化限制或未执行的检查写成产品缺陷。

Rime/PIME 版不设默认退役日期；用户选择只用一版不等于停止另一版维护。未来若要停止维护、删除兼容代码或卸载／清除数据，须针对具体范围另行作出决定，不把这些动作作为自研版独立运行、L6 或独立发布的必经步骤。

2026-09-06 后续：[DP1-K](YIME_DUAL_PRODUCT_DP1_K_NSIS_COMPILER_INTERVAL_2026-09-06.md)关闭 DP1-NSIS-MEMBERSHIP-05 的检测并拒绝边界。上文 DP1-J 的未接入监测描述为历史阶段事实。物理防止、non-OS 和 full closure 保持 false；其他门禁不变。
