# YimeCore 原生维护准备与公开介质归档

2026-09-08，影响产品：YimeCore；双产品来源闭包同步更新。本轮完成带新控制器的 local.13 故障候选、仓外公开介质归档、只读注册表适配器和原生上下文入口。实际维护事务执行器仍未完成；没有安装、注册、卸载、启动产品或读取用户正文、设置、学习状态。已安装 local.12 及其有效 L5 记录保持原样。完整摘要绑定见 [结构化记录](../testing/l6/2026-09-08-native-maintenance-preparation.json)。

## 准备结果与来源

[prepare-local13-maintenance.ps1](../../tools/yimecore/prepare-local13-maintenance.ps1) 固定普通候选 `yimecore-local-0.1.0-local.13-af06362e5433`、85 成员、描述符、控制器与探针源码哈希。默认 `Plan` 只做静态检查；`Prepare` 在全新仓内目录编译无状态退出 86 探针并复制公开文件。没有调用包内脚本、注册工具或探针 EXE。

独立复核故障包 85/85；普通 manifest 为 `dccbf6f7ef553bda1e20d7b8fa1659fe7e4b691d5d492b8210c9b7c606a7ced4`，故障 manifest 为 `5a9b274b9a3a07f847964bc0871b1ea15c3d4a9447e7fd7e3d86a424c5eea3b5`。成员记录中仅 `bin/YimeCoreTrialRuntime.exe` 改变，包清单另外生成；故障包 ID 为 `yimecore-local-0.1.0-local.13-af06362e5433-rollback-failure-643da92717be`。控制器仍为经过审查的 `e65ea013b5c947c68604bc633e180563a811b856ed6c2aa7b09f3d5c291cd95a`，包含 NativeDesktop 提交前强制回退保护。

准备模块不接受调用者自报的保护开关与任意控制器哈希作为证明。清单与描述符从同一持有流计算摘要并解析；源包成员和探针通过 `FileShare.Read` 租约覆盖复制/复核，私有 Go 源码的租约覆盖编译器运行。输出用 `CreateNew` 和同流大小/哈希复核。后续又补入严格字符串、布尔和架构数组检查，拒绝 JSON 单元素数组冒充身份字段。它们不构成未来产品执行的完整同 SID 边界。

实际准备用模块哈希 `988e484980e192d153d45850c83b938ee767dc210e2ce41fab68e9bc8e33b496`，随后严格类型修复的当前模块为 `621d21591f840d73c79b85a8aa2204987a3c165c9d545da54a82982c29ff4101`。归档保留前者的精确源码，后者单独绑定最新 54 项回归；不重写先前准备记录，也不声称已有工件由后来的源码生成。`expected_probe_exit_code=86` 只是源码预期，`probe_exit_observed=false`。

## 仓外公开介质

新根：`C:\Users\tsaan\YimeCore Recovery Archives\local13-maintenance-candidates-20260908-48e207e2e6f9419183ed823423b5472d`。`archive-manifest.json` SHA-256 为 `e539e75cc4159bdbc4b18daf5fb3d61e3600a6813915f9d59d24dff5239ce900`。

归档包含 182 个公开输入，共 910,652,829 字节：正常包、故障包及各自清单，正常构包来源 ZIP/摘要/补丁，以及故障准备记录、实际使用的准备工具和编译日志。源码 ZIP 内 774 项来源逐项核验。复制期间持有输入租约，检查最终句柄路径及单硬链接，输出全量哈希复核，原始来源和历史归档保留。

`static_outside_repository_copy_verified=true`；尚未从独立 Explorer 原生上下文复读，因此 `independent_native_system_visibility_verified=false`。此归档没有用户状态，不是新鲜备份，也不是实际恢复成功证据。没有改写旧 local.12 归档或旧故障包。

## 只读取证入口及验证

[capture-native-maintenance-registry.ps1](../../tools/yimecore/capture-native-maintenance-registry.ps1) 默认 `Plan` 输出固定目录，不访问产品注册表。`Capture` 首先核对 MYCOMPUTER、原生 x64、64 位 PowerShell、真实 token SID，并持有进程句柄验证同 SID、非提升、非打包祖先链到系统 Explorer；未知/不可访问上下文在目录创建和注册表读取之前失败。合格时调用 [类型保真适配器](YIMECORE_NATIVE_MAINTENANCE_EVIDENCE_2026-09-08.md)，只向仓外新目录写入一个同句柄复核的 JSON 文件。

适配器固定 32/64 两视图共 46 个注册表坐标，使用 out-of-process StdRegProv，不退回进程 HKCU；按类型比较完整值。两遍读数一致不证明原子快照、注册表链接身份或持续保护。入口记录的源码摘要是当时磁盘观察，也不认证已加载代码或授权维护。现有 L6 门禁不会把此观察当成安装/恢复许可。

| 验证 | PS5 | PS7 | 实际范围 |
| --- | --- | --- | --- |
| local.13 准备回归 | 54/54 | 54/54 | 合成包、真实文件租约、严格类型与保护来源拒绝；未运行工件 |
| local.12 兼容回归 | 35/35 | 35/35 | 保持旧默认合同和证据字段 |
| 类型保真注册表适配器 | 85/85 | 85/85 | 每 shell 79 合成检查及 6 个自有随机注册表夹具检查；夹具键已清理 |
| 原生上下文与写出 | 48/48 | 48/48 | 自身进程、合成祖先链及临时输出；正向 Explorer/Capture 为模拟 |
| 默认 Plan | 通过 | 通过 | 合成 SID、46 固定坐标，无产品注册表读取 |

当前 Codex 子进程只做了一次上下文观测，实际返回“拒绝访问”；没有调用 `Capture`，也没有创建原生取证目录。不能把此结果改记为已经证明打包祖先或已经取得原生产品快照。

三组新回归已接入 Windows CI 的 PS5/PS7，CI 默认不运行原生注册表夹具。新鲜双产品来源基线为 168 个声明路径加 7 个锁定依赖，68/68，8 项 pending；它是来源/内存模型检查，不替代 DP1-U 安装验收。

## 下一实施边界

还需完成同 SID 原生维护事务执行器、精确候选/控制器的执行来源约束、进程与每阶段注册/配置/旧根证据、新鲜备份/恢复与数据保护指纹，以及失败后的安全停止和回退证明。原生系统可见性、双架构故障回退、保留数据卸载重装及受影响宿主验收要分别产生实际证据。当前不是只差一次授权或执行。

Rime/PIME 的可信可运行候选、独立目标及 DP1-U 完整事务验收仍未提供/完成，DP2/DP3 继续待定。`execution_authorized`、`ready_to_execute`、`L6_sealed`、`local_product_ready`、`public_release_ready` 均为 false。
