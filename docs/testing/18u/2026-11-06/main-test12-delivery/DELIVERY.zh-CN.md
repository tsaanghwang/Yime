# main 合并后的 test.12 完整包固定交付记录

核对日期：2026-11-06（Asia/Shanghai）。产品：独立 YimeCore 18u；目标：原生 Windows AMD64；版本：`0.1.0-18u-test.12`。本轮仅下载、静态核验和源码内交付记录，不执行安装、注册、产品程序、默认输入法或用户数据变更。

## 固定来源与下载

[PR #100](https://github.com/tsaanghwang/Yime/pull/100) 于 2026-11-05 16:17:54（+08:00）合入 main。当前 main 及本包源码均为 **`36ca828b3531d6c61740e02b6835aa930442b97a`**。截至本次查询，最新 main push 制包运行是 [Installed 18u compile and offline checks / 41993377945](https://github.com/tsaanghwang/Yime/actions/runs/41993377945)，attempt 1，success。

- [下载 main test.12 完整包 artifact](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130)：ID `13399696130`，名称 `installed-18u-x64-test-package-36ca828b3531d6c61740e02b6835aa930442b97a`。
- [下载同源 CI 编译、离线与制包证据](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13400010403)：ID `13400010403`。
- 包 artifact 的 GitHub 到期值为 `2026-11-19T08:22:31Z`，即 **2026-11-19 16:22:31（+08:00）**；证据 artifact 到期值为 `2026-11-19T08:22:38Z`。这是固定 artifact 链接，不是永久 Release 资产；过期后不能以其他同名 test.12 包静默替代。

下载得到外层 Artifact ZIP，解开后才是下表内层产品 ZIP。两层 SHA-256 不可互用。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| main 完整包 Artifact 外层 ZIP | 192248008 | `d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c` |
| `YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip` | 192209192 | `0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7956992 | `d9a15e1e7d6da30d21db32813a92ee2c50df03b8855e0cc05f9f1482b0ffecbe` |
| `payload/x64/YimeTextService18u.dll` | 714240 | `9193311f4a5b3aaa6e09d8e6b23adb84235444f6bea8610620fd04aaac6c1a7d` |
| CI 证据 Artifact ZIP | 16680 | `822ecf6055a96703d182631a5c475f1e81bcfc1d2570540f1ad6a21897202af0` |

外层与证据 ZIP 均实际下载并匹配 GitHub API 的大小和 digest；内层匹配已核验 CI 证据中的 [package-receipt.json](ci-36ca828b/package-receipt.json)。本次保留原 ZIP 字节，未重新压缩或制包。机器可读身份见 [delivery.json](delivery.json)，完整静态结果见 [download-verification.json](download-verification.json)。

## 与 PR #100 合并测试包的区别

| 身份 | PR 合并测试包（历史比较） | main 合并后包（本次固定） |
| --- | --- | --- |
| 触发事件 | `pull_request` | `push`，`main` |
| PR head | `cb8bd659cd1f397bb76c7f848670be89fc48066d` | PR 已合并 |
| 实际制包源码 | `df3d9351bdcda9f167473f6d5090506a8dd37bd8` | `36ca828b3531d6c61740e02b6835aa930442b97a` |
| run / artifact | [41975718945 / 13391537298](https://github.com/tsaanghwang/Yime/actions/runs/41975718945/artifacts/13391537298) | [41993377945 / 13399696130](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130) |
| 外层 SHA-256 | `2f15e1116fc35c0052e27684c4e95bd651712e2b9b8a03881d713e3b620122a5` | `d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c` |
| 内层 SHA-256 | `291be7e3c60cc4585e98666289e16f84735d802e1189afd75e5123522d9d1698` | `0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e` |

两次构建版本和内层文件名相同，不能只凭 `test.12` 名称识别。GitHub 的 PR run `head_sha` 指 PR head；PR 临时合并制包 SHA 应从 artifact 名称和 receipt 识别。main push 的 run、artifact、receipt、安装描述符及前端 manifest 则一致绑定最终 main SHA。

[PR 临时提交](github/pr-test-commit.json)与 [main 合并提交](github/main-commit.json)的 Git tree 都是 `03f7ac4f529406b8d3db536dd63ad11e06f5ffb2`，即源码文件树相同；提交身份和构建产物不同。PR 的 CI 签名记录中前端 SHA-256 为 `6bd8bd1c120554752af76e97f73eefde3f54851db894135d99eafb07b324262e`，TIP 为 `4bc5dfe392f0efff424e8044afb86f4607a4e37f21e1865ebaf5cd47190ecbbe`，均不同于本次 main 包。不能把 PR 包改称 main 包，也不能混用两个包的 EXE、DLL、receipt 或哈希。

PR 一栏的证据强度：外层 digest 来自 GitHub 元数据；内层及 PE 哈希来自实际下载并核对 SHA-256/CRC 的 [PR CI 证据](pr-test-evidence-index.json)、[receipt](pr-test-evidence/package-receipt.json)及 [signatures](pr-test-evidence/signatures.json)。本轮未下载 PR 产品 ZIP，不声称对它逐文件复验。main 产品 ZIP 已完成下面的全量复验。

## 包内配套与完整性

已核验两层 ZIP 的 CRC、全部 **46 个文件**的完整清单/大小/SHA-256、六个 AMD64 PE（Machine `0x8664`、PE32+）、四个锁定数据文件及前端/宿主布局资源投影。完整包包含前端、专用 TIP、独立 Broker/Runtime、注册维护工具、安装脚本和三模式词典资源。

[前端 manifest](package-36ca828b/frontend-manifest.json)、[包证据](package-36ca828b/package-evidence.json)和 [CI receipt](ci-36ca828b/package-receipt.json)声明 `frontendProtocol={version:2, pipePrefix:"Yime18u.Frontend.v2."}`；前端模式为 `installed-tsf-auto-focus`，`sourceChanges=false`、`sendInputFallback=false`。前端二进制存在 ASCII v2 标记，专用 TIP 存在 UTF-16LE v2 标记，均无 v1 标记；来源声明与同一次 CI 构建记录吻合。

专用身份：CLSID `{6DFACE1F-562E-4773-A9D6-D5753A314711}`，profile `{1BD904AC-3194-4419-B70A-5574100F18B3}`。其清单见 [installed-18u-product.json](package-36ca828b/installed-18u-product.json)。这里没有更改标准 YimeCore 或 Rime/PIME 的布局、字典或产品身份。

CI 六项 Authenticode 观察均为 `NotSigned`；记录的大小、哈希与实际 PE 匹配。签名原始记录见 [CI signatures](ci-36ca828b/signatures.json)与 [包内 signatures](package-36ca828b/signatures.json)：JSON 内容相同，包内副本多一个末尾 CRLF，两份原字节及不同文件哈希均保留。SHA-256 固定文件身份，不建立发布者签名信任；本机未加载 DLL 或运行包内检查工具。

静态读取器见 [verification/verify_package.py](verification/verify_package.py)，复用未改动的 test.11 核验引擎，仅将预期版本、ZIP 名称和报告身份设为 test.12。引擎原有 12 项合成 ZIP 拒绝/完整性回归均通过，见 [engine-tests.log](verification/engine-tests.log)；实际 test.12 包另由本次全量静态报告覆盖。

## main 同源 CI 结果

| 工作流 | 结果 |
| --- | --- |
| [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/41993377945) | success；31 个步骤均成功，含严格 15 项组装检查、v2 内存编辑、全词典单键序列与完整制包 |
| [Build](https://github.com/tsaanghwang/Yime/actions/runs/41993378060) | success；12 个 job 成功，3 个显式注册/语言探针保持 skipped；含三组 real-Rime、Go race、标准原生构建 |
| [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/41993378076) | success |
| [18u async route contracts](https://github.com/tsaanghwang/Yime/actions/runs/41993378057) | success；两个 job 均通过 |
| [CI retention tests](https://github.com/tsaanghwang/Yime/actions/runs/41993378012) | success |

以上全部是 main `36ca828b…`、push、attempt 1。原本本地符号链接权限导致未完成的 assembly 用例已在该 CI 的 [15 项检查日志](ci-36ca828b/python-tests.log)中原样通过；不改写原本地限制记录。v2 证据为 [内存 TSF/dispatcher 合同](ci-36ca828b/frontend-memory-edits.log)，全词典检查为 [纯 Broker 测试](ci-36ca828b/full-resource-input.log)，均不等同真实宿主输入。

原始 API 响应与来源索引见 [github/api-index.json](github/api-index.json)，CI 下载原字节及哈希见 [ci-evidence-index.json](ci-evidence-index.json)。最新运行列表只用于识别当前 main 的最近运行，另与 main ref 交叉核对；不将 API 的历史 total_count 当作完整历史清单。

交付记录自身的复核见 [record-validation.json](record-validation.json)：逐项核对 77 个已索引证据文件、核验器及引擎哈希、JSON 可读性、main 包身份和本地文档链接。

## 本地记录缺口与 MSI 后续范围

核对 main 基线 `36ca828b…` 中的 `installer/simple/HANDOFF.md`、桌面 `HANDOFF.md`、11 月 5 日整合审阅以及 docs/installer/prototypes：只有 test.12 制包机制和合并后重建要求，没有 main 的固定 run/artifact、两层哈希及下载核验记录。原 `C:/dev/Yime` 准备分支也未记录 main 包，且有用户未提交改动。本次在独立 main 工作树补齐本文、机器可读身份、原始小型证据和 [MSI 后续收包说明](MSI-HANDOFF.zh-CN.md)，更新两个交付入口；原工作区及历史 test.11 原始记录保持不变。

MSI 指 `WIN-JTKUT7KBVN7` 测试电脑，不是另一个 `.msi` 格式安装包。本次固定的是完整 ZIP 包，供后续明确安排的收包/使用任务引用。没有发起 MSI 安装、升级、注册、重启或实机测试；test.11 及更早的已安装、真人手指/笔、Word 等结果仍属于其原包和设备，不继承为本 main test.12 通过。18u 基线及冻结的 17u/23u 候选不变。
