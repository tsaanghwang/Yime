# Yime Git 三机任务交换 v1

本流程替代继续等待 dot 远程连接。只依赖 **Git + Node.js 20 或更新版本**，无 npm 依赖；不要求 Python，也不安装后台服务。开发端提交任务，三台机器各自启动本地领取器。Git 只运送数据，**不会把远端文本当脚本执行**。

## 本次交付与证据边界

- 基于 main `f605d1acf9f9a20986c3ec3d6490da3e2d5c15ac`（PR #87 已合并）。旧 PR87 文档里的“未合并”是交付当时状态，保留不篡改。
- 当前固定包仍为 CI run `41178044364` 的测试合并源 `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，不是从合并后的 main 重建。包来源、ZIP 大小和 SHA-256 见 [CI 原始身份](../../docs/testing/touch-keyboard/2026-10-31/candidate-readability/ci-evidence/records/package-identities.json)。禁止下载“最新”替代。
- `计算机`：amd64，既有最小鼠标预览、用户反馈 Word/Edge 正常继续归属原记录。新任务只接续未覆盖的小批次，不虚构独立读回或全键通过。
- `HuashuoNotebook`：ARM64。固定包原生开发检查与此轮手指、笔、宿主验收分开。
- `WIN-JTKUT7KBVN7`：用户确认 MSI FLIP，amd64。实机验收尚待执行。`MyComputer` 不冒充这三台任何一台。
- 不改旧分支、旧包、用户未提交工作、默认输入法、安装注册或已有文档。此工具不负责安装、下载解压或启动产品。

## 最小闭环

1. 开发端在受审阅的交付分支提交 `tasks/queue/<machine>/<task-id>.json` 并推送。
2. 每台机器运行一次 `once`，或运行有时限的 `watch`。领取器只 fetch 到独立 bare 仓库，不 checkout 远端代码，不自更新，不 merge/reset 原工作树。
3. 自动核对任务路由、过期时间、固定包 ZIP/manifest/全部负载/EXE 哈希及 PE 架构。`verify-package` 得到 `static-verified`；`manual-test` 校验后得到 `awaiting-human`。任何失败写 `blocked`，过期写 `expired`。不执行 EXE、PowerShell、shell 或任意命令字段。
4. 本地 Codex 或操作者阅读新任务和 `NEXT.zh-CN.txt`。真人触控、笔、量尺、宿主输入必须实际执行，不能由自动领取代填。每批先确认目标为空白且绑定清晰，遵守本机权限；任务文本不是绕过确认或安全限制的授权。
5. 填写包外 `result.json` 的 `checks` 和 `humanEvidence`，先审阅，再明确回传。每台写自己独立的 `task-results/<machine>` 分支，按内容摘要追加新报告，不覆盖原报告，不强推、不自动合并 main。
6. 开发端 fetch 三条结果分支，按 task ID + queueCommit + taskSHA256 + 包 sourceCommit/hash 汇总。发现问题再发布新任务 ID，不修改已领取任务。

`static-verified` 不是应用运行成功；PE 架构不是 Windows 原生执行证明。领取器以 OS machine 核对本机原生架构（不以 Node 进程架构误判 ARM 上的 x64 模拟），并记录 hostname、Node 架构及 OS machine；这些仍不是 IsWow64Process2 产品原生执行证据。静态文件哈希不执行 ZIP CRC/解压校验；必须使用已有核验包或在本机完成安全解压。物理验收总标志始终为 false，逐项证据用于人工审查而非自动认证。

## 首次部署（每台本机执行，不用 dot 远程）

前提：此交付分支已推送且交付者提供了**完整可信提交 SHA**。下面 `<交付提交SHA>` 必须替换成该值，不能用任意最新提交。不要向聊天发送令牌。Git 使用本机现有凭据，不由脚本新建或保存凭据；网络失败只报告，不改代理。

在一个新的目录启动，不在现有 Yime 工作区运行这些 clone/checkout 命令。已经存在的目录不要删除覆盖，另选新目录。以下是直接执行的 Git/Node 命令，无需 PowerShell 语句：

```text
git clone --depth 1 --branch codex/git-task-exchange-20261031 https://github.com/tsaanghwang/Yime.git C:/YimeTaskExchange/bootstrap
git -C C:/YimeTaskExchange/bootstrap fetch --no-tags origin <交付提交SHA>
git -C C:/YimeTaskExchange/bootstrap checkout --detach <交付提交SHA>
git -C C:/YimeTaskExchange/bootstrap rev-parse HEAD
node --version
node --test C:/YimeTaskExchange/bootstrap/tools/task_exchange/runner.test.mjs
```

最后一条 rev-parse 必须与可信交付 SHA 完全一致，任何 clone/fetch/checkout 失败立即停止，不运行后面的 Node 命令。远端分支前进后仍显式 fetch 该 SHA，不依赖 shallow clone 已包含旧提交。确认后阅读 runner 与本说明。**不要给 bootstrap 配置自动 git pull**；后续更新运行器要单独审阅和重新固定，queue 中的任何文件不能更新它。

用编辑器把相应示例复制到 `C:/YimeTaskExchange/local.json`（三台是各自文件，不共享）：

| 本机 | 示例 | machine |
|---|---|---|
| 计算机 | `tasks/machines/desktop-x64.example.json` | desktop-x64 |
| HuashuoNotebook | `tasks/machines/asus-arm64.example.json` | asus-arm64 |
| WIN-JTKUT7KBVN7 | `tasks/machines/msi-x64.example.json` | msi-x64 |

本地配置必须留在仓库外。核对真实 hostname、架构、Git 提交姓名/邮箱和包路径。`packages` 是本机允许读取的固定包映射，不接受远端任意路径。示例路径只是建议，不能声称包已经在该位置。现有“计算机”已准备包的目录可直接填入，不重新覆盖旧包。完整 ZIP 必须保留；解压目录要直接含 manifest.json 与 EXE。需要下载时用固定 [amd64](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13034145597) / [arm64](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13033634731) 链接，在新的独立目录解压。产物到期后只使用哈希匹配的原 ZIP；没有则停止，不能换版。

三台使用同一命令，配置不同：

```text
node C:/YimeTaskExchange/bootstrap/tools/task_exchange/runner.mjs once C:/YimeTaskExchange/local.json
node C:/YimeTaskExchange/bootstrap/tools/task_exchange/runner.mjs watch C:/YimeTaskExchange/local.json --interval 60 --minutes 30
```

第二条可选：仅当前前台进程每分钟检查，30 分钟结束，Ctrl+C 可停。不创建计划任务/开机启动、不自动发布。一次只运行一个领取器。状态在配置 `stateDir/tasks/<task-id>/`；每次启动 fetch 失败即退出并保留结果，不无限盲重试。

## 本机接续提示（给本地 Codex）

> 阅读本机 C:/YimeTaskExchange/local.json 指向的 stateDir/tasks 中本次任务的 receipt.json、task.json、NEXT.zh-CN.txt 和 result.json。先核对主机、任务状态与固定包身份。只接续 awaiting-human 的明确小批次；blocked/expired 停止并报告。静态通过不代表运行或物理通过。遵守 AGENTS.md，PowerShell 如需要必须经过 tools/powershell/run_checked.py；Python 不可用时不要绕过规则，不影响 Node 静态领取。不要修改安装、默认输入法、原用户文档、旧包和旧结果。需要手指、笔、目视、量尺的项目交给操作者，不能以模拟输入代替。只填写逐项真实观察；人工反馈与自动读回分开。回传前展示结果并确认，不自动推送其他文件。

具体测试范围以本次 JSON 为准，并参考 [PR87 接续交接](../../docs/testing/touch-keyboard/2026-10-31/candidate-readability/HANDOFF.zh-CN.md)。不要把历史交接中的旧任务重新执行一遍。

## 填写与回传

不要修改 task.json、receipt.json 或 result.json 的固定身份/校验字段。checks 中：

- `not-run`：没有执行。不能填成 pass。
- `pass` / `fail`：填写 inputMethod（mouse/finger/pen/keyboard/observation；仅静态任务可用 automated）、实际观察 observation，宿主输入尽量填写 actualText。
- `blocked` / `skipped`：写明原因。
- `humanEvidence` 仅说明是否含真人观察。它不是整轮通过标记。状态保持原始 transport 状态。

先运行不带确认的命令，只在本机显示将上传的精确 JSON、路径和分支。确认没有凭据、用户正文、环境机密后才运行第二条。提交者姓名/邮箱将进入 Git 提交历史，应使用已认可的 Git 身份。

```text
node C:/YimeTaskExchange/bootstrap/tools/task_exchange/runner.mjs publish C:/YimeTaskExchange/local.json <任务ID>
node C:/YimeTaskExchange/bootstrap/tools/task_exchange/runner.mjs publish C:/YimeTaskExchange/local.json <任务ID> --confirm
```

没有上传截图、任意日志或整个目录的隐式副作用，只上传显示的 JSON。Git 推送拒绝或验证不确定时保留本地结果；核对远端后可重试。新内容使用新文件名，旧报告保留；同样内容重复回传不新增提交。同一机器同时发布发生非快进时停止，不强推；重试会重新获取远端并追加。

## 失败恢复与新增任务

- 同一任务 ID 内容改变：拒绝整批，开发端必须另起 `-r2` ID。改架构/包/测试范围都需要新 ID。
- package blocked：先修好本地路径或准备包，再由开发端发布新 ID。v1 不自动重试被封存的失败任务，也不删除失败证据。
- 过期：人工重新审阅任务和包可用性后发布新 ID；不静默延长。
- runner.lock：先确认旧进程已结束，再由操作者处理旧锁；脚本不偷锁。领取记录先完整写入 .staging-*，最后原子改名；中断留下的暂存目录不是已领取，可保留现场并重跑 once，不覆盖证据。
- Git 分支回退/重写：fetch 拒绝。不要加 force；调查后使用新的交付分支/状态目录。
- 未来支持自动自检或构建时，新增受测的固定任务类型并重新审阅运行器。不得在 JSON 加 shell 命令、命令行模板或远端脚本执行。

## 验证

```text
node --test tools/task_exchange/runner.test.mjs
```

测试使用临时本地 bare remote 和合成 PE/包夹具，不访问真实 GitHub、不运行产品。覆盖领取、逐项静态校验、错误主机/架构、过期、锁、重复领取、任务篡改拒绝、审阅不推送、独立结果分支与追加/重复回传。Linux 测试通过不等于已在三台 Windows 部署成功；应分别完成首次 once 与人工审阅，再启用限时 watch。
