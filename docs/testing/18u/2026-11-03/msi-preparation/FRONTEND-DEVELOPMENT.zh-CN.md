# MSI：安装版触控前端开发交接

2026-11-03，分支 `codex/msi-18u-test-preparation-20261103`。用户要求继续完成完整触控前端与普通应用 TSF 接入。本轮修改源代码、离线制包和开发回归；未安装或注册新产品，未改默认输入法、现有用户数据，未进行真人指笔实测。MSI 当前安装仍为固定 test.6。

## 实现

前端复用现有 `keyboardlab` 会话与同包三模式完整词典，保留 18u 盘面、CN/EN、标点、候选、翻页、取消、设置与指笔事件规则。新安装构建固定 `installedTSFOnly=1`，拒绝旧 SendInput 路线；启动核对安装维护清单中的 descriptor 锚、全部载荷和当前 exe 身份。预览、包内存检查仍为独立入口。

专用 TIP 的 `TouchFrontendEndpoint` 在实际激活的 TSF 线程创建有界命名管道，验证客户端进程路径、登录会话、用户、登录 LUID 和完整性级别。前端核对管道服务端 PID，绑定当前目标的 HWND/进程/线程；TIP 另行取得真实文档及顶层 context。焦点、上下文和激活生命周期变化使旧绑定失效。普通应用不需要调用自有检查宿主接口。

**当前路线为“前端完整引擎会话 → 最终编辑 IPC → 激活 TIP 的 DoEditSession → 文档”。** 不是将全量 UI 事件接到旧 CN/variable Broker 协议。旧 Broker/Runtime 自有宿主检查保留独立职责；不把旧协议误写为三模式，不连接标准产品、不共享可写用户状态。这是对准备清单中原拟 Broker 事件转发方案的实现调整。

只有实际编辑回调成功才返回 applied；排队、超时、写失败或应答丢失均不重放。前端传输当前同步等待，单次 I/O 最长等待 5 秒，可能短暂阻塞键盘 UI；这不是已达成的触控延迟指标。

支持文本替换、退格、Delete、左右移动和选区、全选、文档首尾；左右与删除避免拆开 UTF-16 代理对。Enter 插入 CRLF、Tab 插入制表符；不是控件切换。仅 Ctrl+A 映射全选；其它 Ctrl/Alt、上下方向、功能键和未支持修饰组合明确报错，不伪造系统快捷键。本阶段不是全 Windows 快捷键或所有宿主兼容性完成。

## 验证记录

| 检查 | 本地结果与边界 |
|---|---|
| `go test ./internal/tsffrontend ./cmd/yime-touch-keyboard` | 通过；包括未知结果不重放、回执身份、安装入口、维护锚和既有前端回归 |
| `test_installed_frontend_package.py` | 7/7；同源、完整清单、资源与布局不混包，以及 test.7 完整 ZIP/六个签名观察的模拟制包 |
| `test_package_installed_18u.py` | 原有 12/12 通过；旧 test.6 路径保持 |
| `test_prepare_msi_18u_test6.py` | 9/9；固定基线拒绝路径 |
| `test_assemble_installed_18u.py` | 14/15；链接输入用例在创建夹具时遇到 WinError 1314，即使提升沙箱权限仍失败；未跳过或放宽测试 |
| `TouchFrontendEditTests.cpp` | LLVM-MinGW 原生 x64 编译执行通过；内存 TSF 替身，中文替换、选区、Unicode、延迟失效及拒写；没有注册或真实宿主激活 |
| 完整安装前端开发构建 | `.generated/installed-frontend-development-20261103-r2`；源码含未提交修改，只是本地开发候选，不能冒充固定交付 |
| 开发前端 `--check-package` | 通过；18u/100键及 variable/full/shorthand 分别在内存确认“你”，未向宿主发送 |
| 完整 DLL 集成编译 | 本机未装 MSVC/Windows SDK；LLVM-MinGW 缺少旧工程使用的 `ITfTextInputProcessorEx` 等 SDK 接口，不能替代完整 MSVC 构建。新 endpoint 本身已通过编译 |
| 真实进程间管道、激活 TIP、Word/Edge | 尚未实测；内存替身不能替代 |

便携编译器只解压到仓库 `.generated/validation-tools`，未安装或改 PATH。下载官方 LLVM-MinGW `20261020-ucrt-x86_64`，核验 SHA-256 `fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd` 后使用。

## 构建与后续入口

CI `installed-18u-compile.yml` 已为本分支配置：启用 `YIME_TOUCH_PRODUCT` 与 `YIME_TOUCH_FRONTEND`，MSVC 编译专用 DLL 和内存编辑测试，运行新 Go/制包回归，以 `build_touch_keyboard_desktop.py --installed-tsf` 构建完整前端，再将 `--frontend` 传给安装制包器生成 test.7。前端必须来自相同 clean commit；六个 PE 均进入签名观察。

CI 通过、完整包可下载且 SHA-256 固定后才算完成新包交付。安装、真实应用和指笔验收必须使用该新包独立记录；本地脏树前端、旧 test.6、旧实验包结果不合并为新版通过。使用 [INSTALLED_TSF.zh-CN.md](../../../../../prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md) 了解实际操作语义，使用本目录空白结果表记录新批次。现阶段不要执行旧 `.tmp` 命令或重装 test.6。
