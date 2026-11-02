# S3c.1：真实18u TextService / Broker接线验证

2026-11-01。本地实施记录，未发布、未注册、未安装。基线为S3b远端 `3f6d535e3e35153362c896ac3922d99186b1b487` 同树本地 `6f2016d2716409550ec080c11784f02c5039dd11`。没有自动合入更新main或诊断分支。

## 当前范围

用户已确认独立18u触摸profile与标准/Rime并存，首片x64、CN/variable。实现分片：

- **S3c.1（本片）**：真实独立TextService DLL，经受控单TIP连接的专用Broker协议调用完整身份校验的自研引擎，再由TIP自己的TSF context实际编辑并回传结果。
- **S3c.2（未交付）**：原18u UI的跨进程激活关联、前端角色认证及原UI动作接线。
- **S3d（未授权执行）**：干净环境真实注册与用户显式profile选择；之后再首台用户x64及Word/Edge。

本片不接受任意目标HWND/context、任意提交正文或前端伪造Applied；不改标准v1默认行为、不复用标准索引。开发profile尚不可安装；未提供新的用户机启动指令。

## 证据分层与原生验收计划

1. Linux：身份描述3项；专用Broker协议/owner+connection/sequence/identity/候选/回执/Unknown负例；原标准Broker和引擎/UI/bridge回归；race/vet适用范围。
2. Windows交叉编译：仅证明Go构建，不证明Win32管道认证或TSF执行。
3. 待批准限定Windows x64 CI：MSVC编译实际18u产品DLL及自有宿主测试，Go专用Broker使用受锁定完整词典；LoadLibrary/DllGetClassObject加载实际DLL，通过同一真实TextService路径与本地namedpipe交互；调用实际DoEditSession并独立读回。
4. 原生必须包括正确输入/唯一提交/实际完成回执、错服务端身份拒绝、旧焦点/失焦拒绝、重复和断线不重放，保留前阶段7 TSF＋3 UI回归。缺场景、skip或只用fixture不能作全链通过。
5. 直接加载DLL不等于Windows注册激活通过；即使上述CI通过也不能给用户机日用，不继承S3b或PR87验收。

## 资源身份准备

从已下载并核验的S3b官方artifact `13085582419` 只读提取完整词典到本工作树 `.generated/s3c-full-data`。4项逐一核对现有 `resources.lock.json` 字节数及SHA-256；不下载/导入其他仓库，不改旧包。variable词典SHA为 `43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353`。资源准备并不是本片运行通过。

## 实际结果

本地已执行（Linux，Go 1.25.3）：

- `python tools/test_18u_product_identity.py`：3项通过。
- `YIME_18U_FULL_DATA=<本工作树>/.generated/s3c-full-data go test ./internal/touchbroker -count=1 -v`：6项通过，含完整固定资源加载、canonical ni→候选→Pending→模拟可信owner回执。此次完整资源项耗时12.45秒；**回执仍是协议测试模拟，不是Linux执行了TSF**。
- `go test -race ./internal/touchbroker ./internal/touchhostbridge`：通过。
- `go vet ./internal/touchbroker ./cmd/yimebroker-18u ./internal/touchhostbridge`：通过。
- `go test ./internal/touchhostbridge ./internal/keyboardlab ./internal/touchkeyboard ./cmd/yime-touch-keyboard ./input_methods/yime/yimecore ./input_methods/yime/codemode`：六包通过。
- `go test ./input_methods/yime/yimebroker -run '^Test(ServeLines|Dispatcher|ConnectionLimiter)' -count=1`：标准协议/连接隔离定向回归通过。
- Windows amd64 Go `test -c`：新原生driver所在bridge包及标准Broker含新增OS认证测试编译通过；新Broker命令交叉构建通过。本云端worktree的Go VCS探测错误地在`/workspace/shared`运行git status而失败，本地命令构建显式`-buildvcs=false`仅作编译检查；不提供该EXE作交付，不声称其内嵌提交身份。拟CI正常checkout不关闭VCS标记。
- workflow YAML解析与`git diff --check`通过；C++无MSVC环境，**未编译、未执行**。

