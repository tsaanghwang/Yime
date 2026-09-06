# DP1-C：双产品注册、SID 与事务隔离审计

日期：2026-09-05。影响面为共存安装合同／两版维护事务。依据[双产品开发计划](YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，本批先做只读审计，再实现 Rime/PIME 的定向退出、目标用户源码链并执行纯合成事件模型。另运行 `makensis` 构包验证，以及仓库锁定 librime 配合临时用户目录的退出学习回归；未运行生成的安装器或任何已安装输入法程序。没有实际提升、注册／反注册、安装／卸载、恢复、停止真实进程、修改默认输入法或读取真实用户设置、正文及学习数据。

## 结论和证据等级

新增 [`transaction-isolation.ps1`](../../tools/dual-product/transaction-isolation.ps1) 和 [`test-transaction-isolation.ps1`](../../tools/dual-product/test-transaction-isolation.ps1)，把下一阶段的最低合同变成可执行的纯函数／合成门禁：

- 发起用户、提升后维护进程、目标用户及维护 worker 必须是同一明确 SID；正常 Runtime 返回该 SID 的非提升令牌。
- x64／x86／ARM64 注册操作只能覆盖候选包明确声明的完整架构集合，不能漏一个架构或增加未声明架构。
- COM CLSID、TIP Profile、Run 值、卸载项、精确进程映像、安装根和状态根必须属于所选产品；事件不得依赖或写入另一产品。
- 安装／升级必须在第一项活动维护变更前完成私有构包暂存；只有新注册和 Runtime 均核验后才能删除旧根。
- 失败升级不得提交或删除旧根，必须恢复注册、Run、卸载项、用户 TIP、配置和运行状态，并使注册值类型摘要与失败前一致。
- 无论成功还是回退，另一产品及用户默认输入法的前后摘要都必须完全一致。

完整事务门禁目前**没有接入两个安装器**；本轮只把其中的 Rime/PIME `TargetUserSid` 子合同接入维护／安装源码。合成门禁能拒绝错误 SID、跨用户路径和错误事务，但不证明真实 UAC、注册工具、安装、回退或共存实机流程已经满足合同。`dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false` 保持不变。

## YimeCore 已有、可复用的源码与既有测试

只读核对确认 YimeCore 当前维护链已有以下接缝，后续矩阵应复用而不是另造一套身份规则：

1. `manage-e6c-trial-install.ps1` 在提升参数中传递 `TargetUserSid` 和 `StateRoot`，提升后先核对有效令牌 SID 等于发起 SID；普通 Runtime 另有中等完整性令牌核验。
2. 新包完整复制、重新审计并写好元数据后，才调用 preinstall；旧根和 staging 根在注册、启动完成前保持可恢复。
3. 失败路径恢复此前的 COM／TIP、Run 值、卸载树、用户 TIP、运行配置及先前运行状态，并保留注册值类型。
4. 既有本机安装验收通过系统可见注册读取器对生产 Rime/PIME CLSID/TIP、其他 Run 值和默认输入法作前后保护比较；失败回退验收也比较系统可见注册树。

可复用但本批没有执行的入口包括：`test-e6c-user-tip-rollback.ps1` 的用户 TIP 嵌套值／类型回退，`test-local-product-maintenance.ps1` 的令牌和架构负例，`invoke-local-product-native-install.ps1` 的系统可见非目标产品保护，以及 `invoke-local-rollback-rehearsal.ps1` 的失败后注册、数据、包和 Runtime 恢复。这些历史／源码能力不能替代新候选在获准环境中的实际运行。

## 定向退出关闭链的具体回归

源码红灯证明根 Go 后端在 stdin EOF 时直接返回：两个已跟踪 `TextService` 的 `Close` 计数为 `(0, 0)`，期望 `(1, 1)`。这会使 PIMELauncher 即使关闭 stdin，也不能证明本连接拥有的 Rime 会话已销毁及学习事务已落盘。

修复后，`server.go` 在 EOF、读错误和正常返回时先原子摘除再关闭全部已跟踪服务；一个关闭失败时仍关闭其余服务，最后返回错误，从而阻止 launcher 把失败当作维护成功。重复 client init 也先关闭旧服务，失败的新 init 会关闭新建服务并保留旧服务。`IME.CloseWithError` 继续把错误贯穿到 checked `nativeBackend.DestroySession` 和 `RimeDestroySession`。

隔离验证结果：

- 根后端关闭／失败／重复 init 测试 3／3，通过；IME checked close 1／1，通过。
- 仓库锁定 librime `1.17.0 / 33e7814` 使用 `t.TempDir()` 用户目录；子测试进程选择合成候选后调用 checked `EndSession` 并故意 `os.Exit(0)`、不调用 `Finalize`，父进程跨进程重开确认学习排序保持。`-count=2` 两次通过，约 20.98 秒。
- `go test ./... -count=1` 通过。Go 命令没有单独 JSON 收据；可复核的跨脚本定向退出结果由下文 PS5／PS7 各 17／17 收据固定。

这些结果关闭了“EOF 没有释放会话”的源码回归，但未证明安装包中的真实 worker、命名管道 ACK、退出码 73、watchdog 抑制重启、逐 PID 复核和锁文件释放已经联动通过。

## 原审计四项及当前状态

以下均不是本批观察到真实用户数据损坏或正在运行产品异常；前两项已完成源码／合成收口，后两项仍是源码缺口：

1. **发起 SID 链：源码已接通，实机待验。** NSIS 现在以 `RequestExecutionLevel user` 启动，非提升引导阶段捕获 `InitiatingSid`，创建短时、文件所有者绑定且验证后删除的一次性关联信封，再用 `runas` 启动 worker。worker 必须同时匹配 `InitiatingSid`、`TargetUserSid`、当前 SID、提升状态和关联身份，之后所有维护 helper 都显式收到 `TargetUserSid`。直接拼接内部 worker 参数没有有效未过期信封时按合同拒绝。这里的 `InstallLayoutOrTip` **仍在经同 SID 核验的提升 worker 中执行**，不是回到原 SID 的非提升令牌；真实同账户 UAC、换管理员凭据拒绝、参数／信封互操作及是否需要非提升回调仍须实机确认。
2. **用户注册清理：源码已限定目标 SID，实机待验。** `tools/pime-registry-cleanup.ps1` 现在强制接收并核验 `TargetUserSid`，从 `Registry::HKEY_USERS\<TargetUserSid>` 构造 TIP 和 `Control Panel\International\User Profile` 路径；不再枚举 `HKEY_USERS` 根，也不使用提升进程的 `HKCU`。开发安装、卸载、重置入口及三份命令模板均显式传递同一个 SID。真实注册前后仍需证明其他已加载／未加载 SID 完全不变。
3. **旧／当前注册所有权没有完整绑定所选根。** NSIS 会删除 legacy 安装／卸载键，注册／反注册命令也尚未以“对应 CLSID/Profile 的 DLL 路径确实位于已标记的所选根”为完整前置条件。两个注册视图、当前与批准迁移的历史键都需先读回类型和值，无法唯一归属时拒绝；不得删除父键、另一 SID 或另一产品的值。
4. **完整包事务和注册收敛缺失。** 升级会在完整新包暂存和审计前反注册旧 DLL，普通 `regsvr32` 调用没有形成逐架构退出码与最终 COM/TIP 状态收敛证据；后续文件写入失败也没有恢复旧包、注册值类型、启动项和先前运行状态的完整回退事务。DLL `.new`／`/REBOOTOK` 只处理单个被锁文件，不能等同完整构包事务。

后续源码顺序是：先把当前／legacy 注册读取与精确所有权校验接到任何删除和反注册之前；随后实现 DP1-PIME-TRANSACTION-06 的“完整暂存—哈希审计—目标版静止—注册并核验—启动并核验—提交—最后删旧根”事务和逐失败点夹具。本轮没有开始 06。取得单独授权后，再在隔离目标一次完成 SID／UAC、注册所有权和事务的原生验收。

## 本批合成验证

先补的红灯合同在 PS 5.1／PS 7 上结果一致：各运行 17 项，16 项失败，只有“测试期间源码未变化”通过；失败精确覆盖缺少 SID helper、两阶段引导、显式维护参数、目标 HKU 路径及各入口转发。红灯收据分别为 `.tmp/dual-product/dp1-target-user-red-ps5-20260905-a1/result.json`（SHA-256 `71bd22cee603806e3ec790339b7d625f770a8a37557289caa626b0895797f0ab`）和 `.tmp/dual-product/dp1-target-user-red-ps7-20260905-a1/result.json`（SHA-256 `45adf52686735e9a88ff089c399a0c0c27ea66867b8ac5e923cc6694ce6bc4a2`）。

源码修复后的最终证据：

- 目标用户专项合同：PS 5.1／PS 7 各 24/24。按定向退出最终源码重跑的收据为 `.tmp/dual-product/dp1-target-user-current-ps5-20260905-a2/result.json`（SHA-256 `921ec50a170355551dbc19bd2909f32a9509f6af7a2d060ed130b1b723eee8a5`）和 `.tmp/dual-product/dp1-target-user-current-ps7-20260905-a2/result.json`（SHA-256 `9e896ec01579827ad18ee86eb1905b37642ec87cd90a7638aff25f04cb7510b5`）。
- 事务合同合成回归：PS 5.1／PS 7 各 41/41；05 标记为“源码／合成已过、原生验收待办”，06 仍未实现。收据为 `.tmp/dual-product/dp1-transaction-current-ps5-20260905-a2/result.json`（SHA-256 `dd4eb1adf9adcab6aa1e9f0a53cd77114e5d99bacacf1d5d1f58623b33278d7`）和 `.tmp/dual-product/dp1-transaction-current-ps7-20260905-a2/result.json`（SHA-256 `7b6266bb93b208da6f0cf26d29f31ca2e5c1589494a59ad767f13159081eb3a8`）。
- 全局源码基线：59 个哈希输入、28 项 Python 合同测试通过、0 失败，保留 3 项已分级待办；`.tmp/dual-product/dp1-target-user-current-baseline-20260905-a2/baseline.json`，SHA-256 `499da30aa00401da9cb9d6906a4a5ca9683942658b4807d7cbc9904acef5f616`。
- 既有维护／定向退出回归：PS 5.1／PS 7 分别各为 31/31 和 17/17；均只操作合成夹具。对应四份收据位于 `.tmp/dual-product/dp1-rime-maint-current-ps5-20260905-a3/result.json`、`.tmp/dual-product/dp1-rime-maint-current-ps7-20260905-a3/result.json`、`.tmp/dual-product/dp1-directed-stop-current-ps5-20260905-a2/result.json`、`.tmp/dual-product/dp1-directed-stop-current-ps7-20260905-a2/result.json`，SHA-256 依次为 `bd66b589e4b96ad839bcff4d3ca9359d7a4583515f19338786ec5d6070a4a96d`、`da320ffb21083826e8c250d504f4c5025e73fa9d7d61535beb81b315582893ba`、`3f69d05e47a263e97157f17ff9ac8f2bb076a459ef4caec4c7b2d0bbd75f00a6`、`fc625eed065e338a0fbd8d3aa9bc4aaf490ae73e4896ac20e9c80ff92a95cdc4`。
- `makensis` 3.12 构包退出码为 0，仅生成、未运行 `installer/YIME-1.4.0-dev-setup.exe`；SHA-256 `36156e5a00abfe09bb99ce5c99cb2a5fd72c131da9e4c7481f139d4ef5333756`。开发环境签名脚本明确报告跳过签名，因此该文件不是可发布签名包，也不是安装验收证据。

目标用户收据明确记录没有实际提升、运行安装／卸载器、注册／Profile 变更、真实进程启动／停止或用户注册／数据读取。所有收据继续保持 `dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`。

## 仍须后续授权的真实门槛

继续编写源码、编译安装器和运行纯合成故障夹具不需要触碰当前安装；以下真实操作则必须另行取得明确授权，并在独立、可恢复的目标上进行：

1. 从 Explorer 启动非提升 NSIS 引导器：同账户 UAC 同意必须成功；使用另一管理员凭据、直接构造内部 worker 参数、关联身份错误／过期／重复使用必须在任何变更前拒绝。当前 `InstallLayoutOrTip` 是同 SID 提升态调用；尚未实现或证明回到非提升令牌的回调。
2. 在只含合成账户数据的隔离目标上验证 Profile 启用／禁用及清理只改变 `HKU\<TargetUserSid>`，其他已加载和未加载 SID、另一产品、默认输入法均保持不变。
3. 对全新候选执行逐架构 COM/TIP 注册、状态读回、失败点注入和完整回退；不得在当前生产 Rime/PIME、日用 local.12 或历史冻结载荷上试验。
4. DP2 的仅 Rime/PIME、仅 YimeCore、两种安装顺序、分别升级／失败回退／卸载／恢复及重启矩阵，并验证另一产品的进程、注册、文件、设置和学习均未变化。
5. x64／WOW64 x86 注册宿主和真实应用验收，以及有明确可用设备后的 Windows ARM64 原生包／注册／宿主验收。交叉编译和本批合成架构事件不算物理通过。

本批不授权三选一安装入口，也不改变当前日用 local.12、生产 Rime/PIME、默认输入法、SR4、L5 最终确认或 L6 的既有状态。

## 2026-09-06 后续收口说明

[DP1-D 注册接线与纯事务模型](YIME_DUAL_PRODUCT_DP1_D_REGISTRATION_TRANSACTION_MODEL_2026-09-06.md)已在后续源码上补齐本记录第 3 项的当前注册根所有权／fresh-orphan 合同，并把注册失败传播、Profile／类别闭集、目标用户清理顺序和架构接线纳入源码／构建门禁；第 4 项则形成了独立的纯内存 24 阶段／10 维／96 故障参考模型。所以上文“第 3、4 项仍是源码缺口”和“06 尚未开始”只描述 2026-09-05 DP1-C 时点，不能继续用来描述当前源码。

这次后续收口仍没有把完整事务接入真实安装／维护执行路径，也没有执行 native probe、安装／卸载、真实注册表、提升或真实进程。持久 journal／恢复归档、崩溃或重启重放、真实逐维回滚、非提升 Runtime readiness、registered/live host、legacy migration 和 ARM64 原生验收仍待完成。ARM64 只有交叉构建／接线与合成状态证据。当前日用 local.12 未变，local.13 未安装；DP1、DP2、L5 最终确认和 L6 均未完成。
