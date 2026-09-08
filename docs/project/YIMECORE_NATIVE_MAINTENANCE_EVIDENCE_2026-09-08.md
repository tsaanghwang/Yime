# YimeCore 原生维护只读注册表证据适配器

2026-09-08，影响产品：YimeCore；保护范围同时包含历史 YimeCore 身份与生产 Rime/PIME。新增 `tools/yimecore/native-maintenance-evidence.psm1`，供后续同 SID 原生维护演练入口调用。本轮没有读取任何产品系统注册表实值，也没有运行安装器或已安装产品。结果绑定见 [结构化回归记录](../testing/l6/2026-09-08-native-maintenance-evidence.json)。

公开接口只有三个：`Get-YimeCoreNativeMaintenanceRegistryCatalog -TargetUserSid` 返回固定坐标及摘要；`Get-YimeCoreNativeMaintenanceSnapshot -TargetUserSid` 验证当前 token SID，并由真正的 StdRegProv 采集两次完整观察；`Assert-YimeCoreNativeMaintenanceSnapshotEqual -Before -After` 严格验证结构、坐标闭包和摘要，再比较全部值类型、数据与子树。没有公开 provider、脚本块或任意 registry root 参数。

每个 provider 视图固定 23 个坐标，32/64 两视图共 46 个：active `{E40FA752-BB96-461D-A51D-F40EB437EC65}`、frozen `{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}`、production `{35F67E9D-A54D-4177-9697-8B0AB71A9E04}` 的 HKLM/HKU COM 与 TIP 子树；`YimeCoreExperimentalTrial` / `YIME` 的双 hive 卸载键；精确 `YimeCoreExperimentalTrial` / `PIMELauncher` Run 单值；initiating SID 下 User Profile、Keyboard Layout Preload 与 Substitutes 输入法元数据树。User Profile 包括默认输入法 override 元数据。只枚举其他 Run 值的名字与类型以定位目标，不读取其正文或 Run 子树。

原生 provider 强制 `__ProviderArchitecture=32/64` 与 `__RequiredArchitecture=true`，不退回进程 HKCU 或其他 registry view。REG_SZ、REG_BINARY、REG_DWORD、REG_MULTI_SZ、REG_QWORD 使用明确类型与可复核表示，保留多字符串次序、空成员及无符号整数精度。字符串使用严格 UTF-16LE 编码，孤立 surrogate 明确拒绝。WMI DBNull 空字段及带明确 unsigned CIM 类型声明的有符号承载位模式在 provider 边界处理；未声明类型的负数、浮点数、数组伪真值仍然拒绝。

REG_NONE、REG_EXPAND_SZ、REG_LINK 等未支持类型会使整次采集失败，不忽略该值，也不声称完整快照。StdRegProv 没有对应 REG_NONE 保真 getter；其 [GetExpandedStringValue](https://learn.microsoft.com/ja-jp/previous-versions/windows/desktop/regprov/getexpandedstringvalue-method-in-class-stdregprov) 会展开环境变量，不能用展开结果证明原 REG_EXPAND_SZ 内容不变。null 的 binary/multisz 返回也视为不明确，失败关闭；本版本不以空数组冒充无法判定的数据。

PowerShell 5.1 / 7 最终各 85/85 检查通过：79 项模拟/结构回归加 6 项原生随机夹具检查。真正的 StdRegProv 只接触本次创建的 `HKU/<SID>/Software/YimeCoreTests/NativeEvidence-<GUID>`，两视图逐项读回五种支持类型（包含 DWORD/QWORD 最大值）、拒绝 ExpandString，最后经 provider 确认随机键已清理。生产采集接口在这些测试中使用内部模拟 provider；两 shell 的固定目录及模拟快照摘要一致。早期夹具调试失败及 83 项中间结果原样保留，最终证据仅引用 final-v2 文件。

这只是注册表观察适配器。两次读到一致值不证明原子快照或整个维护期间无瞬变，输出明确 `atomic=false`、`continuous_monitoring=false`、`registry_link_identity_verified=false`，并拒绝把最后一项伪装为 true 或字符串。固定 API 坐标也不等于已证明底层 registry key 无符号链接：StdRegProv 可能按系统规则解析键链接，显式枚举到 REG_LINK 时的拒绝不能替代原生不跟随链接的键身份验证。未来演练入口若要以此作为恶意同 SID 重定向边界，仍须补这一层。

模块不验证维护授权、机器身份、unpackaged ancestry、可执行候选信任、运行中进程或用户备份；这些由各自原生入口与 provider 负责。独立比较器是严格结构比较，不是外来 JSON 的真实性认证。实际当前候选恢复/回退/卸载、产品注册表采集与 L6 门禁本轮均未执行，local.12 和其有效 L5 记录保持原样。
