# S3c：同进程注册、一次编辑与撤销核验

2026-11-02。分支 `codex/18u-same-process-edit-20261102`，基线 `81a61011`。
影响范围是独立 18u 测试接线；保留基线中的 MyComputer 残留恢复修复。

## 本次结果

已完成最小接线源码：同一个受控进程持有注册事务、Windows 激活的
manager/context，以及 Broker 的目标 PID。它取得现存 provider，完成一次
选词、实际 applied 回执和独立正文读回，然后撤销注册并核验。
**Go 与 Windows 原生编译、注册执行及真实编辑均未验证。**
本次没有运行注册工具、恢复工具或真实 TSF 宿主，没有触发 CI 或修改已安装产品。

## 执行链与通过条件

新目标 `Yime18uRegisteredEditProbe` 复用 `RegistrationProbe.cpp` 的注册事务，
由默认关闭的 `YIME_TOUCH_REGISTERED_EDIT_PROBE` 控制，且要求独立 18u 产品构建。
现有注册工作流和 MyComputer stage-1 入口不会自动进入这条路径。

1. Go 控制器只启动一个注册/编辑宿主，Broker 的 `--tip-host-pid` 指向该进程。
2. 该宿主创建自己的窗口和文档，注册并请求进程范围的 profile 激活。
   它通过原 manager 的 `GetFunctionProvider` 取得 Windows 实际激活的实例，
   核对 provider CLSID、COM IUnknown 同一性和接口所属 DLL。
   不再调用类工厂创建替代 TIP，不直接调用 TIP 的 `ActivateEx`。
3. 先独立确认正文为空。输入码沿用受控 canonical ni3 分解与实验布局推导，
   从 Broker 候选中选择“你”一次，不重放选词。
4. E_PENDING 仅表示待完成。必须取得 `applied` 回执，并以独立只读
   `ITfEditSession` 读回精确的“你”；选词次数必须为一。
5. 断开路由并清理注册事务。持有的旧 provider 必须拒绝继续提供路由
   （`TF_E_DISCONNECTED`），随后独立检查注册表和 TSF API 中的身份缺席。
   只有这些条件全部成立，最终结果与退出码才能通过。

纯 C++ `RegisteredEditEvidence` 强制上述顺序，清理成功不能抹掉编辑失败。
Go/Python 结果解析器要求完整的 `18u-same-process-registered-edit-v1` 字段、
两个 PID 与实际宿主 PID 相同、恰好一次编辑以及全部通过条件。
Python 合成记录验证只报告一致性，不认证执行来源，也不证明原生执行。

## 后续原生验证入口（本轮未执行）

只面向明确指定的一次性隔离 Windows x64 环境；此入口不是 MyComputer 历史残留
恢复器，也不具备该专用入口的 DPAPI/机器绑定恢复协议。存在任何旧身份会拒绝开始。
需要先编译、固定并审阅同一版本的宿主、独立 DLL、Broker 和实验词典。

单独选择 `TestNativeSameProcessRegisteredEdit`，使用以下显式参数：

| 参数 | 含义 |
| --- | --- |
| `YIME_SAME_PROCESS_REGISTERED_EDIT_HOST` | 新宿主绝对路径 |
| `YIME_SAME_PROCESS_REGISTERED_EDIT_CONFIRM` | 精确值 `once-registered-edit` |
| `YIME_SAME_PROCESS_REGISTERED_EDIT_EVIDENCE` | 尚不存在的持久证据目录绝对路径，父目录须存在 |
| `YIME_FORMAL_18U_DLL` | 本版本独立 18u DLL 绝对路径 |
| `YIME_FORMAL_18U_BROKER` | 本版本 Broker 绝对路径 |
| `YIME_FORMAL_18U_DATA` | 配套实验词典目录绝对路径 |

证据目录独占创建，保留 `registration-ledger.json`、`host-stdout.jsonl` 和
`host-stderr.jsonl`；不使用测试自动删除的临时目录。目录存在即拒绝再次使用。
控制器出错时关闭输入让宿主清理；120 秒进程期限仍可终止卡住的进程。
超时或清理失败保留账本并报失败，不自动恢复、不重试注册、不重放编辑。
账本本身不等于清理成功证据，缺失结果也不能被解析为通过。

## 本轮验证范围

