# Yime 发布与代码签名指南

本文档定义 Windows 发布物从版本确认、构建、测试、签名、打包到安装验证的标准流程。开发测试包可以不签名，但对外发布包必须使用受信任的 RSA 代码签名证书。

## 1. 发布前条件

- 工作区干净，发布目标提交已合入并推送到 `main`；`yime-stable` 仅作为保留的集成分支
- 子模块提交已先推送到各自 remote，主仓库不引用远端不存在的提交
- `version.txt` 与构建身份一致；当前未发布开发线使用 `1.4.0-dev`，只有创建正式 `v1.4.0` 标签前才改为 `1.4.0`
- 不得重新使用已经存在的历史标签。仓库已有 `v1.0.0`、`v1.1.0` 和 `v1.3.0-*`；即使 Yime 作为独立产品首次公开发布，也不能再次创建同名 `v1.0.0` 标签
- `CHANGELOG.md` 的 `[Unreleased]` 已核对
- Visual Studio、CMake、Rust、Go、NSIS 和 `go-winres` 可用
- Rust 已安装 i686 host 工具链：`rustup toolchain install stable-i686-pc-windows-msvc`。Win32 `PIMELauncher` 构建由根 `CMakeLists.txt` 固定 `Rust_TOOLCHAIN` 指向它（Corrosion v0.6.1），x64 host 工具链会因跨编译 build-script 链接错误而失败
- 发布签名机器已安装受信任提供商签发的 RSA 代码签名证书

## 2. 版本与可复现构建

Go 工具的文件版本和 `main.version` 均取自仓库根目录 `version.txt`。不要恢复使用 `git describe` 作为每次构建的文件版本；提交哈希变化会使所有 EXE 产生新哈希并丢失 Smart App Control 信誉。

发布构建器与 CI 固定为 Go 1.26.4；`go.mod` 中的 `go 1.21` 仅表示源码语言兼容下限。调整发布构建器版本会改变二进制哈希，必须连同 `go vet`、全量测试、race 和连续构建哈希一起重新验证。

日常开发包必须使用带 `-dev` 的版本，避免与历史正式标签或公开测试版混淆。创建发布标签前，先按语义化版本确定 beta/rc/正式版本，更新 `version.txt` 和 `CHANGELOG.md`，完成干净构建后再签名；不得直接给 `*-dev` 安装包创建公开发布标签。

`go-backend/build.bat` 必须为全部 Go EXE 使用：

```text
-trimpath -buildvcs=false
```

同一源码、依赖、Go 版本和 `version.txt` 下连续构建两次，文件哈希应一致：

```powershell
cd go-backend
cmd /c build.bat
Get-FileHash .\build\go-backend\settings-tool.exe -Algorithm SHA256
cmd /c build.bat
Get-FileHash .\build\go-backend\settings-tool.exe -Algorithm SHA256
```

对应自动守卫为 `TestBuildScriptKeepsGoExecutableHashesStableAndSupportsSigning`。

## 3. 发布签名

Smart App Control 对未知且未签名的新文件哈希可能直接阻止执行。VERSIONINFO 只提供文件身份信息，不能替代可信签名；自签名证书也不适用于公开发布。

构建前设置：

```powershell
$env:YIME_SIGN_CERT_SHA1 = "<受信任 RSA 代码签名证书指纹>"
$env:YIME_SIGNTOOL_EXE = "C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe"
$env:YIME_TIMESTAMP_URL = "http://timestamp.digicert.com"
```

`YIME_SIGNTOOL_EXE` 和 `YIME_TIMESTAMP_URL` 可省略；脚本会尝试从 `PATH` 查找 `signtool.exe`，并使用默认时间戳服务。正式发布还要设置 `YIME_RELEASE_SIGNING_REQUIRED=1`，缺少证书或任一签名失败都会中止构建。签名前会验证证书带可访问私钥、位于有效期、使用 RSA 公钥，并包含代码签名 EKU（`1.3.6.1.5.5.7.3.3`）。

需要签名的 Go 文件：

- `server.exe`
- `tool-hub.exe`
- `settings-tool.exe`
- `diagnostics-tool.exe`
- `yime-layout-designer.exe`
- `lexicon-manager.exe`
- `reverse-lookup.exe`
- `system-lexicon-audit.exe`
- `blocklist-manager.exe`

统一签名入口：

```powershell
.\tools\sign-release.ps1 -RequireComplete
```

该脚本覆盖 Go EXE、`rime.dll`、`rime_deployer.exe`、PIMELauncher 和各架构 TSF DLL。NSIS 的 `!uninstfinalize` 与 `!finalize` 会分别签名卸载程序和最终安装包。

验证：

```powershell
.\tools\verify-release-signatures.ps1 -IncludeInstaller
```

`Status` 必须为 `Valid`；验证脚本还会要求签名者指纹等于 `YIME_SIGN_CERT_SHA1`，并确认每个文件都有时间戳证书。

