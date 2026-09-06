# local.12 原生升级与最小复验交接

2026-09-05：用户已同意合并两项修复并安排升级。最新状态为**原生备份、local.12 安装、六组注册宿主自动复验、用户所报设置/未提交切换人工复验及本次电脑重启/登录自启动核对均已完成并通过；重启后候选数保持 7，当前留样为（1/7），与用户说明的退出前其他候选调频过程一致，未发现新增确认回归**。15:17～15:22 的系统核对见 [重启结果](testing/l5/2026-09-05-local12-reboot-outcomes.json)。最终日用确认仍待用户给出；本次有额外候选提交，不能冒称完成了无新训练的严格留样对照。本页不是 L5 总体日用验收通过报告。[构包证据](testing/l5/2026-09-05-local12-build-handoff.json)及 [14:59 人工复验/重启前基线](testing/l5/2026-09-05-local12-manual-pre-reboot.json)保留历史结果。

## 1. 保存关闭及原生入口

用户先保存并关闭 Word、Notepad++、音元设置/工具及其他相关输入宿主，向助手确认“已保存并关闭”。不强制退出、不停止 Explorer，不更改默认输入法，也不为测试切换到旧试验输入法。

13:42 更新：用户已明确确认“已保存并关闭”；只读进程检查未发现 Word、Notepad++、Notepad 或所查询的音元工具仍在运行。当前 local.11 的 74 项清单、Runtime/Broker 身份及相对 13:32 的 12 项保护指纹均正常。该确认只完成保存关闭前提，**真实 Backup、Install、Verify 和电脑重启仍未执行**。元数据见 [保存关闭后的升级前快照](testing/l5/2026-09-05-local12-saved-closed-preinstall.json)。

随后由用户从资源管理器打开普通、非管理员 Windows PowerShell 5.1（系统 `WindowsPowerShell\v1.0\powershell.exe`，不是 PowerShell 7、Codex 终端或其子进程）。保持当前 Windows 用户；安装器需要时自行请求 UAC。若原生上下文保护拒绝执行，停下回报错误类别，不修改权限、清单或绕过保护。

## 2. 先备份旧安装版

只在上述确认后执行。以下命令使用当前已安装 local.11 的维护入口，不使用新包目录的 Backup：

```powershell
& 'C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-f435f463bfd0-5a3f847a\Maintain-YimeCore-Local.cmd' -Action Backup
if ($LASTEXITCODE -ne 0) { throw 'Backup failed; stop before installation.' }
```

默认恢复归档位于 `C:\Users\tsaan\YimeCore Recovery Archives\local-product-<时间及唯一标识>`，在 AppData 和 Git 之外。流程会暂停本产品写入者、核验并备份后恢复运行。备份失败不得继续安装；不要手工复制正在写入的学习库。向助手仅报告成功/失败、归档目录及校验结果，不发送归档内容、学习记录或用户文字。归档需保留，不能清理为“临时文件”。

本步骤已由用户在原生 PowerShell 执行，返回 `Quiesced state and package backup complete`、退出码 0，归档为 `C:\Users\tsaan\YimeCore Recovery Archives\local-product-20260905-135008-38219e5a`。13:54 只读复核清单的原生上下文、写入者停止和复制稳定性标志均通过；85 个归档状态文件的完整目录清单、大小及系统可见性匹配，助手未读取或重新哈希其内容。完整字节复制校验由原生备份流程执行，不冒称助手再次验证了用户状态内容。local.11 已恢复运行，12 项保护指纹未变；此时尚未运行 Install/Verify，也没有执行 Restore 演练。详见 [原生备份证据](testing/l5/2026-09-05-local12-native-backup.json)。

## 3. 核对新包后升级

新包目录：`C:\dev\Yime\.tmp\yimecore-local-product\20260905-132513-73c86ac2\package`。

备份成功后，在同一原生窗口核对版本对应的清单哈希并运行新包入口：

```powershell
$yimeLocal12Package = 'C:\dev\Yime\.tmp\yimecore-local-product\20260905-132513-73c86ac2\package'
$yimeLocal12Manifest = Get-FileHash -LiteralPath (Join-Path $yimeLocal12Package 'package-manifest.json') -Algorithm SHA256
if ($yimeLocal12Manifest.Hash -ine '9b3366b350ef2b23fd285fc9d97d876bf1ae6e2fc0f8613c647640f01184502e') { throw 'Candidate manifest mismatch; stop.' }
& (Join-Path $yimeLocal12Package 'Install-YimeCore-Local.cmd') /nopause
if ($LASTEXITCODE -ne 0) { throw 'Install failed; stop and inspect rollback result.' }
```

