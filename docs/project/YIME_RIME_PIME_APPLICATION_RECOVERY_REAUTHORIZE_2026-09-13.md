# 给“计算机”AI：新建限时恢复授权，继续复用原事务

已审阅 `7395165f`：旧恢复授权在 2026-09-13 01:48:12 UTC 到期，测试端在执行前停止；没有运行验证、窗口或 Apply。不是新增恢复失败，也不是恢复完成。

本页更新[应用退出交接](YIME_RIME_PIME_APPLICATION_RELEASE_HANDOFF_2026-09-13.md)的授权准备步骤。作用域仍是事务 `9fe7f28d-0889-4828-85b5-1f481431b43a` 的剩余文件回滚和原有 TIP 修复；不扩展安装、跨产品维护或跨会话基线权限。

开发端已核实 `823d49f9` 的 [CI 34759094932](https://github.com/tsaanghwang/Yime/actions/runs/34759094932) 成功，当前 95 项策略代码均匹配。本次只补交接文档，无需等待新候选包或为文档重新构包。请在用户已准备好操作时新建授权，避免等待期间再次过期。

## 一、准备新的授权，不改旧文件

保留旧授权、原始 ticket、journal、所有报告和 `approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76/original-bundle`。**不要运行 `prepare-defaultstring-recovery.ps1`**：它会从已不完整的安装目录重新复制全部载荷，不适用于当前部分缺失状态。

由 Golde 在 Explorer 启动的同一用户原生 PS5 中，从仓库执行现有通用准备入口。先在 Git 外档案新建 UTF-8 参数文件，字段如下，路径替换为测试机真实绝对路径：

```json
{
  "DeliveryRoot": "<仓库>\\test-delivery\\rime-pime-coexistence-20260911-defaultstring",
  "ExpectedIndexSha256": "15d4819860f462f071fbac004859eb72392229030cd42f7a93aac9f776e9af9d",
  "Mode": "Resume",
  "RecoveryTicketPath": "<用户档案根>\\approval-9fe7f28d-0889-4828-85b5-1f481431b43a\\candidate-recovery-9fe7f28d-0889-4828-85b5-1f481431b43a.json"
}
```

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file "<新建的准备参数文件>"
```

该入口只读核验候选交付、原生调用环境、当前 SID/MachineGuid 和产品边界，创建新的 `approval-<新 UUID>` 档案及 24 小时授权，读取当前 peer 快照。它不执行旧安装器、不复制残余载荷、不覆盖旧授权，也不恢复产品。必须成功退出并明确输出新目录；失败则保留输出，不能继续。

## 二、创建新的固定恢复参数

在本次新授权目录中新建 `recovery-validate-applications.json`，不要覆盖任何旧参数：

```json
{
  "PolicyPath": "<仓库>\\test-delivery\\defaultstring-recovery-applications-20260913\\policy.json",
  "ExpectedPolicySha256": "c3c0dcbc08e6a5d881171c1b13cd5085b8e1cb83efae0a52bf941a6a84483802",
  "ExecutionParametersPath": "<本次新授权目录>\\execute-parameters.json",
  "PackageRoot": "<用户档案根>\\approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76\\original-bundle",
  "Interactive": true
}
```

PackageRoot 继续指向先前独立保存的完整 original-bundle；不指向剩余安装目录。若原独立载荷缺失或校验失败，停止，不复制或拼接替代品。新 `execute-parameters.json` 仅作为固定恢复入口输入，**不得单独执行**。

## 三、验证当前状态，再执行一次恢复

按原应用退出交接运行 `recover-defaultstring-transaction.ps1`，先传入本次新建的验证参数。只有退出 0 并打印 VALIDATED 后，才复制为新 `recovery-apply-applications.json`，仅增加 `"Apply": true`，随后执行一次。

新授权不能替代原始基线。固定入口仍按原摘要读取初次事务的 peer-preflight，并比较当前 peer 进程 PID、创建时间、映像及其余受保护状态；仅保留既有明确允许的 TIP 差异和诊断日志元数据例外。新准备阶段的 peer 快照用于当前观察，不会被该入口当成原基线。

因此，无论测试机是否曾注销／重启，都不能手工“补正”PID 或复制新快照覆盖旧基线。如果会话或进程变化导致保护检查失败，停在修改前，回传该具体差异；本页不授权跨会话基线重建。不会以新建授权为由跳过这一检查。

窗口交互、取消、System 持有者和静默行为均遵循原交接。不能强杀、手改字体权限、重复 Apply 或在错误后自动续期。只有 RECOVERED 与成功结果才报告整体恢复完成。

## 回传

回传新授权创建 UTC／到期 UTC（不上传授权原件或 SID）、实际执行提交、准备／验证／Apply 的退出码和控制台、应用退出交互，以及新 application-use／exact-removal／peer-repair 证据的脱敏副本与索引。尚未执行的阶段明确标记未执行。原件继续保留在 Git 外档案。
