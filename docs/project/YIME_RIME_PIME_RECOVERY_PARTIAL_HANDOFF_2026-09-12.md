# 给“计算机”AI：部分载荷状态的限定续接

影响产品：Rime/PIME 回滚、YimeCore TIP 恢复。已接收 `6349c170`，此前核对 6 个副本通过。7 项缺失、185 项仍在，TIP 修复未执行。此次不是宣称已修复字体文件的具体阻断原因，而是补齐逐文件证据，并使入口安全接受已经发生的部分移除。

## 改动与验证

- 验证及 Apply 均重新核验所有仍存在文件的原文件身份、大小和摘要；只接受确切缺失，不把访问失败当作缺失。一旦发现部分载荷缺失，必须先重新证明候选注册完全 Absent；否则停止。原授权、计划摘要及未提交成功安装的条件保留。
- 注册 Absent 时 worker 原有路径跳过注册移除，不运行缺失的 DLL。原独立 original-bundle 继续用于必要的验证，不再从已部分移除的安装目录复制。
- 每次移除返回后、抛出未完成错误之前，保存 `exact-removal-*.json`：路径、status、marked_for_deletion、removed、native_error，以及本次开始时的缺失数量。原生移除器打开阶段异常也保存原异常和待处理清单；不会伪造不存在的逐项结果。
- 原移除器首次未完成后停止，后续项为 not-attempted。因此上一轮 185 项仍在不等于 185 项都被占用。首个剩余项是字体文件，但没有原错误码，不能认定具体持有进程、权限或字体映射原因。没有放宽原生删除身份校验，也不强制删除、结束进程或操作字体注册。

已用真实文件句柄复现部分删除：首项移除，中间项因仍被读取而处于删除挂起，末项未尝试；结果先持久化再报告失败。释放隔离测试句柄后，续接只移除剩余项。注册未清理、剩余文件内容改变均被拒绝，未列入计划的文件保持不变。PS5 该回归、恢复适配器、25 项现有维护检查通过，入口静态检查通过；没有对开发机已安装产品执行删除或恢复。

## 测试端执行一次

拉取本页所在提交，等该提交 CI 成功。复用 `approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76` 目录及 original-bundle。**不重新准备、不复制载荷、不运行旧 EXE，不重跑 lockfix 参数。**

策略为 `test-delivery/defaultstring-recovery-partial-20260912/policy.json`，SHA-256：

```text
e7ee39f99a35dec965d6103aa387acf6a232a36a9a1be5e0d7fda6c8d37e5970
```

测试 AI 从已有 recovery-validate-lockfix.json、recovery-apply-lockfix.json 复制生成新 recovery-validate-partial.json、recovery-apply-partial.json，只更新 PolicyPath 为新策略实际绝对路径及 ExpectedPolicySha256；其他字段保留，Apply=true 保留。UTF-8、新建、不覆盖旧文件；若新文件已存在先确认执行状态，不自动重试。

Golde 在 Explorer 启动的非管理员原生 PS5 中执行，替换 `<已有恢复目录>`：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-validate-partial.json"
```

必须退出 0、打印剩余载荷数量及 VALIDATED，再执行一次：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-apply-partial.json"
```

授权过期或任何检查失败即停止，不改时间/摘要、不自动续期、不再次 Apply。若再次移除未完成，必须回传新增 exact-removal JSON 的脱敏副本，尤其第一项非 removed 的 status/native_error；原件、请求、journal 留在 Git 外档案。不得手工删除剩余字体、清理锁文件或补写终态。

回传 UTC、退出码、控制台、移除结果、实际 journal/注册/peer 修复结果。只有 RECOVERED 与成功 result 才报告整体恢复成功；否则保持未完成。物理输入和重启验收单独标记，旧候选继续停用。
