# Yime 测试与验证指南

本文档说明 Yime 的测试分层、CI 稳定集、真实 Rime 测试和安装态验证。测试强度应随修改风险增加，TSF/语言栏、候选分页和部署路径不能只依赖单元测试。

## 1. 测试层级

| 层级 | 目标 | 运行环境 |
|------|------|----------|
| 纯逻辑单元测试 | 词库、设置、反查、布局、构建脚本 | 普通 Windows 开发环境 |
| Go 根包关键回归 | 语言栏命令、分页权、工具启动、用户词库应用 | CI 与本地 |
| 真实 Rime 集成测试 | librime 会话、方案、部署、候选页大小 | CI 与本地独立作业 |
| C++/Rust 测试与构建 | TSF 宿主、启动器、注册组件 | VS/Rust 工具链 |
| 安装态测试 | Program Files 中的真实二进制、进程、注册表和 Code Integrity | 管理员测试环境 |

## 2. CI 稳定集

从仓库根目录运行统一入口：

```powershell
.\tools\test-go.ps1
```

该入口执行 `go vet ./...`、`go test ./...`，并核对根包关键测试名单。CI 必须先通过 `go test -list` 逐项确认名单中的测试真实存在，再执行该名单；不得只依赖可部分匹配的正则。修改 CI 守卫时，应同步更新 [架构文档](YIME_ARCHITECTURE.md)。

GitHub Actions 将 Rust、原生构建、Go 稳定集、真实 Rime、race 和安装器拆为独立作业。前五项可以并行、单独重跑；安装器只消费已通过的原生构建制品，并用提交 SHA 命名和保留制品，回退时可以明确选择上一提交的构建，而不是复用不明来源的本机目录。

CI 当前重点保护：

- 原生 Rime 保有候选分页权
- 语言栏双字标签稳定
- 部署命令和用户词库三方案应用
- 原生工具可执行路径
- 词库重复拒绝、权重边界和中文对话框布局
- 反查顶部单排布局与内容尺寸
- 可复现构建和签名入口

CI 使用 `actions/setup-go` 固定 Go 1.26.4；`go.mod` 的 `go 1.25` 是模块和 Windows Broker/runtime 的最低工具链版本，不得在未重跑 x86/x64 命名管道与进程生命周期门禁时降低。升级构建器时必须在同一变更中复跑 `go vet`、全量测试、race 和连续构建哈希验证。

## 3. 全量根包门禁

`go test ./input_methods/yime -timeout 60s` 已进入 CI。普通单元测试通过可替换后端工厂、独立用户目录和语义化 YAML 断言与真实 librime 隔离；不得删除断言、放宽候选分页守卫或默认跳过普通测试来制造绿色结果。

独立工具通知活动会话的文件协议由 `runtimechange` 包测试，必须覆盖连续通知、并发写入、旧格式迁移、损坏恢复、纯 redeploy 范围和多个 IME 会话独立观察；设置/词库工具还必须覆盖“成功后通知、失败不通知”。Win32 长任务应把外部部署放在 goroutine，并通过 `WM_APP` 返回 UI 线程。语言栏维护菜单还必须覆盖嵌套 `data.id` 点击、默认取消、重复点击拦截、构建失败不通知，以及外部构建后只重建会话而不调用原生全局 redeploy。

运行 `go test ./...` 前后都不应发现 `go-backend/build/go-backend/input_methods` 下残留 `.go` 文件；发布包不得携带复制来的 Go 源码或测试。

普通 IME 测试不得消费开发者真实 `%APPDATA%` 中的 `yime_runtime_change.json`。测试会话应把现有修订号作为基线；只有通知协议专用测试从零修订开始观察，避免候选测试在选择前意外触发 redeploy。

### 3.1 竞态检测

`go test -race ./... -timeout 300s` 是验证基线的一部分，必须在具备 C 工具链的环境运行。Windows Go race 构建依赖 GCC，本机已配置 MSYS2 UCRT64：

```powershell
$env:CGO_ENABLED = "1"
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
$env:CC = "gcc"
go test -race ./... -timeout 300s
```

仓库根目录提供可重复入口，显式设置 CGO、GCC、PATH 和工作区缓存，不依赖当前 shell 的 `go env CGO_ENABLED`。Windows 上应让 `CC=gcc` 通过已加入的 UCRT64 `PATH` 解析；不要把绝对 GCC 路径直接传给 Go 1.26 的 `cgo`：

