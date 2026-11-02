# S3c：本机 TIP 残留的幂等清理与所有权保护审阅

2026-11-02。分支 `codex/18u-native-async-gates-20261102`，基于
`1dbd4792`。本批为源码审阅与交付方案，**未修改原生工具源码、未运行任何
注册/恢复/验证入口、未触碰注册表或原证据目录**。

对象：原工作区 `mycomputer-activation-71a4a2-v2-r1/`（源提交
`71a4a252`）留下的 18u 专用 CLSID 残留；参见
[异步负例与本机失败定位](S3C_NATIVE_ASYNC_GATES_HANDOFF.zh-CN.md)。

## 1. 结论

| 问题 | 结论 |
| --- | --- |
| 残留是否可由源码解释 | 是。stage1 构建的 `Transaction::cleanup()` 以 `#ifndef YIME_MYCOMPUTER_ACTIVATION_STAGE1` 排除了 CI 构建用于清除 `CTF\TIP\{CLSID}` 服务残留的 `ITfInputProcessorProfiles::Unregister` 分支（`RegistrationProbe.cpp:324-330`）。`UnregisterProfile`/`UnregisterCategory` 只删叶节点，不删 `TIP\{CLSID}`、`Category` 与空 `LanguageProfile\0x00000804` 父键，HKCU 侧由 `EnableLanguageProfile` 创建的 `Enable` 叶节点也不随 HKLM 注销而删除。这与本机观察的四视图残留形状一致 |
| 现有 `--recover` 能否清除 | **不能**。`Mode::Recover` 复用同一个 `cleanup()`（`MyComputerActivationMain.h:88-90`）。顺序为注销→`localTipAbsent`（第 334 行）→删除 COM 根。残留存在时 `localTipAbsent` 必失败，`cleanupOK=false`，COM 根保留，返回 `recovery-cleanup-failed` |
| 现在能否运行一次恢复试试 | **不应**。编排脚本 `tools/ci/run_mycomputer_registration.py:190-193` 在调用 `--recover` 前以 `open('x')` 创建持久 `recovery-claim.json`，“失败也消耗、不得删除、不得重放”。用现有工具执行等于确定性地烧掉唯一一次恢复声明，并把本来可判定的现场变成“已尝试恢复、状态未知” |
| 所有权证据是否仍完整 | 是。只读 `--inspect-recovery` 返回 `ownedScopeVerified=true`，说明 `strictLocalComShape` 通过：HKLM COM 根仅含本轮 `YimeMyComputerGeneration` 标记与 `InprocServer32`，`strictLocalTipShape` 通过：TIP 残留只引用本 CLSID/本 profile/0x0804/`TFCAT_TIP_KEYBOARD`。这是后续清理可以绑定的唯一归属锚点，**必须最后删除** |
| 首次失败的原生步骤 | 不可考。原工具在清理失败时覆盖 stage/code，stderr 为空（已在 `1dbd4792` 修复，旧包无法补造）。`writesStarted=true` 且 `registryAbsent()` 在置位 `writes` 之前执行，可排除“注册前已有残留”；其余候选为 `activate-own-profile-forprocess`、`get-active-profile`、`active-profile-mismatch` 或消息泵期间的 TIP 创建失败 |

## 2. 残留形成路径（按源码推演）

```text
run():  registryAbsent/apiAbsent 通过 → comAttempted → COM 根+generation（comOwned）
        → InprocServer32 → RegisterProfile（HKLM TIP\{C}\LanguageProfile\0x0804\{P}）
        → RegisterCategory（HKLM TIP\{C}\Category\...）
        → EnableLanguageProfile(TRUE)（HKCU TIP\{C}\LanguageProfile\0x0804\{P}\Enable）
        → ActivateProfile … 某一步失败（原因已被覆盖）
cleanup(): DeactivateProfile / Deactivate 线程管理器
        → EnableLanguageProfile(FALSE)   仅改 HKCU Enable 值
        → UnregisterCategory             删 Category\Item/Category 叶，父键保留
        → UnregisterProfile              删 HKLM {P} 叶，0x0804 与 TIP\{C} 保留
        → [stage1 无 Unregister(CLSID)]
        → localTipAbsent → 失败（existing-tip-identity）→ cleanupOK=false
        → 跳过 COM 根删除 → registryAbsent 再失败 → 报告 stage 被覆盖为 existing-tip-identity
```

