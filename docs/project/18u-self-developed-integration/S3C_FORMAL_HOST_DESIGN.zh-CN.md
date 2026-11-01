# 18u正式宿主接入：最短路径与信任边界（审阅草案）

2026-11-01。此文保存设计审阅结论。用户随后确认独立18u条目与首片x64/CN-variable；S3c本地实施已获授权，发布、CI、注册及用户机操作仍另行确认。实际实现范围与验证以同目录S3C_VALIDATION为准。
固定源码：S3b `3f6d535e3e35153362c896ac3922d99186b1b487`（本地同树 `6f2016d2716409550ec080c11784f02c5039dd11`）。S3b CI 41311734784 已通过，但只是无注册隔离开发演示；本草案不是扩大其使用授权。

## 决策摘要

**推荐不再增加演示层，直接把下一实施里程碑定为“独立18u产品身份的真实TextService/Broker接线”。** 第一关仍是单x64自有宿主，但必须加载实际产品TextService，之后独立批准的干净Windows测试环境注册/显式选择该profile；通过后再首台用户x64及Word/Edge小范围验收。不能继续把自建text store成功当作已安装正式输入法。

已由用户确认的产品选择：**18u作为独立可选择的输入法条目，与现有标准版并存**，工作显示名暂拟“音元拼音·18u触摸”。显示名可后定；独立产品/CLSID/profile/数据命名空间与安装卸载所有权已在tools/yimecore/18u-touch-product.json冻结为独立开发身份，尚不可安装。不修改当前“音元拼音”或Rime身份，不设默认输入法。首个正式切片已确认暂只接CN variable及其触摸操作；不把此限制当作标准版功能删除，其他模式和标准对应触摸仍保留路线。

无需让用户决定pipe字段或线程细节。产品选择已确认；仍需要新确认的是代码发布/CI，以及后续安装注册地点和操作范围；此次不请求立即安装。

## 1. 现有实现与真正断点

以下路径均相对固定源码，行号便于定位，不是仅靠文件名推断。

| 已存在 | 证据 | 尚未得到的能力 |
| --- | --- | --- |
| 正式TSF激活/停用、键事件和失焦取消 | `YimeTextServiceExperiment/TextService.cpp:273–435`；真实键输入到`ApplyBrokerUpdateToContext`约612 | 没有来自18u前端的可信激活路由和专用会话绑定 |
| 正式Broker引擎会话、mode与sequence | `BrokerClient.cpp:122–168`；`go-backend/input_methods/yime/yimebroker/protocol.go:17–83` | v1 open不带profile/布局/字典/focus epoch，mutationID是引擎选词幂等而非宿主落地确认，不是18u协议；严格解码会拒绝任意附加字段 |
| 本地named pipe安全基础 | `.../yimebroker/named_pipe_windows.go:52–125,272–361` | 已有current-user SID ACL+SYSTEM、拒绝远端、first-instance保留、由管道取得PID/token SID；不等于用户登录会话、应用角色、可信前端/服务身份及活动context证明 |
| 连接/会话隔离 | `.../yimebroker/dispatcher.go:241–258`及`stdio.go:18–30` | 现有连接归属和序列不可丢；还缺前端与激活TIP跨两条连接的授权路由 |
| 真实TSF写入及可选完成/执行时guard | `CompositionEditSession.h:21–44`、`.cpp:69–107` | S2/S3证明了复用能力；正式TextService目前调用不能自动获得新增路由的epoch/提交回执合同 |
| 标准产品身份生成及维护工具 | `tools/yimecore/local-product.json`；`CMakeLists.txt:20–52`；`installer/simple/Product.psm1:4–9` | 当前只支持既有产品身份；18u不能修改旧JSON或冒用旧GUID，installer尚不认识第三产品 |
| 专用实验资源与真实YimeCore | `go-backend/internal/keyboardlab/runtime.go`；`internal/touchhostbridge` | 可复用验证与会话算法，不可把实验码直接传给正式标准索引；S3b前端自持引擎须迁到新路由唯一权威侧 |

固定源码浏览根： https://github.com/tsaanghwang/Yime/tree/3f6d535e3e35153362c896ac3922d99186b1b487

## 2. 只比较必要的两条路线

A. **独立18u profile和产品描述，复用TSF/Broker源码（推荐）**。用户清晰选择专用方案；标准版及Rime原样保持；独立索引、学习状态、卸载边界。成本是增加第三产品描述、构建/注册载荷和新路由，不是复制一套算法。

