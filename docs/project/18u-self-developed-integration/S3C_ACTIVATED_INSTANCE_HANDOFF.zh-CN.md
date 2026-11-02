# S3c：取得 Windows 激活实例的接续补丁

2026-11-02，影响范围仅独立 18u 开发 DLL 与测试。基线为另一开发端最新发布的
`71a4a252641159753b0eff41b871254233c6efd2`，本地分支
`codex/18u-activation-repair-20261102`。当前根目录的旧交接修改未动。

## 结论与边界

补齐了注册态宿主取得**实际已激活 TIP 实例**的源码路径和本机非注册回归。
**尚未验证 Windows 注册态激活、Broker 编辑或原七个场景通过。**
这不是对 `AdviseKeyEventSink/E_INVALIDARG` 最终根因的确认，也不是可安装交付。

旧 `Formal18uHost` 自己调用类工厂创建 TIP，再将宿主的 client ID 传给该对象的
`ActivateEx`；该路径的历史失败仍保留，不能当作 Windows 已经激活独立 profile。
即使之后注册激活成功，也必须取得 Windows 激活的对象，不能再创建第二个对象
冒充它。此次修补这一明确的接入缺口，不修改、跳过或放宽 key-event sink 门。

## 修改

- 独立 18u DLL 在 key sink 和线程观察器都成功后，通过
  `ITfSourceSingle::AdviseSingleSink` 发布 `ITfFunctionProvider`。
  `GetFunction(GUID_NULL, IDedicatedTouchService)` 返回同一 COM 实例的专用路由；
  失活、跨线程、错误 function/IID 均拒绝。失活先撤销入口，再释放已有回调。
  标准产品编译路径不实现这个 provider。
- 新的 `YimeTouchRegisteredFormalHostTests` 是默认关闭的独立构建目标。
  它要求隔离环境已经具备获准配置的中文独立 profile，只做一次进程范围的
  `ActivateProfile`，不创建类工厂对象、不直接调用 TIP 的 `ActivateEx`。
  它核对活动 profile、provider 类型及接口实际所属 DLL，再进入原 Broker/正文测试。
  无注册、启用、默认输入法或系统语言修改 API，失败不回退到旧路径。
- Go 侧新增独立 opt-in `TestNativeRegisteredFormal18uTIP`，要求单独的
  `YIME_REGISTERED_FORMAL_18U_HOST`。严格区分 `windows-activated-profile/registered=true`
  与旧直接加载结果；原七场景、正文读回和负例断言保留。
- 现有 formal CI 增加新目标的**编译**与替身 provider 回归；不运行注册态测试，
  不增加注册 dispatch，也不把原失败步骤移除或改成允许失败。

官方接口依据：
[GetFunctionProvider](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgr-getfunctionprovider)、
[ITfFunctionProvider 生命周期](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itffunctionprovider)、
[ActivateProfile 的进程范围标志](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfinputprocessorprofilemgr-activateprofile)。

## 本机已执行的验证

本机 Windows x64，MSVC 19.44.35225.0，Windows SDK 10.0.26100.0。

| 验证 | 结果和含义 |
| --- | --- |
| CMake / MSVC 构建 | 独立 18u DLL、原标准 DLL、新替身测试、旧直接加载宿主、新注册态宿主、失焦测试六目标成功；两种真实 TSF 宿主均未运行 |
| `YimeDedicatedActivationTests <本次DLL绝对路径>` | 成功；直接加载本次 DLL，但所有 TSF 接口均为内存替身，无真实 TSF 管理器或注册操作。检查同一 COM 实例、跨线程拒绝、失活后保留引用、重复失活/重激活、五类失败回收及 DLL 引用归零 |
| `YimeFocusCancellationTests` | 36 checks / 0 failures，隔离替身测试 |
| `go test ./internal/touchhostbridge -count=1` | 通过；未设置任何原生宿主开关，原生场景未执行，不作为原生输入通过 |
| `go vet ./internal/touchhostbridge` | 通过 |
| `python -m unittest discover -s tools/ci -p test_mycomputer_activation_contract.py -v` | 7 项通过；原注册/恢复源码约束未破坏 |
| `python -m unittest discover -s tools -p test_18u_product_identity.py -v` | 3 项通过；身份与锁定投影未改 |
| 工作流 YAML / `git diff --check` | 通过 |

首次编译与身份测试因稀疏 checkout 未包含 icons、resources.lock 和 physical-layout
文件而停止；补齐同一提交的受控文件后通过，未改资源或断言。编译保留既有区域的
未引用参数/不可达代码警告；不宣称无警告构建。

## 下一阶段与不可继承的结论

1. 此补丁可以先审阅、编译和运行替身测试；它不是新的注册执行授权。
2. 另一端的 v2 一次注册/恢复工具仍保持原实现和范围：它只证明激活切片，当前
   不会在注册存续期间自动运行本补丁的 Broker 七场景。不能把其通过等同于全链通过。
3. 真正执行新宿主前，需要一个明确授权、固定源码/DLL/Broker/词典、允许本轮独立
   profile 在场景期间存续、最后撤销并独立核验的隔离测试方案。当前尚未接入该编排。
   不在用户日常桌面启动任一真实 TSF 宿主，不复用历史的一次性 dispatch 许可。
4. 只有注册态七场景实际完成，才能判断这条路径是否解决当前阻断；可能还会暴露
   profile 激活、焦点或 Broker 层问题。S3c.2 可见 UI、Word/Edge、ARM64、物理验收均未完成。

本次未发布分支、触发 CI、注册/卸载输入法，未改变默认输入法或用户数据。旧失败
记录、PR87 固定包、标准布局与原开发分支均保留。