CTF 由 TSF 同时写 32/64 位视图，所以残留在两视图都可见；`Unregister(CLSID)`
由系统同时处理两视图，手工 `RegDeleteTree` 需显式遍历四个 hive×view。

## 3. 恢复交付方案（待审阅，未实现）

### 3.1 原生工具变更（仅 stage1 构建，`YimeMyComputerActivationStage1.exe`）

1. `cleanup()` 在 `UnregisterProfile` 之后、`localTipAbsent` 之前增加
   **受门控的服务残留清除**，门控全部满足才执行，否则记
   `cleanup-residue-ownership-not-proven` 并保留现场：
   - `comOwned && profileAttempted`，`ledger->validateOwnedCom()` 通过；
   - `strictLocalTipShape` 通过（四视图 `TIP\{C}` 下只允许 `Category` 与
     `LanguageProfile\0x00000804\{P}`，`{P}` 下无子键；任何其他语言、profile、
     类别或值名即停止）；
   - 本 CLSID 在 `apiAbsent` 的 profile 枚举中**不再**出现（证明
     `UnregisterProfile` 已生效，只剩空壳）。
2. 清除动作顺序与幂等规则：
   - 先 `ITfInputProcessorProfiles::Unregister(CLSID)`；
   - 再对 HKLM/HKCU × 32/64 位视图检查 `CTF\TIP\{C}`，仍存在且形状仍通过
     `strictLocalTipShape` 时 `RegDeleteTreeW`；
   - 每步以**再次读取是否存在**判定成功，不以 HRESULT 为准：目标已不存在视为
     成功（`ERROR_FILE_NOT_FOUND` → S_OK），存在且删除失败才计失败；
   - 不扫描、不删除 `CTF\SortOrder`、`Assemblies`、其他 CLSID 或任何值数据；
     这些若含本 GUID，由 `registryAbsent()` 报 `existing-identity-*` 停止。
3. 保持现有尾序：`localTipAbsent` → `validateOwnedCom` → 删除 COM 根 →
   `registryAbsent`+`apiAbsent`。COM 根仍是最后删除的归属证据。
4. 恢复前新增**只读残留快照**写入恢复证据目录：仅导出四视图 `TIP\{C}` 子树
   与 COM 根的键名/值名/类型/长度（值数据只记 SHA-256），不含其他键。供事后
   审阅，不改变判定。
5. `--inspect-recovery` 增加字段 `residueShape`（`owned-empty-shell` /
   `not-owned` / `absent`）与 `recoveryToolCapable`（当前工具能否清除该形状），
   让编排脚本在创建 claim 之前就能拒绝“工具不具备能力”的恢复。

### 3.2 编排脚本变更（`tools/ci/run_mycomputer_registration.py`）

- 创建 `recovery-claim.json` **之前**先调用新 `--inspect-recovery`，要求
  `recoveryRequired=true && recoveryToolCapable=true`；否则以
  `blocked-tool-incapable` 结束，不创建 claim。
