# 十一项通过后的事务与环境补证

> 联合补证已收到并复核，不再重复本页任务。开发端已复现长命令截断缺陷，见[定位与源码修复说明](YIME_RIME_PIME_EXIT51_ARGUMENT_TRUNCATION_2026-09-11.md)。旧事务继续暂停。

影响产品：Rime/PIME 失败事务；YimeCore 继续保持。已接收 `5e62c459a`，逐字节核对 output.json、execution-result.json 的长度和 SHA-256，与索引一致。十一项全通过，returncode=0、attempts=1。它们证明归档计划结构及当前身份绑定检查通过，不代表旧 Resume 执行成功。

## 下一次只读采集：一次交回两组证据

不要再执行旧 Resume，也不要关闭防火墙、Defender 或其它保护。当前没有系统拦截证据，不能把环境差异认定为原因。以下只读工作无需等待 CI，不改变安装、注册、权限或服务状态。

### 1. 事务目录与锁文件

拉取本次更新，在原生同用户 PS5 下复制此前四参数 JSON 到新的外部证据目录，新增 `IncludeJournalReadChecks: true`。此前固定输入摘要仍须匹配，原参数、旧结果不要覆盖。

```text
python tools/powershell/run_checked.py --script tools/dual-product/inspect-resume-bindings.ps1 --edition ps5 --params-file <新增开关后的外部JSON绝对路径>
```

新增五项：唯一 install journal 路径、install/remove 两个 journal 的成员合法性，以及两个 transaction.lock 的独占只读打开、零长度、直接文件身份与命名流检查。共十六项。保留原始 JSON、stderr、Python subprocess.returncode 和脚本哈希。

锁文件只以 Open/Read/FileShare.None 打开后关闭，不调用 TransactionStore、Write、Flush、发布决策或修改 ACL。短暂持有只读共享约束；不要与其它维护并行。此检查并不测试原控制器所需的 ReadWrite 权限，不证明历史失败时没有占用，也不等于完整事务验证。失败结果包含检查名、异常类型及 HRESULT，不要把所有异常都解释为权限不足。

PS5 隔离回归覆盖十六项正常观察、被占用的锁、未知 journal 成员、锁字节及修改时间不变，另保留计划和绑定负例。

### 2. 原失败时段日志与权限元数据

在同一批交回中，由测试端 AI 只读提取已有证据，PowerShell 仍经 run_checked.py。不要重演故障来产生新日志。

- 用原 `resume-attempt-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-preflight2/console.txt` 的 transcript 时间界定失败时段；若只能取得文件时间，明确其局限，并使用前后各十分钟的有限窗口。保留本地时区和 UTC 时间，不用本次诊断时间替代旧失败时间。
- 查询该窗口 Application、CodeIntegrity/Operational、Windows Defender/Operational、AppLocker 的 EXE and DLL、PowerShell/Operational 日志。渠道缺失、禁用、无权限或窗口已无记录分别报告，不启用日志、不提权改策略。不发布无关应用或其它用户内容；原始相关事件留在外部目录。
- 对照原候选安装根、恢复根和临时解包路径筛选事件；记录时间、provider、ID、相关映像路径及消息。需要明确区分审计记录、实际阻止和无关事件；没有记录不等于排除安全软件。
- 只读获取两个 journal 目录及其 transaction.lock 的属性、所有者与 ACL。原始 ACL/身份留在外部，只提交采集是否成功、摘要和分析结论。不得更改所有权/继承/权限，也不测试创建或写入文件。静态 ACL 分析不能替代实际有效写权限证据。

提交本批十六项结果、系统事件/ACL 摘要及外部证据索引到测试分支。如果没有关联事件也提交明确的查询范围与空结果；不再重复原十一项单独报告。开发端据此缩小事务访问或后续进程执行的问题，下一次维护仍需另行制定具体方案。
