# 固定 test.6 三机人工派发候选

本文件须经审阅并发布后，记录其完整提交 SHA 作为 dispatchCommit，再人工转贴给各机现有本地 Codex。Git 获取说明不等于自动执行。本文不创建 machine profile、不修改任务队列或产品代码；不要使用旧 c27 runner 的 once/watch/publish，它只接受旧预览包合同，不能为此安装包生成合法收据。

## 任务与范围

- MSI：installed18u-test6-msi-x64-r1；目标主机 WIN-JTKUT7KBVN7，必须现场确认原生 AMD64。本批仅安装、重启、自有宿主一次输入，不重复触摸/笔/翻转验收。
- 计算机：installed18u-test6-desktop-x64-r1；目标为既有 i7-7820X 普通屏机器，现场记录实际 hostname，不能把“计算机”昵称当已验证 Windows hostname。必须原生 AMD64。本批非性能测试，不新增手指/笔项目。
- ASUS：installed18u-arm64-readiness-r1；HuashuoNotebook，实际 hostname/原生架构仍须本轮只读记录。缺原生 ARM64 安装包，安装及宿主测试 blocked，不用 x64 仿真或 PR87 包代替。
- MyComputer 已完成固定 test.6 限定闭环，本批待命不重测。各机证据独立，不能继承 MyComputer 的安装前基线、重启时间或通过结果。

当前两个 x64 任务的四组步骤可以分开完成。每组结束保存原始证据；任何失败、未知身份、权限拒绝、UAC 取消或已存在证据目录均停，不能自动重试。不要为凑齐字段重复运行。

## 固定依据与包