| 检查 | 结果 |
| --- | --- |
| `test_same_process_edit.py` | 8 项通过；合成证据及源码接线约束 |
| `test_mycomputer_activation_contract.py` | 8 项通过；保留现有注册恢复约束 |
| `test_workflow_contract.py` | 6 项通过；未扩展注册工作流 |
| `RegisteredEditEvidenceTests.cpp` | 便携 C++17 构建与运行通过；正常顺序、十类失败和清理前不得成功 |
| Go gofmt、vet、测试（2026-11-02 开发机补做） | `same_process_edit_windows_test.go` 仅有 gofmt 对齐差异，已修正；`go vet ./internal/touchhostbridge/...` 通过；`TestFormalSameProcessEvidence` 等 5 项证据测试通过；`TestNativeSameProcessRegisteredEdit` 未选择门时正确跳过 |
| MSVC x64 原生编译（2026-11-02 开发机补做） | `YIME_TOUCH_PRODUCT=ON`＋`YIME_TOUCH_REGISTERED_EDIT_PROBE=ON`＋`YIME_TOUCH_REGISTRATION_PROBE=ON`＋`YIME_MYCOMPUTER_ACTIVATION_STAGE1=ON`＋`YIME_TOUCH_REGISTERED_FORMAL_HOST=ON`：含 `Yime18uRegisteredEditProbe` 在内 21 个目标全部编译通过，/W4 无新增警告；MSVC 构建的 `RegisteredEditEvidenceTests`、`MyComputerActivationPolicyTests`、`YimeActivationFailureTraceTests`、`YimeDedicatedActivationTests`（固定 DLL）、`YimeDedicatedAsyncTests` 运行通过 |
| `Yime18uRegisteredEditProbe` 参数门 | 无参数或旧注册参数均返回 3，不进入 COM 初始化或任何写入 |
| Windows 注册、真实 TIP、Broker 编辑和撤销 | **未执行**；仅限明确授权的一次性隔离环境 |

便携测试只使用标准 C++，以现有 UCRT64 g++ 的进程局部 PATH 编译，
启用 `-std=c++17 -Wall -Wextra -Werror -pedantic -static`。
首次直接调用因编译器运行环境未完成构建；补齐该进程的工具目录后构建、运行通过。
未安装工具或修改全局 PATH。

开发机补做的 Go 与 MSVC 检查未发现源码缺陷；入口审阅确认：参数门先于 COM 初始化、
账本在注册前创建、Windows 激活实例按 provider CLSID／IUnknown 同一性／接口所属 DLL 三重核对、
选词恰好一次且失败不重放、清理后旧 provider 必须 `TF_E_DISCONNECTED`、缺席核验独立于清理结果，
对象析构顺序保证 DLL 模块最后释放。

## 接续说明（2026-11-02 开发机，供下一轮）

**分支状态**：`codex/18u-same-process-edit-20261102` 头 `294d4e0c`，基线 `81a61011`（即 PR #88 合并前的最后提交；main 现为 `733f66cb`，已含 #88/#89/#90）。与 main 的差异只有本分支两个提交，预计无冲突；开 PR 前可 `update-branch` 一次。工作树位于 `.worktrees\18u-activation-repair-20261102`（已关闭稀疏检出），构建缓存 `.generated\activation-repair`（MSVC x64，上述五个选项均为 ON）。

**已完成**：源码接线、Python/Go/MSVC 三层静态与隔离验证（见上表）。未开 PR、未触发任何一次性 CI、未注册、未运行 Broker 真实编辑。

**下一步（按顺序，均需用户明确授权才可执行第 3 步）**
1. 开 PR 到 main；CI 只会编译/运行隔离测试，不会进入 `YIME_TOUCH_REGISTERED_EDIT_PROBE` 真实路径。
2. 固定并审阅同一版本的四件套：`Yime18uRegisteredEditProbe.exe`、`YimeTextService18u.dll`、18u Broker、实验词典目录；记录各自 SHA-256。当前开发机 `.generated\activation-repair\Release` 下的产物只是本轮编译结果，不是固定交付。
3. 在明确指定的一次性隔离 Windows x64 环境（提升权限、线程与 TSF 当前语言均为 `0x0804`、18u 身份绝对缺席）单独选择 `TestNativeSameProcessRegisteredEdit`，按本文“后续原生验证入口”六个环境变量执行一次。证据目录独占创建、不可复用。
4. 结果解读：通过须同时满足 `appliedReceipt`、`readbackMatches`、`editAttempts==1`、`routeRevoked`、`cleanupVerified`，且 `registrationOwnerPID==brokerTargetPID==` 实际宿主 PID；任一缺失即失败。失败保留 `registration-ledger.json` 与两份 jsonl，不重试、不自动恢复。

**已知风险与处置**
- `edit-window-foreground-required`：同日注册宿主回归出现过同类前台抢占失败（首案例失败、单格复测通过）。真实运行若因此失败属 fail-closed，允许在确认清理与缺席核验通过后做一次单格复测；不要为此放宽前台要求。
- 本探针不是 MyComputer 历史残留恢复器，使用非 DPAPI 的 `registration-ledger.json`；若在 MyComputer 执行并失败留下写入，恢复需另行审阅（stage1 恢复协议不直接适用）。
- `YIME_TOUCH_REGISTERED_EDIT_PROBE` 默认 OFF 且要求 `YIME_TOUCH_PRODUCT`；现有注册工作流与 stage1 入口不会进入该路径，保持不变。

**不改变**：标准键位 YimeCore（开发机现装 `0.1.0-local.14-pr88`）、Rime/PIME、默认输入法、用户数据；MyComputer 下一次 18u 注册仍按 `S3C_NEXT_REGISTRATION_HANDOFF.zh-CN.md` 等待批准，与本分支的隔离环境验证是两件事。

本补丁只准备一次成功编辑的闭环，不继承历史替身测试的原生结论，也不覆盖原十场景、
Word/Edge、ARM64 或物理触控验收。下一步仍是编译新目标后进行受控原生实测。
