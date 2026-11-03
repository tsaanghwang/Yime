# Rime/PIME 原生 ARM64 构建

本入口仅构建和验证隔离产物，不注册 TSF、不启动产品 Launcher、不修改已安装产品或默认输入法。适用于本机 Windows ARM64、VS 2022 MSVC 19.41+（含 ARM64/ARM64EC/x86/x64 编译工具）和 Windows SDK。

## 执行

在仓库根目录，使用明确的 Python 和原生 ARM64 Go 路径：

```text
python tools/rime-pime/prepare_dependencies.py --root .generated/arm64-rime --lock tools/rime-pime/arm64-sources.lock.json
python tools/rime-pime/build_arm64.py --root .generated/arm64-rime --go <native-arm64-go.exe> --stage all
```

可按 `native`、`rime`、`launcher`、`backend`、`payload`、`verify`、`audit` 分段恢复。`payload` 必须使用不存在的输出目录；已有交付原料不被覆盖。重跑各构建步骤会保留带 attempt 后缀的日志。PowerShell 语句仍应通过仓库 `tools/powershell/run_checked.py`；上述入口本身是原生 Python 程序。

`prepare_dependencies.py` 从官方仓库/发行站下载完整提交或固定发行归档，验证已提交的 SHA-256，并记录源码来源、提交、归档哈希和长度。Boost 为 1.89.0，librime 为 1.17.0；Lua/octagram/predict 与标准产品锁定的插件提交相同。Lua 子依赖也使用独立的完整提交。私有 Rust 1.97.0 ARM64 工具链位于输出根目录的 `rustup-home`/`cargo-home`，使用现有 Cargo.lock 和 vendor 离线构建 Launcher；不改变用户 Rust 默认工具链或 PATH。现有 Win32 默认 target、stable-i686 host 和 Corrosion 固定版本保持原样。

## 产物与验证

`payload/` 为简单安装器的输入原料：

- `arm64/PIMETextService.dll`：ARM64 与 ARM64EC 两阶段构建的 ARM64X TSF，覆盖原生 ARM64 和 x64/ARM64EC 宿主。
- `x86/PIMETextService.dll`：32 位应用的独立 TSF；两目录均有同架构注册状态探针。
- `PIMELauncher.exe`、12 个 Go 后端/工具、`rime.dll`、`rime_deployer.exe`、`rime_dict_manager.exe`：原生 ARM64。
- 标准布局自己的配置、字典、字体及插件资源；没有 18u 字典或产品运行时依赖。
- 固定原生 runtime lock、第三方源锁、许可证及 Rust 依赖锁。

`payload-inventory.json` 记录全部文件大小、SHA-256 和所有 EXE/DLL 的 PE Machine。`logs/` 保留命令、退出码和输出。

`audit` 复核全部 payload 文件与原始清单一致，验证 20 个 EXE/DLL 架构和 ARM64X 三种代码区，并记录每个 PE 的静态导入。`arm64-payload-audit.json` 是简单安装器封包前的原料身份记录。

`native` 在本机分别运行 ARM64/x86 RPC 回归，以及 ARM64、x64、x86 的 DLL 导出加载探针。探针不调用注册函数。x64 探针是明确的 x64 兼容性证据，不能视为原生 ARM64 执行。

`verify` 对已有真实 Rime 回归使用一个显式、进程局部的 Go `-overlay`，只重定向测试数据目录到 ARM64 payload，所有用户词库写入隔离临时目录。检查三模式组句、轻声、编码键与翻页边界、提交/退格/取消/标点、内外部署页数和跨进程学习持久化。源产品 Go 文件、标准 x64 runtime lock/DLL、布局投影与全局 GOFLAGS 不变。

这些是源码构建、隔离运行和 ABI 兼容性证据。安装器封包/注册收敛、登录启动、真实应用输入和物理触控验收由各产品的后续安装验证记录负责。

2026-11-03 本机执行证据见 `evidence/2026-11-03/`：11 项 Go/真实 Rime 顶层回归、15 项 Rust 单元测试和 2 项集成测试通过；ARM64/x86 RPC 与三架构加载探针通过。源归档拒绝路径越界、链接和不符哈希的 3 项离线回归通过。首次本地 librime 编译暴露系统 CP936 解释 UTF-8 注释的问题，构建入口已固定 `/utf-8`，重编译和真实引擎回归通过；没有修改第三方源码。

## 原生维护附件和完整 ZIP

`package_native_maintenance.py` 可同时用于 ARM64 Rime/PIME 与独立 18u 的简单安装包。它不调用安装、卸载或注册操作。

```text
python tools/rime-pime/package_native_maintenance.py prepare-shell --cache .generated/arm64-maintenance-shell
python tools/rime-pime/package_native_maintenance.py attach --package-root <simple-package> --output-root <fresh-archive-directory> --cache .generated/arm64-maintenance-shell --source-commit <current-HEAD-40hex> --go <native-arm64-go.exe> --draft
```

首次准备通过仓库 `run_checked.py`，使用已安装的官方原生 ARM64 PS7 核验 pwsh/coreclr/clrjit/hostfxr/hostpolicy 的有效 Microsoft 签名和 ARM64 PE。完整 PSHOME（包含许可证）复制至独立 cache，再从副本启动原生 PS7 重做签名检查并确认其 PSHOME 已指向副本。`shell-lock.json` 锁定每个文件；两个产品附件只读复用并重新核对该副本。默认源为本机已安装的 `Microsoft.PowerShell_7.6.9.0_arm64__8wekyb3d8bbwe`，可通过 `--source-pshome` 显式指定另一个已审阅来源。

`attach` 把完整壳复制到包内 `maintenance/powershell`，复制当前仓库 preflight；将全部 payload、安装脚本、壳及资源写入 `maintenance-plan.json`。只有 plan 本身和编译绑定 plan SHA 的 `YimeMaintenance.exe` 不在 plan 的文件表中；最终外置 ZIP identity 同时覆盖这两文件。helper 使用原生 ARM64 Go、私有缓存、`GOENV=off` 编译，随后只运行 `-action Check`。该检查不启动包内壳，也不提升或改变产品。

`Setup.cmd` 默认转交无修改的 Check。安装/卸载需明确 `Setup.cmd -action Install` / `Setup.cmd -action Uninstall`。正式维护由 helper 在受保护暂存区验证并执行壳，不依赖 Microsoft Store 将来的目录生命周期。

若输入是既有 18u 包，旧 `package-evidence.json`、`signatures.json` 和 README 移到 `maintenance/prior-assembly/`，只作为原始装配阶段历史记录。新的 `*.identity.json` 才记录最终附件 ZIP 的每一成员及 SHA-256，ZIP 本身会逐文件解压读取复核。旁置 `package-signatures.json` 区分微软壳的有效签名和当前开发产品的未签名状态；字节锁不等于发行者认证。

`--draft` 明确允许未完成源码，文件名及 identity 均标为草稿。省略它则要求工作树干净、HEAD 与指定完整提交一致，并在归档前再次核对。它表示源码已冻结，不自动代表 CI 通过、已发布、已安装或输入验收通过；这些门禁由最终交付流程负责。
