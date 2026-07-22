# Yime 项目综合评估与收口报告

> 评估日期：2026-07-22
>
> 适用基线：`1.4.0-dev`，含 2026-07-22 的拆分 CI、布局设计器和安装态复核
>
> 相关文档：[架构](YIME_ARCHITECTURE.md) | [测试](YIME_TESTING_GUIDE.md) | [发布与签名](YIME_RELEASE_AND_SIGNING.md) | [原生 UI](YIME_NATIVE_UI_GUIDELINES.md)

本文汇总近期两轮全面评估及连续修复的结果，用于回答三个问题：当前项目是否完整、已处理哪些系统性风险、正式发布前还缺少哪些验证。专题实现细节仍以各专项文档为准，本报告只维护结论、证据和未闭环事项。

## 1. 总体结论

Yime 已从“功能基本可用但工具链和安装态边界不稳定”进入“开发版可持续验证、正式版具备明确发布门禁”的阶段。输入法核心、原生工具、用户词库、反查、语言栏命令、异步部署、构建和 CI 均已有回归保护。

当前不应把“CI 绿色”等同于“正式发布完成”。开发包允许未签名；公开发行仍必须完成可信签名和安装态 TSF 冒烟测试。

| 领域 | 当前状态 | 结论 |
|------|----------|------|
| 输入法核心与 Rime | 稳定 | 原生分页权、候选数回读、方案切换和用户词库链路有守卫 |
| Win32 工具 UI | 完整度较高 | 高级布局、设置、反查、词库、审查、屏蔽、诊断和工具箱均为原生窗口，主要列表与缩放布局已统一 |
| 活动会话刷新 | 已完成 | 设置、词库和 redeploy 使用独立累积修订号，不再互相覆盖 |
| 语言栏 | 已清理 | 保留静态标签和稳定命令 ID；高风险点击路径有回归测试 |
| 构建与打包 | 稳定 | 9 个 Go EXE 可复现、统一图标和 VERSIONINFO、包内不携带 Go 源码 |
| CI 与测试 | 完整度较高 | 构建契约、Rust、原生构建、Go、真实 Rime、MSYS2 race 和安装器已拆分；`core-build` 是聚合 required check |
| 正式签名发布 | 开发版待发行 | `version.txt` 当前为 `1.4.0-dev`；正式标签前才切换 `1.4.0`，公开发行仍待受信任签名产物验证 |
| 安装态验证 | 当前开发版已复核 | 07-12 是历史全量验收；07-22 已按 9 个 Go EXE、布局设计器、安装根和文件同步重新复核，详见[07-22 安装态复核](YIME_INSTALL_VERIFICATION_2026-07-22.md) |

## 2. 两轮评估已处理事项

### 2.1 工具与用户体验

- 词库管理补齐连续添加、编辑、删除、权重步进、系统词重复拒绝和用户词库应用链路。
- 统一原生对话框中文按钮和居中布局，消除残留的 `OK`、`Yes/No`。
- 反查工具重新排列查询控件，统一横排宽度并让内部布局撑开主窗体。
- 设置、词库和反查等工具改为 Go + Win32；PowerShell 只保留在开发、测试、构建、安装和维护路径。
- 词库、反查、系统词库审查和屏蔽词表使用带表头的 ListView；工具箱和主要子工具支持内容适配或响应式布局。
- 设置工具提供带清单与 SHA-256 校验的可移植用户数据备份/恢复，恢复前自动创建安全快照并在完成后重建、通知运行会话。
- 设置和词库部署移到后台 goroutine，通过 `WM_APP` 回到 UI 线程，避免窗口卡顿和控制台闪烁。
- 语言栏“同步/重新部署”收进受保护的“数据维护”子菜单并二次确认；显式重新部署改为外部后台构建、当前方案校验和安全边界会话重建，重复点击被拦截，不再在宿主回调中全局重启 librime。

### 2.2 输入法与宿主集成

