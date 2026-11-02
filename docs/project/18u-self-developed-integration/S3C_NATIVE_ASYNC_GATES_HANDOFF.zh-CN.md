# S3c：正式异步负例、证据校验及本机失败定位

2026-11-02。分支 `codex/18u-native-async-gates-20261102`，基于
`d1ab86509b063640be841af25968b31632ae8ac7`。本批完成本地源码和隔离测试。
未推送、未触发远端任务、未注册、未恢复系统项。

## 正式宿主测试补齐

实际 `Formal18uHost.cpp` 的直载与已注册两个目标共用新增场景：

| 场景 | 实际执行时必须证明 |
| --- | --- |
| `pending-focus-away-back` | 选择操作已返回 E_PENDING，再把 TSF 文档焦点切走并切回；旧操作失败，两个自建文档均无正文 |
| `pending-deactivated` | 选择操作已返回 E_PENDING，再停用实际 TIP；旧操作失败，没有正文写入 |
| `disconnect-after-edit` | 宿主独立读回“你”后，在下一次 Poll 发送完成请求前暂停；Go 控制端只停止自己创建的 Broker 子进程并等待退出；随后恢复 Poll，要求 unknown、localEditOutcome=applied、retryAllowed=false；再请求被拒绝，正文仍只有一次 |

最后一个场景证明的故障位置是**真实写入后、完成上报前断线**，不是
Broker 已记录 applied 后仅 ACK 丢失。后一故障位置仍由上一批真实管道、
替身 TSF 的隔离回归覆盖，不能混称真实注册态证明。

正式场景从七项增至十项。三个新执行标记在结果中必须与场景匹配。
`unknownAfterPendingEditCovered` 仅在新写后断线场景经过实际读回和控制屏障后
置 true，旧场景保持 false。历史结果不改写。

Go 校验原先仅依靠 bool 零值，某些缺失字段可能被当成 false 接受。
现要求完整精确字段集，拒绝缺失、null、重复键、大小写替换、额外字段、
尾随数据、错误类型和相互矛盾的标记；直载与注册态证据不能互相替代。
控制端先严格验证写入屏障，再停止自己的 Broker；没有屏障就失败，不补发动作。

现有 formal workflow 的必过清单增加三个场景和证据校验测试，原激活门与
失败行为保留。异步隔离 workflow 只运行纯结果校验和替身测试，不启动正式宿主。
这些新场景在本机**只编译，未实际运行**，没有跨过注册态验收门。

## 最新本机记录揭示的未闭环事项

读取的历史证据为原工作区
`mycomputer-activation-71a4a2-v2-r1/registration-evidence/`，
绑定源提交 `71a4a252641159753b0eff41b871254233c6efd2`：

- 注册执行记录为 failed-or-inconclusive，子进程退出码 1；
  writesStarted=true，cleanupVerified=false，最终 stage=existing-tip-identity。
- 固定检查原独立 18u CLSID 的注册表分支，HKLM/HKCU 的 32/64 位视图均可见
  TIP 残留。HKLM 仍有 Category 和空的 0x00000804 LanguageProfile 分支；
  HKCU 仍有该专用 profile 的叶节点。此观察不能证明它当前被激活。
- 先校验原 EXE 与账本 SHA-256，再只执行原包的 `--inspect-recovery`。
  返回 exit 0、status=verified、bindingVerified=true、ownerDeadVerified=true、
  ownedScopeVerified=true、recoveryRequired=true、cleanupVerified=false。
  stderr 为空，账本检查前后哈希一致。
- 没有执行 `--recover`、`--register-once`，没有创建恢复 claim，
  没有修改账本、原包或系统注册表。

这些结果说明：**“本机那次注册已经完成并清理”不能成立**。原始记录中
actualDllActivationVerified=false、profileActivationApiVerified=false，
且 stderr 为空，不能从最终 cleanup 阶段反推出最初是哪一步失败。

源码另可确认：本机分支没有调用一次性 CI 分支用于清除服务残留的
`ITfInputProcessorProfiles::Unregister`；该差异与残留现象相符，
但本批未尝试扩大清理范围或修改原恢复程序，不能宣布清理根因已通过实机验证。
后续需专门审查幂等清理与所有权保护，形成固定可审阅的恢复交付后，
再按明确的系统恢复授权执行。当前不应重复注册来覆盖这些残留。

## 已修复的诊断遮蔽

`MyComputerActivationMain.h` 原来会在清理失败时覆盖 report 的 stage/code。
现在清理前先把原失败写入固定结构的 stderr 记录，清理失败另写一条 cleanup
记录。只包含 schema、phase、源码固定 stage、数值 code，不记录私有路径、
正文、账本内容或完整报告。成功时无新增 stderr，原唯一 DLL 激活 marker
和严格成功校验保持不变；失败不会因增加诊断而变成通过。
记录函数保证不抛出异常，日志不可写或分配失败不能中断清理路径。

旧包没有这些记录，旧失败原因无法补造。此修复用于下一份经批准的固定交付。

## 本地验证

| 项目 | 本次结果 |
| --- | --- |
| 两个 formal host 目标 | MSVC x64 编译成功，未执行 |
| 本机阶段工具 | 修改后的目标编译成功，未运行新工具；保留原有 C4018 警告 |
| `YimeActivationFailureTraceTests` | 通过：最初错误跨清理保留、仅清理失败、隐私字段排除、成功无噪声 |
| `go test ./internal/touchhostbridge -run "^TestFormal" -count=1` | 四项测试通过，含 10 场景×两种激活身份的证据拒绝测试；无原生宿主启动 |
| `go vet ./internal/touchhostbridge` | 通过 |
| `test_mycomputer_activation_contract.py` | 8 项通过，保留所有权、默认只读和恢复边界 |
| `test_local_activation_evidence.py` | 5 项通过，成功仍要求唯一真实 DLL marker |
| `test_workflow_contract.py` | 6 项通过，未改变一次性执行门 |
| 两份 workflow YAML / `git diff --check` | 通过 |

可见 UI 仍缺经认证的前端与 TIP 跨连接路由，不能用演示宿主或仅替换接口冒充
S3c.2 完成。真实注册态十场景、可见 UI 接线、Word/Edge 和物理指/笔验收仍待完成。