标签 `v*` 会触发正式发布签名门禁。仓库需配置 `YIME_SIGN_CERT_BASE64`（PFX 的 Base64）和 `YIME_SIGN_CERT_PASSWORD`；标签构建缺少密钥会直接失败，临时 PFX 在导入后立即删除。标签产物名为 `YIME-signed-installer`；PR 与普通分支产物名为 `YIME-unsigned-test-installer-{sha}`，不得作为公开发布包。

### 3.1 开发包与证书选择

签名不是本地编译的前置条件。开发者本机和受控测试机可以使用未签名开发包；CI 普通分支也允许产出明确标记的未签名测试安装包。不要为了开发便利移除正式标签的签名门禁。

| 使用场景 | 建议 |
|----------|------|
| 本机开发 | 未签名构建即可；只运行自己核对过的源码产物 |
| 受控团队测试 | 使用内部 PKI、自签名测试证书或设备策略部署信任 |
| 公开开源发布 | 优先评估 SignPath Foundation 开源签名或 Microsoft Artifact Signing |
| 商业/组织发布 | 使用受信任 CA 或托管签名服务，并保护私钥/HSM 凭据 |

自签名证书不会被普通用户的 Windows 默认信任，只适合开发和受控环境。公开发行时，签名必须覆盖安装器及其实际启动、加载和安装的内部 EXE/DLL；只签最外层安装包仍可能在安装过程中被 Application Control 阻止。

## 4. 构建与测试

```powershell
# 根入口串联 Win32/x64、Go 后端和架构门禁
cmd /c build.bat

# 防止 x64 DLL 被误装进 x86 槽位
.\tools\test-build-guards.ps1
```

发布前运行 [测试与验证指南](YIME_TESTING_GUIDE.md) 中的 CI 稳定集、真实 Rime 集成测试和安装态烟雾测试。不得只依据 CI 构建绿色判断功能完整。

## 5. 安装包检查

- 安装包版本与 `version.txt` 一致
- `go-backend/build/go-backend/` 中 9 个 Go EXE 全部存在且带 VERSIONINFO：`server.exe`、`tool-hub.exe`、`settings-tool.exe`、`diagnostics-tool.exe`、`yime-layout-designer.exe`、`lexicon-manager.exe`、`reverse-lookup.exe`、`system-lexicon-audit.exe`、`blocklist-manager.exe`
- NSIS 必装主组件递归包含 `go-backend/build/go-backend/`，安装包中不存在旧 Python/Node 输入法及其组件选择逻辑
- `input_methods/yime/data/`、`rime.dll`、`rime_deployer.exe` 已打包
- 打包目录 `input_methods/` 下没有 `.go` 源码或测试文件
- x86/x64 `PIMETextService.dll` 均存在，并通过 `tools/test-build-guards.ps1` 验证 PE machine type；仅检查文件名或存在性不算通过
- `go-backend/build/go-backend/input_methods/` 只包含带 `ime.json` 的运行时输入法目录
- 安装包和内部二进制签名有效
- 安装包 SHA-256 已记录在发布说明中
- `installer/build-manifest.json` 记录版本、提交、分支、签名状态及关键产物 SHA-256；回退时按该清单选择上一提交制品
- 全新安装、开发卸载后安装和已有版本升级三种情况下，目标目录都保持为 `C:\Program Files (x86)\YIME`

```powershell
Get-FileHash .\installer\YIME-*-setup.exe -Algorithm SHA256
```

## 6. 安装态验证

使用标准流程，不得简化 `Reinstall-PIME-Test.cmd`：

```powershell
.\Reinstall-PIME-Test.cmd
```

验证构建与安装文件一致：

```powershell
$built = Get-FileHash .\go-backend\build\go-backend\settings-tool.exe
$installed = Get-FileHash 'C:\Program Files (x86)\YIME\go-backend\settings-tool.exe'
$built.Hash -eq $installed.Hash
```

至少验证：

1. PIMELauncher 和 `server.exe` 能启动
2. 音元输入法能激活、组字和选词
3. 桌面语言栏三个双字切换按钮不消失、不换位，“用户词库”“反查编码”“工具中心”按钮可用
4. 语言栏停靠在任务栏时，“中 → 设置”内的“用户词库”“反查编码”“工具中心”三个叶子命令均可打开对应窗口
5. 工具箱、高级布局、设置、反查和词库管理可以打开
6. 设置工具“应用”、备份和恢复流程不闪控制台
7. 用户词库应用后在三种方案中可用
8. CodeIntegrity 日志没有新产生的 3033、3077 或 3118 阻止事件

## 7. 回滚

- 保留上一版安装包及 SHA-256
- CI 未签名测试包按提交 SHA 命名并保留 30 天；回退前先核对 `build-manifest.json` 的提交与文件哈希
- 回滚优先使用独立提交或发布标签，不使用 `git reset --hard`
- 若 DLL 被宿主锁定，标准重装流程会自动采用就地安装；只有确需替换被锁 DLL 时才重启 Windows
- 回滚后重新核对安装文件哈希和运行进程时间，不要只检查源码分支
