# 给“计算机”AI：默认值修复候选的单次安装

影响产品：Rime/PIME；保留当前 YimeCore。开发端已复现并修复 com-x64 默认值枚举误判，并保留严格类型检查，详见 [定位记录](YIME_RIME_PIME_DEFAULT_VALUE_FIX_2026-09-11.md)。此前两次失败事务均已回滚完成，不执行旧 Resume、Remove 或 finalizer，不清理旧证据。

本轮使用全新 `-defaultstring` 包。**先拉取本页与包所在提交，等该提交 CI 成功后，才进行下面的一次安装。** 不使用 `-jobexit` 或任何 `.tmp` 中间包，不修改防火墙、安全软件、默认输入或用户数据。

CI 补正：`61248d18` 的 maintenance 检查发现旧空枚举夹具同时模拟默认值读取成功、却断言默认值不存在。已拆分缺失/不支持、默认值存在但类型未明、明确枚举类型、访问拒绝和异常数据场景，PS5/PS7 均通过。本次只修测试，包及 PIN 不变；须等待包含该补正的提交 CI 成功，再执行安装。

## 取包与校验

在测试仓库根目录（通常 `C:\dev\Yime-localtest`）执行；若工作区修改或分叉阻止快进，停下回报，不 reset/clean：

```text
git fetch origin
git merge --ff-only origin/codex/yimecore-replacement-experiment
python tools/dual-product/verify_delivery.py test-delivery/rime-pime-coexistence-20260911-defaultstring --expected-index-sha256 15d4819860f462f071fbac004859eb72392229030cd42f7a93aac9f776e9af9d
```

必须通过六项完整性检查。安装器位于该交付目录的 `YIME-RimePime-1.4.0-dev.1-candidate.exe`；EXE SHA-256 为 `0602438008d5110767857ff9b5facd23a1bd54a74baff1f81fba5b1e56e2bdd3`。其他摘要见同目录 PIN.json。包在 Git 中，无需另等附件或 Actions 下载。

## 准备和执行一次

用 Golde 同一用户，从资源管理器启动非提权原生 PS5；保持 YimeCore 运行。包的正常流程处理同 SID UAC。全部 PowerShell 经 run_checked.py：

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file test-delivery/rime-pime-coexistence-20260911-defaultstring/prepare-parameters.json
```

确认新授权的 Mode=Install、PreparedSha256 为空、InstallerPath 为本页包，且 install/state/recovery 是新的 run ID 目录。已有恢复目录继续保留；若预检发现注册、进程或生产目录占用，停止回报，不手动清理来通过预检。

保留输出的外部授权目录，使用其中实际生成的 execute-parameters.json 执行一次：

```text
python tools/powershell/run_checked.py --script tools/dual-product/execute-rime-pime-coexistence-test.ps1 --edition ps5 --params-file "<本次新授权目录中的 execute-parameters.json 绝对路径>"
```

完整保存退出码、stdout/stderr、UTC 起止时间和新恢复票据。任何失败立即停止，不自动重试，不另行恢复或卸载。新的机器注册断言会提供键 ID/视图、匹配数及预期/实际值数和子键数；请保留完整错误，而非仅报告退出 51。若原生类型或系统/原生值一致性检查失败，也保留完整信息，不降低类型要求。

## 回传后暂停

无论成功或失败，都提交精简报告和带 SHA-256 的外部证据索引：新事务合法终态、载荷、x86/x64 注册/Profile、Run/uninstall、当前候选进程与 native Rime readiness（未启动则未验）、YimeCore peer 前后比较和默认输入比较。依本次新事务采集，不能复用固定旧事务 ID 的诊断脚本。

原始授权、日志、完整快照留在 Git 外档案目录，不提交用户数据。安装后取证通过不等于安装成功；若自动回滚完成，按实际终态记录并保留材料，不重复收尾。完成回传后停在报告点，宿主输入、重启登录和升级/卸载矩阵由下一轮交接安排。
