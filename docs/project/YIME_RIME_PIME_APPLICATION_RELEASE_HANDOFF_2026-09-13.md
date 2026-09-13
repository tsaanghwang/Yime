# 给“计算机”AI：应用退出后重新检查，再继续固定恢复

授权到期更新：测试端 `7395165f` 已确认原授权过期；请先按[新建限时恢复授权交接](YIME_RIME_PIME_APPLICATION_RECOVERY_REAUTHORIZE_2026-09-13.md)创建新授权，并复用原事务与完整载荷。下文指定旧授权目录的参数创建步骤由新交接替代，窗口交互及完成条件仍适用。

影响产品：Rime/PIME 固定事务恢复、YimeCore 保护。开发端已实现并验证应用退出处理入口；本页取代旧 partial 交接页的执行步骤。交付的是仓库中的恢复入口和新策略，不是要求重新安装旧候选 EXE。通用安装器以及 YimeCore 自身维护入口尚未接入此界面。

## 开发端完成情况

- 新增独立的资源使用检查模块：按目标产品计划中的现存文件查询 Windows Restart Manager，并尝试不写入内容的独占打开。正常文件句柄可报告应用名称和 PID；私有字体映射可被独占检查检出，即使 Windows 只报告 System。
- `recover-defaultstring-transaction.ps1 -Interactive` 显示保存工作、正常退出应用的说明，提供“重新检查”和“取消”。每次只重新检查，清除占用后重新验证 peer、默认输入法、注册及剩余文件身份，才进入原有恢复步骤。没有强制关闭、删除权限修改、跨产品字体释放或自动重启。
- 不传 Interactive 时，遇到阻塞立即失败并保存证据，不显示等待窗口。原 Apply 一次性流程、授权有效期、SID、机器、原清单和部分缺失门槛保持不变。检查与实际删除之间若再次出现占用，仍由原精确删除器停止并保存结果，不循环 Apply。
- 提示取消或检查不通过都不进入此次恢复的修改步骤。旧事务已经发生的部分缺失不会因“取消”而自动恢复，也不报告 RECOVERED。

依据：[Microsoft Restart Manager 资源查询接口](https://learn.microsoft.com/en-us/windows/win32/api/restartmanager/nf-restartmanager-rmregisterresources)。仅使用查询和会话清理，不使用关闭或重启应用 API。

## 开发端验证

checked PS5 回归通过：普通文件持有应用 PID 识别；私有字体加载时拒绝继续；只读属性导致的错误 5 不被误判为可继续；取消保留原内容；静默失败；连续两次点击重新检查后观察到字体释放；释放后真实精确删除成功；另一份仍私有加载的字体不变；越界路径与验证异常拒绝。真实 WinForms 提示窗口的取消按钮通过自动点击验证。该自动点击只属于隔离测试，不会操作用户应用。

[开发端结果](../testing/platform/2026-09-13-application-release/result.json)、[校验索引](../testing/platform/2026-09-13-application-release/index.json)。实际字体、句柄和删除均仅在新建 `.tmp/dual-product` 目录中进行，不是生产安装测试。既有部分删除、恢复适配器回归通过；维护回归 33 项通过，并修复该测试将预期失败夹具的退出码泄漏为最终失败的问题。恢复入口通过 PS5 静态检查；固定机器限制没有绕过，未在开发端执行测试机事务。

## 测试端操作

1. 拉取包含本页的开发分支提交，等待该提交 CI 成功。保留当前产品、原始恢复目录、journal 和 original-bundle。不要重新准备、复制残余载荷、运行旧 EXE、手工删除字体或系统字体，也不要为此次恢复先注销或重启。
2. 新策略是 `test-delivery/defaultstring-recovery-applications-20260913/policy.json`，固定 95 个源码／契约文件。其原始文件 SHA-256 为：

   `c3c0dcbc08e6a5d881171c1b13cd5085b8e1cb83efae0a52bf941a6a84483802`

3. 在已有 `approval-fae6c1d4-ca01-4b6e-b3f7-7b430b20cd76` 目录中，从原 `recovery-validate-partial.json` 和 `recovery-apply-partial.json` 分别新建 `recovery-validate-applications.json` 和 `recovery-apply-applications.json`。仅把 PolicyPath 改为新策略的实际绝对路径，把 ExpectedPolicySha256 改为上述摘要，并增加 `"Interactive": true`。其他字段完整保留，包括原 Apply 值。使用 UTF-8，不覆盖旧参数；若新文件已经存在，先核实执行状态，不自动重试。
4. Golde 从 Explorer 打开同一用户的原生 PS5，在仓库目录执行验证：

   ```text
   python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-validate-applications.json"
   ```

5. 出现窗口时，由用户先保存工作并正常退出列出的普通应用，再点“重新检查”。AI 不代替用户结束应用。如果仅列出 System／服务，不能结束它们，也不能声称已识别具体应用；可以由用户正常退出正在使用该输入法的应用后检查。仍不能释放就点“取消”，回传此次证据，不尝试强杀、改权限或重启后复用旧基线。
6. 只有退出码 0 且打印 VALIDATED 后，才执行一次 Apply：

   ```text
   python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<已有恢复目录>\recovery-apply-applications.json"
   ```

   Apply 会重新检查，不把先前的 VALIDATED 当作当前已释放。授权过期、保护变化或其他错误立即停止，不改授权时间、摘要或基线。

## 回传与完成条件

回传本次提交、UTC、两个步骤退出码、控制台、用户点击取消／重新检查及应用正常退出的实际情况。将新增 `application-use-*.json` 和若产生的 `exact-removal-*.json`、peer-repair 结果提供脱敏副本和哈希索引；真实应用名称和路径先检查是否含私人信息，原件留在 Git 外档案。

只有 RECOVERED 及对应成功结果才报告固定恢复成功。取消／失败应报告未完成；不重复 Apply。物理输入与之后的重启验收仍单独记录。此交付不把两产品完整安装、升级、卸载、恢复矩阵标为通过。
