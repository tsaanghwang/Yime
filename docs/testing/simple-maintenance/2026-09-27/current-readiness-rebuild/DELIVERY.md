# current-readiness 双产品重建交付（2026-09-27）

影响产品：YimeCore、Rime/PIME；未修改运行源码。状态：**本地完整包与独立证据包已就绪，远端尚未上传。测试端无安装任务。**

## 来源与范围

- 开发分支：`codex/current-readiness-delivery-20260927`，从刷新后的 `origin/main` 创建。
- 两产品运行源码及安装器来源提交：`0ab8631266736775bf1386f456d4a1d53e8e2eb3`；来源树见 `raw/BUILD-PROVENANCE.json`。
- 来源提交 [CI 35418522827](https://github.com/tsaanghwang/Yime/actions/runs/35418522827) 全部成功。本交付分支仅增加文档与证据；上传前还须确认其提交 CI 成功。
- 9895 个跟踪源码文件构建前后按字节一致；两份完整源清单在 Evidence ZIP 的 `delivery/source-before.json` 和 `source-after.json`，SHA-256 同为 `1e0a848ccbc2b64e0f8f2c36c12c0b9e9e854ff0c9f18fe2224694c2b45c5a29`。
- 切换 main 后显露的 6 个旧触摸原型 `.playwright-cli` / `output/playwright` 未跟踪输出原样保留，未作为构建输入或入包。原始 YimeCore source-manifest 因这些无关输出保留 `dirty=true`，不将其改写为 clean；跟踪源码差异为空。
- 包面向 Windows x64，含 x86 WOW64 TSF；未构建、执行或改写历史 ARM64 载荷。未执行正式签名，不宣称公共正式发布就绪。

## 固定包身份

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `Yime-Current-Readiness-20260927.zip` | 256650784 | `45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341` |
| `Yime-Current-Readiness-20260927-Evidence.zip` | 108540211 | `4755456e9c5eb0813a6c647d1d6953b9560bc7602a5800cb11a8bcfd504d576d` |
| `SHA256SUMS.txt` | 215 | `af016db10889109065d77427c9c47e5809b9ad781dad57b6f52bbbfb101c8534` |

本地持久交付目录：`C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312`。该路径只用于本机复核；测试端不得把共享 `.tmp`、源码 checkout 或 GitHub Source code ZIP 当成完整包交付。远端 URL 在成功上传前保持 null，上传清单见 [UPLOAD.md](UPLOAD.md)，机器可读身份见 [delivery.json](delivery.json)。

| 产品 | 版本 | 载荷文件 | 载荷字节 | product-package.json SHA-256 |
| --- | --- | ---: | ---: | --- |
| yimecore | `0.1.0-local.13` | 65 | 425346226 | `9910c77d96db2e3cd8cedf7ca22f426d097b332ff51873f2bef79e0886d9f89f` |
| rime-pime | `1.4.0-dev.1` | 160 | 159908450 | `dea5cac4065d7c9b36442603660ec7bd178eb514c65e199c28ce8bbf26c99da3` |

完整包根目录有 `Install-Uninstall.cmd`、`Choose-Products.ps1`、`Manage-Products.ps1`、两产品子目录、`BUILD-PROVENANCE.json`、`DELIVERY-MANIFEST.json` 和说明。每产品独立包含 Setup 入口、Product 模块、product-package.json 与自身 payload。总清单覆盖除自身以外的全部包文件。

## 构建与载荷来源

YimeCore 重新执行 Stage5C 准入，随后从当前源码构建 19 个 x64 Go 程序、x64/x86 各 3 个原生载荷、25 个明确源资产、三模式索引和 11 项语流载荷。三模式索引每种独立生成两次，字节一致。原始构建包的清单、源码清单、工具链、参数、源码 ZIP、准入 summary/inventory、导出回执及独立性审计保存在独立 Evidence ZIP；简版包会排除构建证据目录，不能据此丢掉来源链。

Rime/PIME 在全新 x64/x86 CMake 输出重编译 4 个原生文件，固定 i686 Rust host 重编译 Launcher，重编译 12 个 x64 Go 程序，共 17 个本轮构建二进制。另 3 个 librime 1.17.0 / `33e7814` 文件来自仓库锁定的上游运行载荷，已按包内 runtime lock 复核；**未将其描述为本轮从 librime C++ 源码重编**。准确命令、MSVC/CMake 缓存、逐文件来源映射及 runtime lock 位于 `raw/rime-evidence/`。

Rime 驱动保持原 build.bat 的工具、资源与标志，使用 `-mod=readonly` 代替会改源的 `go mod tidy`，跳过自动 ARM64 和可选签名分支。全部 92 个 data 文件与源集合、大小、哈希一致；仅允许原链排除的三项 `yime_core_trial.*`。来源锁定词典条目数 1166753，必需 OpenCC、trainer、三模式语流/儿化/PSC 资源完整。

## 本轮验证

- YimeCore 新源码准入、x64/x86 原生契约与焦点取消 mock、五组 Go 测试、三模式索引双构建、语流导出、两次独立性审计通过。只使用新建测试自有进程和隔离状态。
- 双产品包内 `Read-Package` 在 Windows PowerShell 5.1 下通过；额外完整 descriptor 集合与全部 225 个载荷的大小/SHA-256、45 个 PE 架构核验通过，无遗漏或额外载荷。
- Rime vendor runtime lock、全部 20 PE 架构/静态 CRT、词典与帮助文档 handoff 检查通过。
- PS5 下 `Test-PackageValidation`、`Test-ProfileRemoval`、`Test-Manage`、`Test-ProcessWait` 通过。日志中的 Install/Uninstall 是 synthetic Setup fixture 调度，不是真实安装器调用。
- PS5 `Test-Product` 对实际包的隔离副本执行归属拒绝、私有字体占用、损坏载荷替换、另一产品保持和中断复制清理模拟，通过；不是安装/卸载验收。
- 完整包和 Evidence ZIP 均重新打开，对 CRC、重复成员、精确文件集合、大小及每个解压成员 SHA-256 复核通过，详见两份 `*-zip-verification.json`。
- 构建与包验证前后，经进程外系统视图读取的注册、语言/默认输入及启动项哈希一致。原始证据按字节保留，[evidence-index.json](evidence-index.json) 可逐项复核。

未执行 `Test-Startup`（会写真实启动项）、`Test-Logging`（会写用户目录并运行复制的 Setup Install）、真实 Setup Check（会写用户日志）、安装/卸载、已安装产品进程重启、注册宿主/实机输入/系统重启验收。未修改默认输入法或用户数据。9 月 19 日旧包的本机验收保留在历史报告，不能继承为本次重建包的实机结果。

## 接续

先提交推送本分支并确认 CI，再发布固定的完整包、Evidence ZIP 与 SHA256SUMS；成功后填写真实 Release/asset URL 和远端摘要核对结果。当前测试端无同步、安装或重测任务。后续实机范围须另行明确；本轮不启动历史恢复链或维护矩阵。
