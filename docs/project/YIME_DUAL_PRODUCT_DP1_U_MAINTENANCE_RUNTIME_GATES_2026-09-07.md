# DP1-U：注册、回滚、卸载与 Runtime 门禁

2026-09-08 补修：原门禁遇到缺失 `schema_version`、保护字段或空值时，会在返回拒绝结果之前抛出异常。新增负例先复现这两类失败，再修复对象形状检查及安全属性读取；PS5／PS7 现各 14/14 组通过，包括逐字段缺失、全部布尔字段错误类型、null／数组／标量／字典拒绝。完整合法 v1 输入的语义保持不变；本函数仍只是调用方提供证据的纯判定，不认证观测来源或赋予执行能力。原 11/11 收据保持历史原义，新增结果见 [字段拒绝回归](../testing/dual-product/2026-09-08-dp1-u-gate-shape.json)。

影响产品：独立 Rime/PIME 产品。本阶段完成四类门禁的统一失败关闭准入、PS5／PS7 回归和当前证据审查。依照本轮约束，没有运行安装器、卸载器、注册工具或已安装 Runtime，因此完成的是门禁实现，四类 installed acceptance 仍保持关闭。

## 结果

- 统一证据 schema 与纯准入函数：**完成**。
- 注册、回滚、精确卸载、Runtime 四类字段的逐项失败关闭回归：**PS5／PS7 各 11/11**。
- DP1-T actual canonical receipt 与七组既有源码／夹具结果的双 shell 汇总审查：**通过**。
- `source_contract_ready=true`，`dp1_u_gate_implementation_complete=true`。
- `registration_gate_passed=false`、`rollback_gate_passed=false`、`removal_gate_passed=false`、`runtime_gate_passed=false`、`dp1_u_acceptance_passed=false`。
- `hardware_power_loss_verified=false`、`directory_metadata_durability_verified=false`、hostile same-SID physical prevention 继续未证明。

实现提交为 `c4d9fb45c106b4a45ba2dd60aaacfbac8e1bfaf6`，tree 为 `9c844386a41dc18256fe66be8b4d7c9cf9f11c40`。[结构化证据](../testing/dual-product/2026-09-07-dp1-u-maintenance-runtime-gates.json)绑定本次输入和 non-claims。

## 门禁边界

`rime-pime-dp1u-maintenance-runtime-gate.psm1` 只导出 `Test-RimePimeDp1UMaintenanceRuntimeGate`，导入和调用都不执行文件维护、注册表、进程、安装器或卸载器操作。输入字段集合、顺序和布尔类型必须精确匹配；未知字段、未来 schema、错误产品或字符串化布尔值都会失败关闭。

四个门分别要求：

1. 注册：实际 probe 已执行，x86／x64 收敛，目标 SID 正确，另一产品注册不变。
2. 回滚：实际回滚执行，全部维度恢复，持久 journal 重放和进程崩溃恢复成立，另一产品与默认输入法不变。
3. 卸载：实际 uninstaller 执行，精确 manifest removal，并发替换已排除，外来内容保留，卸载后注册缺席。
4. Runtime：实际运行，非提升、目标 SID、当前映像、Launcher 与 backend readiness 均成立，而且不需要 YimeCore。

任何触碰 installed YimeCore local.12、生产用户数据或默认输入法的证据都会使源码准入失败。物理断电与目录 metadata 字段在当前 schema 中必须保持 false；误写为 true 时最终 DP1-U acceptance 同样拒绝。

## 当前证据汇总

| 检查 | PS5 | PS7 |
| --- | --- | --- |
| DP1-U 门禁真值表 | 11/11；`3ac9ebc3d074cf0e492fa8d7e9bdfec546d515c082b605c8f909e845abe07b88` | 11/11；`37fdec60d412fb4fb719abea04cc66a0c674869013758a2527a8602e8f3d5313` |
| 当前就绪审查 | source ready；`7a13d7cd07fcfcc66c0d233c5ef76c229edcdf101ad9486b8472d1a118ecc36c` | source ready；`4595e99c96f1eb2fe6192a63308f53210eb62dbcfca3e903f900506f4ac48658` |
| 注册所有权 | 22/22；`03ecf271c344a4beab3735259b36320a760f575fcf2abacb4f5467badbf76430` | 22/22；`91f1a18ca986f599b3517ba67ef281170d20f4979dae49e90f7b76c1bbf34567` |
| 注册完整性 | 36/36；`85bfde6c99f9c8efd9a3a7cdaf94b3c2ee51ae432aee44bb48696ed04ef7253a` | 36/36；`66637c91bfdb8312ea1b3d91eb94e94f3854b24355afb9f97292992ed479c601` |
| native 用户清理 | 12/12；`75a33fc41e4c93c22a57cb577fe203235e7eacb44b6f3093e3a959a86072ffcf` | 12/12；`6ec07cf30d873d1c25da25f56f98d843f057a4ff26a55a047cbbfdd013df8054` |
| 事务故障矩阵 | 9/9；`9a23d68c1d8c1382ac74a2b2e9e1539c18e1649ee2e7903c87fec2b9ec9d567d` | 9/9；`89f339703474880ce862d4cffb3df74f02c76dd7229695298142fda4bf89061a` |
| 事务隔离 | 52/52；`76190b8cd2d0dcb0ae07e79a9873988505bd231424df2ba37daf986b82bff8de` | 52/52；`b4507f5b3292f79031a8575b89b6ad8121980670906c5b63b91e9911164703c6` |
| fixture journal | 114/114；`e76a25f2cd22aa48e200f4b3f5480189a4fb9acaac1030d9113674af9a44a3f3` | 114/114；`035b6ce97d4374730fc2bccbe8f37df8feb1bd50d773c89dac49a289025742bd` |
| maintenance | 16/16；`757f0e8b1fd773b0a4a6bb413d93b7a76b59e35f990758f42ed1add902e00953` | 16/16；`81068b79bbe68dd3d5d262e8f265acffd273ec16193c2fadabd1fdcb77a5ee30` |

当前源码基线为 157 个来源、68/68 tests、8 个诚实 pending，SHA-256 `3a9b743339223e7932a5da4eca2f97e65db091099ba9daff4cf55b5c2e69313ff`。DP1-T canonical receipt SHA-256 仍为 `f1b67aa40d0fce85244e00656f6017b4e9e8c313eed538f596da5fd9ba312719`。

## 剩余边界

当前审查用实际 DP1-T canonical 迁移证据证明输入工件身份，用源码扫描和隔离夹具证明门禁接线；它没有把合成结果升级成 installed evidence。要令四类门为 true，仍需在明确获准的隔离目标执行真实安装、注册、失败回滚、卸载和非提升 Runtime 检查。ARM64 原生注册与 Runtime 也须在 ARM64 目标单独取证。

本阶段没有执行安装器或卸载器，没有读取或修改注册表、产品进程、生产用户数据、默认输入法或 YimeCore local.12。DP1、DP2、DP3、L5 与 L6 仍未完成。
