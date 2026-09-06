# DP1-G：密封 stage 驱动 NSIS 与逐项静态归档核对

日期：2026-09-06。影响产品为独立的 Rime/PIME；YimeCore 是必须保持不变的另一产品。本批只构建了默认禁用、未签名、不可交付的 `x86,x64` 静态候选，并对其归档内容做只读核对。没有运行安装器或卸载器，没有安装、注册、启动或停止产品进程，也没有读取或修改默认输入法、生产数据、用户正文、设置或学习记录。

## 本批结果

DP1-F 的全量复制暂存已接入真实 NSIS 构建入口。当前 175 个复制输入仍精确分为 166 个持久安装文件与 9 个 bootstrap helper；其中 Go 构建树由 148 项版本化清单闭合。内容树 SHA-256 保持为 `bec8f30e0d85c854dda9da3b70e26bd6b752fcd89684bbe6572038ab291151b2`，当前 package plan、copied-content manifest 分别为 `b5bcfe3ead26478129621cec7ea376ad028db86500d209d74572be16b04445ad`、`6c56bac7207229c8ca357441011d2752d73f6f5aef59b839cffc6c7274f34fc7`。

[`rime-pime-nsis-stage.ps1`](../../tools/dual-product/rime-pime-nsis-stage.ps1)从密封清单生成 6 个分调用点宏和当前真实 stage 的 176 个显式 `File` 引用。[`installer.nsi`](../../installer/installer.nsi)只通过生成 include 消费产品载荷，已没有仓库相对的直接 `File` 或 `File /r` 产品输入。生成 include SHA-256 为 `aed59cc374fc4bcdf6d3d26eefb87cc31524a6371bb84efa8839876b1e3d14fd`，其 receipt SHA-256 为 `ef9d2a5d85f18ff92c23c8300944c559edaff5336abf1119674f52c48990c029`。

[`build-rime-pime-installer.ps1`](../../tools/build-rime-pime-installer.ps1)在导入前锁定并复核 10 个实际执行的构建逻辑来源，拒绝 reparse、hardlink 与 ADS；随后把 stage、生成 include、manifest、receipt 和编译输入合计作为 200 个 prebuild 租约输入保持到构建完成。`makensis` 前在租约下重新验证 20 个唯一 PE／22 个 stage 路径绑定，调用固定为 `/NOCD`、`/NOCONFIG` 和绝对内置 include／locale 路径。发布采用跨进程互斥、receipt-sidecar-last 的可恢复提交／回滚；这里不把它描述为文件系统原子事务。

默认构建分支只定义 `PACKAGE_UNSIGNED_DISABLED_BUILD=1`，不会启动签名 hook。受保护的 release 分支仍要求绝对 `PACKAGE_POWERSHELL_PATH` 和 `PACKAGE_SIGN_FILE_PATH`，本批没有执行。PS5 与 PS7 的最终构建都把不可执行的 PATH sentinel 放在搜索路径首位，sentinel 未被启动，证明这两轮没有路径搜索式签名宿主。两套宿主产生不同的 NSIS 二进制；它们共同绑定同一个密封内容合同，不据此宣称二进制逐字节可复现。

| 构建宿主 | build-result SHA-256 | 候选 SHA-256／字节数 | publication receipt SHA-256 | 静态归档 result SHA-256 |
| --- | --- | --- | --- | --- |
| Windows PowerShell 5.1 | `17ece115766d063aca84c681d0802f0a0f832a977da2e7e3b10565f010b1da8c` | `67d75fda241f7354d7c1a775afbbd42fbfe7099ba320ea20365050b763fb3e7d`／41,488,070 | `8522a7c17b251099551558e01ccc142036f59471bf7bb340ab974747e14fbebe` | `2241ea660cc67bd772ece8763f250d2933a0f307debeddfe2bd6964a8a32b464` |
| PowerShell 7 | `fddc0d833aea68757dda5baac40bafea392afe7081602b468020dc3b05708aa4` | `89afd38568e624213f69989af99cd02c488925de128e9ba4bd7fd0413589bd70`／41,473,007 | `91bdd5a21bbaab4e2beca751d3c78594a26186b63e073fbd9a6f0191f1958fe0` | `143a38ba366134093d4145b9506cb3b8480081686f18f6099fc2c6776325078b` |

仓内 canonical installer／receipt 当前对应 PS7 构建，sidecar 与 receipt 摘要一致。它仍是禁用候选，不是交付物，不得运行。

