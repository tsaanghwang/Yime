# S2a：单x64自有TSF上下文的选字提交切片

接续S1本地提交 `8b92da9ff53ed59d9bec51932167e0aa5b565fee`（远端同树 `92003802791e78fdba6ab7b6322b9b5a7c6450dc`）。本地分支 `codex/18u-tsf-own-host-s2-20261101`。这是S2的第一小片，不是完整18u前端/正式安装产品完成。

## 实际路径与边界

现有 `YimeTextServiceExperiment/tests/TsfCompositionTests.cpp` 已使用系统 `ITfThreadMgr` 创建自有document/context；可复用这一路径，不要求注册COM产品或改默认输入法。新增仅测试用harness直接复用 `CompositionEditSession.cpp` 的 `ApplyBrokerUpdateToContext`，由Windows Go测试驱动：

```text
专用投影小词典 -> keyboardlab/YimeCore -> S1一次性Commit(Pending)
 -> 自建子进程（有界测试JSON请求）
 -> 自有TSF document/context，TF_ES_SYNC写入
 -> 实际edit完成回调 + 独立read-edit读回核对
 -> 有界结果 -> S1 Complete(Applied)
```

不得把请求排队、进程启动或SendInput数量当成功。失败/超时/输出不可信时不能给Applied，不自动重放。测试代码只创建自己子进程及TSF context，不主动观察或改写用户文本，不注册或显式激活产品DLL。ThreadMgr激活使用NOACTIVATETIP/NOACTIVATEKEYBOARDLAYOUT降低自动激活影响，但这些标志不是永久隔离保证；本片只供隔离Windows测试环境执行，不是用户机可执行任务。测试文本是合成夹具，不采集全局输入。真实Windows通过后也只证明自有TSF上下文，不是Word/Edge/已安装产品。

## 为什么先同步

共享edit层尚无传入的执行时focus guard。本片不修改其正式运行逻辑，先限单STA、TF_ES_SYNC及明确自有焦点，拒绝其它上下文和重复commit，并核对无额外写入。此结果不能证明异步排队期间焦点竞争安全；异步实际执行时的context/epoch guard、失焦取消和延迟完成仍是S2后续门槛，不能以本片成功越过。

## 验证门槛与限制

- Linux：S1及相关Go回归；Windows专有Go测试可交叉编译，但不代表运行。
- Windows原生：编译新增C++测试target，然后显式提供harness路径执行Windows集成测试。缺路径默认普通套件可skip；一旦显式请求，路径无效必须失败，不能skip变绿。
- 正例必须产生实际DoEditSession完成和独立文本核对；负例必须验证错误focus和重复commit不产生额外edit/正文。
- 不访问真实用户窗口、不安装注册、不运行原型UI、不改校准、不碰Rime/标准投影/标准注册身份。
- 当前云端为Linux，无MSVC或Windows原生执行环境。C++编译和Windows实际运行在取得相应远端构建授权/环境前均为未执行，不宣称原生TSF通过。

## 后续与停止

此分支仅本地实现/审阅。新增代码发布需另报范围获得确认，不继承S1四文件发布授权。发现跨上下文写入、重复写入、伪完成确认或标准回归则停止，不放松测试。S2a之后再完成必要的异步/失焦和完整动作合同，随后才接18u前端；不扩ARM、四机或安装。

## 后续隔离Windows验证命令（尚未执行，不供用户电脑运行）

在独立Windows x64 CI环境构建本分支后：

```text
cmake -S YimeTextServiceExperiment -B <fresh-build-dir> -A x64 -DYIME_TOUCH_BRIDGE_OWN_HOST=ON
cmake --build <fresh-build-dir> --config Release --target YimeTouchBridgeOwnHost
# 将 YIME_TOUCH_BRIDGE_OWN_HOST 设为本次构建EXE的绝对路径，仅当前进程环境
# 在 go-backend 执行：
go test ./internal/touchhostbridge -run TestNativeOwnTSFCommit -count=1 -v -timeout=90s
```

CI必须显式设置该路径，保存实际运行（非skip）的测试输出；新代码与对应CI发布仍待独立批准。无安装或产品profile注册步骤。

## 本地验证结果（2026-11-01）

- Linux最终六包回归（touchhostbridge、keyboardlab、touchkeyboard、touch-keyboard命令、标准codemode、yimecore）全部通过；Windows专有测试不在该运行内。
- Windows amd64 Go测试二进制交叉编译通过，未执行该EXE。
- diff空白检查通过。共享CompositionEditSession与标准运行代码未改；CMake仅新增默认关闭的测试target。
- **C++编译、Windows原生三个场景均未执行，S2a验证门尚未通过。** 下一步只应在获准的隔离Windows环境验证，不把本地静态审阅等同原生行为。
- 独立静态审阅无剩余本地交付阻断；审阅中收紧ThreadMgr激活隔离声明及epoch类型检查。原生运行门槛并未因此豁免。
