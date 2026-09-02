# 本开发机：验收、停写恢复与真实安装回退

范围：MYCOMPUTER，原生 x64。其它机型与分档模拟保持冻结。本报告不等同于最终独立发行批准。

21:29 再次重启后，[18 项自启动复核通过](YIMECORE_REBOOT_AUTOSTART_ACCEPTANCE_2026-09-02.md)，自启动阻塞解除。剩余独立终端的实际恢复/回退补验；不将下述隔离环境的历史结果直接提升为完整闭环。

最新纠正：已确认隔离的注册表/AppData 视图造成部分假通过。真实系统 Run/卸载项已修复，三份档案已复制到 `C:/Users/tsaan/YimeCore Recovery Archives` 并验证。旧实际恢复及回退的用户注册项结论需在独立终端补验，不能继续称完整闭环通过；详见[系统视角修复与证据边界](YIMECORE_SYSTEM_VIEW_REPAIR_2026-09-02.md)。下文为历史记录。

后续状态：用户于同日 20:49 正常重启；包和注册保持正确，但 Trial runtime/Broker 未运行，重启复核未通过，见[自启动阻塞记录](YIMECORE_LOCAL_REBOOT_BLOCKER_2026-09-02.md)。以下保留重启前结果，不以历史 `running` 状态冒充当前运行状态。

重启前结论：本轮 Word/记事本验收、停写备份与实际恢复、故障升级自动回退、生产输入法实际提交和数据保留校验均通过。当时剩余下一次正常重启后的自启动/包身份复核，没有自动重启 Windows。设置窗口直接复制备份的边界见下文，不纳入停写恢复的通过结论。

## 已完成的维护闭环

- 关闭 Word 前，将原来打开但有新增内容的文档另存为 `original-word-preserved.docx`，未覆盖旧验收文档，也未丢弃内容。
- 停止 Trial runtime/Broker、检查写入进程退出后，备份完整 Trial state 和完整旧安装介质；复制前后源文件及副本哈希一致。生产 Rime 数据未参与覆盖。
- 在离线副本中分别恢复两份学习 journal：generation 335 / 473，97 / 165 条学习记录；均无截断尾部。
- 实际将本机 user-model 移到恢复档案，再复制一致快照回活动位置，同时恢复本次 6 个数据/设置文件；哈希一致，启动后的三模式探针通过。原数据仍保留在 `pre-restore-user-model`。
- 构造只在启动时退出 86 的隔离故障 runtime，经真实管理员安装事务触发新包启动失败，验证自动恢复旧包；不是 mock 或仅执行 Plan。
- 第一轮发现真实遗漏：HKCU 的 Trial `LanguageProfile/0x00000804/{607895A8-9504-4A2E-9BB1-2C159E3A1757}/Enable=1` 未恢复。已先加入会失败的回归，修复递归注册快照及正常升级/失败回退两条路径，再次实际验证。
- 最终故障演练安装器 exit=1（预期失败），回退检查全部通过：机器 COM/TIP、用户 TIP、Run/卸载项及原始值类型、runtime config、旧包身份、运行状态、旧目录和独立恢复介质。
- 随后正常安装最终修复包成功，用户 TIP、语言列表和 keyboard preload 与原快照一致；生产 x64/x86 COM/TIP 未变，默认输入法仍是微软拼音。
- 验收结束再次停写备份并比较最初快照：旧 journal 136600 字节完全不变；活动 journal 从 210032 增至 215032 字节，原始前缀完整保留；`yime_user_phrases.txt`、`yime_blocklist.txt`、`professional-lexicons.json` 哈希不变。没有用恢复操作抹掉新学习。运行服务随后恢复，自启动和安装态审计再次通过。

最初的 `actual-rollback` 包含真实失败及取证脚本等待常驻后代的问题；`actual-rollback-fixed` 缺少 exit code，不作为最终通过证据。唯一最终故障回退证据是 `actual-rollback-final/summary.json`。取证程序现直接等待安装器自身并拒绝空退出码。

