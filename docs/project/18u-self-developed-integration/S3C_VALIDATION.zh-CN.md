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
