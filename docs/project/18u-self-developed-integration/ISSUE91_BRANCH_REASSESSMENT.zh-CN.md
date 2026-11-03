# Issue #91：旧 18u 分支逐文件复核与最小诊断增量

日期：2026-11-02。影响范围：18u 开发工具的离线证据编排，不是安装包或执行授权。

## 固定比较对象

- [Issue #91](https://github.com/tsaanghwang/Yime/issues/91)。其中的 main SHA 是公告时点；本次以更新后的主线为准。
- main：`d5204c46826c4fd8814b5e673f07cd6dbf32a210`，含 #88、#89、#90、#92。
- A：`3bf7eec98e1fbb30f2500a8a1764c8f355333468`，诊断与新事务归属清理。
- B：`d47f79547e79751f0e92a7280740a8426ecc5800`，HKCU 适配器与手动 CI。
- GitHub compare 再次确认旧分支 ahead 2 / behind 21，merge base 为 `71a4a252641159753b0eff41b871254233c6efd2`。本地使用精简历史检出，不用浅克隆的可达提交计数替代服务端比较结果。
- 本次分支从上述 main 新建；不 rebase、重置、强推或删除旧分支，不修改旧提交、固定包及历史失败记录。

## 功能结论

| 功能 | 主线现状 | 旧分支独立价值与决定 |
| --- | --- | --- |
| 原始激活失败与清理失败分离 | #88 的 `ActivationFailureTrace.h` 在清理覆盖终态前写 operation，再单独写 cleanup；`noexcept`，日志失败不能阻止清理；有纯报告测试 | 主要目标已覆盖，不能因为没有 `ActivationDiagnostics.h` 就判定主线没有诊断。复用已有事件，不引入第二套原生诊断协议 |
| 完整阶段序列与 registryMatch | 主线只保存失败阶段；只读恢复快照覆盖归属树路径、值类型/长度/哈希，但不是逐调用轨迹或预检命中路径 | A 的成功阶段、多个清理错误、具体预检命中位置仍有独立价值；本 PR 不移植。其容器分配/复制可抛异常，未具备主线日志写出失败不影响清理的保证；须单独设计有界、不可抛出的记录策略 |
| 编排回执可直接查看失败 | 主线保存原始 stdout/stderr、哈希、进程和账本绑定；失败时没有结构化诊断摘要，exit 4 的坏 stdout 在启动 `--verify` 后才由证据门拒绝 | 提取 A 的失败回执与损坏 JSON 拒绝思路，适配主线 stderr 协议；这是本次最小补丁 |
| 已知 TIP 残留恢复 | #88 增加归属判断、`Unregister`、四视图定域清理、复读验证、只读 inspect/snapshot、四哈希钉定旧注册 | 已覆盖历史恢复需求。Issue #91 记录旧残留已恢复且独立扫描零命中，不能以本次复核再次执行 |
| 新事务逐项来源记录 | 主线为 ledger-v3，含预检缺席、COM generation、尝试检查点；没有 A 的逐路径 `itemAbsence` | A 的 ledger-v4 和逐项来源是独立增量，但直接移植会拒绝主线支持的 v3，破坏旧包恢复兼容；保留历史设计，暂不接入生产路径 |
| 非递归、逐叶删除 | 主线先核实专用 CLSID 的完整允许形状，再清理专用子树并复读；不是任意注册表路径删除 | A/B 的形状+revision 复核和 `RegDeleteKeyExW` 缩小删除范围，但不是原子比较删除。旧内存测试明确展示末窗口新增值仍可能被删；不能声称解决并发写入风险 |
| 隔离注册表测试 | 主线 `YimeResidueFixtureTests` 使用专用 CLSID 下的合成树及真实 TSF，不做产品注册，覆盖七案 | B 的随机 `HKCU\\Software\\YimeOwnedResidueAdapterTest-{GUID}`、查询权限错误、视图别名观察、部分删除停止是不同机制测试，不被七案完全覆盖；其共享生产适配器尚未进入主线，本次不加入无生产调用者的新适配器/执行入口 |
| 一次性 CI | 主线三类手动确认、固定旧分支、精确 SHA、首次 attempt、互斥门仍在 | B 的第四种互斥手动入口、进程约束自测、写前根路径证据、清理证据校验有独立价值；但 `run_attempt == 1` 与 concurrency 不构成跨 run 的一次性授权消耗，重复 dispatch 可有新的 run ID。不能把旧批准搬到新分支/SHA |

## 删除安全边界的具体差异

主线 `RegistrationProbe.cpp::Transaction::cleanup()` 保留 COM generation，直到前面的清理成功且 TIP 缺席已验证；`CanRemoveResidue` 检查 COM/尝试/形状/枚举等条件。`MyComputerActivationSupport.h::localRemoveOwnedTipResidue()` 先检查专用 TIP 形状，再调用服务 `Unregister`，对 HKLM/HKCU 的 32/64 视图逐项复查和删除专用 CLSID 子树；不把 HRESULT 单独当作缺席证明。主线 API 清理对已不存在的对象通过再次观察实现幂等。

A 的方案采用 v4 逐路径缺席证据、固定路径白名单、父子叶序、仅空键或特定 HKCU profile 的唯一 `Enable=0` 值、删除前 revision 复查、删除后缺席检查；API 失败即停止，COM server/root 最后分开非递归删除。这与主线恢复语义不同，不能删除主线幂等判断后直接替换。`OwnedResiduePolicy.h` 和主线 `MyComputerActivationPolicy.h` 还在同一命名空间定义不同的 `ResidueShape`，直接复制会产生定义冲突。

两种方式均不是对同账户并发写入者的原子隔离保证。B 的随机 HKCU 测试不验证主线固定 CLSID 白名单、DPAPI 账本、COM generation、真实 TSF 生命周期或 v3 旧包恢复；它通过也不能代替这些证据。主线七案为：缺席基线、归属空壳分类/快照/删除、拒绝删除已缺席对象、保留外来语言、保留外来类别、保留外来 profile、保留未知子键。本次只读源码，未重跑这七案，也未重跑 B。

## 逐文件取舍（两笔提交合计 25 个路径）

表中 `tests/` 指 `YimeTextServiceExperiment/tests/`。A/B 为以上固定提交。

| 路径 | 来源 | 对照主线与本次处置 |
| --- | --- | --- |
| `.github/workflows/ci.yaml` | B | 不引入第四手动入口或修改互斥条件；只加常规离线回执/证据测试，全部使用假包和替代进程 |
| `.github/workflows/mycomputer-activation-package.yml` | A | 主线已有自己的 policy/fixture 构建与离线检查；不加入旧 A/B 目标，不改变分支钉定或打包流程 |
| `.github/workflows/owned-residue-registry-adapter.yml` | B | 主线无对应入口；独立价值见上文，但授权/生产适配器未迁移，不复制、不 dispatch |
| `DEVELOPMENT_AB.md` | A | 历史实验说明保留原提交；其中“当前残留”和执行授权仅属于旧时点，不复制为当前指令 |
| `YimeTextServiceExperiment/CMakeLists.txt` | A/B | 主线已有 `YimeActivationFailureTraceTests` 与 `YimeResidueFixtureTests`；不添加 v4 策略或默认 OFF 的 HKCU 测试目标 |
| `tests/ActivationDiagnostics.h` | A | 主线失败保留已覆盖核心需求；完整阶段记录另行设计，不复制 |
| `tests/ActivationDiagnosticsTests.cpp` | A | 旧捕获模板的单元测试不能证明新主线接线；保留历史，不作为本次测试结果 |
| `tests/MyComputerActivationMain.h` | A | 保留主线 operation/cleanup stderr、inspect/snapshot 和恢复分支；不改 stdout schema |
| `tests/NewTransactionResidue.h` | A/B | v4 白名单和缺席捕获与当前账本不兼容；B 的共享适配器调用不接入 |
| `tests/OWNED_RESIDUE_REGISTRY_TEST_SCOPE.md` | B | 保留旧测试范围与限制；“已授权一次云执行”不能作为本次执行授权 |
| `tests/OwnedResiduePolicy.h` | A | 逐项来源、非递归策略仍有价值；存在同名 enum 冲突和账本语义差异，不直接合入 |
| `tests/OwnedResiduePolicyTests.cpp` | A | 内存故障/末窗口竞态表征有价值；当前生产路径不使用该策略，不挂入主线假装覆盖 |
| `tests/OwnedResidueRegistry.h` | B | Win32 Observe/EraseOne 机制有价值，路径允许与来源认证属于调用方；未认证的通用机制不替换主线恢复 |
| `tests/OwnedResidueRegistryTests.cpp` | B | 随机 HKCU 根、写前证据、权限查询和部分失败测试不同于主线七案；暂不移植或执行 |
| `tests/RegistrationProbe.cpp` | A/B | 不改 ledger-v3、检查点、幂等 API、COM 最后清理和归属验证；不混入旧 v4 方案 |
| `local-validation/CMakeLists.txt` | A | 基于旧快照的 object-only/纯策略验证环境；不是主线构建入口，不复制 |
| `tools/ci/run_mycomputer_registration.py` | A | 有独立增量：失败回执和损坏 JSON 提前拒绝；按主线现有 stderr 重新实现，不读取旧 `diagnostics` 字段 |
| `tools/ci/test_local_activation_evidence.py` | A | 旧测试需要新 stdout diagnostics schema；本次不引入该 schema，保留并运行主线严格证据测试 |
| `tools/ci/test_mycomputer_activation_contract.py` | A | 不把源码检查改成 v4 或旧 catch 边界；运行原主线合同，保护恢复及无写 inspect |
| `tools/ci/test_mycomputer_activation_native.py` | A | 不放宽原生报告字段集合；本次不执行原生测试 |
| `tools/ci/test_mycomputer_package_workflow.py` | A | 旧目标接线没有移植，故不复制其断言；运行主线打包 workflow 合同 |
| `tools/ci/test_owned_residue_registry_contract.py` | B | 约束旧生产适配器、旧 v4 和旧 workflow；未移植相应路径，不添加悬空源码断言 |
| `tools/ci/test_run_mycomputer_registration.py` | A | 提取损坏/非对象/重复 JSON、超时保留回执的案例，并新增主线双阶段 stderr、矛盾 exit 4、清理单独失败、格式拒绝测试 |
| `tools/ci/test_workflow_contract.py` | B | 保留主线三个手动门的精确合同；不添加允许新手动入口的例外，原测试通过 |
| `tools/ci/validate_local_activation_evidence.py` | A | 完整保留严格字段集合与唯一 DLL marker 要求；不接受旧 diagnostics 扩展，不把失败日志当成功 |

## 本 PR 的最小补丁

`registration.json` 新增 `nativeStatus`、`nativeFailure`、`failureTrace`、`failureTraceComplete`。它们是现有原生日志的诊断摘要，不认证日志来源，也不证明未记录的阶段没有执行。

解析只接受主线四字段失败事件，最多 operation/cleanup 各一条，按顺序保存；允许已有 DLL marker，但仍由原来的严格证据门单独判断成功。未知行、截断、重复字段、错误类型或超界值不会成为通过证据；已有有效失败行仍保留，`failureTraceComplete=false`。空轨迹仅表示没有收集到失败事件，不代表成功。原始文件、哈希、进程结果和已稳定账本绑定仍保存。

stdout 须先是严格 JSON 对象且符合原生身份。即使进程返回 4，损坏 stdout、失败轨迹或不完整轨迹也会在启动只读 `--verify` 前拒绝。最终成功仍须通过未经改动的 `validate_local_activation_evidence.validate`；不增加重试、恢复、注册或包执行入口。

## 验证及未执行项

- Python 3.14 本地离线测试：`test_run_mycomputer_registration` **24/24**；另六模块 **53/53**，无跳过。模块为 `test_local_activation_evidence`、`test_mycomputer_activation_contract`、`test_mycomputer_package_workflow`、`test_workflow_contract`、`test_mycomputer_stage1_package`、`test_collect_mycomputer_preflight`。
- 首轮 24 项中两个新测试因测试助手重复传递 `runner` 而报错；修复助手后复测 24/24。这个失败属于测试接线，不是原生注册/恢复结果；旧提交中的原始失败证据未改动。
- `git diff --check` 通过；新 CI 步骤只运行上述假包/替代进程回执测试与离线证据验证。常规 CI 结果以 PR 实际运行记录为准。
- 未编译或执行 Windows 原生激活、注册、残留恢复、七项真实注册表夹具、一次性 HKCU 适配器测试；未执行 MyComputer 只读扫描。本次没有新的原生通过证据。

后续若推进 v4 清理或 HKCU 机制测试，应先提交与 v3 共存的明确设计、解决命名冲突和诊断异常安全、定义新 SHA/新运行的一次性授权消耗规则，再交付独立补丁。本 PR 不自动重新钉定旧 workflow，不把历史恢复声明或 CI 确认词视为可复用许可。
