# DP1-U：隔离目标授权与执行前合同

影响产品：独立 Rime/PIME 的未来隔离 package lane；YimeCore 是必须保留边界的另一产品。此次仅新增纯输入校验、JSON evidence schema、合成夹具和文档。没有选择或批准真实目标，没有接入安装器、卸载器、注册工具或 Runtime。既有 DP1-U 执行后门禁与历史收据保持原义。

## 新增入口和证据

- [纯校验模块](../../tools/dual-product/rime-pime-dp1u-isolated-preflight.psm1)：唯一导出 `Test-RimePimeDp1UIsolatedPreflight`。
- [输入 schema](../../tools/dual-product/rime-pime-dp1u-isolated-preflight.schema.json)：精确字段、类型、常量和标识格式，所有对象拒绝未知或缺失字段。JSON 属性顺序不影响准入；schema 中 `required` 的顺序定义摘要规范。
- [合成输入](../../tools/dual-product/fixtures/dp1u-isolated-preflight.synthetic.json)：机器、SID、审批人、摘要及全部观测均为虚构，只用于正负例，**不是审批记录或真实探测结果**。
- [PS5／PS7 夹具](../../tools/dual-product/test-rime-pime-dp1u-isolated-preflight.ps1)：仅读取上述源码／fixture，写入全新 `.tmp/dual-product/dp1-u-preflight-test-*` 结果目录。
- [本批结构化证据](../testing/dual-product/2026-09-08-dp1-u-isolated-preflight.json)。

## 分离的审批和观测合同

调用者必须分别提供 `Evidence`、`TrustedApprovalSha256`、`NowUtc`，没有机器名、SID、目录、时间或许可的环境回退。缺参或格式错误返回拒绝原因。模块仅读取自己的 schema，不查注册表、不枚举产品进程、不探测当前机器、不执行提升、安装、卸载或文件维护。

`Evidence.authorization` 包含单次计划的 `run_id`、独立审批引用与审批人、批准与到期 UTC、目标机器名和稳定机器 GUID、发起用户 SID、安装／状态／恢复根、精确 package／canonical receipt 摘要、产品边界摘要及允许的四种证据操作。审批最长 24 小时；观察必须在批准之后、不在未来且至多 5 分钟前。传入的 `NowUtc` 必须来自未来可信调用方的实时 UTC，不能使用申请人指定的历史时间。

`TrustedApprovalSha256` 必须来自**独立审阅后单独保存的审批记录**，不能从待执行申请自动计算后作为批准，也不能由脚本自批。它绑定授权对象全部字段，包括产品边界摘要。本文和用户授权本轮写源码的指令均不是未来目标批准。审批标识、摘要和观察对象可由任意调用者伪造；纯合同校验无法认证审批人或观察来源，所以通过时仅返回 `supplied_contract_valid=true`，**始终返回 `execution_authorized=false`、`native_target_verified=false`**。没有执行 token、Apply、Resume 或解除包阻断的接口。单次 `run_id` 只是绑定标识，本模块没有持久消费／防重放存储。

摘要算法：授权使用 ASCII 域前缀 `dp1u-authorization-v1;`，产品边界使用 `dp1u-product-boundary-v1;`；按相应 schema 的 `required` 顺序拼接每个标量为 `字段名:UTF8字节长度:值;`，布尔值为小写 `true`／`false`，再计算 UTF-8 SHA-256 小写十六进制。不对字符串隐式改大小写、去空白或转换日期。夹具包含由独立 Python 计算的固定授权摘要，两个 shell 都须匹配。未来正式审批应保存可审阅的原始对象及该规范摘要；摘要不是数字签名。

`Evidence.product_boundary` 明确列出本产品的安装／状态／恢复根，另一产品的对应根，生产 Rime/PIME 的保护根，以及两产品的 CLSID、Profile GUID、Runtime endpoint、Run 值名和卸载子键名。授权与观察中的目录必须与本边界对象精确一致，边界内容必须符合已批准摘要。所有根拒绝相等、大小写别名和目录祖先／后代重叠；GUID 互异，端点和对应注册表名称互异。Run 值限定在发起 SID 的标准 `Software\Microsoft\Windows\CurrentVersion\Run`，卸载项限定为已声明名称的 `Software\Microsoft\Windows\CurrentVersion\Uninstall` 子键；COM/Profile 仅限声明 GUID。本对象不是向任意注册表路径写入的授权。

## 失败关闭边界

