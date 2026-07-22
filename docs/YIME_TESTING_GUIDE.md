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

CI 使用 `actions/setup-go` 固定 Go 1.26.4；`go.mod` 的 `go 1.21` 是源码语言兼容下限，不是发布构建器版本。升级构建器时必须在同一变更中复跑 `go vet`、全量测试、race 和连续构建哈希验证。

## 3. 全量根包门禁

`go test ./input_methods/yime -timeout 60s` 已进入 CI。普通单元测试通过可替换后端工厂、独立用户目录和语义化 YAML 断言与真实 librime 隔离；不得删除断言、放宽候选分页守卫或默认跳过普通测试来制造绿色结果。

独立工具通知活动会话的文件协议由 `runtimechange` 包测试，必须覆盖连续通知、并发写入、旧格式迁移、损坏恢复、纯 redeploy 范围和多个 IME 会话独立观察；设置/词库工具还必须覆盖“成功后通知、失败不通知”。Win32 长任务应把外部部署放在 goroutine，并通过 `WM_APP` 返回 UI 线程。语言栏维护菜单还必须覆盖嵌套 `data.id` 点击、默认取消、重复点击拦截、构建失败不通知，以及外部构建后只重建会话而不调用原生全局 redeploy。

运行 `go test ./...` 前后都不应发现 `go-backend/build/go-backend/input_methods` 下残留 `.go` 文件；发布包不得携带复制来的 Go 源码或测试。

普通 IME 测试不得消费开发者真实 `%APPDATA%` 中的 `yime_runtime_change.json`。测试会话应把现有修订号作为基线；只有通知协议专用测试从零修订开始观察，避免候选测试在选择前意外触发 redeploy。

### 3.1 竞态检测

`go test -race ./... -timeout 300s` 是验证基线的一部分，必须在具备 C 工具链的环境运行。Windows Go race 构建依赖 GCC，本机已配置 MSYS2 UCRT64：

```powershell
go env -w CC=C:\msys64\ucrt64\bin\gcc.exe
$env:CGO_ENABLED = "1"
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
go test -race ./... -timeout 300s
```

仓库根目录提供可重复入口，显式设置 CGO、GCC、PATH 和工作区缓存，不依赖当前 shell 的 `go env CGO_ENABLED`：

```powershell
.\tools\test-go-race.ps1
```

若受限执行环境阻止 `cgo.exe` 拉起 GCC，可能会在 `runtime/cgo` 阶段以 exit status 2 结束；应在正常开发终端复跑上述脚本。只有进入项目包编译或测试后的失败才能归因到项目代码。

`IME.processKey` 与 `onCommand` 通过 `entryMu` 串行化，`TestConcurrentKeyAndCommandNoDataRace` 必须在 `-race` 下保持绿色；不得为绕开竞争而删除该测试或放宽入口锁。CI runner 缺少 C 工具链时该门禁可跳过，但不得删除现有并发压力测试。

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

C++ RPC 回归测试通过 `ctest --test-dir build -C Release --output-on-failure` 执行，CI 不得只编译测试程序。

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

# 需要重新拉取 Corrosion（FetchContent）时，git/cmake 不读 WinINET 系统代理，须显式设置
$env:HTTPS_PROXY = "http://127.0.0.1:1081"; $env:HTTP_PROXY = $env:HTTPS_PROXY

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
cmake --build build --config Release
```

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
  -AllowTextServiceMismatch
```

`complete` 表示全部哈希一致；`partial` 只允许被宿主锁定的 TSF DLL 暂未替换；其它缺失或不一致均为 `failed`。`dev-install.ps1` 会自动把最近一次报告写到 `.tmp\last-dev-install-verification.json`。

语言栏或 TSF 问题必须在安装态至少复现一次；不能用源码目录中的临时 EXE 代替。

真实 32 位宿主使用 `C:\Windows\SysWOW64\charmap.exe`。在 64 位 Windows 上，`SysWOW64` 中该文件的 PE machine 应为 `0x014C`；不要用 `System32\charmap.exe` 代替 x86 验证。发布烟雾测试需在该进程中实际激活 YIME，并完成组字、候选和上屏。

### 8.3 已完成的验证记录

- 2026-07-11：未签名开发包真实安装验证，输入响应正常，用户词“云笺试码”“笺砚验码”应用后活动会话直接出词。
- 2026-07-12：完整安装态清单逐项跑完并留痕（[YIME_INSTALL_VERIFICATION_2026-07-12.md](YIME_INSTALL_VERIFICATION_2026-07-12.md)）——重启后干净全量重装、三件哈希构建↔安装全一致、重启自启动实测（开机 27 秒内自动拉起）、7 工具入口不崩、TIP 注册与真实组词日志、CodeIntegrity 核查、runtimechange 协议 `-race` 全绿。签名完成后须以该文档为模板复跑留新档。
- 2026-07-15：真实 32 位宿主 `C:\Windows\SysWOW64\charmap.exe` 人工烟雾测试完成，暂未发现激活、组字、候选或上屏问题；签名产物仍须重复验证。
- 2026-07-15：完成 [YIME 1.4.0 未签名发布演练](YIME_RELEASE_REHEARSAL_2026-07-15.md)；演练修复锁定 TSF DLL 时标准安装器部分卸载后失败的问题。x64 DLL 已安排重启替换，重启后补核最终哈希。
- 2026-07-22：完成 [YIME 1.4.0-dev 安装态复核](YIME_INSTALL_VERIFICATION_2026-07-22.md)；启动器、x86/x64 TSF DLL、Go 后端、全部原生工具、Rime 运行库与部署器均和当前构建物哈希一致，注册表安装根、自启动项及运行进程正常，无待重启的 `.new` 文件；同轮补齐并实装验证布局设计器 VERSIONINFO 与卸载项 `InstallLocation`。该轮是安装完整性复核，不替代签名发行包的宿主输入烟雾测试。

## 9. 修改类型与最低验证

| 修改类型 | 最低验证 |
|----------|----------|
| 文档 | 链接、命令和当前行为核对，`git diff --check` |
| 纯 Go 逻辑 | 目标包测试 + 相关边界测试 |
| 原生工具 UI | 目标包测试 + EXE 构建 + 安装态打开 |
| Rime 配置/部署 | 设置与 Rime 测试 + 用户目录文件核对 + 安装态重载 |
| 语言栏/TSF | 具体点击回归 + C++ 构建 + 安装态宿主验证 |
| 发布构建 | CI 稳定集 + PE 架构门禁 + 可复现哈希 + 签名验证 + 安装烟雾测试 |
