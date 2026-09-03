# 本机独立开发版 0.1.0-local.7：当前用户 TIP 启用修复候选

当前结果（2026-09-03 16:51）：`local.7` 已从当前工作树完成 native x64 构建、隔离验证和本机原生升级。该候选保留用户更新的秦篆“音”图标，并包含首次安装没有旧用户 TIP 快照时显式写入 DWORD `Enable=1` 的长期修复。

候选目录：`C:\dev\Yime\.tmp\yimecore-local-product\local7-build-20260903-1645\package`

- package ID：`yimecore-local-0.1.0-local.7-7cd3ccfbe999`
- package manifest SHA-256：`0346bbe83eb3dab721e3bd75b14031a604dbdb7fbed041f9021834b7822690bb`
- source manifest SHA-256：`7cd3ccfbe9996d4c9e8ad9e94e9f58cac167c646dab73673e710dc63b0794265`
- 维护器 SHA-256：`4680a94aada563e2fc988529dca27050c5ce43dd7e447577093e2a4a93d721c5`
- 新 profile icon SHA-256：`97f722c6eb439e7a2b7882707a7204b176744dece18b0cd374a33e8eeba12526`

构建结果：生产注册与默认输入法前后快照一致；x64 原生契约通过；Go 核心回归通过；full、variable、shorthand 三个索引各 1,166,753 条，分别两次生成且字节哈希一致；包契约 36 项通过；64 位 TSF composition 和隔离运行时通过。ARM64、x86、旧 x64、其他机器及硬件模拟均未构建、未执行。

固定入口 `Upgrade-YimeCore-Local7.cmd` 已从资源管理器普通用户上下文执行通过。证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local7-native-upgrade-20260903-165044-cbc23e8a`。新安装根为 `yimecore-e6c-efb172e72ec7-0346bbe8`；普通 Runtime/Broker、用户数据、保护注册与冻结载荷均通过，独立系统视图确认活动用户 TIP 升级前后均为 DWORD `Enable=1`。未请求重启。

16:58 的完整卸载重装在卸载间隙被新门禁拦住：语言列表和机器注册已删除，但活动用户 TIP 留下 DWORD `Enable=0` 壳，因此没有继续重装。用户数据、外部恢复介质、生产/冻结注册和默认输入法保留，Runtime/Broker 已停止。证据为 `C:\Users\tsaan\YimeCore Recovery Archives\local7-uninstall-reinstall-20260903-165714-7550706e`。后续修复与恢复候选见 [local.8 记录](YIMECORE_LOCAL_PRODUCT_LOCAL8_2026-09-03.md)。当前 `local_product_ready=false`、`public_release_ready=false`，不请求重启。
