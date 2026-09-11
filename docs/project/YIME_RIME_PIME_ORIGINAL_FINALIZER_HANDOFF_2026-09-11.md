# 原事务专用收尾与 Job 修复候选包交接

> **执行前更新：须拉取本页所述摘要域修复，并等待修复提交 CI 成功。** `e08b5487e` 的 CI 成功不足以执行旧入口。测试端在运行前发现授权摘要域混用，尚未生成新授权或运行 preview/Apply，现场未被本轮工具修改。报告见 [执行前问题报告](YIME_RIME_PIME_FINALIZER_APPROVAL_PIN_REVIEW_2026-09-11.md)。修复通过后，继续下列步骤，无需重制候选包或更改现场文件。

影响产品：Rime/PIME；保留当前 YimeCore。源修复 `6457bb7fedcc733f595ef2dd5b518cc3c3f60ae6` 的 CI [34597860336](https://github.com/tsaanghwang/Yime/actions/runs/34597860336) 成功。**本页新增恢复工具及交付物须等包含本页的提交 CI 成功后才执行。** 当前未取得真实恢复成功证据。

本页替代短路径恢复方案的执行步骤。旧 `-empty` 和 `-request` 安装器都含旧 Job 判断；停止重复 Resume，不替换旧包内的脚本。本次先完成原事务收尾并回传报告，开发端审阅后另行启动 `-jobexit` 新包安装。

## 专用收尾的边界

这是独立、限于本次故障的恢复策略：固定原事务 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`、原票据、原包、原收据和原计划；使用当前源码中修复后的只读注册观察器，确认注册、Run、uninstall 均缺失且无原候选运行时。它不会调用旧注册 worker、启动或停止运行时，也不是新候选包接管旧票据。

授权摘要分开核验：原票据先通过固定文件哈希认证，再用其中 `approval_sha256` 校验计划的 `original_approval_sha256`，两者均为规范化对象摘要（测试端核对值 `1a27c02e0f8af39fd845c2dbb776ea3776ea2c6a504aa6d59fc5816c744e03a6`）。原票据同目录的 `authorization.json` 另以原始文件 SHA-256 `89359001856f4d875dcb109c1b148b655be56fb8e1d4fa5728705fd4c117cfab` 校验。不要将文件摘要填入对象摘要字段，也不要改原件迎合检查。

只有原安装无 commit/terminal、原 removal 已有 remove-requested 且无 terminal、原计划全部 191 个文件的身份/大小/摘要仍匹配、peer 和默认输入未变时才继续。Apply 按原计划精确删除载荷，成功后通过原日志协议发布 removal=remove-complete、install=rolled-back。它不删除未列文件、用户状态、恢复 EXE、原票据、日志或历史证据。任何检查或删除失败立即停止，禁止自动生成新授权重试或手写终态。

预检不删除载荷或发布终态，但会取得事务独占锁、打开并刷新日志、写外部 peer/结果证据，因此不要称为完全只读。实际删除需要用户目录正常权限；遇到权限错误应回传，不改 ACL 或改用管理员身份强行运行。

## 交给“计算机”的 AI

1. 拉取包含本页的当前开发分支提交，确认对应 CI 成功。保留 YimeCore 正常运行，关闭其他候选维护任务。以 Golde 同一用户、从资源管理器打开的**非提权、非打包原生 PS5**执行；所有 PowerShell 经过 run_checked.py。不得在 MYCOMPUTER 执行。
2. 保存当前恢复前证据到 Git 外的 `C:\Users\Golde\Yime Rime-PIME Test Archives`：191 个原载荷、原日志、注册/Run/uninstall 缺失、无候选进程、默认输入及 peer。与上次短路径失败报告不符就停止。
3. 校验 `test-delivery/original-rollback-finalizer-20260911/PIN.json` 中的 ZIP SHA。将原包数据解压到该外部档案目录下一个**不存在的新目录**，例如 `original-bundle-finalizer-20260911`。解压工具先验证固定原 manifest 和全部成员，且不执行内容：

```text
python tools/dual-product/extract-original-recovery-bundle.py test-delivery/original-rollback-finalizer-20260911/original-bundle.zip "C:\Users\Golde\Yime Rime-PIME Test Archives\original-bundle-finalizer-20260911"
```

4. 用原票据生成一次新的、未过期授权。下面仅准备，**不要将生成的 execute-parameters.json 传给旧 execute-rime-pime-coexistence-test.ps1**：

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file docs/testing/platform/2026-09-11-exit51-readonly/resume-preparation.json
```

5. 在外部档案目录新建 UTF-8 `finalizer-preview.json`，仅含以下三个参数。ExecutionParametersPath 使用第 4 步实际输出的绝对路径；其余路径如下（若第 3 步选择了不同新目录，填实际目录）：

```json
{
  "ExecutionParametersPath": "<本次新授权的 execute-parameters.json 绝对路径>",
  "RecoveryTicketPath": "C:\\Users\\Golde\\Yime Rime-PIME Test Archives\\approval-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0\\candidate-recovery-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0.json",
  "OriginalBundleRoot": "C:\\Users\\Golde\\Yime Rime-PIME Test Archives\\original-bundle-finalizer-20260911"
}
```

```text
python tools/powershell/run_checked.py --script tools/dual-product/finalize-original-rollback.ps1 --edition ps5 --params-file "<外部 finalizer-preview.json 绝对路径>"
```

6. 仅当进程退出码为 0，结果 `eligible=true, applied=false, payload_count=191`，且 peer 比较通过时，复制这份参数为外部 `finalizer-apply.json`，添加唯一字段 `"Apply": true`，执行**一次**同一入口。入口重新验证全部条件并创建一次性标记。不要调用安装器，也不要创建短路径 Resume 目录。

```text
python tools/powershell/run_checked.py --script tools/dual-product/finalize-original-rollback.ps1 --edition ps5 --params-file "<外部 finalizer-apply.json 绝对路径>"
```

7. 保存两次完整控制台输出、Python 进程退出码、起止时间、输出的 finalizer JSON 和 peer before/after/comparison；不能仅看 JSON 宣称成功，finally 中的 peer 比较失败也算失败。无论成功或失败都停在这里，提交精简报告和外部证据摘要/索引到测试分支。不得将授权原文或完整用户数据提交 Git。

成功后还需独立核验：原安装 commit 仍缺失，install terminal=rolled-back，removal terminal=remove-complete，191 个计划文件全部缺失，注册/Run/uninstall 仍缺失，无候选进程，peer unchanged、默认输入三字段匹配。保留用户状态、恢复 EXE 和历史材料。任意失败保留原状，回传 failure JSON 和精确错误；不要重复 Apply。

## 后续安装候选

`test-delivery/rime-pime-coexistence-20260911-jobexit` 为从已通过 CI 的 `6457bb7fe` 重新编译 x86/x64 原生组件、Launcher、Go 载荷并封装的候选。包含请求文件传参修复和 Job 退出有界观察修复。六项交付物校验通过，静态源基线 77 项通过；这些不代表已安装或共存验收通过。

- index SHA-256：`7ccf8c4c7116b20eee41aabd0775697192b8929f1d9a434a5e441e3ae097f7f3`
- EXE SHA-256：`ffdd6f380a9fe7518f9c6db6d54c100f526201989d268a8638c6c6a603d3eacd`
- 其他摘要见该目录 `PIN.json`。

新包只用于恢复审阅通过后的新安装事务。本轮不运行其 prepare/Install。专用恢复入口本地已通过 PS5/PS7 各 25 项维护夹具检查、解压认证正反例和入口语法检查。新增回归执行实际入口中的计划校验调用，覆盖正确对象摘要通过、误用文件摘要拒绝、票据不匹配、manifest 变化和文件计数变化；此前 24 项夹具漏测了这个入口校验。真实 SID、注册观察、权限及收尾结果仍需测试机证据。