- 用户词库重新接入三种 Rime 方案，并在应用后通知已存在的输入会话。
- `yime_runtime_change.json` 从单一 scope 改为设置、词库和 redeploy 的独立累积修订号。
- 通知写入增加跨进程锁、旧格式迁移、损坏文件备份、Windows 文件替换重试和多会话独立消费。
- 语言栏实验性动态移动、排序和固定 GUID 逻辑已清理；命令解析继续兼容宿主通过 `data.id` 上报子菜单点击。
- 保持 Rime 拥有原生候选分页，不使用 Go 侧切片绕过候选数配置。
- `IME.processKey` 与 `onCommand` 入口加互斥锁串行化，消除并发按键与命令访问共享状态的数据竞争；生产 TSF 公寓线程本就串行，该锁为无竞争零开销，但使 race 检测器认可的并发场景也安全。

### 2.3 构建、CI 与发布

- Go 构建默认使用仓库内 `GOCACHE`/`GOTMPDIR`，降低临时目录被策略阻止或无权限的概率。
- 9 个 Go EXE 使用稳定版本、`-trimpath -buildvcs=false`、统一 Yime 图标和 VERSIONINFO；连续构建哈希一致。
- 打包脚本递归清理复制目录中的 `.go` 文件，避免发布包泄露源码并防止 `go test ./...` 重复执行打包副本。
- CI 增加反查测试、根包测试、Rust 格式检查和 CTest 实际执行。
- 标签发布强制导入可信签名证书；临时 PFX 在导入后删除。
- 签名前检查私钥、有效期、RSA 和代码签名 EKU；签名后检查签名者指纹及时间戳。
- CI 明确区分带提交 SHA 的 `YIME-unsigned-test-installer-{sha}` 和 `YIME-signed-installer`。
- CI 已拆为可独立重跑的并行作业，`installer-package` 只消费全部前置门禁通过的原生制品，`core-build` 聚合最终结论；普通分支制品名为 `YIME-unsigned-test-installer-{sha}`。
- 新增“高级布局”原生工具，可复制、试打、保存并原子应用个人布局；布局应用同步重建三套系统/用户词典并迁移学习记录。
- 修复 Win32 剪贴板写入失败路径中的 `HGLOBAL` 泄漏，以及 Rust 集成测试临时目录泄漏。
- 修复开发卸载残留卸载项导致 `$INSTDIR` 变空、文件误写盘符根目录的问题；安装初始化保留默认路径并增加二次兜底。
- Yime Go 后端进入 NSIS 必装主组件；安装器、日常构建和 CI 均不再构建或交付旧 Python、Node、McBopomofo、libchewing 输入法。
- 应用用户词库前同步三套共享 schema 到用户目录，升级遗留的 `custom_phrase` 引用不会再阻断 full/shorthand 用户词。
- 修复反查加载测试 fixture：单一等长真源重构后 `full` 列需为 4 的倍数，旧 `b`/`zh` 短码改为 `~~dd`/`zzzz` 等合规等长码。
- 配置本机 MSYS2 UCRT64 GCC 16.1.0（`go env CC` 持久化），`go test -race ./...` 全量通过，补齐此前缺失的竞态检测完成证明。
- 修复 Win32 `PIMELauncher` 重建链路：Corrosion 升级到 v0.6.1 并在根 `CMakeLists.txt` 固定 `Rust_TOOLCHAIN=stable-i686-pc-windows-msvc`（host==target==i686，消除跨编译时 build-script 被链 i686 库导致的 LNK4272/145 个未解析符号）；前置为 `rustup toolchain install stable-i686-pc-windows-msvc`。
- 2026-07-14 复评收口：Win32 回调地址改用显式结构体复制，`go vet ./...` 恢复绿色；CI 固定 Go 1.26.4，并在执行关键测试前逐项确认测试名存在；新增 `tools/test-go-race.ps1` 固化 CGO/GCC/PATH/缓存环境；开发包版本从历史 `1.3.0-beta2` 调整为 `1.4.0-dev`。
- 2026-07-14 安装复核发现旧 `build/` 实为 x64，却因空的 `CMAKE_GENERATOR_PLATFORM` 被误判为 Win32。现已重建显式 Win32 树，并新增 `tools/test-build-guards.ps1`：本地构建、开发安装和 CI 均强制核对 x86/x64/ARM64 PE machine type。后续安装复核又确认旧版 `meow`/`simple_pinyin`/`fcitx5` 演示包已无 `ime.json` 且不可激活，现已删除源码、生产注册和默认回退；协议测试改用测试专用假服务，Go 打包只复制带 `ime.json` 的运行时目录，NSIS 升级以非递归方式清理三个旧空目录。
- 2026-07-15 当日曾将版本切到 `1.4.0` 并以旧聚合作业名 `build` 做发布演练；后续开发已恢复 `1.4.0-dev`，当前聚合门禁名为 `core-build`。当日 32 位 `SysWOW64\\charmap.exe` 宿主人工烟雾测试仍作为历史验证记录保留。
- 2026-07-15 未签名发布演练发现并修复标准安装器的锁定 DLL 升级缺陷：旧逻辑会递归删除后以退出码 2 中止，留下部分安装；新逻辑使用 `.new` 暂存和 `/REBOOTOK` 原位替换。修复后安装器返回 0，YIME-only 目录、版本、许可证、注册表和启动项均通过核对；当前 x64 DLL 已安排在下一次 Windows 重启时替换，重启后需补做最终哈希确认。详见[1.4.0 发布演练](YIME_RELEASE_REHEARSAL_2026-07-15.md)。

