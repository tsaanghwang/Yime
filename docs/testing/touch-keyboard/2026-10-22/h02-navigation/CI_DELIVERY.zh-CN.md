# PR #77 固定 CI 包交付

**历史初版包：发现消息泵内取消缺陷后停止用于真人验收。** 修复与反例证据见 [review-fix/REVIEW_RESOLUTION.zh-CN.md](review-fix/REVIEW_RESOLUTION.zh-CN.md)。下列已通过的 CI/哈希事实保留原样，不提升为修复后结论；后续固定修复包另建身份。

2026-10-22。[PR #77](https://github.com/tsaanghwang/Yime/pull/77) 运行时提交 `df70abc60ce466b2ab40c2b813d8ce89a9fc1946` 已推送；[桌面 CI run 39749274057](https://github.com/tsaanghwang/Yime/actions/runs/39749274057) 全部通过。包的源码是 PR 测试合并提交 `ef3e231793c1b45e89ae9202bbc5245592d99e06`，不是运行时 head 或未来最终合并提交。两个包都为 `sourceChanges:false`。

| 项目 | 固定交付身份 |
|---|---|
| x64 下载 | [artifact 12412164789](https://github.com/tsaanghwang/Yime/actions/runs/39749274057/artifacts/12412164789) |
| x64 ZIP SHA-256 | `1038e8fa39aca95d5f3b4856ae40b570ab3137dd87bbd617ab00f7e9d2fd8188` |
| x64 exe SHA-256 | `3f3e7e5a991068fb4f69d41b94415d156369e797cf110f500ebf5e57eaceb66e` |
| ARM64 下载 | [artifact 12412917810](https://github.com/tsaanghwang/Yime/actions/runs/39749274057/artifacts/12412917810) |
| ARM64 ZIP SHA-256 | `de9963656039eee4d8ba3c9f241a356ddef66935c78a2e0afa0bc0dd8ad1acbe` |
| 验证报告下载 | [artifact 12413236867](https://github.com/tsaanghwang/Yime/actions/runs/39749274057/artifacts/12413236867) |

三份 ZIP 已实际下载、校验 GitHub 报告的 digest 与 ZIP CRC；x64/ARM64 各 29 个载荷逐一核对 manifest 哈希，确认无额外/缺失文件。完整 manifest、资源、路径与字节数见 [ci-package-identity.json](ci-package-identity.json)。CI 原始包报告见 [ci-package-check.json](ci-package-check.json)：仓库外空工作目录、默认 18u/100 键、三模式内存确认“你”、资源缺失/篡改和外部路径拒绝通过，未发送 OS 输入。ARM64 只有交叉构建及静态包核验，没有原生执行结论。

下载通过 GitHub CLI 写入独立 `.generated/touch-keyboard-h02-ci-39749274057` 目录。直连下载过慢，完成代理下载后停止了本次任务的旧直连下载进程；未完成的 `amd64.zip` 不是交付物，核验使用 `amd64-proxy.zip`。本地开发包、旧 #74/#76 包和证据均保留。

本固定包随后只补交付文档，不用后续文档提交产生的 artifact 静默替换。按[18u 验收步骤](../../../../../prototypes/touch-terminal/desktop/ACCEPTANCE_18U.zh-CN.md)重新执行手指/笔与真实应用案例；旧结果不继承。P11 和 H02-N1–N5 仍待真人记录，不能把 CI、模拟触点或本地渲染计入纯触摸/纯笔通过。
