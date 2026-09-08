# YimeCore 原生维护：typed outcome 与观察提供程序（2026-09-08）

本轮推进 YimeCore 维护源码与隔离取证能力；完整原生维护 harness、恢复验收及 L6 收尾仍未完成。
结构化复核记录：[2026-09-08-native-maintenance-outcome.json](../testing/l6/2026-09-08-native-maintenance-outcome.json)。

## 控制器结果必须同时绑定 JSON 和实际退出码

`tools/yimecore/manage-e6c-trial-install.ps1` 当前 SHA256 为 `9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d`。
新增可选 `-RehearsalAttemptId` / `-RehearsalOutcomePath`，仅接受显式 `NativeDesktopRehearsal` 的 Install；默认旧调用不产生 outcome。
输出以新建文件句柄绑定目标位置、attempt、发起 SID、控制器源码与包 manifest；提权明确传递参数，已有输出不能覆盖。
故障 Runtime 的 PID、创建时间和退出码来自保留的实际 `Process` 对象；自然退出 86 与控制器因超时而终止进程分开记录。
只有 x64、x86 两阶段均记录完成、自然退出 86、rollback procedure 和 frozen TIP finalizer 均完成，才产生预期故障回退结果。
`rollback_procedure_completed` 是控制流结果，仍需独立注册表、进程、归档与用户状态观察证明实际恢复；finalizer 失败不能发布回退完成结论。

| 实际控制器退出码 | JSON `outcome` / 含义 |
| --- | --- |
| 20 | `expected_fault_rollback_completed` |
| 21 | `unexpected_runtime_success_rollback_completed` |
| 22 | `rollback_failed` |
| 23 | `protection_finalizer_failed` |
| 24 | `unexpected_failure_rollback_completed`，包含非 86、控制器终止及缺少架构阶段等情况 |
| 25 | `preflight_or_staging_rejected` |
| 26 | 输出写入、持久化 Flush 或关闭失败；不得据 JSON 接受成功 |

未来消费端必须同时核实真实子进程退出码与 JSON `required_controller_exit_code`，并验证完整来源/attempt/阶段绑定。
即使 Flush 失败后留下 `outcome_complete=true` 的完整 JSON，实际退出 26 与 JSON 所需码不符，也必须拒绝。

## 本轮证据及覆盖范围

- typed outcome：PS5、PS7 各 **99/99**，原始结果为 `.tmp/native-rehearsal-outcome-20260908/{ps5-final,ps7-final}.json`，均绑定上述 9f69 源码。
  测试提取实际 source AST 事务和 terminal trap，以合成注册/回退函数驱动；真实自有子进程验证自然退出 86，以及 trap 保留实际退出 1、20–26。未完整调用控制器。
- 普通维护 **60**、desktop guard **41**、legacy rehearsal **5** 在最终 9f69 源码上双 shell 复跑通过；六组工具按 CI 实际调用方式的组合验证也全部通过。最终汇总与逐项记录由关联 JSON 固定至 `.tmp/native-maintenance-final-ci-20260908`，不以早期中间版本结果替代。
- 输入租约：PS5、PS7 各 **52/52** 合成回归；另 `fixed-ps5.json` / `fixed-ps7.json` 实际只读验证固定仓外公共归档的 **184 个文件句柄、33 个目录句柄**，见 `.tmp/local13-maintenance-input-tests-20260908/`。
  两次成员集合检查、路径/单链接/字节哈希与句柄保持通过；`continuous_membership_protection=false`，尚未证明完整执行区间的瞬时成员防护或独立原生系统可见性。
- 原生进程观察：PS5、PS7 各 **53/53**（47 项合成 + 6 项自有原生 helper 夹具），见 `.tmp/native-maintenance-processes-20260908/{ps5-final,ps7-final}.json`。
  提供 Open / AssertCurrent / Close / Get；持有句柄绑定 PID、创建时间、OS 路径、SID/elevation、架构、父子关系和公共映像哈希，拒绝复用、退出竞争、异路径与多实例；未枚举实际产品进程。
  `desktop_session_verified`、`startup_path_verified`、`runtime_ready_verified`、`continuous_monitoring`、`in_memory_code_identity_verified` 均为 false。
- 故障候选准备合同：新 guard allowlist 对 e65 与 9f69 两个受审来源分别准入，PS5/PS7 各 **57/57**；旧 local.12 准备合同各 **35/35**，见 `.tmp/local13-maintenance-guard-allowlist-20260908/`。来源准入不产生执行授权。
- 新鲜双产品来源基线为 **174 个声明路径 + 7 个锁定依赖、68/68、8 项 pending**；新工具已纳入来源闭包和双 shell CI。

## 现有归档没有升级为新控制器

固定公共归档中的普通/故障 local.13 候选仍带 `e65ea013b5c947c68604bc633e180563a811b856ed6c2aa7b09f3d5c291cd95a` 控制器。
普通 manifest 为 `dccbf6f7ef553bda1e20d7b8fa1659fe7e4b691d5d492b8210c9b7c606a7ced4`，故障 manifest 为 `5a9b274b9a3a07f847964bc0871b1ea15c3d4a9447e7fd7e3d86a424c5eea3b5`；既有字节身份和 guard 证据仍有效。
这两个旧候选没有本轮 typed outcome 功能。使用新协议前，必须从当前源码构建新独立候选、重新审查故障派生并归档；不能替换旧包控制器后继续沿用旧 manifest 或证据。

本轮没有执行实际安装、注册、卸载、rollback/restore，也没有完整运行源码控制器；未读取用户正文/设置/学习状态，未改变已安装 local.12 或默认输入法。
`source_readiness=false`、`ready_to_execute=false`、`execution_authorized=false`、`actual_native_rehearsal_passed=false`、`L6_sealed=false` 保持不变。
后续仍需分阶段整合输入租约、原生上下文/注册表/进程观察、严格 outcome 消费与动作编排，补齐独立 backup/restore 和用户状态边界证据，再在明确目标及授权窗口完成原生实际门禁。现有模块与合成通过不等于完整 harness 收尾。
