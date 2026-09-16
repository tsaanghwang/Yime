# 开发与测试分支交接

2026-09-14 起恢复 Git 分支交接。本阶段开发分支 `codex/yimecore-replacement-experiment` 收尾后退役；后续从最新 `main` 创建按目标命名的 `codex/*` 开发分支；“计算机”测试分支：`perf/i7-7820x-local`。当前文档是唯一接续入口，共享目录中的旧指令停用。

## 当前任务

**2026-09-16：包含 PR #57 的完整双产品包交付；测试端无新增安装或维护任务。** 开发分支 `codex/pr57-dual-product-delivery` 从当时最新 `main` 的 `c52168611bbf62653d21357f15c52d230c5588c4` 创建。安装器、YimeCore 与 Rime/PIME 应用均对应该干净源码；[源码 CI 35052224041](https://github.com/tsaanghwang/Yime/actions/runs/35052224041) 成功。该提交包含 [PR #57](https://github.com/tsaanghwang/Yime/pull/57) 的合并提交 `76376080`，无需测试端再次合并旧开发分支。

本轮只构建、制包、运行本地非变更/隔离验证并交付。**不安装、不卸载、不重启产品进程、不改变默认输入法、不修改用户数据，也不要求测试端执行这些操作。新包尚无实机安装、输入或重启验收。** 下方历史包与历史操作记录保持原身份，不能作为本包验收或当前执行指令。

### 本轮完整包

以下固定下载链接在交付分支提交 CI 通过、预发布公开后生效；上传阶段原始收据保留草稿身份，公开结果另见 [发布收据](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/release-publication.json)。不以草稿上传成功代替正式交付。

- [测试预发布页](https://github.com/tsaanghwang/Yime/releases/tag/test-simple-pr57-c5216861)
- [下载完整双产品包](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-Dual-Product-PR57-20260916.zip)：`Yime-Dual-Product-PR57-20260916.zip`，**256620137 字节**。
- SHA-256：`b1e56c1963bae4c9fbc20471ffac524c7ecb9a7ad001ec4db67de937265a74bd`。
- [构建及验证证据](https://github.com/tsaanghwang/Yime/releases/download/test-simple-pr57-c5216861/Yime-PR57-Build-Evidence-20260916.zip)：54364633 字节，SHA-256 `6354dbdf886279ab4b87a9b7f63df950826f40915ac0dad2c4173e7b1f7961cc`。
- 分支内的[制品元数据](../../docs/testing/simple-maintenance/2026-09-16/pr57-package/release-artifacts.json)、[来源证明](../../docs/testing/simple-maintenance/2026-09-16/pr57-package/BUILD-PROVENANCE.json)与[本地验证报告](../../docs/testing/simple-maintenance/2026-09-16/pr57-package/DEVELOPMENT.md)记录两个产品清单、来源哈希和验证边界。Git 源码检出或共享 `.tmp` 路径不作为收包方式。

包内含共同选择入口 `Install-Uninstall.cmd`，以及独立的 `yimecore/`、`rime-pime/` 完整目录。目标为 x64 Windows 和 x86 WOW64 应用；不是 ARM64 安装包。YimeCore 65 个载荷文件，Rime/PIME 160 个；两套各自携带维护脚本、词库、语流资源、私有字体与工具。固定 librime 依赖按仓库 lock 携带并校验，本轮未重新编译 librime。45 个 PE 文件均未签名，属于开发测试预发布，不代表生产发布就绪。

### 本地验证与后续边界

PR #57 两项回归、单套/双套合成调度、测试子进程等待及真实载荷隔离文件维护均通过 PS5。直接 `Read-Package` 与独立核验通过全部载荷大小/SHA-256/集合、45 个 PE 架构、当前产品身份、必需图标/三个工具、源码快照及语流绑定；YimeCore 三模式索引各生成两次且字节一致。构建前后的系统注册、启动项和默认输入法只读快照一致。

本地跳过会写真实用户注册表的 `Test-Startup`，以及会在用户主目录写日志的 `Test-Logging` 和 `Setup -Action Check`；本轮使用直接包读取验证。源码 CI 中这些测试在独立 runner 执行，不能把它们写成本机执行结果。发布顺序为本地验证、交付分支提交/推送、该提交 CI 成功、预发布转为可下载；后续若需要实机测试，再单独明确范围，不重复历史维护矩阵。

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

当前无需执行接收操作。下一阶段按新任务明确指定的主线或开发提交同步到 `perf/i7-7820x-local`；保留本地报告，普通合并后推送测试分支。具体分支、提交和测试范围由新交接给出，不继续拉取已结束的旧开发分支。出现分歧或冲突时保留现场并回报，不强制重置。

下一次需要实机验证时，开发端先完成本地构建、制包及相应验收，再推送并等待该提交 CI 成功；随后在本文件提供明确执行范围和包清单。完整包经 GitHub artifact/Release asset 下载，分支记录下载地址、大小、SHA-256、安装脚本提交和各运行载荷来源。拉取源码不等于收到安装包；缺包时反馈一次，由开发端补齐。

## 测试端回传

在 `docs/testing/simple-maintenance/<日期>/<本轮名称>/` 新建 `TEST-RESULT.md`，写明开发提交、包 SHA-256、机器/Windows、操作、实际结果和未测项。附本轮相关 `.user.log`、`.admin.log` 或小型 JSON 数据；不要提交用户词库、学习库、密码或无关应用数据。保持原报告不变，补充结论另写新报告。原始文件须按字节保留，参照已有 `raw` 目录属性和 SHA-256 索引。

只暂存本轮报告目录，提交并推送到 `perf/i7-7820x-local`，回报提交号。文档和测试结果不通过共享 `.tmp` 目录交回，也不在测试端改写安装器。

## 开发端收取

执行 `git fetch origin perf/i7-7820x-local`，先检查 `git log HEAD..origin/perf/i7-7820x-local` 及报告差异，再挑选报告提交合入当前开发分支。若报告与源码混在一个提交，按路径提取并注明来源，避免整分支回灌旧代码。将审阅结论写入同轮目录，更新本文的当前任务。

安装受阻时保留本次错误和父子日志即可；由开发端修复、验证、CI 成功后重新交付。测试端不接续历史恢复链。
