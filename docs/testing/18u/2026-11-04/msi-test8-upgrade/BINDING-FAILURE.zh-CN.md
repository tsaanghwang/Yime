# test.8：记事本绑定仍失败

日期：2026-11-04，UTC+08:00。用户在正常升级与界面准备后回复“失败”。本次失败记录与[安装成功记录](POST-REBOOT.zh-CN.md)分开；不把安装通过升级为普通应用输入通过。

**后续澄清：用户确认这次失败时未选择独立18u输入法；随后自行选择后可以绑定和输入。两条 `bound` 诊断已核实，见[最新反馈](BINDING-FOLLOWUP.zh-CN.md)。用户同时说明昨天测试时选过输入法；昨天根因不能套用今天的解释。下文保留首次取证时的观察与待确认事项，其“答复待补／停止复试”状态已由本次反馈接续。**

**后续澄清：用户确认这次失败时未选择独立18u输入法；随后自行选择后可以绑定和输入。两条 `bound` 诊断已核实，见[最新反馈](BINDING-FOLLOWUP.zh-CN.md)。用户同时说明昨天测试时选过输入法；昨天根因不能套用今天的解释。下文保留首次取证时的观察与待确认事项，其“答复待补／停止复试”状态已由本次反馈接续。**

## 失败现场

已按原始字节保存当前 test.8 的 8 条绑定诊断，时间为 **14:00:29.539 至 14:02:15.002**。8 条均为：

```text
build: 18u-test.8
stage: endpoint-connect-and-bind
error: endpoint-not-found (...): The system cannot find the file specified.
WindowClass: Notepad
FocusClass: RichEditD2DPT
```

目标进程均为 PID 11816，顶层线程为 TID 15244；正文焦点线程分别为 TID 11920（7 条）和 TID 9080（1 条）。这是已生成的全部本轮诊断，不声称只发生了一次用户点击，也不推断多条日志的触发方式。Codex 收到失败反馈后没有重新绑定、选择输入法或输入文字。

按当前代码，`endpoint-not-found` 来自打开指定 PID/TID 命名管道时的 `ERROR_FILE_NOT_FOUND`，早于服务端绑定请求、组码会话和正文编辑。因此本轮尚未证实进入组合、出现候选或提交中文，不能据此登记正文写入失败或正文为空。

## 后续只读观察

**14:06:02** 对同一记事本进程成功枚举 135 个模块，没有 Yime 模块；同次系统命名管道名称枚举未发现 `Yime18u.Frontend.v1.*`。未打开任何管道连接。该记事本为原生 x64，路径中版本为 `Microsoft.WindowsNotepad_11.2607.14.0_x64`。

安装描述符仍固定源码 `1060e7a787b395484cf51df47d3583b9a20bc620`，18u CLSID 的 64 位 COM 注册指向 `C:\Program Files\YimeCore 18u Touch\x64\YimeTextService18u.dll`，`ThreadingModel=Apartment`。此前完整载荷核验通过，不因本次失败重装或替换单独文件。

从 13:45 起查询 CodeIntegrity Operational，最多取最近 100 条，返回 0 条；该查询没有提供系统阻止加载的证据，也不能排除其他未记录的加载失败。前端当时已最小化，桌面工具未取得失败界面截图；没有为截图恢复窗口或再次触发绑定。

**观察发生在失败之后，不能证明失败瞬间的活动 profile 或 DLL 加载状态。** `endpoint-not-found` 及后续无模块／无端点，均不能单独证明用户没有选择独立18u输入法。已询问用户失败时的实际选择，仅请求回忆，不要求重新操作；答复待补。

## 源码证据与接续边界

- 前端 `go-backend/internal/tsffrontend/pipe_windows.go` 按正文 PID/TID 打开端点并分类原始 Win32 错误。本次尚未到服务端的 `focus-owner-mismatch`、`no-focused-document` 或 `no-top-context` 校验。
- `YimeTextServiceExperiment/TextService.cpp` 在专用 TIP 的 `ActivateEx` 完成既有事件观察／function provider 注册后创建 `TouchFrontendEndpoint`；构造失败会清理并返回 `E_FAIL`。本次没有失败当时的激活阶段回执，不能确定进入过哪一阶段。
- `RegistrationTool.cpp` 已列入 ImmersiveSupport 和 SystraySupport 类别，不能未经证据就以“缺少该类别”修复或扩大注册。
- 顶层与正文线程不同已由日志证实，但该差异本身不解释端点为什么缺席，也不能倒推首次 test.7 失败根因。下一步应核对宿主实际 profile 激活／DLL 加载链路及激活阶段错误，再决定修复；不得盲目改为连接顶层线程或绕过 TSF 身份校验。

本轮只采集失败证据和只读现场，没有代码修复、重新安装、默认输入法变更、自动重试、模拟中文输入或真人验收通过。Word 仍为历史“仅绑定报告、中文提交未确认”。

## 本机证据

原始文件保存在 `C:\dev\Yime\.generated\installed18u-test8-msi-upgrade-r2\evidence\binding-failure\`：8 个原始 `binding-*.json`、`capture.json` 和 `code-integrity.json`。原文件仍在 `%LOCALAPPDATA%\Yime18uTouch\Diagnostics\`。

[失败诊断摘要与哈希索引](binding-failure-summary.json)不含正文、窗口标题或账户信息。索引仅固定本机原始证据，不代表原始文件已有公开下载地址。
