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

## 4. 未决问题（需用户决定）

1. 是否接受在 stage1 工具加入 `Unregister(CLSID)`＋四视图 `RegDeleteTree`
   的受门控清除？替代方案是只保留 `Unregister` 而把 HKCU 残留留给人工审阅。
2. 残留快照是否允许记录值名（不记值数据）？若否，仅记键路径与计数。
3. 新固定包是否沿用 `MyComputer activation x64 package (no registration)`
   workflow 产出，还是另开 recovery-only workflow。
