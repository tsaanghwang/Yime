# local.13 健康协议候选：隔离执行与仓外归档（2026-09-08）

受影响产品：YimeCore。新普通候选已从包含 Runtime/Broker 健康协议的干净提交 `e2d9d4222b09c548f978101668940262b895e4fc` 重建；PS5/PS7 各完成两轮真实父子进程健康挑战，随后退出本次测试进程。故障候选已静态派生，未执行。两份候选和公开证据已写入新仓外目录，并成为固定维护输入。当前日用安装仍是 local.12；本轮没有安装、升级、回滚、卸载或操作实际用户状态，L6、local/public readiness 仍为 false。

这推进了 [健康协议源码与观察器](YIMECORE_NATIVE_HEALTH_PROTOCOL_2026-09-08.md) 的候选实测，承接 [上一批 controller/outcome 候选](YIMECORE_LOCAL13_OUTCOME_CANDIDATES_2026-09-08.md)。旧包及旧证据保留历史身份。可机器核对的汇总见 [本轮证据](../testing/l6/2026-09-08-local13-health-candidates.json)。

## 候选与来源

| 项目 | 固定身份 |
| --- | --- |
| 普通包 ID | `yimecore-local-0.1.0-local.13-7f86b4384fef` |
| 普通 manifest SHA256 | `8f7e44ab9097a99d938891b507d0a07b753ffa66dbbec887cb0576286470f2cc` |
| 源码 manifest SHA256 | `7f86b4384fefedf6d7c3e62bff8397757b0ae780f2a58d13876e79b54e6e008f` |
| 普通 Runtime SHA256 | `ee4efa963a130bcea1695aa2a196d5dc5176ed4c69cdcac3baaefa53724c7e0d` |
| Broker SHA256 | `eee55bd1d2e8c2fd73d947541546c4c4950defec704a1288c8ceda647516e69d` |
| 故障包 ID | `yimecore-local-0.1.0-local.13-7f86b4384fef-rollback-failure-0be33f97a652` |
| 故障 manifest SHA256 | `d8cd1338ea2439620f840ef5f43687f15069200f16e1de16b2b6653c9e217161` |
| 故障 Runtime SHA256 | `0be33f97a6527b0adb2a4fa3f3639f4aebbb32ef4d15d7330333443bf8afbaad` |

普通包在 `.tmp/w13h/.tmp/yimecore-local-product/health13/package`，故障包在 `.tmp/yimecore-local13-maintenance-preparation/health-20260908/package`，均各有 85 个列明载荷成员及一份 manifest。818 个 source ZIP 成员的路径、长度和哈希逐项匹配源码清单，工作树补丁为空。该 ZIP 含先前已提交的健康服务与客户端源码；**不含本轮随后新增的健康测试脚本、输入租约硬化及 Catalog 更新**。这些工具用自身哈希另行绑定，不能称已进入候选源码。

故障包仅替换 Runtime 并派生 manifest；controller `9f69d9ab…`、wrapper `ec206153…` 保持原字节。`expected_probe_exit_code=86` 是规格，`probe_exit_observed=false`，没有执行探针来制造回滚验收结果。

## 实际健康回归

新增 `tools/yimecore/test-local-product-health.ps1`，冻结 SHA256 为 `486ddf90f6c9db0edda02aeb03264469be125d2e6626c215accd61702b295e04`。测试只接受固定来源、哈希与完整成员集合的普通 local.13 包；拒绝故障标记、间接路径、ADS 和硬链接。启动前保留包文件与目录句柄，明确不声称由此保护整段执行中的所有瞬时目录成员。

每个 shell 使用新 `.tmp` 状态目录、随机管道及独立的 APPDATA/LOCALAPPDATA/TEMP/TMP/USERPROFILE。只发现自己启动的 Runtime 的直接 Broker 子进程，并核对原始句柄、创建时间、路径、SID、父 PID 与非提升 x64 身份。没有按全局产品名称发现或停止进程。持有原生进程句柄，在每次挑战前后重新核对身份；没有连接普通输入会话管道。

| 实测 | PS5 5.1.26100.9278 | PS7 7.6.5 |
| --- | --- | --- |
| 外层脚本退出码 | 0 | 0 |
| Runtime/Broker 健康挑战 | 各 2 轮通过 | 各 2 轮通过 |
| nonce、管道服务端身份、保留句柄复核 | 全通过 | 全通过 |
| 未完成客户端 IO / 清理错误 | 0 / 0 | 0 / 0 |
| stopper / Runtime / Broker 退出码 | 0 / 0 / 1 | 0 / 0 / 1 |
| 测试脚本强制终止进程 | 否 | 否 |

