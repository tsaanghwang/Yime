# 本机独立开发版 0.1.0-local.4：注册保护修复与原生升级

当前结果（2026-09-03 08:56）：`0.1.0-local.4` 已安装到本机原生 x64 环境，并完成纠正后的原生安装后验收。生产 Rime/PIME、默认输入法及冻结 x86 注册未改；未重启，未执行 Word 实机切换、实际备份恢复、故障升级回退或自身卸载重装，因此 `local_product_ready=false`、`public_release_ready=false`。

身份补充：活动 x64 和冻结 WOW64 使用同一 CLSID/Profile，Windows 在本机把两视图的 Profile 元数据同步为同一旧值。为遵守冻结注册保护，当前任务栏输入法选择名称仍是“Yime 自研栈试验版”，没有达到描述文件中的“Yime 独立开发版”身份契约。证据为同一归档下 `profile-identity-observation.json`，SHA-256 `170f543e47066ee90b7ff354853f6a97527e77f1dc41785e39171c7aa8f2d11c`。修复需要新 CLSID/Profile 迁移或解除冻结注册，必须由用户明确选择；本轮不擅自执行。

## 当前安装

- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-324e46fc`
- package manifest SHA-256：`324e46fc5c930d79de713b1fe8d4a0c7cefa884c88b25721dec50cb3c2ed4431`
- source manifest SHA-256：`87168aada17fcb1e93216c25c5cafc117e2b48b12f1c64652fa6d801f35bc01d`
- source snapshot ZIP SHA-256：`6f8f647e75de1f6e891760426efff36e2ce25e57f98a9d585e2c98152661f5f3`
- 包内安装管理器 SHA-256：`f51962d6218977ed0e7d46a7ce7e4c0c6a06a1bbf3f0f40f1eeb3f2af36ce3e3`
- 构建证据：`.tmp/yimecore-local-product/20260903-local4-registry-safe-r4/`

构建只覆盖当前开发机原生 x64。三种索引各 `1,166,753` 条，原生合同、Broker、动态句、TSF 64 位组合和包内维护测试通过；未构建或执行 x86/ARM64。

## 本次发现并修复的问题

1. local.3 安装器用 `New-Item -Force` 确保共享 Run 键存在，实际会删除 OneDrive 等同级值；已改成只在缺失时创建，并加入真实临时注册键回归。
2. x64 TSF 注册 API 会改写冻结 WOW64 Profile 的 Description/IconFile；现在在注册/反注册边界快照并原位恢复完整冻结子树及值类型。
3. 新候选的升级前备份错误地把候选包当成已安装包校验；现在显式传入并使用 manifest 验证过的当前安装根完成停写和重启。
4. 冻结 x86 使共享 Profile/Category 在 x64 COM 注销后仍存在。原逻辑继续调用全新 `register`，得到 `0x800700B7`；现在精确完整状态使用 `repoint`，完全缺失状态才用 `register`，混合状态拒绝。
5. 原生验收错误地把“立即前一活动包”当作冻结根，导致安装成功后因正常删除 local.3 而误报失败。现在从 Plan 的冻结引用枚举实际历史根，逐文件验证清单哈希，并只允许清单自身与安装元数据两个额外文件。

## 现场恢复与最终证据

第二次尝试暴露 `0x800700B7` 后，安装器回滚也失败并暂时清除了 local.3 的运行配置和活动 x64 COM。旧包与预安装备份保持完整，固定哈希恢复脚本仅恢复 local.3 的 x64 COM、用户 TIP、Run/卸载元数据、运行配置和普通用户 Runtime/Broker；恢复通过：

`C:\Users\tsaan\YimeCore Recovery Archives\local3-failed-upgrade-recovery-20260903-084519-8462df75`

Edge 在故障后并发新增一个自启动值，恢复流程没有删除或覆盖它，证据中单独记录。随后 r4 安装命令成功；原验收在错误的旧根断言处误报失败，原摘要按要求保留。纠正后验收通过：

`C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-085024-6b3929c6\corrected-postacceptance.json`

该证据确认：已安装 manifest/版本匹配；Runtime/Broker 为同一用户普通主令牌；三模式与动态句验证通过；用户数据与升级前一致；生产、冻结、用户 TIP、默认输入法和无关 Run 保护快照一致；实际冻结根 `yimecore-e6c-45b389e530c0-8d48953a` 的清单负载逐哈希一致。local.3 根不是冻结引用，成功切换后删除符合合同。

## 尚未关闭

- 在用户明确选择“Yime 独立开发版”后做 Word 或其它真实宿主验收；不修改默认输入法。
- 决定独立版身份方案：推荐迁移到新 CLSID/Profile，以继续原样保留冻结 x86 注册；未批准前保留当前旧选择名称。
- 用 local.4 自身维护入口执行一次新鲜备份/恢复演练、故障升级回退和卸载保留数据重装。
- 后续正常重启后核验 StdRegProv 可见自启动、Shell-Core 登录启动证据和当前 PID/映像/启动时间。
- 工作区仍有未提交修改；签名和冻结架构继续不是本阶段阻塞，但也不能标记通过。