## 静态归档证据

[`rime-pime-postbuild-extraction.ps1`](../../tools/dual-product/rime-pime-postbuild-extraction.ps1)固定并持有实际 `7z.exe` 与由 `7z i` 唯一解析出的 `7z.dll`。验证不再让 7-Zip 写入输出路径：安装器外层 181 项和内嵌卸载器 11 项分别通过 `7z e -so -spd` 输出原始字节，由父进程以 `CreateNew` 建立快照、从同一字节流计算摘要并持有读租约直到 seal。每轮共 197 次锁定的 7-Zip 调用，其中 192 次为逐项原始字节读取。

外层 181 项精确分为 166 个安装载荷、9 个产品 bootstrap、5 个 NSIS support 和 1 个生成的 `Uninstall.exe`；内嵌卸载器 11 项为 9 个产品 bootstrap 与 2 个 NSIS support。两套宿主都通过路径、大小写、长度和 SHA-256 exact-set 比较，并确认归档字节来源未被同 SID 的并发替换窗口污染。

这里仅证明生成的 `Uninstall.exe` 是候选归档中的静态成员，且其内嵌文件闭集与预期一致。它没有独立通过 release Authenticode、VERSIONINFO 和交付身份验证；因此证据仍明确为 `generated_uninstaller_verified=false`、`generated_uninstaller_trusted=false`、`final_payload_closure=false`、`delivery_admitted=false`。

## 实际发现并关闭的回归

1. **DP1-NSIS-PS51-04（已关闭）**：真实 builder 最初把默认 `RepoRoot` 直接依赖参数声明期的 `$PSScriptRoot`。Windows PowerShell 5.1 在该时点得到空值，构建在任何系统变更前退出；PowerShell 7 不复现。默认路径现改为参数绑定后解析。最终 PS5 真实 stage、20 个 PE／22 个绑定、NSIS 编译、候选租约和发布提交全部通过。

本批没有产生已安装或 live-host 产品回归结论，因为候选从未执行。审计中关闭的路径替换、归档输出竞态、编译输入漂移和发布中断窗口属于构建证据缺口，不重新包装成用户可见产品缺陷。

## 回归矩阵

PS5／PS7 均无 silent skip：package staging 各 31/31、NSIS stage 各 20/20、staged-build 租约／发布各 9/9、installer static 各 42/42、postbuild synthetic 各 50/50、registration completeness 各 36/36、Rime/PIME maintenance 各 33/33。全局纯源码合同仍为 37/37；新鲜基线固定 109 个来源并保留 3 项真实安装态待办。CI YAML 已实际解析，并确认上述三组新增合成合同各自同时运行 PS5／PS7，PS5 有显式退出码检查，CI postbuild 不绑定本机 7-Zip 或 NSIS 路径。

精确测试路径、摘要、源码摘要和边界见[结构化证据](../testing/dual-product/2026-09-06-dp1-g.json)。DP1-F 的 21/21 及其旧摘要保持原始历史记录，不用本批 31/31 结果回写或重标。

## 下一顺序与硬阻断

下一项仍按既定顺序接入实际维护事务：

1. 将 stage／postbuild 证据写入 canonical v2 package receipt，并闭合完整 NSIS compiler toolchain 输入；
2. 建立持久 prepared／commit journal、恢复归档、精确 removal、逐维回滚与 crash replay；
3. 完成同一发起 SID 的真实 UAC／Profile API、注册收敛和非提升 Runtime readiness；
4. 经另行交接后，才执行 installed／registered／live-host、必要重启、单装和两种共存顺序验收；
5. 在可信签名与上述门禁完成前，不解除安装器、卸载器和 tagged-release 硬阻断。

当前 builder 不自动调用 postbuild verifier，canonical receipt 也尚未绑定这份静态解包证据。完整 NSIS toolchain closure、可信卸载器、签名、持久事务、installed/live、ARM64 原生运行和 DP2 共存验收均未完成。

## 已安装与用户边界

当前日用 YimeCore local.12 未变，local.13 未安装；生产 Rime/PIME、默认输入法、用户正文、设置、学习、恢复档案及冻结历史载荷均未读取、启动或修改。当前包 profile 只有 `x86,x64`；ARM64 仍须在独立原生目标取得自己的 Runtime、Broker、包装事务和 registered/live-host 证据。本批不宣称 DP1、DP2、DP3、L5 或 L6 完成。
