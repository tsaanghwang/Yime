# TSF 退格逐步诊断与离线回归

本轮仅影响独立 18u TIP 的诊断和内存测试。基线为 main
`45be140e528c4a4e818a2bca6717f187a0fcd2b5`，分支为
`codex/tsf-edit-diagnostics-20261106`。用户已批准默认关闭、不含正文的诊断和离线回归；
未授权安装或真实宿主测试。本轮不改变删除语义、焦点判断或 v2 协议。

## 开关和输出

- 仅当装载 TIP 的**宿主进程环境**中 `YIME_TOUCH_FRONTEND_EDIT_DIAGNOSTICS` 精确为 `1`，
  才在 endpoint 创建时启用。缺省、空值、`0`、`true`、`11` 均关闭。读取开关不改变环境或注册表。
- 输出到该宿主的 `OutputDebugStringA` 调试通道，schema 为
  `18u-touch-frontend-edit-diagnostic-v1`。它不是触屏程序的绑定 JSON 文件，也不是 v2 回复。
  没有调试通道接收器时不会自动保存文件或回退到 stdout/stderr。
- 每条小于 1536 字节；同一 endpoint 的新旧 lease 共用 1 MiB 预算，重新绑定不重置预算。
  超出预算或输出失败后丢弃记录，不重试、不改变编辑结果；保存并恢复线程 `GetLastError`。
- 字符串仅允许固定 schema、stage、action 名称。没有正文、组码、候选、UTF-16 值、文本哈希、
  插入文本长度、窗口标题、路径、请求原文或异常文字。数字字段只包含状态、返回码和短范围探测量。
- 诊断只利用业务代码本来取得的结果，不增加 TSF/选区/文字/焦点查询。
  正常轮询不产生日志；排队编辑被既有轮询拒绝时只输出拒绝编号。

后续如需实机采集，须另行批准固定包、宿主和调试接收范围；只给触屏前端设置环境并不能保证
宿主 DLL 启用诊断。调试输出会增加运行时间开销，应与关闭诊断的结果区分。
本轮没有设置任何用户/系统环境变量，没有启动调试接收器或真实宿主。

## 字段解释

共同字段为 `tickMs`（系统启动以来的毫秒）、`process/thread`（输出进程/线程）、
`instanceId`（本进程内 endpoint 编号）、`sequence`、`generation`（绑定世代）、`action/extend`。
它们不替代精确包身份，也不把实际 activationId 或 COM 指针写入日志。
`hr` 是无符号 32 位 HRESULT 原始位值，只有 `hrKnown=true` 时才可解释为已取得的结果；
`S_OK=0` 是有效结果，不能与未取得混同。各 stage 未使用的数字字段是占位值。
除另有说明，API 输出参数仅在该 API 成功时解释；失败时可能是初始化值或前一步保留值，
不能当作实际移动量、读取数量或其他有效输出。`attempted=true` 仅表示通过 lease 校验后进入
`apply`，不证明已调用 SetText 或改变正文；`completed` 也可能由请求层失败处理置为 true。

| stage | 额外字段含义 |
| --- | --- |
| Begin | `flags` 为当前 endpoint 世代；共同 `generation` 仍为原绑定世代 |
| Foreground | `requested/actual` 为绑定/当前焦点线程，`count` 为当前焦点进程；`flags` 位 1/2/4 分别表示前台窗口、非空焦点窗口、根窗口匹配；`value/value2` 为 lease 活跃、回调线程匹配 |
| Eligibility | `flags` 位 1/2/4 为 alive/keyFocused/threadFocused |
| ThreadFocus | 原始查询 HRESULT；`value` 为 IsThreadFocus 的 BOOL 输出（失败时不作有效结果） |
| ActiveProfile | 原始查询 HRESULT；`flags` 为 profile type，`value/value2` 为 CLSID/profile 匹配结果 |
| Document / Context | 原始查询 HRESULT；`value` 为非空，`value2` 为与绑定对象一致 |
| Status | 原始 GetStatus HRESULT；`flags/count` 为 dynamic/static flags |
| Lease | `value` 为接受与否；`value2` 为下表拒绝编号；无 API HRESULT。轮询拒绝时 `flags` 为撤销前世代 |
| RequestEditSession | `hr` 为外层返回值；`actual=1` 才表示 `requested` 是有效的 phrSession 位值；外层非 S_OK 时二者写 0，不把初始化值冒充宿主返回。`flags` 为请求标志，`value/value2` 为 attempted/completed |
| Callback | 已进入实际 DoEditSession，尚无完成 HRESULT |
| GetSelection | 原始 HRESULT；`requested=1`、`actual` 为 range 非空、`count` 为 fetched；`flags/value` 为 ase/fInterimChar |
| IsEmpty | 原始 HRESULT；`value` 为既有选区的空范围判断 |
| Clone / ExtendRange | 原始 HRESULT |
| ProbeShift / StepShift | 原始 HRESULT；`requested/actual` 为请求/实际移动量。StepShift 的 `count` 为探针读取数，`value=1` 表示现有算法选了双 UTF-16 单元宽度 |
| ProbeText | 原始 HRESULT；`requested=2`、`count` 为实际读出单元数；不记录字符内容 |
| SetText | 原始 HRESULT；`value=1` 为删除，0 为非空替换/插入 |
| Collapse / SetSelection | 原始 HRESULT；分别在 `value/flags` 中记录 anchor/active selection end |
| Complete | 实际 DoEditSession 最终返回值，`value/value2` 为 attempted/completed |
| Reply | `count=1/2/3` 对应 applied/unknown/failed，`value` 为 ok，`value2=false` 表示不重试；`flags` 为回复世代。仅本请求进入编辑调度后才引用 lease outcome；它可能是请求层错误或本地 E_UNEXPECTED，不能一律当回调返回 |
| Timeout / Disconnect | 本请求的 attempted/completed；只有已完成且确属本请求时才提供 outcome，未完成不推断成功或失败 |

