# YimeCore 原生维护观察门禁补齐

2026-09-08，影响产品：YimeCore。回退采集编排升级为 v2，增加延期删除、独立系统文件元数据可见性及 Runtime/config 一致性检查。默认入口仍只生成静态计划；本轮不执行备份、UAC、安装、回退、恢复或卸载，不访问已安装 local.12 的状态、设置、学习和文本，不改变正式 Rime/PIME 或默认输入法。

新检查覆盖备份前、故障控制器启动前和退出后的关键位置。任一必要观察缺失、类型不符、提供程序报错或结果不满足条件，都阻止下一步；原始子进程等待、超时保留普通权限父进程及失败后不自动执行第二次维护的规则不变。`collection_completed` 只表示采集序列完成，不能替代真实维护验收。

已按实际 CI 的 14 脚本编排运行，Windows PowerShell 5.1 和同进程 PowerShell 7 各 **1430 项通过**，共 28 份结果。新增延期删除 201 项、文件可见性 104 项、Runtime/config 72 项，采集编排扩至 170 项。双产品基线为 **198 项源码（191 项声明加 7 项锁定依赖）、68 项合成事务测试通过，8 项待办保留**。这些统计不包括另外单列的原生提供程序夹具。

延期删除模块固定使用两个架构视图的 `StdRegProv`，读取 Session Manager 的 `PendingFileRenameOperations` 和 `PendingFileRenameOperations2`。只有成功枚举基座键，并确认两个值均缺失，才允许该次 `point_in_time_clear=true`。整键不存在、访问拒绝、错误返回码、非字面类型、源目标配对不完整和观察间变化均不能放行。队列端点按源与目标分别检查受保护目录本身、祖先及后代；报告仅保存有序摘要、数量、关系和受保护根索引，不返回无关系统文件路径。

删除操作的目标是空字符串，微软明确记录了此队列对 REG_MULTI_SZ 空字符串约束的例外。[MoveFileExW 文档](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)。因此没有将提供程序返回的“未发现相关条目”当成完整队列认证。只要任一队列值存在，即便捕获结果为空或全部看似无关，本版本仍不放行；`provider_raw_multisz_completeness_verified=false`。两次一致观察也不等于整个维护区间连续没有新增条目。

系统可见性模块将本地原生句柄校验的文件长度与固定 SHA-256，同进程外 `CIM_DataFile` 的单一精确路径/类型/长度结果绑定。编排只查询候选 archive manifest、普通/故障 package manifest 和已验证备份 manifest。提供程序的 CIM 类型、实例、主机、命名空间和属性声明均需匹配；错误时没有进程视图替代。元数据文件名有白名单，不能借此查询学习、设置、任意用户文件或可执行文件。

`system_metadata_visible=true` 仅指这些明确元数据文件的系统提供程序观察成功。WMI 文件大小相等不证明 WMI 独立读取了相同内容，因此 `independent_content_hash_verified`、完整系统可见性验收和维护授权继续为 false。没有通过 Win32_Process.Create 启动其他身份的工作进程。

Runtime 模块在保留的真实进程观察引用上，读取配置前后分别执行原生进程身份复核；同时从同一文件句柄验证 `runtime-config.json` 与完整备份的哈希一致。严格配置解析只接受实际源码生成的固定字段，核对安装根、状态根、Runtime/Broker 路径、管道名和当前产品身份；若含部署映像哈希，必须与被观察的映像一致。输出只包含必要配置元数据，不读取 `runtime-status.json`、布局设置或学习数据。

当前 Broker 协议只有 open/apply/select/forget/reset/close。连接生产管道本身会使用连接配额，已有三模式探测也会创建会话，因此本轮不使用这些操作冒充无副作用健康检查。`context_consistent` 不证明引擎正在响应、进程已经采用该配置、本次回退导致重新启动或重启后的登录启动成功。`runtime_consumed_config_verified`、`readonly_health_protocol_available`、`rollback_restart_verified`、`reboot_logon_startup_verified`、E7 和 Runtime 就绪继续为 false。

编排 v2 仅在全部窄范围观察通过后记录 `deferred_delete_points_clear`、`independent_system_metadata_visible` 和 `runtime_configuration_bound`。`deferred_delete_absence_verified`、`independent_system_visibility_verified`、`independent_data_restore_verified`、`startup_verified`、`runtime_ready_verified`、`rollback_acceptance`、L6/local/public 仍为 false。v1 的来源和证据保留在[上一轮采集记录](YIMECORE_NATIVE_ROLLBACK_COLLECTION_2026-09-08.md)，不重写为 v2 已执行。

具体回归、原生自有夹具和源码哈希见[结构化记录](../testing/l6/2026-09-08-native-maintenance-gates.json)。默认 CI 使用私有提供程序与自有文件；编排用私有替身验证实际顺序和失败边界。可选原生夹具只查询新建 `.tmp` 元数据文件，或在固定 `HKCU\Software\YimeMaintenanceFixtures\<GUID>` 自有键中验证空目标 REG_MULTI_SZ，并清理该键；不读取真实系统延期删除队列或产品注册表。原生夹具结果单列，不能由普通合成检查通过推导。

真实 WMI 自有文件测试发现 COM 集合没有被 PowerShell 的 `foreach` 自动展开，原先拿到的是集合而非文件实例。文件观察器改为严格核对 `Count == 1` 后调用 `ItemIndex(0)`；对象路径核对类、实例、主机、命名空间，Name/FileSize 保留原始 CIM 声明核验。PS5、PS7 都已在本次新建的元数据文件上验证成功。旧失败输出保留，不重写成成功。

注册表原生测试先修复了输入 setter 的显式类型绑定。其后，两版 PowerShell 的原生 API 所创建的原始 REG_MULTI_SZ 自有键仍被独立提供程序报告为不存在（字面返回码 2），因此原始字节完整性夹具没有完成；自有键均已清理。另设独立提供程序创建的同 SID `HKU/<SID>/Software/YimeMaintenanceFixtures/<GUID>` 自有键，在两版 PowerShell 都验证了生产读取器对空初态放行、有值时拒绝，以及包含空目标的四字符串提供程序往返，并完成清理。此夹具清理前要求无子键、只含本次唯一值并与预期内容一致；不满足时保留并报告错误。提供程序创建没有原子新建 disposition，`creation_ownership_authenticated` 也保持 false。往返成功只验证该提供程序接口，不认证进程私有视图与系统视图相同，不证明原始队列字节完整，也不改变“任何队列值存在均不放行”的策略。

尚需取得真实候选/备份的独立原生观察和完整维护窗口证据。响应就绪需要另行实现与实际服务端进程绑定、带新鲜请求响应且不消耗生产会话或连接配额的只读健康协议，现有固定候选不能被重新标成已经包含它。完整恢复、卸载重装、重启登录及宿主验收同样未关闭。Rime/PIME 的可信候选、独立目标、DP1-U 实际事务及 DP2/DP3 保持各自原结论；本轮不重建、不替换既有候选或已安装产品。
