# S3c：一次性隔离注册门槛

本文件说明一次性 Windows CI 验证，不是用户电脑部署指南。当前仅准备源码与工作流；实际结果以对应固定提交、run ID 和证据 artifact 为准。

## 授权与边界

用户已单独授权 **一次** 隔离 Windows CI 管理员权限验证：仅独立“18u 触摸” COM、中文输入法条目、键盘类别；在自有测试进程激活，撤销本次新增项并核验清理。不是“仅当前用户目录写入”。不得触碰其他输入法、改变默认输入法或全局语言，不注册标准产品，不使用用户机器。

独立入口 `Yime18uRegistrationProbe --dll <独立 DLL 绝对路径> --ledger <新建绝对路径/registration-ledger.json>`，仅由显式 `YIME_TOUCH_REGISTRATION_PROBE=ON` 构建。本次是 **profile-activation-only**：真实进程内 profile 激活及活动身份核对，**不验证**专用 Broker、正文提交、原七场景、物理触控或用户宿主兼容性。不得以此代替 S3c 端到端验收。

## 固定身份与前轮证据

- COM CLSID：`{6DFACE1F-562E-4773-A9D6-D5753A314711}`；profile：`{1BD904AC-3194-4419-B70A-5574100F18B3}`；语言 `0x0804`。
- 仅 HKLM 64 位 `SOFTWARE\Classes\CLSID\{上述CLSID}\InprocServer32` 的本次 DLL 路径与 Apartment；profile/category 通过 Windows TSF API 处理，仅 keyboard 类别、owner/item 为该 CLSID。不声称所有注册都在 HKCU。
- 注册前检查 HKLM/HKCU 两个视图的 COM/CTF 身份及 TSF API；CTF 值含同身份也拒绝。预存或不确定即停，不预删。DIRECT_TEST 环境绕过开关非空也拒绝。
- 恢复仅依据本轮持久账本且原进程已结束；COM 新建后 owned 尚未成功落盘的崩溃窗口为未知，拒绝猜测所有权删除，保留失败和残留证据。
- 前轮 `5b33561d9c501993a8b830e8fb61c582eee13c6e`：[Build 41318090060](https://github.com/tsaanghwang/Yime/actions/runs/41318090060) 全部成功，含 Windows race；[未注册原生 41318090071](https://github.com/tsaanghwang/Yime/actions/runs/41318090071) 新七项确切停在 AdviseKeyEventSink/E_INVALIDARG，旧10项、OS认证和ABI通过。证据artifact13088272055 SHA256 `a9b2efef6d9d21b3d063389c673bd499c0ec45daedd48b9884871b0c1fae3cac` 已下载核验。当前新增片段不是把该失败改标通过。

## 派发条件

- 入口为已存在的 `Build`（`.github/workflows/ci.yaml`）之 `workflow_dispatch`，新增默认空的 `confirm_18u_registration` 输入；独立 `.github/workflows/touch-bridge-registered-probe.yml` **只有 workflow_call**。两层都检查事件、分支、确认、expected SHA 与首次 attempt，push/PR 不触发注册。
- 仅 `codex/18u-formal-tip-s3c-20261101`，输入 `confirm_18u_registration` 精确为 `once-18u-registration`。
- `run_attempt == 1`，Actions 的 rerun 不再次执行；再次新派发也需要重新确认授权，不能把输入字符串当永久许可。
- 使用隔离的 `windows-latest` x64 托管 runner，`contents: read`，不配置 secrets、不保留 checkout 凭据。
- 编译独立 DLL 与一个 probe EXE；**只调用注册模式一次**（180 秒上限），不遍历七场景注册，不自动重试。finally 单次 `--cleanup-only --ledger <同一账本>`（60 秒）仅恢复清理，随后单次 `--verify-absent`（60 秒）独立只读核验，后二者不得注册。

原生前置要求当前线程键盘语言及 TSF 当前语言均为 `0804`、进程已提升，身份不存在且相关查询确定；不满足即 **no-write blocked**。工作流不得为满足前置而改变语言、安装语言包、启用其他输入法或扩大权限范围。

## 结果与停止规则

- `exit 0 / pass`：只有结构化结果同时确认 `writesStarted=true`、`cleanupVerified=true`、五项操作账本均为 true、两项语言码均为 2052、`stage=completed/code=0`，且 stderr 恰好一条真实 DLL 成功走完 ActivateEx 的固定 `registered-probe/actual-activate-success` 标记，并且独立 cleanup-only 与 verify-absent 均成功，工作流才通过。仅 GetActiveProfile 返回成功不足以通过。
- `exit 3 / blocked`：前置阻断且 `writesStarted=false`、五项操作账本均为 false；保留证据，工作流失败，**不是跳过后绿色通过**。
- 其他退出、未知/不匹配结果、激活失败或清理失败：失败并停止，不自动第二次运行。
- `always()` 上传构建日志、固定提交/run ID、EXE/DLL SHA-256、原生结构化结果及工作流判定。
- 禁止因失败改默认输入法、切换全局语言、放宽身份/前台/焦点 guard 或使用通用注册工具绕过入口。
- 正常退出由原生入口负责撤销与核验；每步持久账本随 artifact 保存。注册进程超时由 subprocess 仅终止并等待该子进程，之后才执行 cleanup-only。缺失/损坏账本或原进程状态未知不能视为 no-write 或擅自删除。清理干净也不能补造激活成功。强制取消、runner 丢失或超时不能宣称清理成功；必须作为结果不确定报告，不能据此重试。托管 runner 的销毁不替代程序清理证明。

## 当前准备状态

Linux 仅能进行工作流语法/静态检查；MSVC 编译、管理员注册、当前语言前置及清理均必须由本次获准的独立 CI 提供证据。在父级审阅及发布前，不派发该工作流。

## 派发交付与当前限制

新文件本身不提供 Run workflow 按钮；改用默认分支已存在的 `Build` workflow 名称，将执行 ref 指向本开发分支。此处只在开发分支新增可选输入及一个受限 reusable job，原 Build jobs、依赖和权限不变；不改 main。

发布后，先核对父级交付的固定 HEAD SHA 与远端分支完全一致，再由用户已有登录态的 `gh` 执行 **一次**：

```sh
gh workflow run ci.yaml --repo tsaanghwang/Yime --ref codex/18u-formal-tip-s3c-20261101 -f confirm_18u_registration=once-18u-registration -f expected_18u_source_sha=<父级交付的40位固定SHA>
```

上述 SHA 占位符必须替换为父级最终交付的 40 位提交值，不要原样执行。两层 job 都要求它严格等于实际 `github.sha`，分支推进时注册 job 不执行。还须核对新 run 的 head SHA 正是审阅/交付版本；不一致就不追加派发，应先报告。若 API 拒绝输入、未产生 run 或状态不确定，先核对实际 run，不重试注册，不改 push 触发，不合并默认分支绕过。

现有云连接器没有 dispatch 能力，云端 `gh` 未登录，因此不能声称我们已经派发或已经验证该入口。命令是给用户已有授权登录环境的交付步骤，不要求提供 token。一次 run 会同时启动原 Build jobs，但只有精确确认值才启用新注册 job。
