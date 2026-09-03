# 本机独立开发版 0.1.0-local.6：冻结用户 TIP 保护候选

当前结果（2026-09-03 16:38）：local.6 的原生升级、真实记事本五项、实际备份恢复和启动失败回退通过。自身卸载保留数据后从完整包重装的 12:49 摘要遗漏当前用户活动 Profile 的 `Enable` 状态；系统视图复核为 DWORD `Enable=0`，该假 PASS 已撤回。16:29 一次性定向修复把它改为 DWORD 1，任务栏重新出现“音元拼音”，Word 实际选择后加载 local.6 x64 DLL，用户确认组合提交、裸数字和 `Shift+1` 三项全部通过。长期修复尚未构建/安装为新候选，因此卸载重装门禁仍保持未关闭。

## 固定候选

- 构建与证据根：`C:\dev\Yime\.tmp\yimecore-local-product\local6-tip-preservation-rc1`
- package manifest SHA-256：`42e28f7de646d476c64e3ef441a4e60b17acb108f623949e990e8c23d05e2087`
- source manifest SHA-256：`81faeea1a764e7c40da47e4493c2fbf3335aeeb9337cc9cb9168c19ae21bc7b4`
- source snapshot ZIP SHA-256：`8e80d6eae1df61d8f2454d0a762315fcc81e4567285f6c234584a754188b68cf`
- working-tree patch SHA-256：`34e887b8cac340a4d7e13a19fe7681e614ee25c2ce06b9d0bbb8b76d60bece93`
- 包内维护器 SHA-256：`6186fb760686b64411c9f3ad774c0ab814a51bf7b91a1381f7aca9a91398e41a`
- 清单：71 个文件、23 个 PE；只构建/执行原生 x64，冻结目标未构建或执行。

## 已通过

- 注册表保护回归 27 项、源码构建契约 61 项、共享维护契约 53 项；
- 包内维护契约 36 项，包内维护器与当前修复源码逐字节一致；
- 三套索引各 1,166,753 条，独立性审计、动态整句、Broker 恢复和 64 位 TSF 组合通过；
- 固定升级编排最终 20 项契约通过；只读 Plan 确认当前 local.5 基线、目标新根、唯一冻结 x86 引用、同 SID 提权和普通用户运行要求；
- 当前安装、注册表、用户数据、默认输入法和运行进程均未因构建或计划检查而改变。

## 原生升级结果

证据：`C:\Users\tsaan\YimeCore Recovery Archives\local6-native-upgrade-20260903-103612-c5cb67ff`。

升级命令成功，新安装根为 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-42e28f7d`，manifest 与固定候选一致。新旧包独立审计、升级前停写备份、安装后三模式、用户数据连续性、语言列表逐结构一致、生产/冻结注册、无关 Run 值和冻结 x86 payload 均通过。Runtime PID 33292、Broker PID 5724 来自新根，属于目标 SID 的非提权中完整性主令牌。未重复身份迁移、未修改默认输入法、未重启。

本次关闭 local.6 原生升级门禁；自身卸载重装门禁因任务栏不可见重新打开。当前 `local_product_ready=false`、`public_release_ready=false`。

## 安装态 registered-host 回归

安装根中的 x64 DLL 和新 CLSID 注册路径一致。三模式 registered-host 回归均通过，证据为 `.tmp/yimecore-experiment/local6-installed-registered-host-r2-20260903/summary.json`；覆盖候选提交、Shift 候选键、英文 Shift 透传、延迟异步写入、失败写入恢复，以及停用后保留语言栏对象。测试使用隔离设置和 Broker，没有改变注册。

首次自动运行曾在 `registered TIP did not become foreground` 停止；未发生输入写入。紧接着的同二进制诊断完整通过，正式三模式重试也通过，因此记录为前台焦点竞争，不作为产品阻塞。它不能替代 Word/记事本中实际选择“音元拼音”的物理宿主验收。

## 真实记事本宿主

用户在新记事本中实际选择“音元拼音”，并确认约定的五项测试未见异常：`tf-cN` 加空格提交“它们”、裸数字保持组合、`Shift+1` 选择首候选、语言栏左键与右键操作后宿主保持运行。只读捕获确认 Notepad PID 2796 加载的是 local.6 安装根 x64 DLL，manifest 为 `42e28f7d…e2087`；同一进程的左键、右键打开和右键命令事件 `HRESULT=0`。

证据为 `.tmp/yimecore-experiment/local6-notepad-live-20260903/desktop-checks.json` 与同目录 `live-host.json`。未导出用户全文，未改变默认输入法。Word 仍需单独复测，因此不把此项写成全部真实宿主验收完成。

## 新鲜备份与实际恢复

local.6 已从安装包入口完成一次停写备份及数据实际恢复，证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local6-backup-restore-20260903-110006-133432a3`。6 类数据恢复后逐哈希一致，恢复前模型与设置分别保留在归档中；离线 journal 恢复、安装后三模式和普通 Runtime/Broker 通过。前后完整系统注册快照一致，没有请求注册表变更、默认输入法变更或重启。

## 启动失败升级回退