- 账本位置校验保留严格相等；因此原证据目录
  `C:\dev\Yime\mycomputer-activation-71a4a2-v2-r1\` 必须留在原路径
  （已以本地 exclude 隐藏，未入库）。
- 原包的 EXE 不能替换：新工具以独立版本号/manifest 进入新固定包，恢复时
  `--ledger` 指向原账本，账本格式需向后兼容 `71a4a252` 版本（仅读取，不改写）。

### 3.3 验证计划

| 层 | 内容 | 门 |
| --- | --- | --- |
| 单元 | 新策略函数：形状判定、幂等成功判定（不存在=成功）、门控任一失败不执行删除 | 全部通过 |
| 夹具 | 复用 `RegistrationQueryTests` 的 HKCU/HKLM 夹具构造“空壳残留”“混入他人 profile”“缺 generation 标记”三种形状，验证仅第一种被清除 | 全部通过 |
| CI 一次性 | 现有 formal/activation workflow 上：注册→在 `ActivateProfile` 后注入失败→旧清理路径留下残留→新 `--inspect-recovery` 报 `owned-empty-shell`→`--recover`→`--verify` 全绝对 | pass 且 stderr 为空 |
| 本机只读 | 用新包对原账本运行 `--inspect-recovery`（不创建 claim），记录 `residueShape` 与快照 | 与第 1 节观察一致 |
| 本机恢复 | 单独授权后由编排脚本执行一次；之后 `--verify` 绝对 | 另行批准 |

### 3.4 执行边界

- 以上任何代码未经审阅合并、固定包未产出前，不运行 `--recover`、不手工
  `reg delete`、不重复 `--register-once`。
- 恢复通过不补造 `71a4a252` 轮次的激活成功；该轮结果保持 failed。
- 不触碰标准键位 YimeCore、Rime/PIME 的任何注册项、默认输入法与用户数据。

## 4. 决定（2026-11-02，用户委托后确定）

1. **接受**在 stage1 工具加入受门控的 `Unregister(CLSID)` → 四视图
   `RegDeleteTree` 清除。`Unregister` 是 TSF 的整树注销入口；HKCU 残留若其不处理，
   `RegDeleteTree` 只允许作用于 `strictLocalTipShape` 通过的空壳，二者均以再读
   不存在判成功。只保留 `Unregister` 而把 HKCU 残留交人工，会使 `--verify`
   无法绝对，方案不闭环，故不采用。
2. 残留快照**记录值名**，不记值数据（只记类型、长度、SHA-256）。TIP 子树下的
   值名为 TSF 标准名（`Enable`、`Description` 等）；DLL 路径属于值数据，不记录。
3. 新固定包**沿用** `MyComputer activation x64 package (no registration)`
   workflow，以新版本号产出同一工具的 v3 包；`--inspect-recovery/--recover`
   与注册模式本在同一 EXE，不另开 recovery-only workflow。
4. `18u formal TIP adapter (S3c.1)` workflow 的分支钉定**本批不改**。在具备
   已获准中文独立 profile 的隔离环境前，该测试必失败；改钉到新分支只会产生
   确定为红的运行。保留 `workflow_dispatch`，待本机残留清理与注册态环境就绪后
   再重新钉定，届时仍保持失败即失败。

下一步：按第 3 节实现原生工具与编排脚本变更，并补第 3.3 节前两层测试；
本机只读检查与恢复执行各自另行确认。

## 5. 实现状态（2026-11-02，同分支后续提交）

| 项 | 实现 | 验证 |
| --- | --- | --- |
| 策略 | `MyComputerActivationPolicy.h`：`Mode::SnapshotResidue`、`ResidueShape`、`RecoveryToolCapable`、`CanRemoveResidue`（需 comAttempted／comOwned／profileAttempted／未 cleanupVerified／COM 形状／空壳形状／profile 已不枚举）、`ResidueStepSucceeded`（只看再读） | `MyComputerActivationPolicyTests` 5 组通过 |
| 形状与清除 | `MyComputerActivationSupport.h`：`localResidueShape`（外来引用阶段与查询失败阶段显式区分）、`localRemoveOwnedTipResidue`（`Unregister` → 逐视图再校验形状 → `RegDeleteTree` → 再读绝对）、`localResidueSnapshot`（值名／类型／长度／SHA-256，无值数据） | MSVC x64 编译通过；未在实机运行 |
| 清理路径 | `RegistrationProbe.cpp` stage1：disable／UnregisterCategory／UnregisterProfile 以再读缺席判成功（恢复可重入）；`UnregisterProfile` 后、`localTipAbsent` 前插入受门控残留清除；任何门失败记 `cleanup-residue-*` 并保留空壳与 COM 标记 | 编译通过；契约测试通过 |
| 报告 | `--inspect-recovery` 新增 `residueShape`／`recoveryToolCapable`；新增只读 `--snapshot-residue`（与检查同样绑定账本） | 编译通过；参数解析测试通过 |
| 编排 | `run_mycomputer_registration.py`：先只读检查，不具备能力或形状 not-owned 则拒绝且**不创建声明**；声明 → 快照 → 恢复 → 核验；快照字段严格校验、拒绝值数据；`recoverableRegistrations` 四哈希钉定允许较新包恢复旧注册，DLL 仍由原生工具按账本原路径校验 | 19 项流程测试通过（新增 5 项） |
| 包 | `build_mycomputer_stage1_package.py --pinned-registrations`，读取审阅文件 `tools/ci/mycomputer_recoverable_registrations.json`（当前钉定 `71a4a252` 注册的 manifest／源码／EXE／DLL 哈希）；包 workflow 重新钉到 `codex/18u-native-async-gates-20261102` 并传入该文件 | 包测试 2 项新增通过；workflow 契约测试通过（共 77 项） |

未做：实机 `--inspect-recovery`／`--snapshot-residue` 只读检查、CI 一次性注入失败场景、本机恢复执行。
原证据目录 `mycomputer-activation-71a4a2-v2-r1/` 未被触碰，仍无 `recovery-claim.json`。