### 已复现的基线回归缺口

首次全Broker包测试有两项临时目录清理断言失败；在未修改的S3b同树基线也复现相同失败：

- `TestBundleGenerationManagerModuleIdentityAndFailureResourceCleanup`，`bundle_generation_manager_test.go:436`。
- `TestBundleGenerationManagerCloseDuringStagingAndConcurrentVersionConflict/duplicate`，同文件`:516`。

未改这两项测试或相关实现，不以定向通过冒充全包通过，也不从此推定Windows表现或根因。

### 本片实际实现与尚未证明

独立产品描述/生成GUID、实际TextService目标、受控namedpipe单TIP连接、固定布局/词典和焦点租约、同步TSF编辑完成回执已写入代码；标准默认路径保持。客户端核实际服务PID/映像/同SID、Windows session与登录身份并持进程句柄，服务端只允许bootstrap指定的宿主PID及同登录身份，连接绑定不来自JSON。此门槛是受控开发宿主授权，不是任意应用中的TIP模块防篡改认证。

TIP自行取得实际context与自身STA前台窗口，不接受外部HWND/context。编辑前及执行时重新核前台/文档/context；只有明确guard拒绝才记Failed，guard放行后的非成功或回执丢失记Unknown、停止且不重放。候选回执不接受前端伪Applied。

首次完整资源加载仍是有界同步开发启动（管道连接30秒、open响应60秒，普通操作5秒）；不是最终前端非阻塞产品路由。执行时前台/doc/top校验不等于已经证明阻塞等待期间“失焦后又返回”的完整世代观察；这仍是后续异步产品接线必须处理的限制，不可据本片宣称日用焦点防护完整。

组合和候选目前仅保存在Broker/返回快照，**尚未将未确认组合写入宿主、尚未接18u可见UI路由**；实际宿主路径为选词后的同步一次提交。不要把单次提交片段称为完整正式IME体验。

拟限定Windows原生CI：原7 TSF＋3 UI回归、新2个真实OS管道身份/错进程负例、实际独立DLL→Broker→TSF的7个场景（commit、duplicate、wrong-server-pid、wrong-server-image、deactivated、focus-lost、disconnect-before-action），逐项拒绝skip/缺项。还编译原默认TextService DLL，保留标准编译路径。

新原生断线场景只覆盖**动作前**连接中断；写入后ACK丢失Unknown仅有Go协议合同与此前S2范围，不声称新原生端到端已经覆盖。真实Windows注册/选择、前端跨连接授权、异步正式路由、密码/提升权限宿主、日用签名/安装均未完成。不得向四台日常用户机派发本片。

独立终审（2026-11-01）确认：当前受控S3c.1切片无剩余本地提交阻断；复跑两包race、Windows Go交叉编译、身份3项及diff-check通过。已核标准默认路径/owner连接隔离、执行guard、guardDenied与Unknown区分、COM生命周期、独立serviceClientId和观察器失败关闭。此结论允许申请限定CI，不代表C++已编译或原生19项已通过。

## 首轮原生CI记录

远端 `c62fc20daa3a885f53dc31518fa195d83898108e`，run `41315522058`：MSVC实际编译（含新DLL/runner及原默认DLL）、旧7 TSF＋3 UI、2 OS认证、完整资源与Broker构建均通过；新7场景全部在connect响应前失败。原测试吞掉初始化阶段信息，当前无法确定具体原因。失败证据artifact `13087231981` ZIP SHA-256 `b80a40b119ccc1ca2a4bb1e20e5e1acbaeaf48df83915d552ffaaec677cb41cd`已下载核验并保留。