入口会验证全部包文件。失败时保存错误和回滚结果，不重跑旧版本快捷入口、不强删被占用 DLL、不终止 Explorer。成功时仅回报退出码、版本、实际安装目录、运行/回滚状态；不要贴可能包含用户状态的完整原始日志。

用户已从原生 PowerShell 运行安装入口，返回 `PASS`、退出码 0。14:01 从独立系统注册视图解析出的实际安装根为 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-62af8b507c91-9b3366b3`，本次没有冲突后缀；不是仅沿用 Plan 猜测。74/74 文件清单匹配，双架构 COM、卸载版本/目录与 REG_SZ 类型的 Run 均指向 local.12。Runtime PID 8844 / Broker PID 38052、父子关系和用户身份匹配；相关宿主仍关闭。证据见 [安装元数据](testing/l5/2026-09-05-local12-installed-metadata.json)。

14:08 保护核对：12 项生产/旧身份/默认输入保护指纹未变；当前用户的完整产品 TIP 子树及值类型仍匹配升级前。机器级当前产品 TIP 子树的唯一差异是图标文件路径从旧安装根变为新安装根，属于本次预期升级变化。见 [安装保护证据](testing/l5/2026-09-05-local12-installed-protection.json)。

原计划的包内 `Maintain-YimeCore-Local.cmd -Action Verify` **本次取消执行**：源码复核发现它会把实际运行 Broker 返回的首选候选文字写入 `modes.first_candidate`。即使请求是合成编码，响应仍可能受用户词库/学习影响，因此不能在“不记录用户文本”的本次验收中原样运行；过滤已落盘报告也不能消除曾经记录的事实。已安装包不因此修改，尚未执行该命令，不把它记为通过。

旧 `test-installed-local-host.ps1` 也不原样执行：它只隔离 LOCALAPPDATA、继承工具烟测环境，未强制检查新增焦点结果；其宿主程序会调用 `EnableLanguageProfile(TRUE)`，不能笼统声称完全没有注册写入。后续改用独立的原生测试入口，要求当前产品已启用、私有四项环境/管道/内存 Broker、真实结果标志、前后保护比较与仅元数据输出；它不修改 local.12 包、不访问真实学习文件，也不代替用户人工确认。

### 隐私安全注册宿主入口及已完成的自动复验

`tools/yimecore/test-local12-installed-privacy-safe.ps1` 的 SHA-256 为 `71bd6440b6d1219995cd299073f61f9e751d58b3ecbb79f35010f0c31655bd95`。Windows PowerShell 5.1 解析和 8 项纯合成过滤/摘要检查通过，独立审查完成；见 [静态验证证据](testing/l5/2026-09-05-local12-privacy-runner-static.json)。这些不是原生预检或注册宿主已经通过。

用户随后已实际运行以下命令并返回 PASS / 退出码 0。14:25 的结果根为 `C:\dev\Yime\.tmp\yimecore-experiment\local12-20260905-142517-06e26544`，六组逐项记录与 summary 一致：x64/x86 × 全码/变码/简码 6/6 通过，全部 17 项必需布尔结果及位数/取消结果正确，无超时。23 项保护指纹前后相同，日常 Runtime/Broker 身份未变，环境恢复、自有进程清理和包复核均通过；当前 Runtime/Broker 及运行器均为同 SID 的 medium、非管理员主令牌。见 [注册宿主验收证据](testing/l5/2026-09-05-local12-registered-acceptance.json)。**此自动阶段已完成，不再重复运行下面的历史执行命令。**

保持 Word/Notepad++/音元工具关闭。用户在当前原生普通 PowerShell 窗口粘贴以下命令，执行后直到结束不操作鼠标或键盘。新子进程确保退出码明确，并使用该进程的一次性执行策略，不修改系统策略：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\test-local12-installed-privacy-safe.ps1" -ConfirmHostsClosedAndInputIdle
Write-Host "退出码：$LASTEXITCODE"
```

