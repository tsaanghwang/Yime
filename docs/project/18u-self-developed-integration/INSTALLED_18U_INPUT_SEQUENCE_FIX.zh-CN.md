# installed-host 整段输入码错误修复

2026-11-03，基线 `da3223e5674b34a998397abdae3c960c7df6468e`。

## 问题与改动

`Formal18uHost.cpp` 原来将 canonical ni3 的完整 variable 输入码放进一次
`input` 请求。固定数据实际推导得到两个字符，而 `keyboardlab.validateEvent`
及 `keyboardEngine.Apply` 均要求每次 input 恰好一个字符。因此该请求被真实引擎
拒绝，Broker 返回 action rejected，路由转换为 E_ABORT。既有完整资源 Broker
测试已经逐字符输入，原生宿主却没有复用同样的调用约定。

修复仅改变测试宿主：逐字符发送，以上一成功响应的 revision 构造下一请求；
每次必须无提交并且 revision 精确加一。首错立即退出，不发送后续字符，不重试。
全部字符成功后仍沿用原有一次选词、实际异步编辑完成与独立读回。
断连/失活负例也使用合法的首字符请求，避免由错误输入载荷伪造拒绝通过。

不改变 DLL、Broker、词典、键盘协议、焦点/身份门或默认输入法。
新增独立纯 C++ helper 回归，覆盖逐键/revision、失败后停止、错误 revision、
意外提交及不合法完整输入。CI 增加实际引擎拒绝整段请求的回归、完整固定词典
多键回归及 helper 编译运行；新构包版本为 test.4，旧包不覆盖。

## 本地验证

- MSVC x64 Release：修复后的 registered formal host 与纯 helper 测试编译通过。
- helper 回归通过；Go touchbroker、touchhostbridge、installed18uhost 包测试通过，
  默认未选择的原生测试未执行。
- 使用原 test.2 包的完整三模式字典，`TestFullResourceDedicatedBroker` 通过；
  canonical ni3 为 2 次单键事件，单次选词产生待确认提交。该测试的 Applied
  是模拟可信宿主回执，不是 Windows TSF 编辑证据。
- 33 项制包/维护 Python 测试中 32 项通过，`test_linked_input` 因当前进程没有
  创建符号链接权限返回 WinError 1314；没有提升权限重跑或弱化该测试。
- 5 项 input-abort 诊断接线检查通过。

## 原始实机证据与边界

当前安装仍是 `bb7cc136c284a5d5ee3a764749119b0b423da482` / test.2，
manifest SHA-256 `89928fe4c4496462d9198e4be9be28b72ddb9816594b6eab7986fac766844adf`。
此前原宿主 connected 后 engine input E_ABORT 的记录保留在
`C:\Users\tsaan\Yime18u-host-test2-r1`。

一次修复宿主验证使用新构建的宿主及未修改的已安装 test.2 DLL/Broker，
不是修改清单或冒充原固定包验收。2026-11-03 07:51 +08:00，该运行在
`own foreground not granted; no bypass` 停止，尚未到连接或输入阶段。
没有自动重试。运行前后全部 installed manifest 载荷 SHA-256 相同。

本地原始记录：`C:\dev\Yime-evidence\18u-input-fix-20261103`，
其中 `native-fixed-host-r1` 保存输入身份、进程 PID、stdout/stderr、退出结果及
安装载荷未变核验。证据不可覆盖；该前台失败不被源码/离线测试成功抹去。

实际安装态编辑读回仍需获准后在能够取得前台的运行环境中执行一次。
不据此宣称固定 test.4 安装、Word/Edge 或物理触摸验收通过。
