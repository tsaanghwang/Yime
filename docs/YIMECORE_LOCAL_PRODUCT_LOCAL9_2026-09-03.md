# 本机独立开发版 0.1.0-local.9：朱红色 profile 图标

`local.9` 只把 `profile-icon.ico` 从低对比度蓝色改为朱红色，字形透明蒙版、稳定产品身份、用户数据格式、Runtime/Broker、三模式索引和 x64 TSF 代码不变。源图标和包内图标 SHA-256 均为 `04460ff80df7e5aec12a2dff897e18f9192c06de39015d0873035f0c1a9034e`。

候选目录为 `C:\dev\Yime\.tmp\yimecore-local-product\local9-vermilion-20260903\package`，package manifest SHA-256 为 `4a395e073bb58b432c4a35c9446eae5d277234f2e8f8b2e4d66d0ca30c07f262`。native x64 构建、三模式索引双写、36 项包维护契约、包/运行时独立性、Broker 恢复克隆和 64 位 TSF composition 隔离验证通过；构建前后生产/冻结注册和默认输入法快照一致。

2026-09-03 19:03，用户从普通资源管理器运行包内通用 `Install-YimeCore-Local.cmd`。窗口没有保留成功摘要即退出，但只读核验确认原位安装实际成功：活动根为 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-d099576a9d31-4a395e07-20260903190318`，清单和朱红图标哈希与候选一致，Runtime PID 20136、Broker PID 40940 从该根启动，安装态独立性审计通过；独立 `StdRegProv` 确认系统 `IconFile` 指向新根、发起用户 TIP 的 `Enable` 为 DWORD 1。没有 `maintenance-last-error.txt`。

无可见结果是包内 CMD 的交互问题，不是安装失败。工作树通用入口现显示 `PASS` 或 `BLOCKED`、退出码并等待用户确认；脚本化调用显式使用 `/nopause`。因为这是包内字节变化，下一候选描述为 `local.10`，但文件名和维护实现不按版本复制。当前 local.9 不需要仅为提示窗口再次安装。

2026-09-03 19:15 正常重启后，Runtime PID 28368 于 19:16:13 由 Explorer PID 14504 启动，Broker PID 28400 同秒作为其子进程启动；二者映像、`runtime-status.json` 和安装根一致。Shell-Core 9707/9708 对应当前 Runtime，其中 9708 的 PID 和用户 SID 精确匹配。独立 `StdRegProv` 再次确认 Run、x64 COM、profile `IconFile`、当前用户 TIP DWORD `Enable=1`；新身份 WOW64 COM 仍不存在，默认输入法仍为微软拼音。安装根 71 个清单文件和独立性审计通过，Code Integrity、AppLocker、Defender 与 Application 日志未发现本次开机后匹配 Yime 的事件。

用户确认重启后的 profile 图标“已红”，因此朱红图标和登录自启动复核通过。Computer Use 能绑定已打开的 VS Code，但启动 Word 的应用审批超时，窗口/任务栏输入返回未知结果；这单列为自动化限制，不算产品失败。用户随后在重启后新开的 VS Code 中确认组合提交、裸数字继续组字、`Shift+1` 选择第一候选三项通过；只读模块核验确认主进程 PID 4656 加载的是 local.9 根下的 x64 DLL，SHA-256 为 `cf1a0c82072deb4e77ad70059a4553d19b2d75d484686baa95dcf2df8679b42c`，不是跨升级存活的旧 DLL。证据为 `.tmp/yimecore-experiment/local9-post-reboot-20260903/desktop-checks.json`。

local.9 的重启后图标、登录自启动和实际 x64 宿主复核已经关闭；L4 当前候选验收完成。长期日常使用仍需覆盖长文本、应用切换/失焦重入、设置与学习持久化以及实际异常恢复，因此 `local_product_ready=false`；签名及冻结机型继续暂缓，`public_release_ready=false`。