B. 在标准profile内加“标准/18u”运行时切换。少一个系统条目，但每个宿主会话须额外处理投影切换、索引/学习隔离和恢复规则，容易误把标准键击送进专用索引，也改变既有产品行为。当前不推荐。

不考虑把S3b演示长期当产品、不用SendInput替代正式接入、不做通用任意程序文本注入平台。

## 3. 推荐最终数据流与所有权

```text
用户在目标宿主显式选择18u profile
  -> Windows正常激活该宿主线程内18u TextService
  -> 经认证的产品Broker连接，发布短期活动context租约
18u触摸前端（不抢目标焦点）
  -> 专用受限前端入口 -> Broker唯一18u会话/真实引擎
  -> 快照revision+候选ID -> 提交意图
  -> 已绑定TIP连接 -> TIP拥有线程 -> RequestEditSession
  -> DoEditSession执行时重新检查 -> 写入完成 -> 带token结果
  -> Broker终结本次提交 -> 前端显示明确状态
```

- 保留Dispatcher的owner＋connection隔离：TIP连接拥有引擎会话，UI另开连接不得借sessionID直接操作。新增受限activation capability关联层将UI语义动作路由到被绑定TIP的授权会话，不能简单放宽现有跨连接检查。
- TIP拥有真实ITfContext及其COM生命周期；Broker持不透明target lease和引擎会话；前端只持候选快照/会话能力，不拥有任意HWND写入权，不提供“PID/HWND就可绑定”接口。
- 使用独立版本/端点的18u加法式适配层，复用现有传输/Dispatcher安全原语及YimeCore；不就地改变v1标准客户端语义。标准/Rime回归继续走原协议和数据。
- 不把新事件处理器放在另造的测试controller：最终入口必须是产品TextService + 原18u UI处理路径。
- 路由通知需要Broker→TIP受限事件通道。最小实现用已认证连接的有界接收工作线程，将拥有的请求对象投递到TIP自己线程的私有调度窗口/队列；所有COM/context与编辑在所属线程执行。私有窗口消息只作唤醒，请求留在受控队列中并再次核验；收到窗口消息本身不构成授权。不通过外部窗口消息携带裸指针/正文，不在键事件线程无限阻塞网络，不允许传任意命令。具体复用/新增连接在实现小设计中定稿，不承诺现有请求-响应协议已支持双向推送。

## 4. 激活、焦点与候选

1. 启动前端不自动切换系统profile、不抢宿主焦点。界面先显示“未绑定/请在目标窗口选择18u输入法”。用户选择由Windows正常管理，前端只在该profile实际激活且TIP报告有效context后允许绑定。
2. 首次及失焦后需明确绑定/恢复；目标显示可用应用名但不可将标题作为权限。普通触摸前端不激活；用户切去其他应用、profile、文档/context、宿主销毁、TIP停用或连接断开均撤销租约并递增世代。恢复焦点不自动复用旧候选。
3. Broker的“当前活动”报告可能延迟，因此最终执行必须在TIP的DoEditSession内重验profile、目标context、文档、焦点世代和取消状态，任何不一致拒绝。复用IBrokerEditExecutionGuard，不只做发送前检查。
4. 候选必须绑定layout/dictionary/mode/session/revision/id；翻页/退格/恢复后的旧候选无效。原始按键/手势只来自此前端，不收全局输入。
5. 第一正式切片不处理安全桌面、密码框、提升权限宿主和跨用户/跨登录会话目标，检测到不可支持或权限未知即停，不提升权限解决。后续Word/Edge需独立测其可编辑context，不能从自有宿主推定。

## 5. IPC信任：现有机制保留，缺项逐项补

- 端点名包含产品及用户登录会话隔离标识，不从任意环境变量取得正式目标；以本机pipe为限、拒绝远端和第二服务抢占，沿用现有ACL与有界连接/帧/超时。
- 由OS取得两端PID、用户SID、Windows会话ID及token登录身份（两者分开校验，相同SID或session ID本身不是产品认证），并持有进程句柄/创建身份防PID复用；校验期望Broker实际映像/安装根/资源身份。路径和哈希不是签名，也不代表同用户恶意注入不可发生。
- 前端角色只允许经验证的产品前端，不能仅凭JSON自称role=frontend或随机token自称可信。首个受控验证可限定自有宿主/前端的确切进程；正式任意宿主中TIP运行在宿主EXE里，**不能通过要求Word.exe等于产品EXE来认证TIP**。
- 因此必须区分威胁模型：同用户进程不是天然产品可信，但PID/SID也不能证明加载的TIP绝未被同用户篡改。产品TIP先从受控安装载荷正常激活，绑定连接能力并始终在本地核验焦点/context；新路由不允许同用户任意进程借前端请求指定其他目标。需负例证明未授权前端、旧连接/旧租约、错session、错布局不能触发写入。不得宣称防御已控制宿主进程的攻击者。
- 用户数据/学习文件与标准/Rime完全分目录、分source-id；首片关闭持久学习写入，后续另明确数据兼容。布局、派生词典/索引和包manifest固定匹配，验证在Broker加载侧实际进行，不信前端自报hash。