## 最终已安装身份

- 安装目录：`C:/Program Files/YimeCore Experimental Trial/yimecore-e6c-45b389e530c0-8d48953a`。
- manifest SHA-256：`8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64`。
- x64 DLL SHA-256：`5adaad4ed9b255865831ba19b7537d3deb650e0cf48d42033ada521fe7be252e`。
- runtime SHA-256：`415ef8b09b26ca884cff935c8b61b5b970a4e28f6d1e2603df62514b5592fff4`。
- E6-D：62 个载荷文件、29 个 PE；包完整性、独立依赖、活动 runtime/Broker、COM 和当前 Run 一致性通过。未把源码改动直接当作已生效。
- 最终包的 x64 构建/隔离 TSF、64 个英文 Shift 组合、三模式、12 个整句及 Broker 恢复通过。
- 安装版 x64 注册宿主，full/variable/shorthand 三模式通过：Shift 透传、裸数字/候选提交、延迟锁、写入失败恢复、宿主保留语言栏对象。测试使用独立 Broker、独立设置目录，不将自动化学习写入真实用户模型。未运行 x86/ARM64 宿主。

## 真实桌面宿主：本轮已通过

本轮前段在原安装包 Word PID 19852 中，逐项完成 Shift+1 至 Shift+9 选词检查，保留 DOCX 和截图。第一次 Shift+3 得到 `t#`，重试成功；原因未证明，不能删掉失败记录，也不能据此直接认定是产品或自动化焦点问题。临时候选数 9 已恢复原值 5。

最终修复包安装后，新开记事本 PID 9600 起初是微软拼音；用户实际选择 Trial 后，确认加载上述最终 DLL。`tf-cN → 它们`、Shift+1 提交、裸数字 `2` 及候选可见时追加 `3`（组合为 `23`）、Esc 取消通过。Shift+T 后继续 `hey`，Shift+1 后继续 `a`，均保持英文模式。由于原设置全角=true、英文标点=false，实际文件是 `它们Ｔｈｅｙ！ａ`；不把这条记录宣称为半角英文标点测试。

用户再实际选择生产 Rime/PIME，同一记事本中 `t` 显示生产候选，Shift+1 提交“天窗儿”并成功保存。确认加载生产 DLL `C:/Program Files (x86)/YIME/x64/PIMETextService.dll`，PIMELauncher/worker/server 分别为 PID 14756/19900/28952。这补充了真正的生产输入法回退输入证据，不只是确认注册存在。原有记事本标签未改动。

新 Word PID 24060 已打开“文档1”并重新选择 Trial，确认加载最终 DLL。已捕获该 PID 在 12:23–12:24 UTC 的 `left_click`、`right_click_open` 和 `right_click_command`，hresult 均为 0；command 27744 将全角切为半角。这补齐最终包的物理语言栏证据。

Word 采集中途曾返回 `no monitor found for window` / `no screenshot targets found for Microsoft.Office.WINWORD.EXE.15`。用户将窗口恢复可见后继续成功；没有越过 UI 权限注入，也不将该限制误报为输入法崩溃。

最终 Word 的半角 `They!a`、Shift 后继续英文、`tf-cN` 空格提交“它们”、裸数字 `2` 后追加 `3`（组合 `23`）及 Esc 取消全部通过。临时候选数 9 时，Shift+1～9 每项均一次成功，文档实际记录“他是大天天他同同同”；候选数恢复 5，保留用户手动选择的半角与英文标点。分项见 `desktop-checks.json`、`word-final-live.json`。

最终文档 `word-final-build.docx` 已保存、关闭并检查 ZIP 内正文 XML，SHA-256 为 `cc5f51a351290095e53dbbad6260b3731659e173b57d1a6284716cd30a5351bf`；用户手工输入的前两段完整保留。截图为 `word-final-build.jpg`。先前旧包 Shift+3 的一次异常仍保留，不由新包成功记录覆盖。

