# S3c：异步 Broker 通信与失焦撤销源码交接

2026-11-02。分支 `codex/18u-async-focus-20261102`，基于已发布的
`bba5e96fe84a2d5b4f75fd5ef7b41d2a8e00e6ca`。影响独立 18u DLL、测试适配器，
以及共用管道帧函数的可选取消参数；标准产品调用保持原参数及同步行为。

## 已修复的源码问题

原专用路由在 TIP 的 STA 上等待管道连接、open/action/complete 响应。
等待期间不能正常处理失焦通知；连接时的绑定也只在 open 返回后成立。
正文已经写入但 complete 确认丢失时，原调用仅返回一般错误。

现在：

- 管道打开、进程身份核验和帧通信由后台工作线程执行。工作线程不持有 COM、
  文档、窗口对象；原 STA 正常处理消息和 TSF 焦点通知。
- 绑定在等待 open 前捕获。失焦、context 替换、断开都会撤销 epoch；
  切走再切回同一对象不能恢复旧操作。正常结果与实际写入分别核验绑定。
- 取消只发信号，工作线程用 `CancelIoEx` 后等待该 I/O 真正完成，
  再释放缓冲区和句柄；不能从 STA 关闭仍有 I/O 的句柄。
  工作线程持有独立 DLL 模块引用，释放 C++ 状态后通过
  `FreeLibraryAndExitThread` 退出，避免停用后线程执行已卸载的代码。
- 文档编辑使用 `TF_ES_ASYNC`。只有实际 `DoEditSession` 的执行检查和完成
  回调均成功，才发送 applied。排队本身不算写入；旧请求的 context、
  composition 槽位和执行 guard 在回调释放前继续存活。
- 一次请求只允许一个未完成操作。旧编辑还排队时禁止重新绑定；
  撤销后的旧回调拒绝写入，新一代连接不能复用旧回调。
- 已写入但确认丢失返回失败 HRESULT，同时提供
  `outcome=unknown / localEditOutcome=applied / retryAllowed=false`。
  会话断开，重复 Action 被拒绝；绝不据此重放或撤回已确认正文。

## 私有接口迁移

`IDedicatedTouchService` 已换为 v2 IID
`E4647B73-53B6-4F62-AAB9-55D28740C465`。旧同步 IID 明确拒绝，
产品 CLSID/Profile、布局和字典身份保持不变。DLL 与调用程序必须一起重编译。

调用方只能启动 Connect/Action **一次**。接受后返回 `E_PENDING`；
随后在拥有 TIP 的 STA 上正常泵消息并调用 `PollDedicated`。
第二个启动请求返回 `ERROR_BUSY`；Poll 返回 `S_FALSE` 表示没有待消费操作，
不是成功结果。终态只消费一次。停用、调用方超时或丢失终态均不授权重放；
可先断开，再由用户明确进行新的输入。

直载与已注册 formal host 都更新为此调用顺序，超时会断开并失败，
不会自动重新启动请求。本批只编译这两个程序，没有执行它们。

## 本地验证

Windows x64、MSVC 19.44.35225、SDK 10.0.26100.0。

| 检查 | 结果与证据范围 |
| --- | --- |
| 新专用 DLL、标准 DLL、两个 formal host、隔离测试编译 | 成功；保留原先未使用参数/不可达代码警告，不宣称无警告构建 |
| `YimeDedicatedAsyncTests` | 11 场景通过，实际跨进程 Win32 命名管道 + 生产 route/编辑会话代码 + 内存 TSF 替身 |
| `YimeDedicatedActivationTests <DLL绝对路径>` | 实际 DLL 加载及替身 TSF 生命周期通过，包含旧同步 IID 拒绝 |
| `YimeFocusCancellationTests` | 原 36 项检查、0 失败 |
| Go formal 隐私摘要测试 | `TestFormalFailureSummaryPrivacy`、`TestFormalActivationProbePrivacy` 通过；未启用 native host |
| CI 调度约束 / 独立产品身份测试 | 6 项 / 3 项通过，未修改一次性注册调度门 |

11 场景包括：等待 open 时失焦往返、等待 action 时失焦往返、
context 替换、排队到实际写入、写入后丢失 ACK、写入失败、排队请求失败、
旧回调撤销后新一代连接、释放 route 后迟到回调、取消中释放 route、
共用帧 API 不传取消句柄的兼容调用。
fixture Broker 明确观察 complete 的 outcome；文本和写入次数由内存文档独立核对。
这些是原生代码的隔离回归，**不是 Windows 已注册 TIP 或真实文档的端到端验收**。

新增 `.github/workflows/touch-bridge-async-contract.yml` 自动构建与运行上述
隔离原生测试；formal host 仅编译。新 workflow 不执行注册、profile 激活、
安装或真实宿主，不改原注册任务的授权与一次执行限制。
此交接记录的是本地通过，不代替尚未产生的远端 CI 结果。

## 仍未闭环

1. 将“已注册且保持激活的独立 profile”与原七场景串入同一受控任务，
   验证实际 Windows 激活实例到真实 Broker/正文的整条链路。
   历史 `AdviseKeyEventSink / 0x80070057` 失败没有因此宣布解决。
2. 在明确获准的隔离注册环境中，增加真实宿主的等待中失焦及写后断线验证。
   `unknownAfterPendingEditCovered=false` 仍如实保留在旧正式结果中。
3. S3c.2 原可见 UI 接入 v2 异步路由，以及 Word/Edge 和物理指/笔验收。

未运行本机注册/安装、真实 TSF 激活或物理测试；未改变默认输入法、用户数据、
18u 几何、标准布局分支或原工作区的未提交交接文件。
