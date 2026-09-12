# 给“计算机”AI：事务锁交接修复后继续恢复

> 已进入载荷移除，但部分文件未完成。下一步按 [部分载荷续接交接](YIME_RIME_PIME_RECOVERY_PARTIAL_HANDOFF_2026-09-12.md) 操作，不再执行本页旧参数。

影响产品：Rime/PIME 限定回滚、YimeCore TIP 恢复。已接收 `be63ab95`，5 个证据副本核对通过。上一轮 worker 已启动，但打开安装 journal 时失败，尚未进入注册移除及 TIP 修复。

## 修复与验证

控制器原来从验证开始一直持有 ticket.store；在等待 worker 时，该 store 仍独占 transaction.lock。现在完成验证后、进入回滚前释放这一 store，保留已核验计划、外部摘要、代码/授权/包租约和产品 coordinator。worker 依旧独立打开 journal，校验 prepared 摘要和注册操作条件；后续终态处理也重新打开并验证 journal。finally 对已释放 store 不再重复调用 Dispose。

没有删除锁文件、放宽 FileShare.None、杀进程或增加自动重试。新增回归使用真实 TransactionStore 和独立 PS5 子进程，确认：父持锁时子进程被拒绝；使用生产释放函数后子进程可打开并核验计划；错误外部摘要仍被拒绝；子进程退出后父进程可重开，原锁文件仍在。已通过该回归、恢复适配器测试和现有 25 项维护事务检查，并将分进程回归接入 CI。测试在隔离目录运行，没有真实 UAC 或产品注册写入。

## 测试端步骤

拉取本页所在提交，等该提交 CI 成功。复用 `approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76` 目录；不重新准备、不复制 original-bundle、不执行旧安装器。

新策略：`test-delivery/defaultstring-recovery-lockfix-20260912/policy.json`，SHA-256：

```text
c54430ec9565e0680bd0a232604474034b57ff900961ca872d5f2595a60d836e
```

测试 AI 将已有 recovery-validate-pythonfix.json 和 recovery-apply-pythonfix.json 复制成同目录的新 recovery-validate-lockfix.json、recovery-apply-lockfix.json。只更新 PolicyPath 为新策略实际绝对路径、ExpectedPolicySha256 为上述摘要；其他字段不变，Apply 文件保留 Apply=true。UTF-8、新建、不覆盖旧参数。新文件若已存在，先核对执行状态，不自动再跑。

Golde 从 Explorer 启动非管理员原生 PS5，替换 `<已有恢复目录>` 为实际绝对路径后执行：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-validate-lockfix.json"
```

只有退出 0 且打印 VALIDATED，才继续一次：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-apply-lockfix.json"
```

授权有效期继续检查。过期或任何失败立即停止，原样报告；不改时间/摘要，不删除 transaction.lock，不强杀进程，不自动重试。原失败日志、授权、委托请求、载荷副本、journal 全部保留。

回传 UTC、退出码、控制台、新错误和实际事务/注册/peer 修复结果。仅 VALIDATED 不算恢复成功；须有 RECOVERED 和相应 result。成功后物理选择当前 YimeCore 做空白记事本输入确认，未做则标未测；重启验收另行安排。原共存保护和诊断日志比较规则不变，旧候选仍停用。
