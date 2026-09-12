# 给“计算机”AI：复用已准备目录，重做恢复验证

> 本轮验证已通过，Apply 停在 Python 路径数组绑定。下一步转 [Python 启动修复交接](YIME_RIME_PIME_RECOVERY_PYTHONFIX_HANDOFF_2026-09-12.md)，不要重复执行本页旧参数。

影响产品：Rime/PIME 恢复、YimeCore peer 比较。已接收 `459272d7`，5 个仓库副本大小/摘要均匹配；确认准备成功，验证因 `evidence/language-bar-host.log` 元数据变化退出，Apply 未执行。

## 修正范围

源码 `YimeTextServiceExperiment/TextService.cpp` 的 `RecordLanguageBarHostResult` 以 FILE_APPEND_DATA 写入该固定路径，内容是 PID、架构和语言栏 HRESULT 诊断，不是配置或学习数据。分类依据是写入代码，不是“增加 133 字节”这一现象；未声称测试机新增内容已验证为正常追加。

比较器只在临时副本中忽略这个精确 state 文件的 bytes/sha256。原始快照仍保留真实大小和摘要，不删除或改写日志。文件存在性、名称、其他字段、其他日志、配置、学习数据、payload、注册和进程身份继续比较。采用同一规则完成验证、worker 保护和恢复后比较，避免只放过第一关而在最后一关重复失败。

已通过 PS5/PS7 针对性回归、PS5 peer 保护 9 项及维护事务 25 项。原始证据未改动；真实恢复仍未执行。

## 复用现有准备结果

拉取本页所在提交，等待该提交 CI 成功。**不要再运行 prepare-defaultstring-recovery.ps1，不生成新授权，不复制 original-bundle，不运行旧 EXE。** 使用已有目录：

```text
%USERPROFILE%\Yime Rime-PIME Test Archives\approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76
```

新策略是仓库内 `test-delivery/defaultstring-recovery-logfix-20260912/policy.json`，原字节 SHA-256：

```text
9fa481a3efd3795d7207462aafbc699788a7be204c5099a0f47365ebc659a3c8
```

由测试 AI 读取现有 `recovery-validate.json`，复制生成同目录的新 `recovery-validate-logfix.json`；只把 PolicyPath 改为新策略的实际绝对路径、ExpectedPolicySha256 改为上述值，保留 ExecutionParametersPath 和 PackageRoot。同样复制原 recovery-apply.json 为 recovery-apply-logfix.json，保留 Apply=true。使用 UTF-8 JSON、新建文件，不覆盖旧参数。若新文件已存在，不覆盖或自动重跑，先确认是否已经执行。本步骤仅生成参数，不改变原授权或期限。

让用户在 Golde 同一用户、Explorer 启动的原生非管理员 PS5 中，依次执行以下命令（将 `<已有恢复目录>` 替换为上面的实际绝对路径）：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-validate-logfix.json"
```

只有退出 0 且打印 VALIDATED 才继续：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-apply-logfix.json"
```

原授权的有效期检查仍执行；若已过期或其他检查失败，停止并报告，不改时间、摘要或授权。UAC、回滚和 TIP 恢复边界沿用 [原恢复交接](YIME_RIME_PIME_DEFAULTSTRING_RECOVERY_HANDOFF_2026-09-12.md)。任何失败停止，不自动再执行 Apply。

## 回传

保留本轮退出码、控制台、原始 peer 快照和错误档案；按实际结果回传。成功记录中的 peer_snapshot_restored 表示上述比较规则下恢复，不表示诊断日志回到旧内容；应单列日志元数据差异，不能宣称所有文件字节一致。宿主输入与重启验收仍单独标记，未测不算通过。

这轮只修正动态诊断日志的分类，不解释最初 TIP 消失的底层触发，也不重新开放旧候选安装。