[MyComputer 固定完成报告](https://github.com/tsaanghwang/Yime/blob/cf4f371984acc4265305f70c751c11457109eae9/docs/testing/18u/2026-11-03/upgrade/TEST6.zh-CN.md) 及其 raw 原件只证明该机通过。报告中“暂不分发”是当时状态；本次新派发依据后续用户协调授权，不修改历史报告。

- 产品源码：5367accdb6f18bb298f2282df67d4cc6d342aa5e
- 版本：0.1.0-18u-test.6；仅 native Windows AMD64、CN/variable，自有宿主。无 hostname 锁不等于允许选错机器。
- [构建 41563052934 / artifact 13198347201](https://github.com/tsaanghwang/Yime/actions/runs/41563052934/artifacts/13198347201)
- artifact 名称：installed-18u-x64-test-package-5367accdb6f18bb298f2282df67d4cc6d342aa5e
- 外层 artifact：92412989 bytes；SHA256 5834bf583b12048c3c436a4dd36b03b3770b509f52b93a71d6acc5e08aaab002
- 内层 ZIP：YimeCore-18u-0.1.0-18u-test.6-windows-amd64.zip
- 内层大小：92394419 bytes；SHA256 df03629e0bc1512e265beb43b80c58c7d53ada21b1ee3776b6b73bdbfeaa7282
- package-evidence.json SHA256：64c5996cfc3ab71ff0ffe7df54bd8ee0786d0ed0226816329cfbf37bde8c31a6
- payload/installed-18u-product.json SHA256：096920dfaf62178fbbf3bd049a0057237dbe360ad04bed9364f947d315392880

未核实此版本 Release 下载地址。只使用官方 artifact，或复制上述同字节内层 ZIP 并核哈希；不要下载最新分支源码当安装包。artifact 可能过期或被清理，不可用即报缺包，不换版本。EXE/DLL 未签名，哈希不是发布者认证；安全保护阻止时停，不绕过。

## x64 第 1 组：核包、现场前提与保护基线

预先展示完整步骤，人工确认目标机器后开始。只在新的绝对目录中准备，不覆盖已有文件。记录本机实际 hostname、原生及当前进程架构、用户/提升状态、实际中文 HKL 与 TSF 语言；无法安全查询记 unknown 并停，不下载探针、改语言或强行切换 TIP。

若实际取得官方 artifact 外层 ZIP，核外层大小与哈希；若复制固定内层 ZIP 或 gh run download 已展开外层，外层记 not-collected，不因此阻塞。所有路径均须核内层 ZIP 大小与固定哈希；展开内层至新 package 目录后，核 package-evidence 全部文件集合/长度/哈希、安装清单的 16 载荷和 descriptor 15 成员、源码/version/product/资源身份、5 个 PE 的 AMD64 架构及签名状态。不得混入校准、旧日志、其它包文件。

记录这台机器自己的受保护基线：标准 YimeCore/Rime 的既有安装身份及文件/相关注册摘要、独立 18u 是否存在及版本/marker/维护清单/COM 绑定、相关用户数据存在性与哈希摘要、默认输入法覆盖和语言设置。只记录相关产品，原始含用户名路径的数据留本地。不要复制或预设 MyComputer 的微软拼音默认项、部分卸载状态或旧 test.2 安装状态。

预期：包完全匹配，目标机器原生 AMD64；独立 18u 若不存在就是新安装，若存在须证明同产品、完整合法状态。未知/外来/损坏/部分安装状态停止交开发侧，不照抄 MyComputer 卸载续行脚本。

## x64 第 2 组：同一用户提权，正常安装一次

使用固定源码 tools/powershell/run_checked.py 与其 preflight.ps1；本地 checkout 若非该提交，先只读核这两个文件与固定源码一致，不能默用别的修改版。Python/PowerShell 使用已有正常安装，缺少则报告，不自动下载安装。

在本机把下列占位路径替换为已验证的绝对路径；执行前应显示最终命令供本机用户确认。不要直接双击 Setup.cmd，因为默认即 Install。

```powershell
& '<本机已存在的 Python.exe 绝对路径>' -B -X utf8 '<固定源码 tools\powershell\run_checked.py 绝对路径>' --script '<新 package\Setup.ps1 绝对路径>' --edition ps7 --params-file '<新证据目录内 install-params.json 绝对路径>'
```

参数文件采用 UTF-8，内容固定为 `{"Action":"Install","Silent":true}`，保留该文件作为本轮输入证据。同一登录用户确认 UAC，不换账户；必要管理员动作仅此产品正常 Setup 链。预期 Setup exit 0 和安装成功输出，独立目录为 %ProgramFiles%\YimeCore 18u Touch，用户数据为 %LOCALAPPDATA%\YimeCore 18u Touch。本产品 CLSID 为 {6DFACE1F-562E-4773-A9D6-D5753A314711}，profile 为 {1BD904AC-3194-4419-B70A-5574100F18B3}，语言 0804；允许正常写本产品 COM/TIP/类别、当前用户启用记录和卸载项，不主动改默认选择、其它产品或语言设置。

保留 Setup 日志、退出码和逐阶段结果。安装后只读核 16 载荷及版本、COM 路径、profile/category 身份与标准/Rime/用户数据/默认设置基线。需要状态查询时仅使用固定工具 status，不调用注册或清理入口。不能仅凭 count 宣称身份匹配。

DLL 被占用、未知残留、Setup 非 0 或仅部分完成都停，不手删注册表/文件、不 ResetData、不重试或自动卸装。正常安装成功不等于输入通过。

## x64 第 3 组：用户保存工作并正常重启

只有第 2 组确认成功后，提示用户保存所有工作，由用户确认并进行正常重启；不强制结束文档宿主，不自动重启。记录维护完成时间与重启后实际启动时间，后者须更晚。重启后只读再次核版本/全部载荷、独立注册身份、保护基线。未知或变化停。

## x64 第 4 组：前台一次 installed-host 验收

用户在同一登录会话的前台普通 PowerShell 中执行，避免后台远程窗口不能取得前台焦点。源码流程总预算 180 秒，不改超时，不重复激活、不自动重跑。使用本机新的包外绝对证据目录，父目录已存在、末级目录必须不存在；不要照抄 tsaan 用户路径，也不要预创建末级目录。

```powershell
& 'C:\Program Files\YimeCore 18u Touch\bin\Yime18uInstalledRuntime.exe' --installed-18u-check --install-root 'C:\Program Files\YimeCore 18u Touch' --manifest-sha256 '096920dfaf62178fbbf3bd049a0057237dbe360ad04bed9364f947d315392880' --evidence-dir '<本机包外全新绝对证据目录>' --confirm 'once-installed-18u-host'
```

如果本机实际 %ProgramFiles% 不是 C:\Program Files，两个安装路径必须使用已核真实根，不能猜。该入口不安装/注册/卸载，使用已有 profile 的进程级激活并写入新证据目录。调用层另存 stdout/stderr 和退出码；失败可能早于证据目录创建，不能因缺报告而重跑。保存终端退出码和目录内 installed-host-result.json、host-stdout.jsonl、host-stderr.jsonl、broker-stdout.txt、broker-stderr.jsonl。

成功必须同时满足：exit 0；schema=installed-18u-host-check-v1，两个 PID 为正且不同；status=evidence-consistent、stage=completed；sourceCommit/manifestSHA256 与固定身份相同；hostExitSucceeded、brokerExitSucceeded、readbackEvidenceConsistent 均 true；registrationMutationRequested=false；原始 nativeResult 的 activationIdentity=windows-activated-profile、actualDLLLoaded=true、registered=true、outcome=applied、readbackEmpty=false、readbackMatches=true、otherContextEmpty=true、sendInput=false。nativeResult 的 stage=result、scenario=commit，rejected/duplicateRejected/replayRejected/unknownAfterPendingEditCovered/operationPendingObserved/postWriteDisconnectObserved 均 false。原始 JSON 必须是完整对象，拒绝缺字段/null/重复键或错误类型。核实际原始输出与汇总一致，不只看 connected。

installedProfilePresenceVerified=false 是现检查器固定未填字段，保留原值，持久注册由安装后独立状态证据支持。duplicateRejected/replayRejected 等未覆盖字段不能改 true。输入后只读核载荷和保护基线。只认本机 CN/variable 自有宿主一次提交，不计 Word/Edge、完整触摸 UI、手指/笔、性能或整体验收通过。

## ASUS 只读准备

只读记录实际 hostname、原生 ARM64/当前进程架构及既有相关产品基线。无安全查询手段记 unknown，不安装或编译工具。记录 native ARM64 test.6 包未提供，安装及宿主步骤保持 blocked。不得下载运行此 AMD64 包作仿真验收，不以 PR87 ARM64 预览包替代。完成这份准备即可待命。

## 回传与保留

这是新安装任务格式，不是 PR87 任务收据。不要改旧任务或任何 r1/r2 历史结果。

- MSI 结果目标 task-results/msi-x64，路径 installed-results/msi-x64/installed18u-test6-msi-x64-r1/result.json。
- 计算机目标 task-results/desktop-x64，路径 installed-results/desktop-x64/installed18u-test6-desktop-x64-r1/result.json。
- ASUS 目标 task-results/asus-arm64，路径 installed-results/asus-arm64/installed18u-arm64-readiness-r1/result.json。

先在本地用对应模板填事实并预览差异。阶段没有执行填 not-run，缺条件填 blocked，实际失败填 failed，不把未运行或未知改 pass。记录 dispatchCommit、固定包身份、每阶段退出/时间/证据来源；本地原件保持字节不变，结果用 SHA256 引用。

首次只回传指定 result.json 和 evidence-index.json 两个脱敏文件；如需 native 原始 JSON/日志，先审阅具体文件和分享范围，不整目录上传。evidence-index 仅记录相对文件名、大小、SHA256、证据类型和是否实际读取，不上传用户数据、词库、凭据、完整环境、账本或无关注册信息。提交前确认目标分支及精确文件集合；不 force、不 main、不改其他机器记录。回传是人工审阅后的独立提交，不调用旧 runner publish，不伪造自动领取或执行状态。

证据索引格式：schema=installed-18u-evidence-index-v1，taskID/dispatchCommit 与 result 相同，files 为数组；每项仅含 name（相对名）、bytes（整数）、sha256、kind、readLocally（布尔）、uploaded（布尔）。原件仅留本地时 uploaded=false。不得用模板预填值代替实测；未收集的退出码为 null，不能填 0。x64 模板必须替换 taskID/machineID，ASUS 的 readiness 未完成时保留 not-run，而不是将 blocked 安装当失败。

## 参数与判断的固定源码依据

- [Setup 与同账户提升/正常退出](https://github.com/tsaanghwang/Yime/blob/5367accdb6f18bb298f2282df67d4cc6d342aa5e/installer/simple/Setup.ps1#L2-L44)；成功不自动启动入口见 L213–216。
- [runtime 的有限参数](https://github.com/tsaanghwang/Yime/blob/5367accdb6f18bb298f2282df67d4cc6d342aa5e/go-backend/cmd/yimecore-trial-runtime/main.go#L65-L84)。
- [新证据路径/180 秒/一次宿主流程](https://github.com/tsaanghwang/Yime/blob/5367accdb6f18bb298f2282df67d4cc6d342aa5e/go-backend/internal/installed18uhost/controller.go#L32-L66)。
- [完整原始成功字段合同](https://github.com/tsaanghwang/Yime/blob/5367accdb6f18bb298f2282df67d4cc6d342aa5e/go-backend/internal/installed18uhost/evidence.go#L3-L67)。
- [实际 profile 与 DLL 检查](https://github.com/tsaanghwang/Yime/blob/5367accdb6f18bb298f2282df67d4cc6d342aa5e/YimeTextServiceExperiment/tests/Formal18uHost.cpp#L132-L158)。
