# 给“计算机”AI：取包并执行一次新候选安装测试

> **本轮已执行且安装失败，自动回滚完成；停止重复执行本页安装步骤。** 见 [测试报告及开发端审阅](YIME_RIME_PIME_JOBEXIT_INSTALL_FAILURE_2026-09-11.md)。保留新旧恢复材料，不运行 Resume、Remove 或旧 finalizer。

后续改用 [默认值修复候选交接](YIME_RIME_PIME_DEFAULTSTRING_INSTALL_HANDOFF_2026-09-11.md)，须遵守新交付提交的 CI 门槛。

影响产品：Rime/PIME；当前 YimeCore 是共存保护对象。本页是原事务收尾审阅通过后的新安装交接。原事务 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0` 已回滚完成，不再运行其 Resume、preview 或 Apply，继续保留全部恢复材料。

## 包已在仓库，无需等待另发

候选包自 `e08b5487e` 起已提交到 `codex/yimecore-replacement-experiment`。在测试端当前仓库根目录取更新，保留测试分支和已有工作；若合并冲突或本地修改阻止合并，停止并回报，不 reset/clean：

```text
git fetch origin
git merge --ff-only origin/codex/yimecore-replacement-experiment
```

在 `C:\dev\Yime-localtest` 为仓库根的情况下，安装器完整路径为：

```text
C:\dev\Yime-localtest\test-delivery\rime-pime-coexistence-20260911-jobexit\YIME-RimePime-1.4.0-dev.1-candidate.exe
```

如果实际仓库路径不同，使用其根目录下相同相对路径。文件长度应为 **41,209,079 字节**，它不是 LFS 指针，也不需要去 Actions 下载。交付目录同时包含 receipt、manifest、inventory、基线、PIN 和准备参数。不要只复制 EXE 或双击安装。

从仓库根运行完整交付校验：

```text
python tools/dual-product/verify_delivery.py test-delivery/rime-pime-coexistence-20260911-jobexit --expected-index-sha256 7ccf8c4c7116b20eee41aabd0775697192b8929f1d9a434a5e441e3ae097f7f3
```

必须得到 `integrity_passed=true, artifact_count=6`。EXE SHA-256 为 `ffdd6f380a9fe7518f9c6db6d54c100f526201989d268a8638c6c6a603d3eacd`。找不到文件或校验失败时，回传当前提交、仓库根、上述命令完整输出，不执行安装。

## 本轮执行范围

仅在“计算机”上，以 Golde 同一用户，从资源管理器启动的非提权原生 PS5 执行；保持 YimeCore 运行、默认输入不变。安装器需要的同 SID UAC 由其正常流程处理。本轮进行一次新的 Rime/PIME 候选 Install 及安装后观察，不执行升级、卸载、旧事务恢复或自动重试。

相关代码 CI 已通过：候选交付 `e08b5487e` 的 [34602235883](https://github.com/tsaanghwang/Yime/actions/runs/34602235883)，恢复工具修复 `40e45635f` 的 [34606641192](https://github.com/tsaanghwang/Yime/actions/runs/34606641192)。本交接只增加文档，没有更换已校验的包或工具，无需等待另一份包。CI 成功不代表本机安装验收已通过。

1. 核对原事务收尾报告及当前候选注册/Run/uninstall 仍缺失，无旧候选进程。旧 install/state/recovery 目录允许保留；不清理它们。准备工具将生成新的 run ID 和三个全新目录。若出现新的占用或产品变化，停止回报。
2. 全部 PowerShell 经 run_checked.py。在仓库根执行新包准备，下面的参数默认 Mode=Install：

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file test-delivery/rime-pime-coexistence-20260911-jobexit/prepare-parameters.json
```

3. 保留输出的外部 `approval-<新ID>` 目录。核对其 execute-parameters.json：Mode=Install，InstallerPath 指向本页 jobexit 包，ExpectedInstallerSha256 匹配上述摘要，PreparedSha256 为空；install/state/recovery 为新路径。不要填写旧票据、旧 PreparedSha256 或将 Mode 改成 Resume。授权有效期为 24 小时，不改写授权内容。
4. 准备成功后，通过实际生成的参数文件执行一次。记录 Python 进程退出码、完整 stdout/stderr、起止 UTC 时间。此路径是上一步实际输出，不是仓库中的 prepare-parameters.json：

```text
python tools/powershell/run_checked.py --script tools/dual-product/execute-rime-pime-coexistence-test.ps1 --edition ps5 --params-file "<本次新授权目录中的 execute-parameters.json 绝对路径>"
```

5. 无论成功或失败，独立保留新生成的 candidate-recovery 票据、授权、日志与 peer 比较。失败立即停下，回传错误和 failure JSON 索引，不调用 Remove/Resume、不重新准备授权重试、不删除失败目录。成功也先完成下列观察并回传，不直接开始后续维护矩阵。

## 回传内容

- 实际 Git 提交、候选包 SHA、交付完整性结果、新事务 ID、执行退出码与时间。
- 新事务安装 commit/terminal 的合法关联及状态；注册 x86/x64、Profile、Run、uninstall 指向本次新根的观察。按新事务采集，不套用固定旧事务 ID 的诊断脚本。
- 候选 Launcher/server 当前 PID、映像路径和实际 native Rime readiness；不能以旧日志或持久化 running 状态替代当前进程证据。
- 安装前后 YimeCore peer 比较和默认输入比较。保留两产品数据边界，用户数据原文及授权原文不提交 Git。
- 完整控制台和原始 JSON 留在 Git 外档案目录，仓库提交精简报告、必要的非敏感结果副本和带 SHA-256 的外部证据索引，然后推送测试分支。

本轮只判定新的候选安装及共存保护是否通过。真实宿主输入、重启登录、自启以及升级/卸载矩阵仍单列待验；没有实际执行就保持未验。先回传本轮结果，由开发端审阅下一阶段。