```powershell
.\tools\test-go-race.ps1
```

若受限执行环境阻止 `cgo.exe` 拉起 GCC，可能会在 `runtime/cgo` 阶段以 exit status 2 结束；应在正常开发终端复跑上述脚本。只有进入项目包编译或测试后的失败才能归因到项目代码。

`IME.processKey` 与 `onCommand` 通过 `entryMu` 串行化，`TestConcurrentKeyAndCommandNoDataRace` 必须在 `-race` 下保持绿色；不得为绕开竞争而删除该测试或放宽入口锁。CI 的 `go-race-msys2` 作业安装 MSYS2 UCRT64 GCC，并且是 `core-build` 的必需依赖；缺少 C 工具链只能视为本地环境未满足前置条件，不能在 CI 中跳过该门禁。

## 4. 真实 Rime 集成测试

真实测试默认不混入普通 Go 稳定集；使用独立入口显式运行：

```powershell
.\tools\test-real-rime.ps1
```

脚本会临时设置并恢复 `YIME_RUN_REAL_RIME_TESTS`。运行前确认 `input_methods/yime/data/` 完整，且没有其它测试或输入法进程同时操作相同 Rime 全局状态。

## 5. 原生 UI 测试规则

Win32 UI 应把可计算布局抽成纯函数并测试：

- 控件顺序和无重叠
- 同排左右边界一致
- 内容边界决定客户区尺寸
- 标签按文字宽度收紧
- 按钮组居中且间距一致
- 最长中文标签不会被截断
- 取消、窗口 X 和确认返回值一致

现有示例：

- `TestBuildUILayoutPlacesSearchControlsInOneRow`
- `TestBuildUILayoutUsesEqualRowWidthsAndContentSizedWindow`
- `TestCenteredButtonRectsCentersGroupAndPreservesGaps`
- `TestWeightAdjustmentRectsFillContentRow`
- `TestNoticeTitleForFlags`
- `TestExecuteApplyNotifiesActiveSession`
- `TestNativeLanguageBarLeavesToggleIdentityAndSortToHost`

C++ RPC 回归测试必须覆盖两个架构：Win32 使用
`ctest --test-dir build -C Release --output-on-failure`，x64 使用
`ctest --test-dir build64 -C Release -R "^PIMERpcResponseTests$" --output-on-failure`。
CI 必须先构建 x64 `PIMERpcResponseTests` 目标并实际运行，不能只构建
`PIMETextService.dll` 或只执行 Win32 测试。

UI 修改还必须构建对应 EXE，并在安装目录中实际打开一次；源码测试通过不代表 Smart App Control、焦点和模态行为正常。

NSIS 守卫还必须确认默认安装目录不会被空注册表值覆盖、必装主组件包含 `go-backend`、安装器不再出现旧 Python/Node 后端路径或组件选择页，以及开发卸载会删除新旧卸载项。

## 6. TSF 与语言栏高风险测试

修改下列区域前先添加具体失败路径的回归测试：

- 语言栏命令 ID、子菜单 `data.id` 回退
- 动态按钮增删、排序、GUID 或 `GetInfo`
- Rime 激活、点击和会话重载
- `menu/page_size` 读写与回读链
- 候选分页所有权

必须遵守 `AGENTS.md`：原生 Rime 会话保持 `UsesBackendCandidatePaging() == true`，不得用 Go 侧候选切片掩盖配置问题。

### 6.1 C++/TSF DLL 调试（Cursor / VS Code）

Cursor 不兼容 `${command:pickProcess}` 时有两条不依赖 QuickPick 的路径：

```powershell
# 启动真实常驻 TSF 宿主并打印 PID；随后使用 launch.json 的 Cursor-safe PID 配置
.\tools\start-tsf-debug-host.ps1 -Architecture x64

# 或完全绕过 cpptools，直接启动 CDB 并附加到新建的 charmap
.\tools\attach-tsf-cdb.ps1 -Architecture x64
```

x86 宿主把 `-Architecture` 改为 `x86`；脚本会使用
`C:\Windows\SysWOW64\charmap.exe`，不能用 x64 宿主替代其安装态验证。

C++ 侧（`PIMETextService.dll` 等组件）用 `cppvsdbg`（由 `ms-vscode.cpptools` 提供）调试。Release 默认产出 PDB，由 CMake 选项控制：

