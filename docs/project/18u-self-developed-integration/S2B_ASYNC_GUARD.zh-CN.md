# S2b：异步执行时焦点/取消与迟到完成保护

2026-11-01。本地分支 `codex/18u-tsf-async-s2b-20261101`，基于已验证S2a远端 `5cf619dafadccc844c40ea131d6d935d28de3896` 的同树本地提交 `ca2f1b65e170bd7cc7f0da66e0da05e47751d4b8`。用户授权分阶段本地实施；本阶段新代码发布及原生CI另行确认。

## 目的和最小改动

S2a已在隔离Windows x64 CI真实通过同步提交、重复拒绝和请求前失焦拒绝，但没有证明排队之后失焦安全。本阶段补实际 `DoEditSession` 入口的可选guard：确认目标context、宿主document焦点、activation epoch及取消状态，只有精确允许才执行文本变更。guard由COM引用持有生命周期；旧调用默认不传guard，不改变标准版现有运行行为。

异步请求所有被回调引用的状态必须活到完成或宿主清理；不能继续使用S2a调用栈中的composition/termination/completion地址。完成结果始终绑定原请求ID/epoch；旧回调不能更新新会话。已请求但结果不明仍为Unknown，不自动重放。

## 证据分层

- S1：Linux真实小字典自研引擎＋传输中立合同；不是Windows TSF。
- S2a：隔离Windows原生自有TSF上下文同步写入＋独立read-edit读回，已通过；不是Word/完整前端。
- S2b：新增实际 `TF_ES_ASYNC` 的Windows请求。用于失焦/取消的时序由测试在自有read edit lock内发起write并使guard失效，再释放锁、限定时间泵消息，以确定性测试迟到执行。**这是测试诱发的排队，不是自然用户操作延迟、系统调度性能或稳定性证据。** 必须实际收到异步排队标志/完成回调并独立读取文本，不能用模拟pending状态替代。

消息泵会接触TSF异步运行，ActivateEx的抑制标志不是永久阻止TIP自动激活的保证；只供隔离Windows CI环境，不供用户机器执行。不得注册产品profile、改变默认输入法或写用户文档。

## 必要场景及预期

1. 保留S2a三场景：同步实际提交且读回一致、重复请求不追加、错误焦点请求不写。
2. 有效异步提交：实际排队/实际edit完成、独立读回精确一致后才Applied。
3. 已排队再失焦或取消：执行guard拒绝，旧目标与新目标不得获得提交；旧完成仅归旧请求，新activation状态保持。
4. 默认空guard的既有FocusCancellation原生测试继续通过，不放松标准合同。

同一commit不会因失败、超时、取消或断连被再次发送。取消pending不等于已证明宿主无写入；只有本片实际拒绝和读回能证明对应场景未写。未知状态保持未知。

## 当前验证门槛

本地Linux可跑相关Go回归、交叉编译Windows Go测试及静态审阅；不能原生编译/运行MSVC TSF harness。限定workflow须显式构建原生harness与既有FocusCancellation测试，逐项拒绝skip/缺失/失败，保留证据。批准发布并原生成功前，S2b不记通过。

## 非目标和后续

不接18u完整UI，不改标准/Rime数据或注册身份，不扩ARM/四机/安装，不处理混合笔指或a837诊断故障。本片没有解决所有前端/宿主预编辑动作；待原生门通过后，再据实际缺口准备S2剩余正常动作及S3接线，不能把此测试适配器称为正式产品IPC认证方案。

## 本地交付和验证（原生门待执行）

代码准备7个文件（含本说明）：共享CompositionEditSession头/实现的可选guard、FocusCancellationTests补充受控fake回归、原生harness、Windows Go集成测试、限定workflow以及本文。

- 保留原3个同步场景，增加async-commit/async-focus-lost/async-cancel/async-old-epoch，共7个原生场景；workflow精确要求父测试及7子项均实际pass，skip/缺项失败。
- 失效反例创建另一真实自有TSF context，独立读取旧/新目标为空；旧epoch测试在Go子进程运行前先失效旧会话、创建新会话，再接收旧回执，拒绝污染新状态。这是测试控制的生命周期，不是完整产品激活流程。
- FocusCancellationTests补充S_FALSE guard拒写、guard排队引用生存期及请求失败引用释放。这些使用fake context，必须标为合成契约回归，不能当作OS异步排队证据；原有null-guard测试保留。
- Linux六包测试通过：touchhostbridge、keyboardlab、touchkeyboard、cmd/yime-touch-keyboard、标准codemode、yimecore；此运行不执行Windows专有测试。
- Windows amd64 Go测试交叉编译通过；diff空白检查通过。
- **共享C++ guard及新增合成回归尚未编译执行，7个原生场景也未运行；当前不得写S2b通过。** 本地环境没有Windows/MSVC，下一门槛是批准后在隔离Windows x64 CI实际验证，而不是要求用户重测。
- 独立静态审阅无剩余本地提交阻断；另独立跑Linux bridge `-race`和Windows Go交叉编译通过。审阅补强新context实际读回、先建立新会话再接迟到回执、fake guard析构次序，未放宽原生门槛。
