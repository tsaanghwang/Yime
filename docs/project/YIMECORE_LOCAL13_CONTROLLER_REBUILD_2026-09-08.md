# YimeCore local.13 新控制器候选构包复核

2026-09-08，影响产品：YimeCore。新普通候选 `yimecore-local-0.1.0-local.13-af06362e5433` 已从干净提交 `8f6422e7c2522cdc352103b2e5815e8fc7d85b35` 独立构建，完整通过隔离验证。候选仅保留在仓内 `.tmp/yimecore-local-product/rb13-0908-b903f821/package`，尚未仓外封存或安装。结构化绑定见 [构包复核记录](../testing/l6/2026-09-08-local13-controller-rebuild.json)。

包 manifest SHA-256 为 `dccbf6f7ef553bda1e20d7b8fa1659fe7e4b691d5d492b8210c9b7c606a7ced4`，85/85 成员的大小与哈希通过复核。774 项构包来源的 manifest SHA-256 为 `af06362e54338732875209456025d9531ada3170020edc320a73e032788fc74b`。源码 `tools/yimecore/manage-e6c-trial-install.ps1`、源码 manifest、源码 ZIP 内控制器及包内 `maintenance/Manage-YimeCoreTrial.ps1` 均绑定 `e65ea013b5c947c68604bc633e180563a811b856ed6c2aa7b09f3d5c291cd95a`，因此新普通候选包含 [NativeDesktop 演练提交前回滚保护](../testing/l6/2026-09-08-native-desktop-rehearsal-source.json)。

构包前重新执行连读准入，未复用历史准入。新根为 `.tmp/yimecore-experiment/speech-admission-20260908-105515-a54ff8e1409c445c8d1e96e26ecbadf5`，summary SHA-256 为 `8b7e257c1eccf096aae4b9b9d853d57f6b7b419330052840f2388599915cc865`；580 项来源清单 SHA-256 为 `0c0b1aa9b19d06b6d08f5e90fc92109e5ade386f88861d02db030cb9edb979e8`。构包输入独立绑定这两个摘要及实际导出回执，源集合、已安装公共包保护和保留历史工件的前后校验均通过。

| 验证层 | 实际结果与范围 |
| --- | --- |
| 连读准入 | 499 PASS、0 FAIL、3 SKIP；仅原有 24 条 Stage5C 记录、72 行三模式别名，私有 Broker 生命周期 |
| 来源清单回归 | PowerShell 5.1 / 7 各 21/21；运行实际准入清单函数，与独立 Go 导出器固定清单逐项比较 |
| 原生与 Go 构建 | x64/x86 合同各通过、焦点取消各 32 项；五个 Go 测试包通过；自有随机注册表夹具 28 项通过 |
| 三模式索引 | 每模式 1,166,753 条；每份独立构建两次，字节一致 |
| 包与隔离 Runtime | 37 项包合同；12 个句子用例；三模式合成学习/恢复 generation 12、11 条恢复记录；私有 Broker 故障重启及最终停止通过 |
| 直接 TSF | 新输出 x64/x86 直接组合测试通过；`text_extent_anchor=false` 原样保留，不推定真实宿主光标位置验收 |
| 最终保护 | 包测试前后独立性审计通过；生产注册与默认输入法保护一致；构包转录历时 143 秒 |

三项 SKIP 原样保留：`TestSpeechManifestRejectsOutsideAndIndirectPaths/symlink`、`TestSpeechPackageRejectsSymlinkPayload`、`TestSpeechProductExportRejectsIndirectSources`。源码已有专项符号链接测试入口不等于本次准入中的这三项执行通过。

首轮从 `41f4e855dc5501811c6f17cda753564ce033a524` 构包，在独立连读导出时报 `export evidence source set incomplete`。原因是准入器漏收 `tools/yimecore/test-speech-symlink-evidence.ps1`，只封存 579 项而独立导出器要求 580 项。原失败根 `.tmp/yimecore-local-product/rb13-0908-a641d36f` 原样保留，不作候选使用。该轮旧摘要的 `installable=true` 是错误字段；本轮同时修复为只有构包与保护门禁全部通过才可声称产物满足 installable 合同。此字段始终不代表已获原生维护执行许可。

本轮执行的是新输出内的编译、只读 Plan 合同与私有 Runtime/TSF 测试。没有执行安装或注册，没有运行已安装 EXE，没有读取用户正文、设置或学习状态。注册表写入仅发生在自动清理的随机测试夹具中；正式产品保护检查为只读。根代理在构包后另行只读核对 installed local.12 的固定 manifest 与 74 项公共成员仍一致；该独立观察只留有命令输出，不虚构额外原始证据文件。

旧 local.12 manifest `9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e`、其有效 L5 用户确认、封存包及旧准备故障包均未改动。旧封存控制器仍为 `ff3a563bf58999683f34e9c6fb73656ea6790b120e48fd322b71f97c99818cca`；旧故障包 manifest `36b897897ebf579dbb2cad5e7e9479a3ff0803f12f8aa8e36cd836f3c77ae03a` 不因新普通候选构建成功而获得新保护或执行资格。

下一步仍需实现并审查同 SID 原生维护演练入口和所需原生证据提供程序，另行从当前来源准备有明确身份的新故障候选，并安排新普通候选的仓外恢复归档。之后才能在另行授权的维护窗口完成受影响路径与已安装宿主验收；当前并非只差授权或按一次执行。新故障演练、实际当前候选恢复/回退/卸载、L6 封存和 `local_product_ready` / `public_release_ready` 均保持未通过。隔离合成恢复不能替代真实安装态恢复。
