# MSI test.7：完整触控前端开发候选交付

固定源码 `33b7113c8b76d6c95447856c2d5cca374b542507`，分支 `codex/msi-18u-test-preparation-20261103`。
[专用 MSVC/离线/制包 CI 41617296801](https://github.com/tsaanghwang/Yime/actions/runs/41617296801) 全部通过；[桌面原型 CI 41617296829](https://github.com/tsaanghwang/Yime/actions/runs/41617296829) 通过。
[通用 Build 41617297028](https://github.com/tsaanghwang/Yime/actions/runs/41617297028) 的 Go、竞争检测、三组真实 Rime、分片覆盖、原生 Win32、Rust i686、离线词典及安装器检查均通过；无需执行的一次性注册/语言环境任务按条件跳过。
本页交付源代码及完整候选包，不是本机安装或普通应用/指笔验收通过记录。

这里的 MSI 指微星测试机 WIN-JTKUT7KBVN7；交付物是 x64 ZIP，不是 Windows Installer `.msi` 文件。安装仍由包内 `installer/simple` 维护入口承担，下载和解压不等于授权执行该入口。

## 固定包

[下载完整 GitHub Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41617296801/artifacts/13221664045)，名称 `installed-18u-x64-test-package-33b7113c8b76d6c95447856c2d5cca374b542507`，保留至 2026-11-17。Artifact 外层 ZIP 内含产品 ZIP，两个文件的哈希不同。

| 对象 | 字节数 | SHA-256 |
|---|---:|---|
| GitHub Artifact 外层 ZIP | 192176992 | `166779e2bef48ac2302acc079aca32dc64e1c68b3ec74dd3c79ae0fb37678c11` |
| `YimeCore-18u-0.1.0-18u-test.7-windows-amd64.zip` | 192137872 | `a9ee98aefc93bd3b579dcbd388bc7de34a8a2fcb5839666598d660b4e9d39e8a` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7843840 | `8c5067ce0b4bd1ef3453b5c4c77efee84e0331802941f3ea55622ea12241ef8a` |
| `payload/installed-18u-product.json` | 7383 | `29c3cce5f62c77d287c4410fdea8665e58f961e46e5dbc53b2ab5133beb1cef2` |
| `package-evidence.json` | 8136 | `876748ab46401a387244803bb427b958d3828afb393dc2c27e4155baa44dada5` |

包内六个 PE 的 Authenticode 观察均为 `NotSigned`，见[签名记录](ci-33b7113c/signatures.json)。哈希证明固定内容一致性，不是发布者签名。上表产品 ZIP 哈希来自 CI 实际归档后逐成员校验的[原始回执](ci-33b7113c/package-receipt.json)，本机没有下载或运行整个安装包。

## 验证范围

专用 CI 执行了旧版 15 项组装回归、12 项制包回归、新增 7 项前端制包回归、9 项 MSI 预检拒绝路径、Go 前端/TSF 客户端回归、完整 MSVC DLL/前端构建、原生内存 TSF 编辑回归、锁定全量词典输入检查，以及实际 PowerShell 制包与 ZIP 逐成员核对。新前端所有权的 1 个接受和 8 个拒绝用例在 PS5/PS7 均通过，旧版所有权回归保留。

保留[原生编辑输出](ci-33b7113c/frontend-memory-edits.txt)、[PS5 所有权输出](ci-33b7113c/frontend-ownership-ps5.txt)、[PS7 所有权输出](ci-33b7113c/frontend-ownership-ps7.txt)及[范围记录](ci-33b7113c/scope.json)。[完整 CI 证据 Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41617296801/artifacts/13221673900) SHA-256 为 `519b2d7c5a39242868d906831a45947b8b03931caa639ccb76fa8b20718a49a9`；本机下载并核对该哈希后摘录上述原始文件。

首轮 CI 发现旧制包白名单漏带 `frontend/`，现已修复并补齐安装后所有权边界。`b254ce1c` 曾通过专用 CI，但其检查快捷入口仍向安装目录写报告；最终 `33b7113c` 改为写当前用户临时目录。`ci-b254ce1c/` 仅保存早期成功制包的历史回执，不作为本次固定交付。

## 本机接续边界

### 安装前检查与派测条件

2026-11-03 再次只读核对远端：上述 CI 仍为 success，包 Artifact 的 ID、大小、SHA-256 与本页一致，尚未过期。此查询没有下载、运行或安装包内程序。

| 项目 | 当前状态 | 安装前需要的证据 |
|---|---|---|
| 源码、构建、固定交付 | 已固定 | 只使用本页 `33b7113c`；不能仅凭同名 test.7 或旧 `b254ce1c` 回执判断身份 |
| 本机收到的包 | 待核对 | 下载后分别核对 Artifact 外层 ZIP 和内层产品 ZIP 的字节数、SHA-256；外层解压到新的包外目录，不写现有安装目录 |
| 解压后的载荷 | 待核对 | 静态核对 `package-evidence.json`、descriptor、前端 exe 及逐成员哈希；遇缺失、额外成员、错身份或哈希不符就保留记录并停止，不执行文件来试探 |
| 设备及旧安装 | 待刷新 | 确认 WIN-JTKUT7KBVN7、原生 x64 和当前 test.6；已有预检报告只证明其采集时状态，不能证明安装时无变化 |
| 维护条件 | 待安装阶段确认 | 明确本轮安装范围，保存文档并正常退出前端及相关宿主；保留原固定包和证据，不强杀、不改变默认输入法、不重置其它产品或用户数据 |
| 未签名可执行文件 | 已知限制 | 六个 PE 均为 NotSigned；实际机器是否允许加载尚未验证，不能据 CI 成功判定，也不通过关闭系统保护来放行 |
| 新版输入验收 | 未执行 | 安装后的身份、真实进程间连接、普通应用输入/读回及指笔分别建立新证据；test.6 结果不继承 |

**派测结论：可以作为下一批候选交付核对，尚不能标为“本机已安装可测”或“输入验收通过”。** 本页不是安装指令；此轮不运行 `Setup.cmd`、`Setup.ps1`、注册工具或包内检查程序。现有 `prepare_msi_18u_test6.py` 只核验旧基线，不能用于认证 test.7；安装器的 `-Action Check` 也会生成日志，不能当成零写入静态核对。

WIN-JTKUT7KBVN7 当前仍安装 test.6。本轮未执行新安装、注册、重启、默认输入法修改、Word/Edge 输入或真人指笔实测。旧安装成功记录保持，不重复、不转记为 test.7。

本候选支持原生 x64、同用户/登录会话/权限级别的可写 TSF context。触控前端三模式、CN/EN、候选等复用专用引擎；最终文本和支持的编辑动作通过激活 TIP 的实际 DoEditSession 提交。Home/End 为文档首尾，Enter/Tab 为文本；其它 Ctrl/Alt 快捷键、上下方向及功能键尚不支持，明确报错，不回退 SendInput。没有宣称所有应用兼容或完整系统键盘替代。

以后安装此固定包并准备真实应用验证时，先按正常维护流程关闭前端和相关文档，再使用安装目录 `frontend/Start Installed Touch Keyboard.cmd`。不能复制新 exe 到 test.6，也不能把预览或内存回归当成新链路已通过。实际进程间认证/激活 TIP/普通应用读回与每种指笔输入仍需独立观察。操作语义见[安装版说明](../../../../../prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md)，实测使用本目录空白结果表。
