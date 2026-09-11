# 原事务短路径恢复与新候选交付

影响产品：Rime/PIME；YimeCore 继续保护。修复提交 `9aeadc74c` 的 CI [34590441170](https://github.com/tsaanghwang/Yime/actions/runs/34590441170) 已成功。此处新增恢复准备与执行保护还需本次交付提交的 CI 通过，不能把上一轮 CI 当作新增代码验证。

## 先恢复旧事务，后测试新包

旧事务仍是 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`。恢复继续使用固定 `-empty` EXE 和原收据，所有字节与摘要不变。新入口只把这两个文件复制到同用户目录下新建的 `YRP-<12位随机标识>`，命名 p.exe/r.json；产品 install/state/recovery 根、原票据和 journal 不移动、不改名、不重写。

原收据验证器以内容摘要及当前只读文件身份验证传入文件，没有要求使用旧交付文件名。开发端已实际验证两份副本通过原收据验证，错误摘要仍拒绝。原 NSIS 字符串的真实编译夹具在短路径下完整保留 929 字符及 64 位摘要；准备/执行工具用更长临时目录叶名估算为 939，并要求不超过 1000。旧包的原目标、SID、授权、收据、共存及事务检查都保留；没有加载新维护模块接管旧票据。

这只解决旧 NSIS 的长命令截断，不能保证后续恢复阶段没有另一故障。不得以短路径方案跳过恢复前的状态检查。

## 给“计算机”端 AI：准备阶段

使用资源管理器启动的同用户、未提升原生 PS5；所有 PowerShell 通过 run_checked.py。执行前保持 YimeCore 静止，不停止它。不要运行新包 Install。

1. 重新核对原固定包六项交付、原票据 SHA-256 `05352e3da345967e3e71fb5b6551f1db5739473f46a36ce3b311c46313d2b039`、原授权 SHA-256 `89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab`；在外部目录保存恢复前证据。原安装 commit/terminal 仍缺失、remove-requested 关联有效且 removal terminal 缺失、191 项已列载荷身份/大小/哈希仍匹配、原注册/Run/uninstall 仍缺失、无原候选进程、默认输入仍匹配。任何变化先交回，不执行恢复。
2. 用原票据重新准备 Mode=Resume 的新授权，不修改旧授权过期时间。沿用 `docs/testing/platform/2026-09-11-exit51-readonly/resume-preparation.json`，通过 prepare-rime-pime-coexistence-test.ps1 生成新的 execute-parameters.json。该准备过程获取当前 peer 和原生上下文；不运行安装器。
3. 在外部 UTF-8 JSON 中填 `ExecutionParametersPath` 为刚生成参数文件的绝对路径，运行：

```text
python tools/powershell/run_checked.py --script tools/dual-product/stage-original-resume-transport.ps1 --edition ps5 --params-file <外部短路径准备参数JSON>
```

输出新的 `YRP-.../execute.json`。核对与刚生成参数相比，只有 InstallerPath 和 ReceiptPath 改变；Mode、PreparedSha256、新授权路径/摘要、BoundaryPath 等均保持不变。PreparedSha256 必须取自原票据，不是 prepared.bin 整文件哈希。transport.json 记录来源参数摘要、两文件固定摘要和命令长度上界。保留新旧两份参数及摘要，不公开身份/授权内容。

## 单次执行与结果

本次交付 CI 成功、用户确认执行本方案且以上检查全部通过后，使用新的 execute.json，通过同一个 execute-rime-pime-coexistence-test.ps1 执行一次。它会再次计算原包命令长度、要求正确的短路径布局，并以 CreateNew 写 resume-started 标记；同一暂存目录不能重复执行。不要双击 p.exe，不直接运行旧目录 EXE，不自动新建暂存目录重试。

```text
python tools/powershell/run_checked.py --script tools/dual-product/execute-rime-pime-coexistence-test.ps1 --edition ps5 --params-file <新YRP目录中的execute.json>
```

原 EXE 会按既有规则请求同 SID UAC。保留 Python subprocess.returncode、完整控制台输出、执行前后证据及精确时间；任何失败立即停止。即便退出零，也必须确认：安装 commit 仍缺失且 terminal=rolled-back；removal terminal=remove-complete；191 项计划载荷均缺失；注册/Run/uninstall 缺失；无原候选进程；peer 前后比较 unchanged；默认输入匹配。未列文件、用户状态、恢复 EXE、原 journal、票据和短路径副本保留。

若出现新错误，提取本次准确时段 PowerShell 事件，不能继续重复旧十六项诊断替代新阶段异常。没有满足全部判据就不声明回滚成功。

## 新安装候选

`test-delivery/rime-pime-coexistence-20260911-request` 保存重新构建的新候选，固定摘要见该目录 PIN.json。它包含请求文件传参修复，用于旧事务闭合并复核后的新安装测试，不能用于接管旧票据。本次不改变根目录准备入口以免误触发 Install，也不把原失败状态认定为干净环境。

新交付 index SHA-256：`956aa4e145c6c63da31c4887b08622fc0043b28cc00175344280eed179062b8e`；EXE SHA-256：`4dbbb26a4e5e3bee76964c875d0ccd0b5ab4fcbf7721919a01cf0a066f73931e`。构建来源为已通过 CI 的 `9aeadc74c`，重新构建 x86/x64 原生组件、候选 Launcher 和 Go 载荷，六项交付完整性核验通过。静态检查不是实机验收。