local.6 已使用严格清单覆盖、仅将 Runtime 改为退出码 86 的故障包完成一次真实升级失败回退。最终纠正证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local6-failed-upgrade-rollback-20260903-110721-19d95018\corrected-postacceptance.json`，时间为 11:25；原始失败 `summary.json` 保留，没有重演故障。

安装器权威错误记录确认新 Runtime 在 15 秒内未就绪。事务回退后，活动根仍为 manifest `42e28f7d…e2087` 的 local.6，故障目标根不存在；完整系统注册快照、6 项用户数据路径/大小/SHA-256、独立恢复介质均保持一致。Runtime PID 8120 与 Broker PID 31944 来自恢复后的 local.6 根，均属于目标 SID 的普通用户中完整性主令牌；包独立性审计通过。未改变默认输入法、生产组件或冻结载荷，未请求重启。

首次外层验收因 UAC 子进程没有把维护错误转发到父进程 stdout/stderr 而形成假阴性；纠正验收改用带时间和故障包路径关联的 `maintenance-last-error.txt`。随后又发现 Windows PowerShell 5.1 对顶层 JSON 数组的单层包装会让相同的 6 条记录被误报为 `1` 对 `6`；仓库纠正脚本改为两步展开，26 项回退契约通过。数据新鲜度保护没有放宽，也没有用旧备份覆盖当前数据。

## 自身卸载保留数据及完整包重装

证据：`C:\Users\tsaan\YimeCore Recovery Archives\local6-uninstall-reinstall-20260903-121508-ef668e62`，最终完成时间 12:49。新鲜停写备份包含 86 项状态文件、73 项旧包文件和 6 类用户数据；候选、仓库外 `reinstall-package` 与重装后的安装根均通过独立性审计，manifest 均为 `42e28f7d…e2087`。这些子项仍有效，但原 `passed=true` 不再代表完整的任务栏可用性门禁。

卸载间隙确认活动 x64 COM/TIP、Run、卸载项、Runtime/Broker、活动配置和旧安装根均已消失，6 类用户数据未变。卸载触发 `Set-WinUserLanguageList` 后，冻结用户 TIP 再次按卸载前完整系统快照恢复；之后从新鲜备份中按 manifest 复制出的完整仓库外包走首装入口。重装后完整系统注册快照除允许的安装根替换外一致，生产组件、冻结目标、默认输入法及用户数据不变；Runtime PID 40924、Broker PID 21192 均为目标 SID 的普通用户中完整性主令牌，三模式 Verify 通过。未清除数据、未执行冻结目标、未请求重启。

原始编排在卸载已实际成功后，因为从被删除的安装根启动维护 CMD 而收到误导性的退出码 1；`failure.json` 保留该事实。固定完成入口先核验活动注册、进程、配置和旧根确已消失，再恢复冻结用户 TIP 并从已经创建和审计的独立包完成重装。通用编排随后改为始终从保留介质启动卸载，46 项专项契约和 54 项共享维护契约在 Windows PowerShell 5.1 下通过。没有重演卸载。这些契约此前只保护冻结旧用户 TIP，没有要求首次安装后的新用户 TIP 为 `Enable=1`，属于测试缺口。

16:26 只读复核确认：`Get-WinUserLanguageList` 含新 TIP；x64 注册工具 `status` 报告 COM/Profile 与 5 个类别正常；Runtime/Broker 来自 local.6；机器级 Profile 为 `Enable=1`，但 `HKEY_USERS\<SID>\Software\Microsoft\CTF\TIP\{E40F…}\LanguageProfile\0x00000804\{126F…}\Enable` 为 DWORD 0。这一用户级覆盖直接解释了任务栏缺项。

源码先加入失败回归，再修复共享安装器：若已有用户 TIP 快照则原样恢复；仅在首次安装/完整卸载后重装、旧快照不存在时显式写入 DWORD `Enable=1`。一次性 `Repair-YimeCore-Local6-Taskbar.cmd` 仅用于把当前精确故障从 0 改为 1，并保护语言列表、默认输入法、生产/冻结注册、用户数据和运行进程；15 项修复契约、用户 TIP 回归和 54 项共享维护契约通过。

原生修复归档为 `C:\Users\tsaan\YimeCore Recovery Archives\local6-active-user-tip-repair-20260903-162926-d955dffc`，其独立系统视图确认 `Enable` 从 DWORD 0 变为 1，其余活动用户 TIP 内容、完整保护快照、默认输入法、语言列表、生产组件和普通 Runtime/Broker 不变。用户随后从任务栏选择“音元拼音”，Word PID 19212 加载 `yimecore-e6c-4bfa828009d1-42e28f7d\x64\YimeTextServiceExperiment.dll`；`tf-cN` 加空格提交、裸数字组合及 `Shift+1` 首候选选择全部通过。证据为 `.tmp/yimecore-experiment/local6-word-after-taskbar-repair-20260903/desktop-checks.json` 与 `live-host.json`，未导出文档正文。

当前机器可继续宿主验收，但一次性修复不替代安装包修复。下一步构建并安装含长期修复的新候选，再重验完整卸载重装；浏览器、开发工具、日常使用确认和最终登录自启动仍待完成。`local_product_ready=false`、`public_release_ready=false`。