- `PIME_RELEASE_DEBUG_INFO`（默认 `ON`）会给 Release 加 `/Zi` 和链接器 `/DEBUG`，生成 PDB。发布构建可 `-DPIME_RELEASE_DEBUG_INFO=OFF` 关掉以精简产物。标志在 `CMakeLists.txt` 中以去重方式追加，重复 configure 不会累积。
- PDB 位于 `build64/PIMETextService/Release/*.pdb`；`launch.json` 的 `symbolSearchPath` 指向该目录与 `build/PIMETextService/Release`。

`.vscode/launch.json` 提供三个 C++ 配置：

| 配置 | 用途 | 备注 |
|------|------|------|
| `Debug PMERpcResponseTests (x64 Release)` | 直接启动 gtest 风格测试程序 | 冒烟验证 `cppvsdbg + PDB` 链路，不依赖 IME 激活 |
| `Debug IME in charmap (x64)` | 用调试器启动 `charmap.exe`，切音元按键命中 DLL 断点 | launch 模式，能抓到 DLL 加载/注册阶段 |
| `Attach to PIMETextService host (TSF)` / `... in charmap (x64)` | 附加到已加载 DLL 的宿主进程 | **Cursor 里不可用**，见下 |

要点与坑：

- **不用 notepad**：Win11 的 `C:\Windows\System32\notepad.exe` 是重定向存根，启动后转交 Store 版记事本并自身秒退（exit 0），vsdbg 附到存根会随之结束、断点不可能命中。改用 `charmap.exe`（字符映射表，含“搜索”文本框，常驻）。需要真实记事本大文本区时，从开始菜单打开 Store 记事本，再用 attach 配置附加。
- **Cursor 里 attach 失败**：cpptools 1.33.4 的 `pickNativeProcess`（`${command:pickProcess}`）与 Cursor QuickPick API 不兼容，会抛 `TypeError: Cannot read properties of undefined (reading 'id')` → `Process not selected`。两个 attach 配置在 Cursor 里都会失败；**需要 attach 请用 VS Code**（同一份 `launch.json`/`tasks.json`，VS Code 的 cpptools pickProcess 正常）。Cursor 里 launch 配置不受影响。
- **cpptools 装进 Cursor**：Cursor 的 Open VSX 市场没有 `ms-vscode.cpptools`，需从 VS Code Marketplace 下载 **win32-x64** 平台 VSIX（带 `?targetPlatform=win32-x64`）后 `cursor --install-extension <vsix>` 离线安装。下错成 universal/Linux 包会报「Incompatible or Mismatched C/C++ Extension Binaries」。
- **前置**：先用 `.\Reinstall-PIME-Test.cmd` 安装与 `build64` 同位、带 PDB 的开发包，确保宿主加载的 `C:\Program Files (x86)\YIME\x64\PIMETextService.dll` 与源 PDB 一致。
- **断点建议**（`PIMETextService/PIMETextService.cpp`）：`onLangProfileActivated`（切音元时建 Client 连接）验证激活；`filterKeyDown`/`onKeyDown` 验证按键路径。
- **源码改动后**：`requireExactSource` 默认为 true，改 C++ 源后 PDB 校验和对不上、断点绑不上；必须 重建 x64 `PIMETextService` → `Reinstall-PIME-Test.cmd` → 再 F5。

## 7. 构建验证

```powershell
cd go-backend
cmd /c build.bat
```

连续构建哈希验证见 [发布与签名指南](YIME_RELEASE_AND_SIGNING.md)。`go-backend/build.bat` 在变量未设置时会把 `GOCACHE` 和 `GOTMPDIR` 指向仓库 `.tmp`；手工运行 `go test` 遭 Application Control 阻止时也应使用这两个工作区目录。这只解决本地执行位置，不替代发布签名。

## 8. 安装态验证

标准重装：

```powershell
.\Reinstall-PIME-Test.cmd
```

### 8.1 Win32（`build/`）重建前置

`dev-install.ps1` 硬性要求 `build/PIMELauncher/PIMELauncher.exe` 和 `build/PIMETextService/Release/PIMETextService.dll` 存在，缺失会在早期断言处中止重装。重建 Win32 树的前置与命令：

```powershell
# 一次性前置：i686 host 工具链（CMakeLists.txt 已固定 Rust_TOOLCHAIN 指向它）
rustup toolchain install stable-i686-pc-windows-msvc

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
cmake --build build --config Release
```

