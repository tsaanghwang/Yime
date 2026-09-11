# Resume 补证复核与只读绑定诊断

> **十一项已通过并复核。** 本页两轮任务均已完成，下一步见[事务目录与系统环境联合补证](YIME_RIME_PIME_EXIT51_JOURNAL_ENVIRONMENT_2026-09-11.md)。不要单独重复本页历史步骤。

> 已收到 `6769f5c4d`：原始 JSON 的十项检查全部通过，字节哈希与索引一致。历史十项结果保留，不需要为缺少退出码重跑。下一步使用更新后的同一入口补查 `complete-plan-schema`；它会同时复测十项绑定，总计十一项。

## 本次追加：完整计划结构

新的 `resume-plan-diagnostic.psm1` 逐字复制原编译提交 `6321067de` 中 Read-MaintenancePreparedPlan 的纯结构校验块，检查全部文件记录的类型/路径/唯一性、默认输入类型、版本、目录身份格式、恢复 EXE 绑定和两项生成文件关联；没有导入维护控制器，也没有打开原 journal。代码块与原版本逐字比对通过，PS5 隔离回归另外验证了末项文件 bytes 被改为字符串时会拒绝。

测试端拉取本次更新，复用此前四个参数及固定输入摘要，执行下方同一只读命令一次，将输出保存到新的外部目录。原输出 JSON 保留，提交新增输出及 SHA-256。新检查失败时会返回检查名称、异常类型和固定格式校验消息；不要修改计划来消除错误。全部十一项通过仍不是恢复完成，还需排查事务锁和后续运行阶段。

本次可直接执行只读诊断，无需等待 CI；不得运行 Resume。进程退出码请使用 Python subprocess.returncode 等结构化方式记录，或正确分隔 CMD echo 与重定向符；旧空 exit-code.txt 不补写。缺少旧退出码不影响已经核对的十项 JSON 结论。

影响产品：Rime/PIME；YimeCore 为保护对象。已接收 `5ef571a61`。

现存控制台仍只有外层 51，辅助入口没有补出旧包异常。PS5 元数据中的数组、计数、默认输入字段类型符合此前检查预期，但未覆盖全部计划不变量，不能认定为原控制器验证通过。接下来只补查此前遗漏的新授权七项绑定、install/state 目录身份和 recovery EXE 身份。

## 索引复核

八份文本副本的实际 SHA-256 与索引一致。plan-types.json 的 Git 文件为 LF，SHA-256 为 `3f37d475e27f4f5c41718b80dcec0af5d7cd6d47979aa8e2b8f5e4ced0dded79`；仅恢复 CRLF 后为索引所列 `3a1e99b4f5748aa25bf7abd9827217afbb8565d6a222c132bb3a0c743eeb2545`。这是可复现的换行差异，原索引与文件保留；不宣称访问或重验了测试机原始文件。

## 给测试端 AI 的操作

拉取包含本页的开发分支，从资源管理器启动同用户原生 PS5。这里只执行 `tools/dual-product/inspect-resume-bindings.ps1`，不运行 Install/Remove/Resume、不生成新授权、不替换固定包文件。入口只读取归档 prepared、新授权、两个目录及恢复 EXE；不打开 transaction store，不启动或停止产品。源码模块的解析器及原生身份助手与原编译版本一致（模块仅换行不同），没有导入维护控制器。

先核对以下原件摘要，然后在 Git 外创建 UTF-8 参数 JSON，四个字段为：

- ArchivedPreparedPath：已有执行后归档 `readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-8848c54e5746489390c27a2876951f74/install-journal-copy/prepared.bin` 的绝对路径。该完整文件 SHA-256 应为 `9f14badfc704b77fc1ac1cae458f1a004b1df0710516ffe46e6a7fec3557f908`。
- ExpectedPreparedSha256：从原恢复票据读取 prepared_sha256。票据文件先核对 SHA-256 `05352e3da345967e3e71fb5b6551f1db5739473f46a36ce3b311c46313d2b039`；不能填写 prepared.bin 整文件哈希。
- AuthorizationPath：失败 Resume 的 `approval-fa4e23d2-e352-4e44-ad7c-b96162f91e67/authorization.json` 绝对路径。
- ExpectedAuthorizationSha256：`1500f6abd862e5ddd39f162a9c4bcead1609a172da9df33e1e30363c253765bd`。

```text
python tools/powershell/run_checked.py --script tools/dual-product/inspect-resume-bindings.ps1 --edition ps5 --params-file <外部参数JSON绝对路径>
```

把输出与错误原文保留在新建的外部证据目录，提交输出 JSON、诊断脚本版本及外部文件哈希。正常结果只含十项检查名称、布尔值和异常类型，不含路径或身份值；输入校验提前失败时，脱敏错误后交回。任意失败都停止，不自行修复或重试维护。全部通过也只关闭这十项证据缺口，不能证明原控制器、锁权限、提升 worker 或完整计划验证通过。

目录观察使用短暂只读句柄，拒绝间接路径/命名流；共享模式比原事务 PinDirectory 更严格，故句柄打开失败只说明本次观察受阻，不直接等同旧包失败原因。身份按观察时点判断，不作为之后维护的授权或免检凭据。

本工具未制入候选包，固定旧包和票据继续保留。PS5 隔离回归覆盖十项正常检查、目录/授权/恢复文件不匹配、原归档不变和错误票据摘要拒绝。这里只读诊断可以执行；安装和恢复继续暂停，不以 CI 成功解除。