补充仅测试诊断：固定阶段标签和数值HRESULT/Win32错误，Go等待stderr收集结束后严格白名单解析；不输出异常文本/路径/正文，不改变激活、身份或前台检查。增设隐私解析回归并纳入CI。此变更不声称修复了尚未定位的初始化原因。

## 第二轮诊断与夹具ID修正

`a90b174a16e5e809536429a4c9da7f77ac126eeb` / run `41316058606` 确认7项都在 `actual TIP activation` 返回 `E_INVALIDARG (0x80070057)`；辅助隐私测试通过。证据artifact `13086749489` ZIP SHA-256 `a08d1449cd054a6d2d9f466521bce2b797d94449d85beff88f0cce242f0f27ac`已下载保留。此时尚未进入Broker动作。

纠正此前夹具和审阅中的ID假设：`GetClientId(new CLSID)`并不等于Windows激活注册文本服务时交给它的ID。旧TsfCompositionTests同时启用了DIRECT_TEST跳过key sink，不能仅照搬其ID分配。官方AdviseKeyEventSink要求激活所得client ID；GetClientId说明面向非应用、非文本服务类别的TSF对象。因此本片direct-load adapter改为借用测试宿主真实ThreadMgr ActivateEx取得的client，仍执行真实DLL的AdviseKeyEventSink及全部身份/前台/观察器检查，**不打开DIRECT_TEST、不注册、不跳过失败**。结果字段明确 `activationIdentity=owned-host-activation-client`，Go必须严格核对。

此修正只能验证真实DLL组件链，不能宣称独立18u profile已被Windows激活；此前“独立serviceClientId”描述属于已纠正的历史夹具假设。修正是否解决初始化失败仍须下一次原生CI证明。

依据：https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfkeystrokemgr-advisekeyeventsink 、 https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfclientid-getclientid

同一a90b174普通Build `41316058471` 的Windows race job `124876418928` 另有新增测试 `TestDedicatedNamedPipeHandlerUsesActualSameLogonPeer` 等handler超时（10秒）；不是DATA RACE报告，不是前述两项旧清理断言。同提交非race实际OS认证通过。先补测试对认证错误/监听提前退出的固定分类诊断和失败清理，不增加超时、不放宽SID/PID/登录身份要求；根因仍待CI证据。

## 第三轮结果与精确门槛探针

`09839c04104b736deb8800eb2e46c10603d02e18` / 原生 run `41316988230` 仍是新7项在实际TIP激活返回E_INVALIDARG，旧10项和非race OS认证通过。失败artifact `13087363077` ZIP SHA-256 `794f968550ba2b48cb527b17163fd93df53b8dafdbc0313bf541e825d0ee5268`已下载保留。借用宿主激活client并未证明解决问题，不再猜换ID或跳过key sink。

此次仅在独立18u DLL编译默认关闭的诊断开关：限定CI启用后记录固定阶段（null-manager/null-client/already-active/query-keystroke-manager/advise-key-event-sink/thread-observer）及原返回HRESULT；成功无输出。观察器标签仅表示原门返回E_FAIL，不细分其内部API。严格解析至多一条探针加一条对应失败；不输出正文/路径/凭据，不改变输入逻辑、激活参数、调用顺序或清理。若确认真实key sink门在此未注册路线拒绝，保留阻塞并另行申请隔离注册验证，不绕过激活门。

同head普通Build `41316988238` race job `124879251558` 已将失败缩小为实际peer登录身份查询返回“Invalid access to memory location”，不是超时或DATA RACE警告。原TokenSessionId/TokenStatistics输出采用只保证字节对齐的byte数组；最小ABI修正改用uint32和完整对齐TOKEN_STATISTICS结构，保持SID、Windows session、AuthenticationId比较及little-endian字节编码不变。新增结构尺寸/偏移/对齐/编码等价与实际Token查询测试，并细分TokenUser/SessionId/Statistics错误。对齐缺口与race现象相符，但尚无原生证据证明具体根因或修复成功；不增加重试，不放宽认证。官方结构依据：https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_statistics