拒绝编号固定：0=通过，-1=未分类；1=activation-ended，2=key-focus-missing，
3=thread-focus-missing，4=thread-focus-unavailable，5=profile-unavailable，6=profile-inactive，
7=lease-inactive，8=callback-thread-mismatch，9=foreground-changed，10=focus-changed，
11=focus-owner-mismatch，12=no-focused-document，13=document-changed，14=no-top-context，
15=context-changed，16=context-status-unavailable，17=context-read-only，18=context-loading，
19=generation-exhausted，20=stale-activation，21=stale-generation。

同步编辑时 Callback/Complete 可以先于 RequestEditSession 的**返回记录**，这是合法时序。
迟到回调仍关联原 lease 的 sequence/generation；旧回调不会因重新绑定而恢复写权限。

## 观察边界

- 没有新增 ACP 端点查询、删除后读回或最终范围查询；最终控件文字仍需人工观察。
- 端点只知道 TSF action，不知道操作者点的是主区 Back Space 还是顶栏退格；入口须人工记录。
- 非编辑期间已被轮询撤销的 lease，下一编辑可能只显示 stale-generation；本记录不能恢复更早的状态。
  排队编辑的轮询拒绝保留固定原因，但不重查原始 GetStatus HRESULT。
- 预算耗尽、接收器未运行、宿主提前退出都可能缺少后续记录；无日志不等于无操作。
- 零移动、探针短读时仍沿用当前 width/SetText 路径。本轮新增的是观测和 BMP 行为刻画，
  **不是**修复区域边界或不完整代理对，也不能据此认定 VS Code 根因。
- `applied` 仍是现有协议的完成结果；合法边界或零移动后的空写入可能不改变正文。
  写入成功后 Collapse/SetSelection 失败仍为 unknown，不回滚、不补发。

## 离线验证

使用独立输出目录 `.generated/tsf-edit-diagnostics-20261106`，仅配置子项目：

```text
cmake -S YimeTextServiceExperiment -B .generated/tsf-edit-diagnostics-20261106 -G "Visual Studio 17 2022" -A x64 -DYIME_LOCAL_PRODUCT=OFF -DYIME_TOUCH_PRODUCT=ON -DYIME_TOUCH_FRONTEND=ON -DYIME_TOUCH_REGISTERED_FORMAL_HOST=OFF -DYIME_TOUCH_REGISTRATION_PROBE=OFF -DYIME_18U_PRODUCT_REGISTRATION=OFF -DYIME_TOUCH_FRONTEND_NATIVE_HOST_PHASE_A=OFF
cmake --build .generated/tsf-edit-diagnostics-20261106 --config Release --target YimeTouchFrontendEditTests YimeTextService18u --parallel 4
ctest --test-dir .generated/tsf-edit-diagnostics-20261106 -C Release -R "^YimeTouchFrontendEditTests$" --output-on-failure
go -C go-backend test ./internal/tsffrontend -count=1
```

只执行内存 TSF 和假传输测试，不加载编译出的产品 DLL，不运行 native/formal/registered host。
回归包含正常 Unicode/边界/导航、选区退格、GetSelection 失败/零项/空指针、BMP 零移/短移/短读、
范围与读取错误、SetText 拒绝、写后 Collapse/SetSelection 失败、请求/同步/异步完成、
失焦撤销、旧身份和 unknown 禁止重放，以及默认关闭、精确开关、字段脱敏、预算、异常 sink、
上一请求结果不串入新请求、v2 回复精确形状。

初始提交的执行结果及源文件/日志哈希见同目录 `validation.json`。日志保留原始字节，目录内
`.gitattributes` 仅将这些日志按二进制证据保存，避免换行转换；源文件哈希按 UTF-8/LF 计算。所有结果仅为源码和离线证据，
不代表 VS Code、记事本、指笔或已安装产品验收。本轮没有生成可安装交付包。

## PR #118 审查修正（2026-11-07）

Copilot 指出新增的请求返回诊断会读取成员 `lease`，而宿主 `RequestEditSession`
可能重入超时或断开处理，使该成员被清空；即使关闭诊断，构造观测参数时仍会解引用。
本次用局部共享引用保留原请求 lease，诊断和完成记账只使用该对象，避免空指针以及旧结果
写入重连后的新 lease。不会将旧 lease 恢复到 endpoint，不恢复编辑权限，不补发请求。

新增内存回归覆盖请求返回前关闭、超时和重新绑定，区分排队、同步完成与请求失败，
并分别检查诊断关闭/开启。已执行的同步删除不会回滚；被撤销的迟到回调仍拒绝写入，
旧请求不能改写新绑定的状态或回复。原始证据保持不变；本次构建、精确 CTest
及源文件哈希另存于 `review-fix-20261107/validation.json`。
