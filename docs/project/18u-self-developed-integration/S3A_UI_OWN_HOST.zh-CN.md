# S3a：18u 实际 UI 路径与持久自有 TSF 宿主

2026-11-01。隔离分支 `codex/18u-own-host-ui-s3a-20261101`。基于 S2b 远端 `720fcd514330f6f51bd6b837990da971c692b520` 的同树本地提交 `0e1bd39bc72e3bb3d7da8ab146c97179a9d7ca39`。本阶段仅开发侧隔离实现；不是用户安装或重测指令。

## 已确认的前置门

S2b 在固定提交的[原生 Windows x64 CI](https://github.com/tsaanghwang/Yime/actions/runs/41307255280)中，7 个自有 TSF 场景均实际通过、无 skip；共享 edit 的合成回归 36 checks、0 failures。[普通 Build](https://github.com/tsaanghwang/Yime/actions/runs/41307255306)全部成功。原 S2b 文档描述的是发布前状态，保留历史，不倒改成当时已通过。

证据 artifact `13083548338`，ZIP SHA-256 `e169493a1f36e9f976c1f9e747d550d7dfed968fc73b0913bc30ac7b059e7ee0`。它证明自有 context 的同步及受控异步合同，不证明完整产品或用户宿主。

## 本片边界

复用现有18u盘面的窗口鼠标消息/命中、DOWN/UP、候选 stamp 和 preview 操作路径，通过显式实验适配连接唯一 `touchhostbridge.Session`，不另造一套输入控制器冒充 UI 接线。固定 variable/CN；未支持模式、语言、裸字面输出与导航必须拒绝，不能落回 SendInput 或本地 editor 冒充 TSF 成功。默认预览和既有 host-input 入口保持原行为。

Go UI 与 C++ TSF 的语言边界采用仅父进程启动的固定绝对路径子宿主及匿名 stdin/stdout 管道。没有监听端口、命名服务或第三方客户端；不是正式跨进程产品认证设计。原生宿主持续拥有同一个 document/context；不以每次新建一次性子进程伪装连续输入。

S3a 主路径先用真实同步 edit 完成和独立 read-edit 读回，保持 STA 操作单线程；S2b 的 7 个同步/异步场景仍独立回归。不把同步主路径称为自然异步调度验证。所有数据仅为测试自建 context，不能写用户文档；ActivateEx 抑制标志不是运行于用户桌面的安全保证，此入口仅隔离 Windows CI 使用。

## 最小验证与停止条件

- 真实窗口消息经原有 UI 命中/释放路径进入专用会话，候选提交只有 actual edit 完成且独立读回一致才 Applied。
- 连续提交保留同一宿主 context，核对累计正文长度与精确内部内容；过期候选释放和重复释放不追加。
- 明确失效后旧会话不再使用；重新绑定使用新 epoch/新会话，正文保留，未提交组合不继承。
- 关闭有受控确认和子进程退出；超时/断连/无法确认的提交为 Unknown，不自动重启或重放。
- 原 S2b 7 场景、标准版与原 preview 回归保留。

自动投递本窗口消息属于**合成 UI 路径证据**，不是真人鼠标、手指、笔或可日用前端验收。小测试词典不代表完整词库/所有模式。此片没有注册产品 profile、安装、Word/Edge 接入、ARM 验证或修改标准/Rime 数据。

## 当前状态

本地实现已完成；Linux 六包回归、UI/bridge race 检查及 Windows amd64 Go 测试交叉编译通过。Windows C++ 与三个 UI 原生场景尚未编译执行，S2b 七场景在本提交也尚未重新运行；不得写 S3a 原生通过。新分支发布及限定 CI 需要单独确认。下一片才根据结果确定独立候选包、实际 UI 启动入口、正式激活/信任和 profile 并存策略，不能直接跨到安装。

## 实际测试层次和有界协议

- `TestTouchBridgePersistentOwnHostUI` 三组：continuous-commit、stale-candidate、invalidate-rebind。输入键与候选通过真实 HWND 的 `SendMessageW` 到既有 `windowProc`；重复 UP 不追加。过期候选组以直接调用 preview.page 改变 revision，不冒称翻页按钮已经验过。失效/重绑由测试显式控制，不是自然用户焦点切换证据。
- 本窗口 WM_CLOSE 后核对窗口销毁；随后确认子宿主 close ACK、EOF、exit 0。这是受控测试关闭序列，不等于已存在完整产品退出协调器。
- Linux fake sink 只证明 Unknown 不重放、不支持动作无 fallback、旧键/clear/backspace stamp 拒绝；不算 TSF 证据。
- 子宿主使用单 outstanding、单调 seq/epoch；init/commit/read/invalidate/rebind/close，16 KiB 帧、每请求 5 秒/每子进程 30 秒、最多 64 请求/16 提交/1024 UTF-16 累计正文。未知、错误或超时终止并回收本 child，不重启重放。stdout 仅协议；只报告测试正文长度和匹配布尔，原生内部独立读回全文。
- `GetFileType` 仅核对 pipe 类型，并不认证匿名性或父身份；连接信任来自测试直接创建固定绝对路径子进程及专属匿名管道。没有正式产品 IPC 安全声明。
- `.github/workflows/touch-bridge-ui-host.yml` 只限本分支：原生 MSVC 三目标编译、36 条合成 guard 回归、S2b 七场景和本片三组 UI 场景。任一缺失、skip 或失败均失败，保留日志与固定源码/宿主哈希；尚未发布运行。

独立静态审阅无剩余本地交付阻断；独立两包 Linux race、Windows amd64 Go 交叉编译、diff-check 通过。审阅修正了旧 DOWN 的全 revision 校验、侧区退格误入本地 editor、原生读回上界截断与初始化清理；默认产品路径未接入实验适配。