Broker 的实际退出码 1 如实保留；Runtime 常规停止源码使用 Broker 终止操作，不能据此写成 Broker 自然退出 0。本轮验证真实健康协议响应，未证明引擎 ready、配置已消费、登录自启或真实桌面维护上下文。生产进程租约适配器与 collector 的健康接线仍为 false。

## 仓外封存与输入租约

新归档目录：

```text
C:\Users\tsaan\YimeCore Recovery Archives\local13-health-candidates-20260908-9d59c3b5324f4313921901325effcc79
```

186 项公开输入共 911,194,310 字节，连同 archive manifest/summary 共 188 个文件。除两份包与构建/派生材料，还保存两份健康实测 summary、冻结测试脚本和归档 helper。清单经过源文件逐项复核、保持输入读取句柄、CreateNew 复制、同句柄哈希校验及复制前后成员复核；源文件与旧归档保留。

| 绑定 | SHA256 |
| --- | --- |
| 复制 inventory | `c9f2917d236f5a83501c94f0653ed222bfddd1dea535f9b7499ccbdab7c98441` |
| archive manifest | `19c96df216e8a246e07ca967c3d1e215a058bda2a6708c95f7cc4e29a1ee0b1d` |
| archive summary | `5391b75f5f30dedaf65bfa36b7f3963b6f5cc0acfdeef829d16cc2c9bfa40b69` |

`local13-maintenance-inputs.psm1` 固定绑定上述归档，PS5/PS7 都实际打开并复核 188 个文件、36 个目录，关闭租约后确认释放。类型初始化改为私有随机命名空间及保留的 Type 引用，调用方预装同名全局类型不能充当证据。目录访问改为 `LIST_DIRECTORY | READ_ATTRIBUTES` (`0x81`) 配合 `FILE_SHARE_READ`；空目录的实际重命名在持有句柄时失败，释放后成功。仍保持 `continuous_membership_protection=false`，没有把目录本身不可重命名扩大成子成员连续不变。

两 shell 另通过进程外 `CIM_DataFile` 确认 archive manifest、archive summary 和两个包 manifest 的路径/长度元数据可见。四项观察不证明全部归档的独立内容哈希或文件身份；`independent_content_hash_verified=false`，也不升级既有归档原始记录中的完整原生可见性结论。归档的 `artifact_executed=false` 仅指复制操作；普通包此前确已在隔离测试中执行。

## 验证与待办边界

- 新来源的 speech admission：590 个源文件，499 PASS、0 FAIL、3 SKIP；三个符号链接测试保留跳过结果，未写成通过。
- 新构建：x64/x86 原生契约通过，焦点测试各 32 项通过；包维护契约 37 通过；三模式索引各 1,166,753 条并重复生成一致。隔离 Runtime/Broker、x64/x86 直接 TSF 测试通过，`text_extent_anchor=false` 保持原结果。直接 TSF 不等于已注册真实宿主验收。
- 新健康脚本的 PS5/PS7 纯契约各 65 通过；实际候选健康结果另有两份原始记录。
- 当前维护 CI 的实际 15 脚本步骤以独立 PS5、同进程 PS7 执行，30 份结果全通过；每个 shell 1,510 项，其中输入租约各 59 项、准备阶段各 57 项。
- 双产品源码基线 220 项、纯测试 68 项通过，8 项物理/执行待办保持未关闭。

构建保护检查只读核对已安装公开载荷与必要注册元数据，回归也使用自己创建的临时注册表测试键；不能描述为全轮“零注册表访问”。没有执行安装器、触及 actual user-state 备份/恢复或修改已安装 local.12、生产 Rime/PIME、默认输入法。发布归档不是用户数据恢复介质。

下一步是实际维护编排的原生上下文和完整事务证据：备份、故障升级/回滚、正常升级、卸载/重装及相应 Runtime/注册观察。源码编排已有实现，完整真实事务尚未发生。collector v2 不强制新增健康协议，因为回滚后的旧 local.12 没有该端点；任何新增健康接线必须保留旧版本的诚实兼容边界。DP1 实际完成、DP2 物理矩阵、DP3 安装入口、E7/L6、local/public readiness 均不因本轮结果自动关闭。
