# 本机独立开发版 0.1.0-local.8：卸载残留 TIP 修复与恢复候选

当前结果（2026-09-03 17:12）：`local.7` 完整卸载重装门禁在卸载间隙发现 DWORD `Enable=0` 残留并正确停止；固定 `local.8` 恢复随后通过。活动安装根现为 `yimecore-e6c-efb172e72ec7-0354fd33`，用户数据、外部恢复介质、生产/冻结注册和默认输入法保留，普通 Runtime/Broker 与三模式通过，独立系统视图确认活动用户 TIP 从 DWORD 0 恢复为 1。

失败证据：`C:\Users\tsaan\YimeCore Recovery Archives\local7-uninstall-reinstall-20260903-165714-7550706e`。其中 `active-user-tip-uninstalled.json` 固定了 `Enable=0` 残留，`preuninstall-backup` 保留完整 local.7 包、状态和 6 类用户数据。

根因不是单纯的任务栏刷新：`Set-WinUserLanguageList` 在删除 TIP 后留下禁用壳；原安装器只判断用户 TIP 子树是否存在，因此卸载后的首次安装会把该壳误当成真实升级快照并恢复为 0。

`local.8` 同时修复两侧：完成卸载时显式删除当前产品的用户 TIP 子树；安装时只有存在真实旧安装根才允许恢复用户 TIP 快照，否则必须显式创建 DWORD `Enable=1`。回滚仍保存和恢复原完整子树及值类型。相关临时注册表回归、54 项维护契约和 55 项原生安装契约通过。

候选目录：`C:\dev\Yime\.tmp\yimecore-local-product\local8-build-20260903-1705\package`

- package manifest SHA-256：`0354fd33fcae9171004ecd7c9a33f2e56bcf27c2cc99e58fbf857bc67e8e1fc2`
- 维护器 SHA-256：`70d6c04c85d35d018c69510b7158198f13d08efb1d12dffb707972d3e762d4df`
- 目标安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-efb172e72ec7-0354fd33`

native x64 构建、三模式双写索引、包/运行时独立性、64 位 TSF composition 全部通过，构建前后系统保护快照一致。ARM64、x86、旧 x64、其他机器及硬件模拟未构建、未执行。

一次性恢复入口 `Recover-YimeCore-Local8.cmd` 已通过。证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local8-recovery-from-local7-20260903-171149-7b5120c2`。它固定上述失败归档、local.7 恢复介质与 local.8 清单；写入前确认精确的已卸载状态和 `Enable=0` 残留，安装后确认 DWORD `Enable=1`、语言列表、产品注册、普通 Runtime/Broker、三模式、生产/默认保护和冻结载荷全部通过。

用户已确认恢复后的任务栏输入法列表显示“音元拼音”。随后 local.8 自身完整卸载重装通过：卸载间隙的活动用户 TIP 子树为不存在，重装后完整恢复为 DWORD `Enable=1`；6 类用户数据、生产/冻结注册、默认输入法、恢复介质、普通 Runtime/Broker、三模式和包审计均通过。证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local8-uninstall-reinstall-20260903-171745-7fffaaf1`。用户再次确认重装后的任务栏仍显示“音元拼音”，记录为 `.tmp/yimecore-experiment/local8-taskbar-after-uninstall-reinstall-20260903/desktop-checks.json`。随后安装态 x64 registered-host 的 full、variable、shorthand 三模式全部通过，证据为 `.tmp/yimecore-experiment/local8-installed-host-after-reinstall-20260903/summary.json`。用户又在 Word PID 20664 中从任务栏实际选择“音元拼音”，确认组合空格提交、裸数字继续组字、`Shift+1` 选首候选全部通过；只读模块核验确认加载的是重装后 local.8 根的 x64 DLL，证据为 `.tmp/yimecore-experiment/local8-word-after-uninstall-reinstall-20260903/desktop-checks.json`。

浏览器/开发工具首轮中，用户确认 Microsoft Edge 与 VS Code 的三项输入行为均通过。只读模块核验确认 Edge PID 30076 加载 local.8 x64 DLL，因此浏览器宿主可计入通过；VS Code PID 35852 仍加载跨升级存活的 local.6 DLL，因此首轮行为不能作为 local.8 开发工具验收。证据为 `.tmp/yimecore-experiment/local8-edge-vscode-hosts-20260903/desktop-checks.json`。用户随后完全退出并重开 VS Code，再次确认三项输入行为通过；只读模块核验确认新进程 PID 11440 加载 `yimecore-e6c-efb172e72ec7-0354fd33-20260903171828\x64\YimeTextServiceExperiment.dll`，开发工具门禁关闭。当前卸载重装、任务栏缺项、Word、浏览器和开发工具门禁已关闭；日常使用和登录启动仍待完成。`local_product_ready=false`、`public_release_ready=false`，不请求重启。
