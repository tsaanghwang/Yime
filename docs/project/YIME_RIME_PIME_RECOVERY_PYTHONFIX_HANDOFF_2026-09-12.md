# 给“计算机”AI：修正 Python 启动路径后继续限定恢复

影响产品：Rime/PIME 恢复工作进程启动；YimeCore 恢复边界不变。已接收 `b628d676`，5 个证据副本大小与摘要核对通过。上一轮 VALIDATED 成功，Apply 在 Start-Process 参数绑定时失败；未启动该提权 worker，未执行 TIP 修复。不能把 Apply 启动前已执行的协调、运行时停止检查和档案写入表述成整个入口完全没有作用，也没有新证据证明原事务已闭合。

修复仅涉及适配器：按 PATH 顺序选取一个存在的原生 Python 文件，跳过 WindowsApps 执行别名，确认 FilePath 为单个字符串后才启动。找不到则明确停止。新回归通过实际启动辅助函数检查传入 Start-Process 的参数，覆盖多命中、别名在前、多个原生版本、缺失文件、只有别名、无匹配及带空格参数；PS5/PS7 均通过。本机原生 Python 只读探测通过，未执行真实 UAC 或产品恢复。

## 测试端操作

拉取包含本页的开发分支，等本提交 CI 成功。继续使用已有 `approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76` 恢复目录，**不重新准备授权、不复制载荷、不运行旧 EXE**。

新策略：`test-delivery/defaultstring-recovery-pythonfix-20260912/policy.json`，原字节 SHA-256：

```text
281d0cdfcb0bee955333bb92741bc1b58e70e10719ebd7f09be0de13b3443102
```

测试 AI 从现有 recovery-validate-logfix.json 和 recovery-apply-logfix.json 分别复制生成同目录的新 recovery-validate-pythonfix.json、recovery-apply-pythonfix.json。只更新 PolicyPath 为新策略的实际绝对路径、ExpectedPolicySha256 为上述摘要；其他字段保留，包括 Apply=true。使用 UTF-8 JSON，不覆盖旧文件或修改授权。新文件若已存在，先确认是否已经执行，不自动重跑。

由 Golde 在 Explorer 启动的原生非管理员 PS5 中执行（替换 `<已有恢复目录>` 为实际绝对路径）：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-validate-pythonfix.json"
```

退出 0 且打印 VALIDATED 后，才执行一次：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-apply-pythonfix.json"
```

原授权期限和全部绑定仍检查；过期或任何其他失败即停止，不改时间/摘要、不自动续期、不重复 Apply。按 [原恢复边界](YIME_RIME_PIME_DEFAULTSTRING_RECOVERY_HANDOFF_2026-09-12.md) 和 [日志比较规则](YIME_RIME_PIME_RECOVERY_LOGFIX_HANDOFF_2026-09-12.md) 保留原始材料，回传 UTC、退出码、错误、实际原事务终态和 peer 修复结果。未出现 RECOVERED 及成功 result，不报告整体恢复完成。