告警：打开 Word/记事本不会自动激活 Trial。Computer Use 仅能向已授权应用窗口输入，不能凭宿主辅助功能树中的任务栏条目操作独立任务栏；其 Alt+Space 也可能只是宿主系统菜单。需要实际选中目标输入法并确认 DLL/profile。这是自动化入口限制，不是已证实的 Yime/Word 产品故障，不修改默认输入法绕过它。

下一次正常重启后仍需核对 Run 和活动包身份。本轮没有重启 Windows；先前 Run 重启后回旧值的根因尚未确认。

## 数据恢复边界

恢复档案位于：

- `C:/Users/tsaan/AppData/Local/YimeCore Recovery Archives/local-closure-20260902`：初始包、一致快照、离线恢复输出、实际恢复证据、原始数据。
- `C:/Users/tsaan/AppData/Local/YimeCore Recovery Archives/local-closure-second-20260902`：后续演练前一致快照与中间版本恢复包。
- `C:/Users/tsaan/AppData/Local/YimeCore Recovery Archives/local-closure-final-20260902`：全部验收完成后的最新一致快照和最终已安装包。

正常升级已清理中间试验包 `yimecore-e6c-45b389e530c0-f67a3e76` 的安装目录，可从第二份恢复档案取回；用户数据未删除。不要依赖 Program Files 中的旧目录充当备份。

维护入口为 `tools/yimecore/backup-local-trial-state.ps1` 和 `restore-local-trial-state.ps1`。恢复脚本为本机受保护演练：发现备份之后新增学习会拒绝覆盖；不是无条件覆盖任意历史快照的通用恢复工具。没有模拟破坏真实用户数据。

现有设置窗口的备份/恢复直接复制文件，未在这次验收中证明它能一致地快照正在写入的学习模型。不能用“窗口提示备份成功”替代停写与恢复验证；本次数据安全通过结论仅适用于上述停写维护路径。

## 证据索引

下列路径以 `C:/dev/Yime` 为基准：

- `.tmp/yimecore-experiment/local-closure-20260902/closure-summary.json`：维护子集结论和未完项，含证据哈希。
- `.tmp/yimecore-experiment/local-closure-20260902/actual-rollback-final/`：真实失败安装输出、前后注册/运行快照及最终回退结论。
- `.tmp/yimecore-experiment/local-closure-20260902/final-installed-state.json`：正常升级后安装状态。
- `.tmp/yimecore-experiment/local-closure-20260902/post-acceptance-state.json`：全部验收、停写和服务恢复后的状态。
- `.tmp/yimecore-experiment/local-closure-20260902/data-continuity.json`：原始学习字节及词库哈希保留证据。
- `.tmp/yimecore-experiment/local-closure-20260902/word-final-build.docx`、`word-final-build.jpg`、`word-final-live.json`：最终包 Word 文本、截图、DLL 和物理语言栏事件。
- `.tmp/yimecore-experiment/local-closure-20260902/notepad-final-build.txt`、`notepad-production-fallback.jpg`：最终包及生产版真实宿主提交。
- `.tmp/yimecore-experiment/local-closure-20260902/registered-x64-final/`：安装版三模式注册宿主日志。
- `.tmp/yimecore-experiment/local-closure-20260902/word-shift-1-9.docx`、`word-shift-1-9.jpg`：前段 Word 实际输入证据，含首次 Shift+3 异常。
- `.tmp/yimecore-experiment/e6c/local-closure-final-20260902/summary.json`：最终包构建与隔离验收。
- `.tmp/yimecore-experiment/e6d-independence/local-closure-20260902/summary.json`：最终安装态审计。
- `.tmp/yimecore-experiment/e6d-independence/local-closure-final-20260902/summary.json`：全部验收后活动服务与自启动再次核对。

现在已分别具备失败安装事务回退、生产输入法宿主提交和重新进入 Trial 宿主的证据；重启复核仍待完成，不将全部发布回退闭环提前勾选通过，也不改变保留方案审批字段。工作区仍未提交形成 clean 源码证据。

签名证书正在申请，等候审批，暂缓相关事项。
