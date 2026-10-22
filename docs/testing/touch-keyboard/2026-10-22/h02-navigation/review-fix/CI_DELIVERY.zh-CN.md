# PR #77 消息泵取消修复包：固定交付

2026-10-22。[桌面 CI run 39751192421](https://github.com/tsaanghwang/Yime/actions/runs/39751192421) 已全部通过。运行时修复 head 为 `ceed533ff98796deb4003e2020aa8cf1ee23dd2b`，包源码为 PR 测试合并提交 `f2e1a03659bc6b90b9bcc8ec1acba4c5ba63cf6c`，两个包均为 `sourceChanges:false`。后续提交仅补交付文档，不用其新 artifact 静默替换此包。

| 项目 | 固定身份 |
|---|---|
| x64 下载 | [artifact 12413647726](https://github.com/tsaanghwang/Yime/actions/runs/39751192421/artifacts/12413647726) |
| x64 ZIP SHA-256 | `ba9a5f4c1fb638fe40700dd008bd2b6ae2ae7eb65c338bc859c2ee3b684da74c` |
| x64 exe SHA-256 | `e01cef476b93aee09e1f96214f289dbc1a33c10ebcbcf916045723711dcaacf9` |
| ARM64 下载 | [artifact 12414405688](https://github.com/tsaanghwang/Yime/actions/runs/39751192421/artifacts/12414405688) |
| ARM64 ZIP SHA-256 | `80d747a55c26ab56c729a7db5b20e7e1ddc6a2ba17ff4f5da931f6d193f21108` |
| 检查报告下载 | [artifact 12413712468](https://github.com/tsaanghwang/Yime/actions/runs/39751192421/artifacts/12413712468) |

三份实际下载 ZIP 的 SHA-256 均与 GitHub artifact digest 一致，ZIP CRC 完整，x64/ARM64 各 29 个载荷逐项核对 manifest 哈希及精确文件集合。完整清单见 [ci-package-identity.json](ci-package-identity.json)，CI 包检查报告见 [ci-package-check.json](ci-package-check.json)。三模式完整词典在仓库外空工作目录内存确认“你”、18u/100 键默认 profile、资源/路径拒绝检查通过，没有 OS 宿主输入。ARM64 仅交叉构建与静态核验。

本机下载目录为 `.generated/touch-keyboard-h02-ci-39751192421`，与历史初版和本地开发包分开。下载使用仓库约定代理，无安装或用户数据修改。初版及失败反例证据不覆盖。

依照[验收步骤](../../../../../../prototypes/touch-terminal/desktop/ACCEPTANCE_18U.zh-CN.md)与[结果模板](../RESULT_TEMPLATE.zh-CN.md)重新执行真人手指、纯笔和真实宿主案例。模拟消息泵回归、CI 和包核验不计入物理验收；全部真人结果仍待记录。
