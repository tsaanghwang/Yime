# PR #57 双产品包交付：主线对齐与独立复核

日期：2026-09-19。影响产品：YimeCore、Rime/PIME；本轮只接续交付文档和证据。

## 提交与交付身份

本轮分支 `codex/pr57-delivery-main-alignment` 从 `main` 的 `d8776121ce90456c2cb8bda6e51b0795364392bd` 创建。[该主线 CI 35294563072](https://github.com/tsaanghwang/Yime/actions/runs/35294563072) 成功。接入原交付分支 `codex/pr57-dual-product-delivery` 最终提交 `c178f9cf9cab90922fd552081a761d3092138f6b` 的证据，并对齐当前文档；没有重新构建或上传附件。

| 身份 | 固定提交及验证 |
| --- | --- |
| PR #57 安装器修复 | [PR #57](https://github.com/tsaanghwang/Yime/pull/57)，合并提交 `76376080df7e58c1fde9f8bb3275f51ddabf20b7`；其原开发分支是 `codex/simple-installer-pr55-fixes` |
| 包的源码及安装器 | `c52168611bbf62653d21357f15c52d230c5588c4`；包含 PR #57；[源码 CI 35052224041](https://github.com/tsaanghwang/Yime/actions/runs/35052224041) 成功 |
| 原交付记录 | `c178f9cf9cab90922fd552081a761d3092138f6b`；[交付 CI 35079492080](https://github.com/tsaanghwang/Yime/actions/runs/35079492080) 成功后公开预发布 |
| 本轮文档基线 | `d8776121ce90456c2cb8bda6e51b0795364392bd`；不将包改称从此提交重建 |

源码 `c5216861` 到文档基线 `d8776121` 共变化八个文件：七个文档和 `go-backend/build.bat` 的安装路径输出提示。PR #59–#61 对 Rime/PIME 路径、PowerShell checked 入口、外部归档边界和配置文件归属的修订全部保留；安装器及运行程序源码未变。本轮仅调整首页、现状、路线图及 simple 的 README/HANDOFF/VALIDATION，并新增证据目录。

## 公开附件

[测试预发布](https://github.com/tsaanghwang/Yime/releases/tag/test-simple-pr57-c5216861) 为非草稿预发布，发布时间 `2026-09-16T09:34:46Z`。tag 实际指向 `c52168611bbf62653d21357f15c52d230c5588c4`，未仅依赖 release 的 `target_commitish` 文本。五个附件均实际下载，逐字节复算 SHA-256 并对照本轮 GitHub API；四个原始附件另对照发布收据，两个 ZIP 再对照原交付元数据及 `SHA256SUMS.txt`。

| 附件 | 字节 | SHA-256 |
| --- | ---: | --- |
| [完整双产品包](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-Dual-Product-PR57-20260916.zip) | 256620137 | `b1e56c1963bae4c9fbc20471ffac524c7ecb9a7ad001ec4db67de937265a74bd` |
| [构建证据 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-PR57-Build-Evidence-20260916.zip) | 54364633 | `6354dbdf886279ab4b87a9b7f63df950826f40915ac0dad2c4173e7b1f7961cc` |
| [release-artifacts.json](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/release-artifacts.json) | 1759 | `f3363d2bab015457f8f177f119664b54a6e04dc9d9f857473b9b75daef1c8e69` |
| [SHA256SUMS.txt](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/SHA256SUMS.txt) | 208 | `5522fe7db7f7f3bbeeaf9c547d4fd7ba7c63423374780f7b7323a21bdf06c90d` |
| [release-publication.json](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/release-publication.json) | 2451 | `d138c04de47b6d8c16fddc5902126a17616c605dd418042d711aad699cb17c7d` |

本轮远端快照保存在 `raw/release.json`、`raw/tag-ref.json`、`raw/source-ci.json`、`raw/delivery-ci.json`、`raw/main-ci.json` 和 `raw/pr57.json`。原 `raw/github-release-assets.json` 保持草稿上传时的原始内容；新增发布收据副本用于闭合“上传→CI→公开下载”的记录，不回写历史文件。

## 独立静态核验

机器可读结果见 [delivery-verification.json](raw/delivery-verification.json)，核验代码见 [verify_delivery.py](verify_delivery.py)。首次核验记录保留在 [delivery-verification-initial.json](raw/delivery-verification-initial.json)：两项未通过来自新核验脚本的假设错误——包内制包说明实际名为 `DELIVERY-README.md`，安装脚本含混合换行。修正检查器后重新核验，未修改任何发布附件或历史证据；包的原字节摘要始终保持匹配。制包说明以 ZIP 摘要绑定，不要求等于包含最终 ZIP SHA-256 的后续 Git 报告。

- 原交付目录的 29 个 raw 文件大小与 SHA-256 全部匹配；原交付目录已暂存，并与交付提交逐个 Git blob 比较，完全相同。证据 ZIP 的 68 个索引项全部通过，另一个成员为索引自身。
- 两个 ZIP 检查 CRC、成员路径和完整集合；两产品清单及 225 个载荷逐项核验大小、SHA-256 和集合。YimeCore 65 项，Rime/PIME 160 项；45 个 PE 的 x64/x86 头符合产品架构。必需图标、工具、语流文件、当前产品身份及 librime lock 分别核对。
- 来源清单 8,930 项对应 `c5216861` 的 Git tree/blob；Core 源码快照 660 项与源码清单的集合、大小和 SHA-256 一致，并分别核对 Git blob。Windows 检出换行和 Git blob 的 LF 分开处理；Core 551 项原字节匹配、109 项仅 CRLF→LF 后匹配。两份来源清单重合的 615 项字节摘要一致。
- `BUILD-PROVENANCE.json`、Core 构建输入、源码归档、独立核验报告和语流准入/来源/导出绑定闭合；语流导出清单的 11 项对应最终包载荷。安装维护入口与固定源码提交及当前安装器对应。

原 `verify_package.py` 的七组通过记录由 `BUILD-PROVENANCE.json` 中的 `independent_verification_sha256` 绑定。它的 `fresh_build` 表示 9 月 16 日与本地构建副本的比较；发布证据 ZIP 未携带该脚本所需的完整 Core/Rime 构建目录，不能仅用下载 ZIP 原样重跑。**本轮没有重新编译、生成索引或重跑 Stage5C，也没有用最终包复制出构建目录来声称重新验证 fresh build。** 本轮新增 Git/blob/源码快照检查，补齐旧脚本仅比较来源元数据哈希的范围。

45 个 PE 为 `NotSigned` 的结论来自哈希绑定的原始签名记录，本轮未重跑 Authenticode 信任验证。包仍是开发测试预发布；x64 Windows/WOW64 范围不扩展成 ARM64 或生产签名发行。

## 本轮实际执行的非变更验证

| 检查 | 结果与范围 |
| --- | --- |
| PS5 `Test-PackageValidation` | 通过；合成包资源缺失拒绝 |
| PS5 `Test-ProfileRemoval` | 通过；合成 API 失败时保护 COM/启动项/文件清理边界 |
| PS5 `Test-Manage` | 通过；合成 Setup 的单套/双套调度及失败停止；日志中的安装/卸载字样不是实际安装 |
| PS5 `Test-ProcessWait` | 通过；仅测试自有隐藏子进程及其自然退出 |
| PS7 `validate-build-contract` | 通过；只读源码契约 |
| Python workflow contract | 两项测试通过；只读 CI 调度与汇总契约 |
| PS5 直接 `Read-Package` | 两套通过，分别 65/160 个载荷；不执行 Setup 或载荷程序 |

六组源码检查的结果与 stdout/stderr 摘要见 [local-validation-summary.json](raw/local-validation-summary.json)，调用见 [run_validations.py](run_validations.py)。各组独立进程的 TEMP/TMP/APPDATA/LOCALAPPDATA 都指向本仓新建隔离目录；PowerShell 全部经 `tools/powershell/run_checked.py`。真实包仅解压到本仓隔离目录并直接读取，脚本见 [read_packages.ps1](read_packages.ps1)，结果见 [Read-Package.result.json](raw/Read-Package.result.json) 与[读取输出](raw/Read-Package.stdout.log)。

本轮跳过 `Test-Startup`、`Test-Logging`、真实 `Setup -Action Check` 和注册宿主验收，避免写真实注册表或用户日志。没有重复历史真实载荷文件维护、系统保护快照或构建；已通过的旧记录仅按原身份引用。

本轮 33 个原始证据文件的大小与 SHA-256 见 [evidence-index.json](evidence-index.json)。[最终一致性检查](raw/final-consistency.json) 确认十组包核验、六组源码检查和两套直接包读取通过，原交付目录暂存内容完全一致，八个主线后续修订文件未回退，并核对了当时 94 个本地文档链接。

## 复现与后续边界

先从上述固定 Release 下载五个附件到新的本地目录，再按 `python verify_delivery.py --help` 指定本地附件及新的输出位置。源码回归使用 `python run_validations.py --help` 选择全新输出及隔离目录；不要覆盖本目录已有 raw 记录。直接包读取需完整解压并经 checked 入口调用 `read_packages.ps1`，使用 UTF-8 JSON 参数文件提供 `BundleDirectory`，选择 PS5。`.tmp` 仅是复核时的临时工作目录，不是交付或测试端接续入口。

本轮没有安装、卸载、重启已安装产品进程、改变默认输入法或修改用户数据。未执行真实应用输入或重启确认，未发起测试机同步/安装/维护任务。本包仍无实机安装、输入或重启验收，不能继承 2026-09-14 旧包结果。后续仅以 [HANDOFF](../../../../../installer/simple/HANDOFF.md) 的明确新任务接续。
