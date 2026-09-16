# PR #57 完整双产品包：本地构建与交付

日期：2026-09-16。影响产品：YimeCore、Rime/PIME。开发分支 `codex/pr57-dual-product-delivery` 从最新主线 `c52168611bbf62653d21357f15c52d230c5588c4` 创建；本轮只新增交付文档和证据，没有修改运行程序或安装器源码。

## 包身份与来源

完整包为 [Yime-Dual-Product-PR57-20260916.zip](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-Dual-Product-PR57-20260916.zip)，256620137 字节，SHA-256 `b1e56c1963bae4c9fbc20471ffac524c7ecb9a7ad001ec4db67de937265a74bd`。发布类型为开发测试预发布，tag `test-simple-pr57-c5216861` 对应构建源码；交付分支只记录交接和证据。完整 URL、证据 ZIP 身份及 ZIP 校验见 [release-artifacts.json](release-artifacts.json)。上传后的服务器大小/摘要核对另记 `raw/github-release-assets.json`。

安装器及两套应用均从干净 `c5216861` 构建；Git 祖先检查确认包含 PR #57 合并提交 `76376080df7e58c1fde9f8bb3275f51ddabf20b7`。[源码 CI 35052224041](https://github.com/tsaanghwang/Yime/actions/runs/35052224041) 已成功。构包时工作区干净，随后的交付文档不改变包内源码身份；交付分支提交通过 CI 后才将预发布公开。

| 产品 | 载荷文件 | 载荷字节 | product-package.json SHA-256 |
| --- | ---: | ---: | --- |
| YimeCore | 65 | 425307314 | `00661b3e51a30109beadfef3c1b04b6d04730a6749602b2ea06baec0bf256d1c` |
| Rime/PIME | 160 | 159908450 | `bb130a4978f8591b053456bfdc6294e3784a6190b89f8e7fe0b2bd3875758fd3` |

包内含两套独立维护入口及共同选择入口，x64 运行程序、x64/x86 TSF、各自词库/语流资源/私有字体与工具。不是 ARM64 安装包。45 个 EXE/DLL 的静态 Authenticode 状态均为 `NotSigned`，不宣称生产发布就绪。

- Rime/PIME：`Build.ps1` 构建当前源码的双架构 PIME、固定 i686 Rust launcher、Go 后端和工具，再调用 `Build-RimePackage.ps1`。固定 librime 1.17.0 的 DLL、deployer、dict manager 来自仓库 lock，三项 SHA-256 全部吻合；未声称重新编译这些依赖。
- YimeCore：针对当前源码重新运行既有 Stage5C 隔离准入，再经 `build-local-product.ps1` 源码构建和 `Build-Package.ps1` 制包。当前 CLSID/Profile、19 个 Go 程序、6 个原生载荷、25 个 descriptor 资源、3 个普通索引、11 个语流载荷及 descriptor 全部齐全。语流规则及词库内容未修改。
- 工具链：Go 1.26.4 windows/amd64、CMake 4.3.1、Visual Studio 17 2022 / MSVC 19.44.35225；Rust launcher 使用 `stable-i686-pc-windows-msvc`，构建记录的 Cargo 为 1.97.0。
- `go mod tidy` 仅改变 `go.mod` 换行形式，`git diff` 无内容差异；恢复本次构建引入的换行变化后，YimeCore 从干净工作区构建。未更改依赖版本。

[BUILD-PROVENANCE.json](BUILD-PROVENANCE.json) 绑定源码提交、Core 源码清单/归档、语流准入摘要、来源清单、两产品清单及独立验证报告。证据 ZIP 携带 Core 53,579,262 字节源码快照、8,930 个构建来源文件的 Git blob/字节哈希记录、构建输入、完整日志、产品清单和可复查的核验脚本。未使用已安装产品作为构建输入。

## 本机实际执行的验证

| 项目 | 结果与范围 |
| --- | --- |
| PS5 `Test-PackageValidation` | 通过；缺图标或三个必需工具之一，即使清单哈希自洽也拒绝 |
| PS5 `Test-ProfileRemoval` | 通过；合成 API 返回失败时，后续 COM、启动项和文件删除均不执行 |
| PS5 `Test-Manage` | 通过；仅合成 Setup 的单套/双套调度与失败停止 |
| PS5 `Test-ProcessWait` | 通过；只创建测试自有隐藏 PowerShell 子进程，验证父进程退出等待 |
| PS5 `Test-Product` | 通过；真实载荷复制到仓库新临时目录，验证所有权、另一产品隔离、进程私有字体占用、损坏副本替换、中断复制清理 |
| PS5 直接 `Read-Package` | 两套通过；没有运行会写用户日志的 Setup 入口 |
| 独立 Python 包核验 | 7 组通过；225 个载荷的大小/哈希/集合、入口源码字节、完整 descriptor 资源、来源绑定、固定 Rime 依赖、45 个 PE 架构 |
| YimeCore 构建检查 | x64/x86 契约和焦点取消、5 个 Go 包、两次独立性审计通过；三个普通索引每种 1,166,753 条，各生成两次且字节一致 |
| Stage5C 隔离准入 | 通过；24 条既有审核记录、72 个模式别名。仅新建匿名管道测试 Broker 和私有合成状态，不连接已安装产品 |
| 系统保护 | 构建及本地测试前后，19 个系统注册/用户输入配置/启动项相关路径的只读摘要一致 |
| 最终 ZIP | 两个 ZIP 均通过 CRC、完整成员集合及解压读取的逐文件 SHA-256 对照 |

测试调用经 Python `tools/powershell/run_checked.py`，构建选 PS7，安装器兼容验证选 PS5。4 个源码测试与真实包隔离测试分别在新进程中隔离 TEMP/TMP/APPDATA/LOCALAPPDATA。`Test-Manage` 日志中的 Install/Uninstall 是合成 Setup 的操作标签；`Test-Product` 的删除只针对新建测试副本，不是卸载本机产品。

## 本轮不执行的项目

`Test-Startup` 会写当前用户的临时注册表键；`Test-Logging` 和真实 `Setup -Action Check` 会在用户主目录建立日志。本轮本地跳过这些入口，直接读取包。它们在独立 CI runner 的执行结果归于源码 CI，不算本机执行。

未安装、卸载或重启任何已安装产品；未改默认输入法或用户数据。没有运行注册宿主验收，也没有真实应用输入或重启确认。新包不能继承 2026-09-14 旧包的验收结论，本轮不发起测试机执行。后续范围以 [HANDOFF](../../../../../installer/simple/HANDOFF.md) 的新任务为准。

## 证据

本目录 `raw/` 保留所选日志和 JSON 的原始字节，[evidence-index.json](evidence-index.json) 列明大小与 SHA-256；仓库既有 raw 属性防止换行转换。完整构建与来源材料通过 [证据 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-PR57-Build-Evidence-20260916.zip) 交付，本机 `.tmp` 仅用于构建，不是测试端接续入口。其他日期的历史证据均未改写。

`raw/github-release-assets.json` 是上传阶段的草稿收据，保留其 `draft_at_verification=true` 和临时 URL。交付提交 CI 成功后才公开；公开时另附 [release-publication.json](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/release-publication.json)，记录交付提交/CI、tag 实际目标、最终下载 URL 与四个原始附件的服务器摘要，不回写草稿证据或重打包。
