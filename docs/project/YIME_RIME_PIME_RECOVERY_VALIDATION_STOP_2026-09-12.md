# 限定恢复在验证阶段停止：peer 日志摘要变化

影响产品：Rime/PIME 恢复、YimeCore 保护。恢复源码 `09120188b512893901100799cb28e3b26e68f90f`，CI 34663400675 成功；执行前策略原字节 SHA-256 及 93 个代码规范化摘要全部匹配。唯一目标仍为 `9fe7f28d-0889-4828-85b5-1f481431b43a`。

用户从 Explorer 原生入口运行“准备—验证—执行”。准备退出 0：新恢复授权 `fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76`，复制 189 个原清单成员到独立 original-bundle，未启动旧 EXE。准备 UTC 2026-09-12 01:48:09.011796 至 01:48:21.626750。

验证 UTC 01:48:21.629099 至 01:48:34.335203，退出 1，错误 `Peer changes extend beyond the admitted missing TIP; stop recovery.`。调用栈在 defaultstring-peer-repair.ps1 第 38 行，经 recover-defaultstring-transaction.ps1 第 72 行。未打印 VALIDATED，入口没有调用 Apply；未进入恢复 UAC、候选 Remove 或 TIP 修复。验证会打开事务读取租约并生成观察材料，不声称完全没有档案写入。原事务终态本轮未重新采集，不能称其已闭合。

## 额外变化

与固定原 peer-preflight 比较，当前验证快照的顶层差异只有 registry、state。registry 保留已知用户 TIP 缺失；state 仅一项文件元数据不同：

| 项目 | 原快照 | 本次准备及验证快照 |
|---|---|---|
| 相对路径 | evidence/language-bar-host.log | evidence/language-bar-host.log |
| 字节数 | 13119 | 13252 |
| SHA-256 | 798c6f380dfbcb340a7dd2c08296a5d6a6ab5641eed8b7af2e0b8130616d37ac | 2d1f97dd3570b95b526ecdd4a5544576a5ac325205ed1d632700682f6ab2d694 |

增加 133 字节不证明只是安全追加；未读取日志内容，也未校验原内容前缀。不能据此归因于用户操作或恢复准备。其他状态文件元数据一致；本次新授权的准备 peer 快照与验证快照结构相同，说明额外差异在准备快照时已被观察到。该工具只允许缺失 TIP，因而按设计拒绝进一步恢复。

保留新授权、原载荷副本、诊断和前后所有档案。没有删除或改写日志、更新策略摘要、放宽保护，也没有创建另一份授权重试。请开发端审阅如何处理该额外差异，并交付限定的后续步骤。恢复未完成，旧包继续停用。

## 证据

[复核结果](../testing/platform/2026-09-12-recovery-validation-stop/verified-result.json)、[错误原记录副本](../testing/platform/2026-09-12-recovery-validation-stop/failure.json)、[外部证据索引](../testing/platform/2026-09-12-recovery-validation-stop/external-index.json)、[仓库索引](../testing/platform/2026-09-12-recovery-validation-stop/index.json)。原始控制台位于 Git 外 `recovery-09120188-once`，错误为 diagnostics/failure-541c4def249a48c995d2737ab493fc9d.json。原错误栈中的中文已有乱码，副本保留该现状，未伪造修复。授权及完整 private peer 快照不提交 Git。