Corrosion v0.6.1 和 `Cargo.lock` 对应 crates 均已 vendored；上述 configure/build 不访问
GitHub 或 crates.io。`PIMELauncher/.cargo/config.toml` 强制 Cargo 离线解析，依赖缺失或哈希变化会
直接失败。Rust i686 host 工具链仍是必须预装的系统级编译器。

构建完成后必须运行架构门禁：

```powershell
.\tools\test-build-guards.ps1
```

期望结果为 Win32 `PIMETextService.dll` 和 `PIMELauncher.exe` 均为 `0x014C`、x64 DLL 为 `0x8664`；存在 ARM64 DLL 时必须为 `0xAA64`。`build.bat` 不再仅凭空的 `CMAKE_GENERATOR_PLATFORM` 判断旧缓存为 Win32：只有解决方案明确包含 Win32 平台才允许复用，否则必须移走旧 `build/` 后以 `-A Win32` 重建。

不得通过取消工具链固定、删除 `PIMELauncher/.cargo/config.toml` 的 `build.target` 或降级 Corrosion 来“修”链接错误：x64 host 跨编译 i686 时 Corrosion 会把 i686 目标库泄给 host 端 build-script，产生 LNK4272 与大量未解析符号（详见 `AGENTS.md`）。

### 8.2 重装行为与验证顺序

需要完整闭环时，在管理员 PowerShell 中运行：

```powershell
.\tools\dev-build-install-verify.ps1
```

该入口依次执行现有 `build.bat`、规范的 `Reinstall-PIME-Test.cmd`（保留
DLL 锁定时的就地安装路径），最后核对安装文件哈希、注册表和运行中的
PIMELauncher。若 `build/` 或 Go backend 制品被清理，安装会在写系统目录前
明确失败并要求重建。

`PIMETextService.dll` 被 `explorer.exe` 等宿主加载时，脚本自动走就地安装（DLL 跳过、其余全部更新），这是设计行为不是失败；需要干净全量重装（含 DLL 替换、反注册重注册、删安装树）时先重启 Windows 再跑一次。

验证顺序：

1. 比较构建与安装 EXE 的 SHA-256
2. 确认安装文件 VERSIONINFO 与 `version.txt` 一致
3. 重启 PIMELauncher 和 `server.exe`，不需要注销 Windows
4. 复现原始失败路径
5. 检查 `%LOCALAPPDATA%\PIME\Logs\go_backend.log`
6. 检查 CodeIntegrity Operational 日志（注意区分：本机 SAC 强制模式下，未签名 `server.exe` 的 3033/3077 为审计记录；Bonjour/Keyman 等第三方事件与 YIME 无关，先看事件消息中的文件路径再定性）

可先运行机器可读核验，结果同时打印到终端并可写入 JSON：

```powershell
.\tools\verify-installed-runtime.ps1 `
  -JsonPath .\.tmp\installed-runtime.json `
  -AllowTextServiceMismatch `
  -RequireFreshRimeCache
