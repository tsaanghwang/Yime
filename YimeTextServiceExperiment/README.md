# YimeTextServiceExperiment：自研 TSF 表层（试验）

本目录是 YimeCore 替换试验（E6-B/E6-C）的 C++ TSF/COM 薄表层。它只负责
Windows 文本服务框架接入、按键转发、预编辑写入、候选呈现和提交；全部输入法
逻辑（切分、候选、排序、学习）由 Go 侧 `YimeBroker` 通过命名管道提供。

总体设计、阶段门禁与验收证据见
[docs/project/YIMECORE_REPLACEMENT_EXPERIMENT.md](../docs/project/YIMECORE_REPLACEMENT_EXPERIMENT.md)。
本组件不改变生产 PIME/Rime 链，使用独立 CLSID / profile，与
`PIMETextService.dll` 可并存。

## 构建

顶层 CMake 已包含本目录；也可单独配置：

```powershell
cmake -S YimeTextServiceExperiment -B build_yts -G "Visual Studio 17 2022" -A x64
cmake --build build_yts --config Release
```

产物：

- `YimeTextServiceExperiment.dll` — TSF 文本服务（静态 CRT `/MT`）。
- `YimeTextServiceContractTests.exe` — 契约测试宿主（`ctest` 注册，参数为 DLL 路径）。

试用安装需要 x64、x86 与 ARM64 三种架构各构建一份（见
[tools/yimecore/run-e6c-package-experiment.ps1](../tools/yimecore/run-e6c-package-experiment.ps1)）。

## 源码结构

| 文件 | 职责 |
| --- | --- |
| `DllEntry.cpp` / `ModuleState.h` | DLL 入口、类工厂、模块引用计数。刻意不导出 `DllRegisterServer`，注册统一走注册工具。 |
| `TextService.cpp/.h` | `ITfTextInputProcessorEx` / `ITfKeyEventSink` 主体：激活/停用、按键分发、composition 生命周期、UI 元素注册。 |
| `SurfaceSession.cpp/.h` | 表层会话状态机；把 Broker 的每次响应当作权威完整快照（见 AGENTS 约束）。 |
| `BrokerClient.cpp/.h` | 命名管道客户端：newline 分帧 JSON 请求/响应，256KB 帧上限，断线重连。 |
| `BrokerEndpoint.cpp/.h` | 管道名解析：默认 `\\.\pipe\YimeBroker.YimeCoreTrial.v1`，可用环境变量 `YIME_TEXTSERVICE_EXPERIMENT_PIPE` 覆盖。 |
| `CompositionEditSession.cpp/.h` | 同步/异步 TSF edit session：开始/更新/终止 composition、提交文本。异步结果只经 completion handler 生效。 |
| `CandidateListUIElement.cpp/.h` | `ITfCandidateListUIElement`，宿主接管候选 UI 时的数据源。 |
| `CandidatePopup.cpp/.h` | 宿主要求自绘时的自有候选窗口（鼠标选择、分页）。 |
| `LanguageBarItem.cpp/.h` + `LanguageBarResources.*` | 语言栏按钮（模式图标、右键菜单）。 |
| `PunctuationPalette.cpp/.h` | `Shift+\` 一次性本地标点层（固定映射表见实验主文档）。 |
| `KeyContract.cpp/.h` | 按键契约：裸数字键始终组码，`Shift+1..9` 选候选，`Ctrl+Left/Right` 段导航，`Ctrl+Delete` 遗忘候选。 |
| `OutputTransform.cpp/.h` | 提交前的输出变换（全/半角等）。 |
| `ExperimentSettings.cpp/.h` | 试验设置读写：`%LOCALAPPDATA%\YimeCore Experimental Trial` 下 JSON + 文件锁。 |
| `RegistrationTool.cpp` | 独立注册工具（`YimeTextServiceRegistration.exe`）：`register` / `unregister` / `status`，需提升令牌；失败自动回滚。 |
| `tests/` | 契约、Broker 桥、TSF composition、注册宿主四组测试。 |

## 关键不变量

- 裸数字键永远用于组码，绝不选候选；候选选择只用 `Shift+1..9`。
- Broker 每次响应是完整权威快照；表层不得回填旧的 sentence/候选缓存。
- Broker 不可达时按键必须报告"未吃掉"，宿主文本保持不变。
- 选择键宿主诊断默认关闭，普通按键路径不得访问诊断文件。仅在启动宿主前设置
  `YIME_TEXTSERVICE_EXPERIMENT_KEY_DIAGNOSTICS=1` 时写入 `evidence/tsf-key-host.log`；
  该文件达到 1 MiB 后停止追加，删除后才重新采集。
- 段候选模式只在显式点击句段后进入；替换后由 Broker 决定恢复全局候选。
- 注册/反注册只经 `YimeTextServiceRegistration.exe`。AMD64 系统使用 x64 工具注册
  profile、x86 工具补齐 COM 视图；ARM64 系统由 ARM64 工具注册 profile，并由
  x64/x86 工具补齐兼容进程所需的 COM 视图。

## 当前兼容性状态（截至 2026-09-01）

- `BrokerClient` 使用有截止时间的 OVERLAPPED 管道 I/O；连接使用
  `SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION`，超时取消会等待 I/O 真正结束后再释放状态。
- 自绘候选窗处理 `WM_DPICHANGED`，尺寸以 DIP 为基准按窗口 DPI 缩放。
- E6-C 包同时包含 x64、x86 与 ARM64 表层构件；非 ARM64 构建主机只编译和校验
  ARM64 PE，真实 ARM64 宿主执行门禁需在 ARM64 Windows 上运行。