## 3. 固化的架构约束

以下约束不得为了局部问题而绕开：

1. 真实 Rime 会话继续拥有候选分页权，`nativeBackend.UsesBackendCandidatePaging()` 保持为 `true`。
2. Go 的 `candidatePageSize` 必须通过 `rimeState.PageSize` 与 Rime `menu.page_size` 回读同步。
3. 语言栏菜单 ID、反查 ID 或宿主点击解析发生变化前，先增加具体点击路径的回归测试。
4. 用户工具运行时不得调用 PowerShell；耗时工作不得阻塞 Win32 UI 线程。
5. 活动会话通知是广播状态，不是单消费者队列；每个 IME 会话独立记录已处理修订号。
6. 开发包和发行包必须明确区分，未签名开发包不得作为公开正式版本上传。
7. 源码修复只有在重新构建、安装并重启相关进程后，才算完成安装态验证。

## 4. 验证基线

本轮已通过：

```powershell
cd go-backend
go vet ./...
go test ./... -shuffle=on -count=2 -timeout 120s
go test -race ./... -timeout 300s
# 或从仓库根目录运行：.\tools\test-go-race.ps1

cd ..\PIMELauncher
cargo fmt --check
cargo test --verbose

cd ..
ctest --test-dir build -C Release --output-on-failure
git diff --check
```

验证结果：