1. 拒绝 `MYCOMPUTER`（含大小写变体），也拒绝任何目标存在 YimeCore local.12 或生产 Rime/PIME。当前只能声明已识别、可用的独立 mainstream Windows x64 目标和当前 `x86,x64` package。x86 是 WOW64 应用；ARM64 必须另建原生包与证据合同，不能借用本合同。未授权购置、云资源或任何新目标配置。
2. 明确禁止生产用户数据、默认输入法变更、跨产品维护、共享 Runtime／可写状态以及历史载荷执行。另一产品的注册快照、生产注册保护快照与默认输入法快照必须独立绑定；不能通过把生产程序改名或把其状态目录写成隔离目录来满足边界。
3. 发起、当前调用进程、未来提升 worker 与非提升 Runtime 必须属于同一 SID；观察中的 HKU 必须精确为 `HKEY_USERS\<initiating_sid>`。不能只凭 worker 的 HKCU 推导发起用户。
4. 当前进程无 package identity **且**祖先链完整、没有 packaged ancestor，入口为 Explorer 独立启动的未打包 PowerShell。只知道子进程 `APPMODEL_ERROR_NO_PACKAGE` 不够；未知、缺失、打包祖先或其他入口都拒绝。
5. 注册观察必须使用进程外 `StdRegProv`，明确 `Registry32,Registry64`、正确 HKU、成功且无歧义的双视图、无 COM shadow、保留值类型；provider 错误或回退进程视图都拒绝。两个进程内视图一致不能代替系统可见证据。
6. 本产品根必须为规范本地盘符绝对路径；拒绝 UNC／device path、环境变量、相对路径、ADS、点段、尾点／空白、重复分隔符、短名和保留设备名。安装／状态／恢复根不准位于 AppData、Windows 或 Program Files；保护根可以位于这些系统位置。词法检查不能证明不存在 junction、挂载别名或并发替换，另要求未来原生系统可见性与 alias／reparse 排除证据。恢复材料还必须在 AppData 和所有 Git worktree 之外。
7. 静态 payload integrity、严格 receipt／package 身份及独立执行安全审查都是必需观察字段。当前 disabled／unsigned 候选和安装器早期硬阻断未改变；填 `true` 不代表本次取得了这些事实，也不能运行该候选。

## 未来实际运行的交接要求

未来另行批准的执行适配器必须先独立验证审批来源、实时目标机器身份、完整进程祖先链、SID、系统注册视图、文件系统身份和精确源码产品标识；按实际 package manifest 验证整个边界对象，不能信任调用方自报布尔值。原生阶段尚未实现。本合同不替代 DP1-T strict receipt、静态载荷完整性或注册保护检查。

将批准对象及摘要、完整 preflight evidence 的原始字节摘要、schema／校验模块摘要和实际观察附件一起持久保存到批准的系统可见恢复根。注册、失败回滚、精确 removal、非提升 Runtime 的每份实际证据都必须引用同一 `run_id`、目标机器 GUID、发起 SID、产品边界／package／receipt 摘要及 preflight 原始证据摘要。每次跨提升、重启、重放或维护阶段都要重新检查当前上下文与审批有效期；不能复用五分钟前的观察或把 fixture receipt 提升为原生证明。防重放、审批撤销、真实探测及维护适配器仍是后续工作。

执行后的实际结果再交给既有 [DP1-U 四门合同](YIME_DUAL_PRODUCT_DP1_U_MAINTENANCE_RUNTIME_GATES_2026-09-07.md)，分别证明注册、回滚、移除和 Runtime。旧门禁不读取本合同；本轮没有把二者接为执行链，也不更改旧 evidence schema 或历史结果。单装、两种共存安装顺序、各自恢复、重启和 ARM64 原生矩阵仍独立待验收。

## 夹具结果与复现

PS5／PS7 各 **246/246** 通过：逐字段缺失／错误类型／常量篡改、未知 schema／字段、审批摘要与对象错配、目标／SID／root／artifact 替换、MYCOMPUTER、超期／未来／陈旧观察、危险路径、跨产品目录／身份／端点重叠及不提升 installed 门禁。初轮发现测试函数形参遮蔽循环字段名，以及 PS7 的 JSON 日期自动转换；已在测试工具内修复并保留初轮失败结果，未放宽生产合同的字符串类型要求。PS7 读取输入应使用可用的 `ConvertFrom-Json -DateKind String`，较旧版本的可信读取器须显式保留规范 UTC 字符串。

从仓库根目录分别运行（两个命令仅执行 fixture 测试）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/dual-product/test-rime-pime-dp1u-isolated-preflight.ps1 -OutputRoot (Join-Path $pwd ('.tmp/dual-product/dp1-u-preflight-test-ps5-' + [Guid]::NewGuid().ToString('N')))
pwsh.exe -NoProfile -File tools/dual-product/test-rime-pime-dp1u-isolated-preflight.ps1 -OutputRoot (Join-Path $pwd ('.tmp/dual-product/dp1-u-preflight-test-ps7-' + [Guid]::NewGuid().ToString('N')))
```

真实目标批准、执行授权、四类 installed acceptance 和 DP1-U 总验收仍为 false。DP1、DP2、DP3、L6、目录 metadata durability、hardware power loss 和 hostile same-SID physical prevention 均未据此完成；YimeCore local.12 的 L5 最终确认已于 2026-09-08 另行完成，不由本预检证据证明。

## 来源闭包与 CI 接线复核

后续项目审查发现，本批四个预检输入最初已有独立 246/246 结果，但尚未列入 `tools/dual-product/contract.json` 的受保护来源集合，也没有进入 CI 的 PS5／PS7 步骤。若继续实现执行适配器，这会允许强制前置条件在全局基线外漂移。现已先关闭该接线缺口：模块、schema、合成输入及测试共四个路径加入来源闭包；全局基线绑定其关键语义和禁止执行面；CI 在两种 PowerShell 下运行同一测试。

[接线证据](../testing/dual-product/2026-09-08-dp1-u-preflight-wiring.json)记录 PS5 5.1.26100.9278 与 PS7 7.6.5 各 246/246、全局基线 161 个来源与 68/68 测试、8 个诚实 pending，以及两种 shell 的构建守卫通过。基线新增字段确认预检源码与 CI 已接线，同时 `real_target_approved=false`、`execution_authorized=false`。这次只修复来源治理，未实现或运行执行适配器，也未触碰 installed YimeCore local.12、生产 Rime/PIME、注册表、产品进程、默认输入法或用户数据。
