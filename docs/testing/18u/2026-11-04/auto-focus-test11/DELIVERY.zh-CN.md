# test.11 完整包：自动跟随与前端/TIP v2 配套

日期：2026-11-04（Asia/Shanghai）。产品：独立 YimeCore 18u，原生 Windows AMD64。版本 `0.1.0-18u-test.11`。

[PR #99](https://github.com/tsaanghwang/Yime/pull/99) 已合入 MSI 准备分支，合并提交 `c0e67e47cbd7128461ac502f7449a2b5146e7fe2`。新包从其后继版本提交 `aed8116262ab5ddce2395f533ee6309baa2f1969` 构建，分支为 `codex/msi-18u-test-preparation-20261103`；交付文档后续提交不改变这个固定包身份。

[下载完整 test.11 Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41837039112/artifacts/13327157015)。保留至 **2026-11-18 21:22（Asia/Shanghai）**，GitHub 原始到期值为 `2026-11-18T13:22:47Z`。下载的是外层 Artifact ZIP，解开后取得下表内层产品 ZIP；两层哈希不同。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 下载的 Artifact 外层 ZIP | 192248039 | `911680c4d1f94f935c6429f0bcd0b229930b481af30f2a4bc4994bf1c9a23563` |
| `YimeCore-18u-0.1.0-18u-test.11-windows-amd64.zip` | 192209196 | `7fba42fbe954e3c5d6df5c3a9b220f93bf9e5c2f7a5be8c7c69aed1ddb9742fc` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7956992 | `eacee66df11e25dc705a5903dc38a98d738d7505e1a2031c3c8618c52aa69129` |
| `payload/x64/YimeTextService18u.dll` | 714240 | `331347e1f36450afa89dbe17acecd48f3b7f72923c221c66e85afa71051e9e56` |

本机核验后的内层 ZIP：`C:/dev/Yime/.worktrees/18u-test11-20261104/.generated/test11-delivery/verified-aed81162/YimeCore-18u-0.1.0-18u-test.11-windows-amd64.zip`。慢速下载已由同一 Artifact 的有界分段下载替代，重组字节与 GitHub 原始摘要完全一致；没有重新压缩或重新制包。

## 配套与完整性

前端 manifest、包证据和 CI receipt 均声明 `frontendProtocol={version:2, pipePrefix:"Yime18u.Frontend.v2."}`。前端为 `installed-tsf-auto-focus`、`sourceChanges=false`，与专用 TIP 来自同一干净源码提交。前端 ASCII 与 TIP UTF-16LE v2 管道标记均存在，两者无 v1 标记；CI 实际执行内存 v2 dispatcher、状态/身份/编辑及生产 profile 查询回归。

两层 ZIP 的 CRC 与哈希、包内 **46 个文件**的完整清单/大小/SHA-256、6 个 AMD64 PE、四个锁定资源、前端与宿主资源投影均已核验。完整包包含前端、专用 TIP、独立 Broker/Runtime、注册维护工具、安装脚本和资源；不能只取 EXE 或 DLL 混入旧安装。

原字节清单见 [package-evidence](package-aed81162/package-evidence.json)、[frontend manifest](package-aed81162/frontend-manifest.json)、[package receipt](package-aed81162/package-receipt.json)。完整核验见 [download-verification.json](download-verification.json)，独立读取脚本见 [verify_package.py](verification/verify_package.py)，其 12 项合成 ZIP 回归通过。

## 同源 CI

- [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/41837039112)：success；包括全部 15 项组装测试、前端 v2 配套拒绝回归、原生内存测试及完整包构建。
- [Build](https://github.com/tsaanghwang/Yime/actions/runs/41837039188)：success。
- [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/41837039365)：success。

[CI 状态快照](ci-runs.json)、[CI 原始日志与摘要索引](ci-evidence-index.json)、[原生内存回归输出](ci-aed81162/frontend-memory-edits.log)。本地组装测试受符号链接权限影响的单项已由 CI 原有严格检查补全，未删除或跳过；本地历史限制仍保留在[准备记录](DEVELOPMENT.zh-CN.md)。

## 范围

本轮只合并源码、离线构建、下载和静态核验。未安装、未执行输入法注册或默认设置修改、未重复 test.8 实测、未启动包内产品程序。真实宿主自动跟随和手指/笔验收仍未执行，不继承旧包或源码回归结论。旧会话取消、未知结果锁定与禁止重放合同继续保留。

六个 PE 的 CI 签名观察均为 `NotSigned`；SHA-256 用于固定文件身份，不是发布者签名。原始签名记录已与实际载荷哈希核对，见 [signatures.json](package-aed81162/signatures.json)。