- Go 全量测试通过，运行时通知并发压力测试连续 20 轮通过。
- Go 竞态检测全量通过：本机 MSYS2 UCRT64 GCC 16.1.0 已配置（`go env CC`），`go test -race ./...` 全部通过；并发按键与命令测试 `TestConcurrentKeyAndCommandNoDataRace` 不再报告数据竞争。
- Rust 11 个单元测试和 2 个集成测试通过。
- CTest 3/3 通过。
- 9 个 Go EXE 连续两次构建 SHA-256 一致。
- NSIS 开发安装包构建成功，包内未发现 `.go` 源码。
- 上一轮远端 GitHub Actions 构建成功。
- 2026-07-11 使用未签名开发包完成真实安装；Go + Win32 输入路径响应流畅，新增“云笺试码”“笺砚验码”后可在活动会话直接出词。
- 2026-07-12 C++/TSF DLL 调试链路就绪：CMake 新增 `PIME_RELEASE_DEBUG_INFO` 选项（默认 `ON`）持久化 Release PDB 生成（`/Zi` + 链接器 `/DEBUG`，去重追加、重复 configure 不累积）；`go test -race ./...` 复跑全绿；`.vscode/launch.json` 提供 `Debug PMERpcResponseTests`、`Debug IME in charmap (x64)` launch 配置，已用 `Reinstall-PIME-Test.cmd` 安装带符号开发包。Win11 `notepad.exe` 为重定向存根，调试改用 `charmap.exe`；cpptools 1.33.4 的 `pickProcess` 在 Cursor 里 attach 失败，需 attach 时用 VS Code。详见 [测试指南 §6.1](YIME_TESTING_GUIDE.md)。
- 2026-07-12 安装态验证清单逐项跑完并留痕（[验证留痕](YIME_INSTALL_VERIFICATION_2026-07-12.md)）：重启后干净全量重装通过，`PIMELauncher.exe`/x86 DLL/x64 DLL 构建↔安装哈希全一致；重启自启动实测（开机 27 秒内 PIMELauncher 自动拉起）；7 个工具入口启动不崩且 SAC 强制模式未阻止；TSF TIP 注册指向安装 DLL，`go_backend.log` 有真实组词/选词/上屏与语言栏模式按钮更新记录；CodeIntegrity 无 3118，历史 3033/3077 为未签名 `server.exe` 的 SAC 审计（当前已放行、14h+ 无新增）；runtimechange 与全 yime 包 `-race -count=1` 全绿。

未纳入本轮完成证明：

- **已完成——最终发布版本**：2026-07-15 已将版本和 Changelog 定稿为 `1.4.0`；历史标签仍不得复用。
- **待办——可信签名**：证书正在办理，尚未生成和验证公开受信任的完整签名安装包。
- **待办——签名后验收**：受签名事项阻塞；签名完成后必须重建、重装并重新执行 TSF、工具入口、语言栏菜单和 CodeIntegrity 清单。
- **已完成——真实 x86 宿主烟雾测试**：2026-07-15 已在 `C:\Windows\SysWOW64\charmap.exe` 中完成用户人工验证，暂未发现激活、组字、候选或上屏问题；签名产物仍须按同一清单复跑。
- **已完成——x64 charmap 宿主烟雾测试**：2026-07-15 已在 `C:\Windows\System32\charmap.exe` 的搜索框和复制框完成组词与上屏；当前进程路径表明这是 x64 宿主，不能替代上一项 x86 验证。
- ~~**仓库物理裁剪**：~~ 2026-07-15 已获明确授权并完成；旧 Python、Node、McBopomofoWeb、libchewing 目录及对应子模块记录已永久删除。

## 5. 开发版与发行版边界

| 场景 | 是否必须购买/使用公开受信任证书 | 要求 |
|------|----------------------------------|------|
| 开发者本机源码构建 | 否 | 标记为开发包，不公开发布 |
| 受控测试机 | 否 | 可使用未签名包、内部 PKI 或显式部署的测试信任 |
| GitHub 分支/PR 构建 | 否 | 产物名保持 `YIME-unsigned-test-installer-{sha}` |
| 面向普通用户公开发布 | 是 | RSA Authenticode、时间戳、全文件签名验证 |
| GitHub `v*` 标签发布 | 是 | 缺少证书时 CI 必须失败 |

公开发布可选择受信任 CA 证书、Microsoft Artifact Signing，或在满足条件时申请 SignPath Foundation 开源签名。自签名证书只适用于开发和受控环境，不能作为公开分发方案。

## 6. 剩余风险和下一步

### 发布前必须完成

