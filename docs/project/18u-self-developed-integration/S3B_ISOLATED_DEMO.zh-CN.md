# S3b：可启动的隔离开发演示（不是用户机安装包）

2026-11-01。分支 `codex/18u-own-host-demo-s3b-20261101`，基于已通过 S3a 的远端 `01af55ef96b1b3e4f29ec3f2bf380212104dec05` 同树本地 `2f06d4b196c240cffd18637753e2dea11ce7940e`。本地实施已授权，发布和原生 CI 待单独确认。

## 前置事实与安全边界

S3a [原生 CI](https://github.com/tsaanghwang/Yime/actions/runs/41308612182)的3组真实窗口消息路径＋7个TSF场景均通过、无skip；[普通Build](https://github.com/tsaanghwang/Yime/actions/runs/41308612114)及[盘面CI](https://github.com/tsaanghwang/Yime/actions/runs/41308612102)通过。证据ZIP SHA256 `64e01e3b9c570bca8af67b2eeff5210affadc43aaa0e078ce5b655913788366a`。这不是用户产品、自然焦点切换或物理触控验收。

**本演示仍只供干净、隔离的 Windows x64 开发环境。不能在用户日常桌面执行。** Microsoft 对 `ITfThreadMgrEx::ActivateEx` 明确说明抑制标志仅有受限作用，后续线程获焦仍可能异步激活已安装 TIP。此风险未解决，不靠隐藏窗口、删注释或修改用户输入法设置绕过。官方依据：https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgrex-activateex 。本阶段实现不是用户机运行授权。

## 最小可用范围

- 独立演示包、显式 `--own-tsf-demo`，固定 CN/variable。裸运行演示EXE不得落回旧 SendInput；普通构建/默认preview/host-input不改。
- 18u盘面与实际完整专用三模式资源保留其锁定身份，本片只接variable；不能把小fixture自动测试称为完整词库验收。标准布局、Rime与已有注册身份不变。
- 仅两个自有进程：键盘UI与固定包内 `YimeTouchBridgeDemoHost.exe`。无任意可执行路径、命令、外部HWND、监听端口、注册/安装或全局输入捕获。
- 子宿主拥有可见只读正文窗口与真实TSF context；显示文本来自独立read-edit读回，不来自请求文字echo或累计预期镜像。预期累计值只用于内部一致性检查。
- 真正执行写入前同时核对当前宿主前台窗口、TSF document/context、活动绑定与epoch。自然失焦使绑定持续无效；切回窗口不自动恢复，必须明确重新绑定，重绑才递增epoch。
- 键盘窗口保持不抢焦点；最小化/失焦后旧组合和触点不可继续；重绑保留实际已提交正文而不继承未提交组合。
- 未支持的语言/模式/修饰组合、正文编辑等明确拒绝，不回退本地editor/SendInput。提交未知、超时或断连即停止，不自动重启/重放。

## 身份与生命周期

Go先校验编译绑定的resources.json及资源/宿主哈希，真实OpenRuntime导出layout/dictionary/mode/sessionPolicy身份；v2每帧携带并检查同一身份/seq/epoch。native锁定已验证父传入身份，但不声称它独立验证了磁盘词典，也不宣称这是正式产品IPC认证。

STA通过有界管道轮询与消息循环处理空闲期窗口事件；同步实际edit完成后才报告提交结果。每请求有限超时，人工空闲不继承S3a测试30秒进程期限。正文容量与提交次数有限，达到上限停止而非悄悄清空。父退出/正文窗口关闭/EOF/错误只清理自身子进程；未知写入不伪装为未写入。

## 独立包与验证分层

`tools/build_touch_keyboard_demo.py`使用既有锁定完整词典验证与资源搬运，先构建native、将host哈希纳入资源清单、再编译绑定清单的Go程序。所有普通启动器移除，旧使用指南替换；单独manifest scope为`isolated-own-tsf-demo-development-only`，`userDesktopExecutionApproved=false`。哈希不是签名，不能覆盖原PR87/a837包或继承原验收。

`tools/check_touch_keyboard_demo.py`核完整文件集合/哈希与原生x64架构，复制到仓库外执行`--check-package`只读/内存检查，确认完整三模式词典及篡改宿主被拒绝；此检查不启动演示或TSF。实际演示入口、自然焦点/重绑/退出须另列原生CI证据，保留S3a十个场景回归。源码/fixture/静态包检查不互相冒充。

初始本地交付时完成独立审阅，原生验证当时未运行；后续已获准发布本分支限定CI与隔离开发包，进展见下方CI记录。授权不覆盖用户机试用、Word/Edge、ARM、产品profile、签名或安装。

## 本地交付验证（尚非原生通过）

- Linux六包回归通过：touchhostbridge、keyboardlab、touchkeyboard、cmd/yime-touch-keyboard、标准codemode、yimecore；独立UI/bridge两包race通过。
- Windows amd64 Go测试交叉编译通过；新Python打包/校验合同3项通过；YAML与diff-check通过。独立静态审阅无剩余本地交付阻断。
- 修正空闲read轮询耗尽请求额度、重复inactive轮询取消重绑手势、协议version类型及guard拒写状态一致性；read可空闲持续，只有变更操作128次、提交16次及正文1024 UTF-16上限。
- 新限定CI预备先编译四个原生目标，重跑旧3+7场景；再用锁定完整词典构建独立demo、仓库外静态检查、实际完整包自测。自测经真实run/窗口命中/两次提交与独立读回，仅显式自测模式下，原生宿主新建另一临时自有窗口实际取得前台验证失焦，再经原UI明确重绑、关闭。它是受控原生窗口切换，不是用户自然操作稳定性或触控实测。
- **初始本地交付时，C++、完整包及真实前台门均未执行。** 后续第三轮CI已构建并通过静态整包门，但实际整包自测在前台切换处失败。当前焦点自测修复仍须重新验证；不能替换为模拟焦点放行。

## CI 中发现的问题与最小修复

首次发布后已修复Python夹具的Windows短路径/UTF-8读取，以及证据目录污染clean-source门；未放松资源校验。第三轮实际完整包已通过静态检查并完成首个提交，随后父进程测试窗口未被确认取得前台，门槛正确失败；错误同时涉及前台与无关GUIThreadInfo查询，不能据此确定系统权限根因。

后续失焦自测不扩大父进程前台权限：只有显式`--own-tsf-demo-self-test`会以`--self-test`启动原生子宿主，开放固定`test-focus-away`操作；native自己创建第二个临时窗口，严格验证真实前台切换与原窗口失活，销毁后保持inactive，再经原UI显式重绑。普通交互模式禁止该操作，不接收任意PID/HWND，不使用ASFW_ANY或AttachThreadInput。此证据只证明受控真实宿主失焦，不证明父进程可以抢占前台或用户自然切换稳定性。修复须重新通过原生CI，不能用`invalidate`模拟替代。
