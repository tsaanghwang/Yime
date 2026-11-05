# main test.12 完整包核验交付

核验日期：2026-11-06（Asia/Shanghai）。产品：独立 YimeCore 18u，原生 Windows AMD64；版本 `0.1.0-18u-test.12`。

## 合并与审查状态

[PR #100](https://github.com/tsaanghwang/Yime/pull/100) 已于 **2026-11-05 16:17:54 +08:00** 合并到 main，提交为 `36ca828b3531d6c61740e02b6835aa930442b97a`。本轮查询时已经合并，因此没有再次发起合并。远端 main 与本包源码一致；原 `C:\dev\Yime` 的本地 main 未切换，五个未跟踪目录原样保留。

最新审查状态为 COMMENTED，摘要为“No open issues”，没有 inline review thread 或后续顶层评论；不是 APPROVED。审查提醒原生 TSF 生命周期、异步编辑与安装边界仍需真实 Windows/TSF 专项验证，本轮保留该范围限制，不以 mock/内存测试替代真实宿主或物理验收。未发现待修复的具体审查项。

PR head `cb8bd659` 的五项 PR CI 全部成功；合并后 main 的五项 push CI 也全部成功。PR 测试合并源码 `df3d9351` 的旧 artifact 不作为本次交付。当前使用 **main 实际合并提交 `36ca828b`** 构建的完整包，前端/TIP 均包含 PR #99 与 `f3056aab` 的暂停模式偏好修复。

## 固定下载与哈希

[下载 main test.12 完整包 Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130)，到期时间 **2026-11-19 16:22:31 +08:00**。下载为外层 Artifact ZIP，解开后取得下表内层产品 ZIP；二者哈希不同。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Artifact 外层 ZIP | 192248008 | `d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c` |
| `YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip` | 192209192 | `0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7956992 | `d9a15e1e7d6da30d21db32813a92ee2c50df03b8855e0cc05f9f1482b0ffecbe` |
| `payload/x64/YimeTextService18u.dll` | 714240 | `9193311f4a5b3aaa6e09d8e6b23adb84235444f6bea8610620fd04aaac6c1a7d` |

本机已核验的内层 ZIP：`C:/dev/Yime/.worktrees/18u-test12-main-delivery-20261106/.generated/test12-main-download/verified-36ca828b/YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip`。保留下载的原始归档字节，没有重新压缩、重新制包或只取 EXE/DLL。

## 实际静态核验

- 两层 ZIP 的 CRC、大小和 SHA-256 通过；外层摘要与 GitHub artifact metadata 一致，内层摘要与独立 CI receipt 一致。
- 包内 **46 个文件**全部逐项校验，包含安装脚本、专用 TIP、前端、Broker/Runtime、注册维护工具、宿主检查器和完整资源；多层 manifest 与完整清单一致。
- 六个 PE 均为 AMD64。前端 ASCII 与 TIP UTF-16LE v2 管道标记存在，v1 标记不存在；manifest 声明 `installed-tsf-auto-focus`、`sourceChanges=false`、`sendInputFallback=false`。
- 包证据、独立产品描述、前端 manifest、resources 与 CI receipt 全部绑定 `36ca828b3531d6c61740e02b6835aa930442b97a`。四个锁定数据文件、布局投影和前端/宿主同名资源字节一致。
- 六个 PE 的 CI Authenticode 观察均为 `NotSigned`；已将记录中的大小/哈希与实际载荷匹配。哈希固定文件身份，不代表发布者签名或安装接受。
- 从 test.11 已有独立读取核验器复制到本交付目录，仅更新 test.12 版本标识；[12 项合成 ZIP 回归](verification/test_verify_package.py)通过，覆盖篡改、CRC、重复路径、源/版本不符、v1、错误架构及缺失资源拒绝。

完整核验结果：[download-verification.json](download-verification.json)。原字节证据：[包清单](package-36ca828b/package-evidence.json)、[前端 manifest](package-36ca828b/frontend-manifest.json)、[CI receipt](ci-36ca828b/package-receipt.json)、[签名观察](package-36ca828b/signatures.json)。[核验脚本](verification/verify_package.py)只读取 ZIP，不执行产品程序。

## 合并后 CI 与证据

- [Build](https://github.com/tsaanghwang/Yime/actions/runs/41993378060)：success。
- [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/41993378076)：success。
- [18u async route contracts](https://github.com/tsaanghwang/Yime/actions/runs/41993378057)：success。
- [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/41993377945)：success；严格执行全部 15 项组装检查、前端/维护隔离回归、原生内存 TSF 回归、全词典输入检查及完整制包。
- [CI retention tests](https://github.com/tsaanghwang/Yime/actions/runs/41993378012)：success。

[CI 快照](ci-runs.json)、[制包步骤](ci-job.json)、[原始证据索引](ci-evidence-index.json)。[证据 Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13400010403)也已实际下载：16680 字节，SHA-256 `822ecf6055a96703d182631a5c475f1e81bcfc1d2570540f1ad6a21897202af0`，与 GitHub 摘要一致；原始日志按字节保存，未重写历史记录。

## 范围与接续

本轮只有远端状态核对、完整包下载和静态核验。未安装、未执行注册或默认输入法修改、未运行包内任何 EXE/DLL/安装脚本、未修改用户数据。真实宿主自动跟随、窗口内上下文变化与手指/笔验收仍须另行观察记录；不继承 test.6–test.11 或其他机器的通过结论。焦点取消、会话代次、失败锁定及禁止重放合同保持。

交付记录分支为 `codex/18u-test12-main-delivery-20261106`。后续文档提交不改变固定包源码和哈希；本分支不重制包、不重写已合并的 PR #100，也不将原本的 main 包改称为文档提交构建。