- 将当前 `1.4.0-dev` 更新为实际发布版本并核对 `CHANGELOG.md`；只有准备创建正式标签时才切换为 `1.4.0`。
- ~~执行一次未签名标准安装器发布演练。~~ 2026-07-15 已完成构建、连续哈希、标准安装器和原位升级验证；锁定的 x64 DLL 已进入正常的重启替换队列，重启后只需确认最终哈希。
- 使用可信签名服务或证书生成一次完整签名安装包，并运行 `tools/verify-release-signatures.ps1 -IncludeInstaller`。
- 对最终版本和签名后的新二进制重新执行安装态 TSF、工具入口、语言栏菜单及 CodeIntegrity 清单。
- ~~通过标准 `Reinstall-PIME-Test.cmd` 安装，核对构建与安装文件哈希。~~ 2026-07-12 完成：干净全量重装，三件哈希构建↔安装全一致。
- ~~在真实 TSF 宿主中验证激活、组字、选词、语言栏按钮和当时全部工具入口。~~ 2026-07-12 完成：`go_backend.log` 真实组词/上屏证据 + 当时 7 个工具入口启动验证；07-22 又完成含布局设计器的 9 个 Go EXE 安装态复核。
- ~~检查 CodeIntegrity 日志没有新增 3033、3077 或 3118 阻止事件。~~ 2026-07-12 完成：无 3118；3033/3077 为未签名开发包的 SAC 审计（签名后应复查归零）。
- ~~验证设置“应用并重建”和用户词库应用后，已有输入会话无需注销即可刷新。~~ 2026-07-12 完成：runtimechange 协议 `-race -count=1` 全绿（协议层）；2026-07-11 已有活动会话直接出词的安装态实证。
- ~~验证“数据维护”全部可点击路径不会使宿主退出或静默无响应。~~ 2026-07-14 完成：重建安装后逐项点击同步、重新部署和目录入口，未发现异常；构建/安装 `server.exe`、`rime_deployer.exe` 和 x64 TSF DLL 哈希一致，相关进程已重启。

签名完成后需复跑一次上述清单（签名会改变全部二进制哈希与 SAC 信誉状态），以[验证留痕](YIME_INSTALL_VERIFICATION_2026-07-12.md)为模板留新档。

### 可接受的开发期限制

- 未签名开发包可能被 Smart App Control 或企业 Application Control 阻止。
- Go race detector 依赖 MSYS2 UCRT64 GCC；本机由 `tools/test-go-race.ps1` 固化环境，CI 通过 `msys2/setup-msys2` 安装 GCC 并执行同一脚本。`tools/test-build-guards.ps1` 会在 race 步骤或 GCC 安装被删除时失败。
- 真实 Rime 集成测试继续显式启用，避免普通测试共享本机 librime 全局状态。
- C++ 调试在 Cursor 里仅 launch 可用；cpptools 1.33.4 的 `pickProcess` 与 Cursor QuickPick 不兼容，attach 配置需在 VS Code 里运行。`ms-vscode.cpptools` 不在 Cursor 的 Open VSX 市场，需从 VS Code Marketplace 下载 win32-x64 VSIX 离线安装。
- Win32 `build/` 树重建依赖 `rustup toolchain install stable-i686-pc-windows-msvc`（`CMakeLists.txt` 已固定 `Rust_TOOLCHAIN`）；命令行 configure 需要重新拉取 Corrosion 时须设 `HTTPS_PROXY=http://127.0.0.1:1081`（本机 git/cmake 不读 WinINET 系统代理）。
- 本机 Smart App Control 为强制模式；未签名 `server.exe` 会产生 CodeIntegrity 3033/3077 审计事件（当前已放行）。在其它 SAC/WDAC 强制机上未签名开发包可能被直接阻止。

## 7. 文档维护规则

- 行为和进程边界变化：更新 [架构文档](YIME_ARCHITECTURE.md)。
- 新增或调整测试门禁：更新 [测试指南](YIME_TESTING_GUIDE.md)。
- Win32 布局、按钮或模态行为变化：更新 [原生 UI 规范](YIME_NATIVE_UI_GUIDELINES.md)。
- 打包、签名或 CI 产物变化：更新 [发布与签名指南](YIME_RELEASE_AND_SIGNING.md)。
- 用户数据格式变化：更新 [数据格式参考](YIME_DATA_FORMAT_REFERENCE.md)，并说明迁移兼容性。
- 本报告只更新结论、验证状态和剩余风险，不复制专题文档的实现细节。