它先校验原生同 SID 普通权限、新包全部清单和当前已启用 TIP；只对合成宿主进行六组回归，连接六个各自唯一管道的内存 Broker，不使用日常 Broker。每组宿主上限 45 秒，失败立即停后续组，使用持有的进程对象清理自身子进程，核对环境恢复及前后保护/运行身份。只保存白名单布尔结果、数值和元数据，不落盘子进程任意输出或候选文字。

上述回报和助手核对已完成。用户随后完成设置及未提交切换人工复验，并已手动正常重启；本次登录自启动核对通过。14:59 的 7 /（1/6）是较早参考，退出前的其他候选提交改变了排序，当前留样为（1/7），见下文。不需要再次运行预检、注册宿主或立即再重启。保留结果目录，不提供用户正文或候选文字。

## 4. 安装后、本日最小复验

第 1～4 项已完成，第 5 项按实际干预过程分层记录；第 6 项最终日用确认仍待完成。结果仅限下面所述证据范围；发现具体不符就记录该项并停下，不重复覆盖现场。

1. 新安装版 x64/x86 三模式注册宿主回归已经实际执行通过，包括真实焦点路由、延迟取消、失败写入保护及物理候选点击；这仍是自动合成宿主，不是用户 Word/Notepad++ 已通过，不再重复执行。
2. 已完成：用户报告设置显示 7、重开显示 7、实际单页候选数 7，留样 `(1/6)`；补充确认候选数一致，未提交时位置经换算一致。历史页大小 6 与当前 7 下的首页第 6 项均对应总第 6 位，保留旧记录，不据此推断设置改变时点或重启保持。`D2-S-UI-01` 在本次用户所报设置路径的人工复验通过；当前重启前基线采用实际值 7 / `(1/6)`，不改回 6。只记录数值和结果，不提供词、编码或正文。
3. 已完成：用户报告 Word 与 Notepad++ 未提交切换已测，暂未发现异常；`D2-F-01` 在此应用配对的用户所报人工复验通过。验收策略仍为取消未确认组合、不固化原码或自动选字、保留已提交文字并可继续新输入；本次用户没有逐项重述这些布尔结果、模式或次数，不补造覆盖。14:59 元数据确认 Word 加载当前 x64 DLL、Notepad++ 加载当前 x86 DLL，加载本身不等于当前 profile 激活证明。不再要求重复往返，不收截图或正文。
4. 已完成：用户报告正常重启；实际新开机为 15:07:41.500，晚于 14:59 的重启前记录。当前 Runtime 31596 / Broker 31672 的完整映像、启动时间、SID 和父子关系正确，74/74 包文件及双架构 COM 正常，12 项基础保护和 3 项当前产品 TIP 子树不变。独立 StdRegProv/HKU 的完整 Run 命令及 REG_SZ 类型匹配；Shell-Core 9708、RecordId 125135 同 SID/PID，在 Runtime 创建后约 2.506 秒记录启动。该事件 Command 是不含目录、保留尾引号的已知渲染，精确白名单匹配后结合真实完整进程映像与独立完整 Run 形成身份链，不冒称事件自带全路径。本次自启动/重启门槛通过，助手没有重启或启动产品，也未读取 `runtime-status.json`、配置或运行日志。
5. 用户报告重启后候选数正常，按明确前值记录为 7 保持。随后精确更正当前留样为 `(1/7)`，说明退出前把另一个靠后候选连续提交两次，该候选升至 `(1/1)`，原 `(1/6)` 留样顺延为 `(1/7)`；不再将旧 `(1/6)` 当成退出前最终值。当前排序与用户所述调频过程一致，未确认学习丢失。用户对于退出前是否查看的答复先有回忆性限定，之后补充操作顺序，未取得当时单独固定的提交后前值；因此不声称严格无干预留样对照已完成。保留当前 **7 / `(1/7)`** 为后续自然重启的参考，无需立即再重启或重复测试；若有新调频，记录实际最终值即可，不收词或编码。
6. 本日继续按实际方便程度日用；仅报告大致时长及计划外具体异常。D1 历史结果不改写，D2/L5/L6 不因上述源码和构包通过而自动关闭。最终日用确认仍由用户给出。

不扩展生产 Rime/PIME、词库修整、硬件配额、ARM64 安装、冻结旧身份或额外目标；不读取私人文档、观察笔记、用户学习内容或原始输入。
