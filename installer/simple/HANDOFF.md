# 开发与测试分支交接

2026-09-14 起恢复 Git 分支交接。本阶段开发分支 `codex/yimecore-replacement-experiment` 收尾后退役；后续从最新 `main` 创建按目标命名的 `codex/*` 开发分支；“计算机”测试分支：`perf/i7-7820x-local`。当前文档是唯一接续入口，共享目录中的旧指令停用。

## 当前任务

**2026-09-29：YimeCore 首次注册查询修复已完成源码/CI/独立完整包交付；测试 PC 的有限验证待执行。开发机 MYCOMPUTER 不执行安装或重装。** 分支 `codex/yimecore-registration-fix-20260929`；源码及安装器提交 [`2ffee43242af9981c462aeabb0d5b26c4f99286c`](https://github.com/tsaanghwang/Yime/commit/2ffee43242af9981c462aeabb0d5b26c4f99286c)，[全部 CI 通过](https://github.com/tsaanghwang/Yime/actions/runs/36503447392)。本节在完整包上传、远端大小及 SHA-256 核对成功后更新；原始 [current-issues 报告](../../docs/testing/simple-maintenance/2026-09-28/current-issues/RESULT.md) 保持历史原文。

- [完整单产品包 `YimeCore-Registration-Fix-20260929.zip`](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/YimeCore-Registration-Fix-20260929.zip)：**187973541 字节**，SHA-256 `849bfc21fa9222dec3948f88c5652bcf404960f82e84f72175865293e7a3c073`。
- [Evidence ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/YimeCore-Registration-Fix-20260929-Evidence.zip)、[SHA256SUMS](https://github.com/tsaanghwang/Yime/releases/download/test-yimecore-registration-20260929-2ffee432/SHA256SUMS.txt)；[Release](https://github.com/tsaanghwang/Yime/releases/tag/test-yimecore-registration-20260929-2ffee432)；[来源、清单与验证记录](../../docs/testing/simple-maintenance/2026-09-29/registration-fix/DELIVERY.md)。Git checkout 和自动 Source code ZIP 不是安装包。
- 65 个载荷、25 个 PE、PS5 包检查及 71 个完整 ZIP 成员验证通过；新包尚无实机安装/输入结果。**9 月 27 日旧包未变，不能用于验证本修复或标为已修复。**

### 后续测试安排（仅“计算机”测试 PC）

对象为已识别的“计算机”测试 PC，报告分支 `perf/i7-7820x-local`。只维护 YimeCore，保留 Rime/PIME、默认输入法及双方用户数据；不要求重跑历史矩阵，不扩展 ARM64 或新增硬件。不在开发机执行本节。

1. 保留现有报告，通过 Git 获取本目标分支；下载上面的新 ZIP，核对大小和 SHA-256，解压至新的本地目录。记录机器/Windows、当前两产品状态和默认输入法。源码提交固定为 `2ffee43242af9981c462aeabb0d5b26c4f99286c`。
2. 保存工作、关闭输入法宿主，在新包目录执行 `Setup.cmd -Action Install` **一次**。保留本次 `.user.log`/`.admin.log`；检查注销成功后预检 `com=false; profile=false; categories=0`，首次 `register-profile` 成功。不要用等待、重启或重复点击后的成功替代首次结果。
3. 用包内 x64/x86 `YimeTextServiceRegistration.exe status` 只读核对两架构 COM/profile 状态。已存在的注册再次请求应拒绝 `0x800700B7`，不得覆盖；该项受控诊断只在测试 PC 进行，记录操作前后状态。安装器设计仍是 x64 完整注册加 x86 COM 注册，不称两次独立完整 RegisterProfile。
4. 用同一完整包执行一次 `Setup.cmd -Action Uninstall`，用两架构包内工具 `verify-absent` 记录注销后立即 absent，再立即执行 `Setup.cmd -Action Install` 一次。保留首次结果；完成后保留 YimeCore 安装。全程不使用 `-ResetData`，不手工删注册表、不运行历史恢复链、不改 Rime/PIME。
5. 验证当前产品身份和包内两架构注册宿主检查；真实应用先明确选择当前 **音元拼音**，在可用 x64/x86 宿主中检查候选显示与 Shift+1 上屏，并确认 Rime/PIME仍可独立输入。真实宿主与 synthetic registered-host 分开执行/记录；不要在 Word 正占用前台 TIP 时并行跑 synthetic host。没有执行的模式/宿主就写未测；无需为本轮额外安装宿主或重启系统。
6. 在 `docs/testing/simple-maintenance/2026-09-29/registration-fix-test/TEST-RESULT.md` 记录源码提交、包哈希、每次首次操作及状态、实际宿主/架构、另一产品与默认输入法保持情况，附本次父子日志和只读状态，通过 `perf/i7-7820x-local` 提交推送。不要修改 9 月 28 日原始报告。

任一步失败即保留本次首次失败日志并回传；不自动重试、不以重启恢复掩盖失败，也不继续旧事务/授权链。上述都是待执行安排，不能写成已完成验收。

## 其他独立工作与历史交付（2026-09-28 / 2026-09-27）

**2026-09-28：touch-terminal KLE 模板导入与实屏基线开发中；测试端无安装任务。** 目标分支 `codex/touch-terminal-kle-baseline` 从已合并 PR #64 的当前主线 `af8ea73f` 创建，并接续 9 月 22 日隔离浏览器原型。范围仅为 KLE 触摸几何模板、离线生成/校验、浏览器交互与已连接触摸屏的本地基线；不连接或修改已安装输入法，不改变默认输入法、用户词库或桌面键位真源。接续入口为 [运行说明](../../prototypes/touch-terminal/README.md)，另见 [验证记录](../../prototypes/touch-terminal/VALIDATION.md)、[适配协议](../../prototypes/touch-terminal/PROTOCOL.md) 和 [硬件可行性](../../prototypes/touch-terminal/HARDWARE.md)。触摸屏已以复制显示模式连接，但在真实手指测试记录完成前，不宣称误触率、端到端延迟或宿主输入通过。

**2026-09-27：current-readiness 双产品完整包已重建并发布为开发预发布；测试端无安装任务。** 目标分支 `codex/current-readiness-delivery-20260927` 从当前 main `0ab86312` 创建，两套运行源码和安装器均固定于完整提交 `0ab8631266736775bf1386f456d4a1d53e8e2eb3`。来源提交 [CI 35418522827](https://github.com/tsaanghwang/Yime/actions/runs/35418522827) 成功；交付记录提交 `a274730fd3230ff22c04632be62ffe18397555ec` 的 [CI](https://github.com/tsaanghwang/Yime/actions/runs/36280832479) 全部成功后，发布固定资产；远端 size 与 SHA-256 digest 已逐项匹配本地。

完整包 `Yime-Current-Readiness-20260927.zip`：**256650784 字节**，SHA-256：`45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341`。本地目录：`C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312`。[Release 页面](https://github.com/tsaanghwang/Yime/releases/tag/test-current-readiness-20260927-0ab86312)；下载：[Yime-Current-Readiness-20260927.zip](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/Yime-Current-Readiness-20260927.zip)、[Yime-Current-Readiness-20260927-Evidence.zip](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/Yime-Current-Readiness-20260927-Evidence.zip)、[SHA256SUMS.txt](https://github.com/tsaanghwang/Yime/releases/download/test-current-readiness-20260927-0ab86312/SHA256SUMS.txt)。Git 源码 checkout 和自动 Source code ZIP 不等于收到完整包。

已通过来源/清单/逐载荷哈希、PE 架构、PS5 包检查、隔离维护模拟和 ZIP 逐成员验证；YimeCore 65 文件、Rime/PIME 160 文件。来源证据与工具链保存在独立 Evidence ZIP。详见 [交付记录](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/DELIVERY.md)、[固定上传清单](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/UPLOAD.md) 和 [机器可读包身份](../../docs/testing/simple-maintenance/2026-09-27/current-readiness-rebuild/delivery.json)。

**本轮未安装、卸载、重启已安装产品进程，未修改默认输入法或用户数据；新包未做实机输入验收。** 不将 9 月 19 日旧包的本机结果继承到本包，不要求测试 PC 同步、安装或重复历史维护；任何后续实机任务另行交接。

## 历史文档交接（2026-09-16，当时状态）

**2026-09-16：工程文档更新，测试端无新增执行任务。** 开发分支 `codex/project-docs-refresh` 从当前主线 `76376080` 创建，统一项目首页、现状、架构、路线图、测试及工具说明。本轮只改文档，不制作安装包，不要求测试端同步、安装或重测。当前概览见[项目现状](../../docs/YIME_PROJECT_ASSESSMENT.md)与[文档导航](../../docs/README.md)。

此前的安装器修复已通过 [PR #57](https://github.com/tsaanghwang/Yime/pull/57) 合入主线 `76376080`，[合并后 CI 35041052421](https://github.com/tsaanghwang/Yime/actions/runs/35041052421) 成功。修复补齐 YimeCore 图标和三个必需工具的包校验；Windows 拒绝移除用户输入配置时，在 COM 注销、启动项清理和文件删除之前停止。新增的包完整性与配置移除失败隔离回归已纳入 `simple-installer` CI。

**包含 PR #57 修复的新完整包尚未交付，也没有该新包的实机安装或输入验收。** 下方已验收 ZIP 不包含这些修复。下一次需要实机测试时，另行发布具体范围、通过 CI 的源码提交、完整包 URL 与 SHA-256；不能因本轮文档更新重复执行历史步骤。

## 已完成阶段记录

**2026-09-15 本阶段已完成。** PR #55 的主线代码及 CI 已通过；测试端已同步主线 `86005b58`，回传 `1509b860` 已收取，见[同步报告](../../docs/testing/simple-maintenance/2026-09-15/main-sync/TEST-RESULT.md)和[阶段收尾复核](../../docs/testing/simple-maintenance/2026-09-15/main-sync/REVIEW.md)。测试端当前无待执行任务。同步执行单和下方安装步骤仅作历史记录，不因收尾文档合并再要求测试机同步、安装或重测。下一阶段另建开发分支并发布新的具体任务。

**本轮验收已完成，测试端无需再次安装或重测。** 已收取安装/重启报告 `85aec9c4` 和应用补充 `7ab9566f`，并补齐收包记录 `50f70a9c`。两套产品在“计算机”的 Codex 与记事本中重启前后均可输入，原始日志和 10 个证据文件校验通过，见 [开发端复核](../../docs/testing/simple-maintenance/2026-09-14/source-candidate-test/REVIEW.md)。保留两套安装，正常使用；下方下载和操作步骤作为本轮已执行记录，不是新任务。

清理后的两套程序现已从源码构建并在开发机替换安装，用户确认重启前后均可正常输入，见 [本轮源码候选包验收](../../docs/testing/simple-maintenance/2026-09-14/source-candidate/DEVELOPMENT.md)。YimeCore 首次注册遇到 `0x800700B7`，稍后重试成功，原始失败和重启处理建议保留在报告中。

本轮代码提交 `a4fa6f7616b41658361a9f5b14ea3c96311ed8b0` 的 [CI 34856928836](https://github.com/tsaanghwang/Yime/actions/runs/34856928836) 已成功。当时交付的完整包及安装、两套输入和重启确认现已完成。不重复历史维护矩阵。`5c9a5d77` 的已完成维护结果仍见 [验收汇总](VALIDATION.md) 与 [原始报告索引](../../docs/testing/simple-maintenance/2026-09-14/README.md)。

## 历史完整包与已完成操作（2026-09-14）

- [候选包发布页](https://github.com/tsaanghwang/Yime/releases/tag/test-simple-source-a4fa6f76)
- [下载完整安装包](https://github.com/tsaanghwang/Yime/releases/download/test-simple-source-a4fa6f76/Yime-Source-Candidate-20260914.zip)
- 文件：`Yime-Source-Candidate-20260914.zip`，256617810 字节。
- SHA-256：`8474875273b42404e8d1e6a29206216a329aca44e6b01499a0e749170ae3021d`。
- 安装器及应用源码均对应本轮已验收内容。包在提交前从工作区构建，包内 `BUILD-PROVENANCE.json` 保留当时基础提交 `58e360a5`、源码快照和两套产品清单哈希；构包时的 `pending` 不是当前验收状态，后续结果见本轮开发验收报告。此处交接更新仅为文档，不更换已验收 ZIP。

1. 按下节同步分支。下载上述 ZIP，核对文件大小和 SHA-256，完整解压至测试机本地新目录。不要使用 GitHub 自动生成的 Source code 压缩包，也不要从共享 `.tmp` 取包。
2. 保存工作，退出 Word 等输入法宿主，切换到英文键盘。运行解压目录中的 `Install-Uninstall.cmd`，Action 选 `1`，Product 选 `3`，允许 UAC，完成两套安装。无需预先手工删除目录、注册项或用户数据；如仍有旧安装，由包自身处理。
3. 分别选择两套输入法，在 Word 和测试机可用的另一常用应用输入并上屏。记录实际测试的应用；不为本轮专门安装额外宿主。
4. 保存工作、正常重启并登录，再分别确认两套输入法仍可输入。本轮结束保留两套安装，不再做最终卸载。
5. 在 `docs/testing/simple-maintenance/2026-09-14/source-candidate-test/TEST-RESULT.md` 记录包哈希、安装前状态、各步骤结果及真实应用名称，附本次安装父子日志，通过 `perf/i7-7820x-local` 提交推送。不要只回传“成功”而缺少包身份。

若显示文件占用，退出相关应用后重试，不能释放就取消并正常重启后重试。若发生与开发机相同的注册 `0x800700B7`，保留本次日志，正常重启后再运行同一完整包一次；不能把重试成功记成首次成功。重启后仍失败或出现其他错误，回传本次失败与日志，由开发端处理；不接续旧恢复脚本，不反复尝试。

## 下一阶段测试端接收

本轮仅按上方“当前任务”接收 `codex/yimecore-registration-fix-20260929` 的已交付修复及完整包；保留本地报告，普通合并后推送 `perf/i7-7820x-local`。不继续拉取已结束的旧开发分支。出现分歧或冲突时保留现场并回报，不强制重置。

下一次需要实机验证时，开发端先完成本地构建、制包及相应验收，再推送并等待该提交 CI 成功；随后在本文件提供明确执行范围和包清单。完整包经 GitHub artifact/Release asset 下载，分支记录下载地址、大小、SHA-256、安装脚本提交和各运行载荷来源。拉取源码不等于收到安装包；缺包时反馈一次，由开发端补齐。

## 测试端回传

在 `docs/testing/simple-maintenance/<日期>/<本轮名称>/` 新建 `TEST-RESULT.md`，写明开发提交、包 SHA-256、机器/Windows、操作、实际结果和未测项。附本轮相关 `.user.log`、`.admin.log` 或小型 JSON 数据；不要提交用户词库、学习库、密码或无关应用数据。保持原报告不变，补充结论另写新报告。原始文件须按字节保留，参照已有 `raw` 目录属性和 SHA-256 索引。

只暂存本轮报告目录，提交并推送到 `perf/i7-7820x-local`，回报提交号。文档和测试结果不通过共享 `.tmp` 目录交回，也不在测试端改写安装器。

## 开发端收取

执行 `git fetch origin perf/i7-7820x-local`，先检查 `git log HEAD..origin/perf/i7-7820x-local` 及报告差异，再挑选报告提交合入当前开发分支。若报告与源码混在一个提交，按路径提取并注明来源，避免整分支回灌旧代码。将审阅结论写入同轮目录，更新本文的当前任务。

安装受阻时保留本次错误和父子日志即可；由开发端修复、验证、CI 成功后重新交付。测试端不接续历史恢复链。
