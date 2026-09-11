# 专用收尾入口执行前发现授权摘要域混用

测试端已合入 `6457bb7f` 与 `e08b5487`；再次 fetch 后远端 HEAD 仍为 `e08b5487e8ab995251f71af1b354923b3e996f9f`，尚无第三个更新提交。交付 CI 34602235883 成功。新 jobexit 候选六项完整性通过，original-bundle.zip 的长度和 SHA-256 匹配 PIN。

**未运行 finalizer preview/Apply，未生成新授权，未解压或修改产品。** 执行前阅读入口并只读核对现有归档，发现 `tools/dual-product/finalize-original-rollback.ps1:36` 的固定摘要与实际计划字段不属于同一种摘要。

| 对象 | 已核对的值 |
| --- | --- |
| 原计划 original_approval_sha256 | `1a27c02e0f8af39fd845c2dbb776ea3776ea2c6a504aa6d59fc5816c744e03a6` |
| 原票据 approval_sha256 | `1a27c02e0f8af39fd845c2dbb776ea3776ea2c6a504aa6d59fc5816c744e03a6` |
| 原 authorization.json 文件 SHA-256 | `89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab` |
| 收尾入口第 36 行比较常量 | `89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab` |

计划和票据记录的是原授权的规范化对象摘要；第 36 行却使用授权 JSON 原始文件摘要。故原件正确也会触发 `Finalizer plan differs from reviewed original transaction.`，不能把此拒绝解释为现场计划被修改。

本次读取现有执行后归档 `readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-09d74715032c46a4af47642e44e61071/install-journal-copy/prepared.bin`，先校验 YDP1UTX1 魔数和内嵌 payload 摘要，再读取字段；原票据和授权文件只读。未打开 transaction store，也未为复现运行维护。

请开发端修正固定摘要域并覆盖实际 finalizer 入口的这一校验。建议从已固定原票据验证计划授权对象摘要，并将原授权文件哈希作为独立证据校验，不能删除摘要检查或修改现场值以迎合常量。修复及对应 CI 通过前，保留现状，不让用户运行一个已知会失败的 preview。原收尾完成并复核之前，新 jobexit 包也不安装。

另按 `6457bb7f` 修正此前解释：active-descendants 事件是旧代码对即时 Job 计数的解释，不能证明用户看到的两个 PowerShell 是未退出后代。开发端已复现初始进程退出后 Job 记账延迟，修复保留有界等待后的终止保护；现场缺少当时 PID/Job 计数，仍不将复现推演成全部现场细节。