## 6. 提交、读回与关闭

提交状态：Prepared → Queued → Applied / Rejected / Unknown。Queued或Broker产生commit字符串都不是成功。

- Applied须来自实际DoEditSession完成与写入返回；自有测试宿主另做独立文本读回证明唯一写入。后续真实宿主回执不等于自动读取整篇文档，更不采集整篇正文做日志；编辑失败若可能部分写入不能伪装未写，应Unknown。
- token严格单次，候选选择期间锁定该提交；不在确认前做持久学习。超时/断线/进程退出导致结果不确定即Unknown，停止该会话，不自动重发文字；旧完成可记到旧token，但不能推进新会话。
- 关闭前端撤销其路由、取消未提交组合；已经排队的编辑仍由执行时guard决定。关闭不是“已撤回正文”保证。TIP停用按现有取消/结束组合生命周期释放对象；不杀用户宿主、不退出其他产品Broker、不删除用户数据。

## 7. 为什么S3b不能直接发日用机

S3b启动自有TSF thread manager并使用NOACTIVATETIP/NOACTIVATEKEYBOARDLAYOUT，官方说明只在ActivateEx调用期间限制激活/布局同步，获得焦点时仍可能发生。因此它不是隔离已有TIP的沙箱，不能通过禁用别的输入法、改默认或扩大SetForegroundWindow权限补救。

正式路线不规避Windows机制：由用户选择独立18u profile，让Windows把正确TIP激活在真实宿主线程；前端只认该TIP的实际活动上下文。切到标准/Rime/其他输入法即停止18u路由，保持其他产品正常工作。

官方依据（本次重新核查）：https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgrex-activateex

## 8. 下一里程碑与最短到日用顺序

| 里程碑 | 最小交付/必须证据 | 权限与停止点 |
| --- | --- | --- |
| **S3c.1 TIP↔Broker首片** | 独立18u产品描述/资源身份；加法式路由合同；实际TextService接线；此首片不接UI跨连接路由；正确提交、过期目标拒绝、Unknown不重放。先单x64自有宿主直接加载真实DLL测接线并独立读回；保留S3b原10场景和标准回归 | 产品选择确认后可按整体实施授权本地实现/独审；不注册。直接加载不等于安装态激活；此关结束必须进下一关，不再新增无止境demo |
| **S3c.2 原UI激活关联** | 在S3c.1真实链基础上接原18u前端，受限能力关联TIP会话；错前端/旧租约拒绝，不能任意选宿主。S3c.1通过不代表此项完成 | 后续本地实现/独审，发布另批；不再另造演示宿主 |
| **S3d隔离注册激活关** | 在获批干净Windows环境实际注册独立profile，显式选择、18u UI→产品TIP→Broker→宿主编辑；切走/恢复、重复释放、断连、正常退出；旧标准/Rime身份及数据不变 | 注册/卸载动作另批，包括CI若涉及注册；代码推送/CI另批。无获批环境则阻塞并报告，不能以mock/直接DLL冒充 |
| **首台用户x64可回退试用** | 固定包、manifest、签名状态如实披露；安装/启用/卸载流程只拥有18u；用户选机器和时间；先单专用宿主，再Word/Edge各小组。保留原包与数据 | 明确安装授权后执行，绝不默认输入法变更。卸载失败/误写/重复/标准回归即停 |
| 后续扩展 | 三模式/常用编辑补齐、标准对应触摸按原路线、ARM及更广宿主覆盖 | 按优先级与分阶段授权，不把当前CN variable/x64成功泛化 |

正式首片的“正常闭环”至少包括启动/绑定、输入候选与普通翻页、组合退格取消、唯一提交、失焦恢复和正常退出；不附加混合笔指疑难、诊断版崩溃专项、性能封版或四机大矩阵。

## 9. 本次交付与未做事项

设计核查阶段未实现新路由。后续本地实施逐项验证记录另见S3C_VALIDATION；未验证或未接通能力不能由本文推定。未推送、运行安装器、注册profile、访问用户机或派发物理任务。当前S3b限制仍有效。本文件描述目标契约，不是全已实现保证。