```

`complete` 表示文件哈希、安装状态和三套 Rime 编译缓存均一致。非严格模式下，被宿主锁定的 TSF DLL 暂未替换，或 Rime 后台尚未完成 table/reverse/prism 重建，都可能得到 `partial`；使用 `-RequireFreshRimeCache` 时任何缓存缺失或过期均为 `failed`。其它文件缺失或不一致始终为 `failed`。`dev-install.ps1` 会自动把最近一次报告写到 `.tmp\last-dev-install-verification.json`。

Stage 6D 语气词“啊”还应单独闭合安装数据与用户态缓存链：

```powershell
.\tools\verify-installed-particle-a-stage6d.ps1
```

该脚本逐模式核对安装清单、Program Files 词典和 `%APPDATA%\PIME\Rime` 已部署词典的 SHA-256
及 5,618 行全量别名，确认三个主句子词典仍导入对应别名表，并要求 table/reverse/prism 与编译
schema 缓存全部新鲜。`dev-build-install-verify.ps1` 已把这项检查纳入完整闭环；脚本自身的夹具回归为
`.\tools\test-installed-particle-a-stage6d-verifier.ps1`。

语言栏或 TSF 问题必须在安装态至少复现一次；不能用源码目录中的临时 EXE 代替。

真实 32 位宿主使用 `C:\Windows\SysWOW64\charmap.exe`。在 64 位 Windows 上，`SysWOW64` 中该文件的 PE machine 应为 `0x014C`；不要用 `System32\charmap.exe` 代替 x86 验证。发布烟雾测试需在该进程中实际激活 YIME，并完成组字、候选和上屏。

### 8.3 YimeCore trial 本地构建、事务升级与宿主验证

已安装过受清单验证的 YimeCore trial 后，可在仓库根目录运行：

```cmd
Upgrade-YimeCore-Trial.cmd
```

人工验证时建议从当前用户的普通（非预先提权）终端运行以下命令，并在安装阶段接受一次 UAC；这样升级器会保留
发起用户 SID。运行前先保存工作并关闭所有 Word 窗口：

```cmd
C:\dev\Yime\Upgrade-YimeCore-Trial.cmd /norestart
```

`/norestart` 会跳过脚本末尾的 Windows 重启询问；完成后仍应在方便时重启，再检查任务栏语言项。规范升级入口从
`%LOCALAPPDATA%\YimeCore Experimental Trial\runtime-config.json` 解析当前安装根，逐文件校验其
`package-manifest.json`，再以该安装包为 base 重建当前工作树；安装目录额外生成的
`install-metadata.json` 不属于包清单，也不得被复制到新 staged package。

流程固定为：构建 x64/x86/ARM64 表层并完成隔离包验证、完整 staging 后事务升级、修复并读取真实 Run 值、验证安装态
三模式和 Broker 恢复、运行当前机器可执行架构的 `YimeRegisteredHostTests.exe`。非 ARM64 主机必须编译并校验 ARM64 PE，
但不得把跳过真实 ARM64 宿主执行描述为已经通过 ARM64 桌面验收。运行前必须关闭 Word；安装阶段会
请求一次 UAC。若新版本注册或启动失败，旧版本目录、COM/Profile、TIP、runtime 配置、Run、卸载项
和升级前运行状态必须自动恢复。不能把该流程简化为先删除旧版本再复制，也不能用源码目录中的 DLL
contract 代替注册宿主测试。

> **宿主激活与自动化告警：** 新打开 Word 或其他宿主并不等于已经激活 Yime 试验版；只有 Windows 默认输入法明确设为
> Yime 时才可能自动进入。当前 x64 本机产品验收前应先通过任务栏输入法切换按钮（例如当前“拼”图标）选择 **音元拼音**，不要把冻结旧 Profile 的 **Yime 自研栈试验版** 当作当前产品；或使用
> 本机已经物理确认有效的切换快捷键，再以活动 Profile、宿主实际加载的试验 DLL 或裸数字进入 Yime 组合等证据确认激活。
> 不得为了让自动化通过而修改用户默认输入法。Computer Use 把 `Alt+Space` 解释为 Word 窗口菜单，或只能在 Word 的辅助功能树中
> 看见任务栏但不能操作独立任务栏界面，属于自动化输入/界面附着差异；若物理操作正常且安装态 x64/x86 注册宿主回归通过，
> 必须单列为工具限制，不得误报为 Yime 或 Word 阻塞。Word 未关闭时并发注册宿主还可能报告
> `registered TIP did not become foreground`；保存并关闭 Word 后必须重跑，重跑结果才用于判断安装态。

### 8.4 已完成的验证记录

- 可信签名安装包：签名证书正在申请，等候审批，暂缓相关事项。此项不得以未签名试验包、测试证书或关闭 Windows 安全策略代替。
- 2026-09-02：完成 [YimeCore 试验版安装态验收](YIMECORE_TRIAL_ACCEPTANCE_2026-09-02.md)。当前用户升级、Word x64 新会话、安装态 x64/x86 注册宿主、64 个 Shift 组合及 `Shift+1` 至 `Shift+9` 契约通过；最终 Rime 对照正确性通过但相对延迟/内存失败，真实 ARM64 桌面宿主仍待外部机器执行。E7 不启动。
- 2026-09-01：YimeCore 分支综合审查的 7 项高危与 26 项中危修复完成。Go 全量 test/vet/build 与 `go test -race -count=1 ./...` 通过；x64/x86 DLL contract 和真实 TSF composition 宿主通过；ARM64 表层完成编译及 `0xAA64` PE 校验；E6-C 安装契约通过 staging 后复核、预卸载中途失败回滚、同 SID 每用户卸载项和三架构清单门禁。真实 ARM64 桌面宿主仍需在 ARM64 Windows 上执行。
- 2026-07-11：未签名开发包真实安装验证，输入响应正常，用户词“云笺试码”“笺砚验码”应用后活动会话直接出词。
- 2026-07-12：完整安装态清单逐项跑完并留痕（[YIME_INSTALL_VERIFICATION_2026-07-12.md](YIME_INSTALL_VERIFICATION_2026-07-12.md)）——重启后干净全量重装、三件哈希构建↔安装全一致、重启自启动实测（开机 27 秒内自动拉起）、7 工具入口不崩、TIP 注册与真实组词日志、CodeIntegrity 核查、runtimechange 协议 `-race` 全绿。签名完成后须以该文档为模板复跑留新档。
- 2026-07-15：真实 32 位宿主 `C:\Windows\SysWOW64\charmap.exe` 人工烟雾测试完成，暂未发现激活、组字、候选或上屏问题；签名产物仍须重复验证。
- 2026-07-15：完成 [YIME 1.4.0 未签名发布演练](YIME_RELEASE_REHEARSAL_2026-07-15.md)；演练修复锁定 TSF DLL 时标准安装器部分卸载后失败的问题。x64 DLL 已安排重启替换，重启后补核最终哈希。
- 2026-07-22：完成 [YIME 1.4.0-dev 安装态复核](YIME_INSTALL_VERIFICATION_2026-07-22.md)；启动器、x86/x64 TSF DLL、Go 后端、全部原生工具、Rime 运行库与部署器均和当前构建物哈希一致，注册表安装根、自启动项及运行进程正常，无待重启的 `.new` 文件；同轮补齐并实装验证布局设计器 VERSIONINFO 与卸载项 `InstallLocation`。该轮是安装完整性复核，不替代签名发行包的宿主输入烟雾测试。
- 2026-07-24：候选窗独立组句分段条完成安装和重启验证；已安装 `server.exe` 与构建物 SHA-256 一致，x86/x64 `PIMETextService.dll` 也分别一致。Notepad、Codex IDE 已完成初步试用，确认功能可见并有实际作用；由于鼠标分段改选需要长期使用评价，本轮记录为“进入观察期”。真实 x86 宿主基础链路曾于 2026-07-15 初步测试通过；Phase 5.6 的 x86 复测安排在取得代码签名后，随签名产物重复第一/中间/末段切换和发行验收。

### 8.5 独立组句分段条

鼠标组句纠错必须点击 Yime 自有候选窗中的分段条，不得点击宿主编辑区中的
composition 文字。源码测试需覆盖：

- librime `commit_text_preview` 与带空格 preedit 生成稳定的
  `{start,end,code,text,active}` 映射；
- 已选汉字替换原始编码后，缓存映射仍能把汉字与原编码对应；
- C++ 宿主只接受字段完整、范围有效的结构化分段；
- 点击发送原始编码范围，优先使用 librime `set_caret_pos` 直达，拒绝重入、
  越界、循环和无进展导航，并保留键盘 navigator 兼容回退；
- 导航响应不得携带上一按键遗留的 commit；
- 导航失败必须回送当前 composition 与候选，不得用空响应结束组句；
- 分段条点击优先于候选项命中，且窗口保持 `WS_EX_NOACTIVATE`。

安装态必须覆盖 Notepad、Codex IDE 和
`C:\Windows\SysWOW64\charmap.exe`。详细步骤、显示示例和失败判据见
[独立分段条使用与安装态验收计划](project/SENTENCE_SEGMENT_CORRECTION_TEST_PLAN.md)。

## 9. 修改类型与最低验证

| 修改类型 | 最低验证 |
|----------|----------|
| 文档 | 链接、命令和当前行为核对，`git diff --check` |
| 纯 Go 逻辑 | 目标包测试 + 相关边界测试 |
| 原生工具 UI | 目标包测试 + EXE 构建 + 安装态打开 |
| Rime 配置/部署 | 设置与 Rime 测试 + 用户目录文件核对 + 安装态重载 |
| 语言栏/TSF | 具体点击回归 + C++ 构建 + 安装态宿主验证 |
| 发布构建 | CI 稳定集 + PE 架构门禁 + 可复现哈希 + 签名验证 + 安装烟雾测试 |
