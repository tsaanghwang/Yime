# DP1-U 原生只读探测适配器增量

日期：2026-09-08。影响产品：独立 Rime/PIME 隔离 package lane。保护对象：YimeCore local.12、历史 YimeCore 身份及生产 Rime/PIME。本批提供原生只读观测代码和隔离回归，不执行安装、卸载、注册、恢复、Runtime，也不改变默认输入法或读取用户数据。

以下 V1 实现/待办/74 项记录保留为首批历史；后续 V2 strict candidate 接线进展见本页末段。首批 JSON 及其源码摘要不改写。

## 本批实现

- `tools/dual-product/rime-pime-dp1u-native-probe.psm1` 唯一导出 `Invoke-RimePimeDp1UNativeReadOnlyProbe`；必须显式传入授权文件、独立授权摘要、产品边界文件、package 文件和 canonical receipt 文件。不存在可注入命令、scriptblock、provider 或 Apply 开关。
- 最先以 OS 提供的 `[Environment]::MachineName` 拒绝 `MYCOMPUTER`，发生在打开任何调用者文件、查询注册表或读取产品事实之前。其他机器也必须匹配已声明目标、MachineGuid、发起 SID、实时批准/到期窗口和现有严格授权/边界 schema。
- `rime-pime-dp1u-native-facts.cs` 用 Win32 查询 native architecture、持有句柄的进程映像/创建时间、token SID/提升状态、每个祖先的 package identity。只接受同 SID、未提升、未打包的 PowerShell 到系统 Explorer 的完整可观察链；缺失祖先、PID 重用迹象或无法确认身份均拒绝。这里只观察发起进程，未替未来 worker 或 Runtime 填写 SID 通过。
- 注册读取使用进程外 `StdRegProv`，指定 `__ProviderArchitecture=32/64` 和 `__RequiredArchitecture=true`，HKU 精确绑定发起 SID；无进程注册视图回退。固定源码身份的 COM、TIP、卸载和 Run 坐标只要存在就拒绝，Run 先枚举精确值名以覆盖非字符串类型伪装，不读取无关 Run 值内容。现有 Rime GUID 与 `installer/installer.nsi` 的 `YIME_TIP` 一致；当前及历史 YimeCore GUID 固定，申请者不能靠换成虚构 peer GUID 隐藏 local.12。
- 仅支持新隔离安装目标的初始观测：三个目标根必须不存在；声明的保护安装根以及固定 Program Files 生产/另一产品安装根存在即拒绝。只检查路径/存在元数据，不进入状态、设置、学习或正文文件。新建目录、注册/文件状态保存以及共存目标探测尚未实现。
- 读取文件前拒绝模糊路径和可见 reparse 祖先。package、receipt、授权和边界以 `FileShare.Read` 持有，Win32 复核最终路径、单硬链接和文件身份；package/receipt 原始字节必须匹配批准的哈希，receipt 的 installer 哈希/长度必须对应 package。授权与边界的规范摘要遵循既有 schema，输出同时保留原始文件摘要。文件读取有大小上限。

这不是先填满纯预检的 true 字段再调用旧合同。成功输出使用单独的 `yime-rime-pime-dp1u-native-readonly-observation-v1`，只有 `native_readonly_observation_completed=true`；`native_preflight_complete`、`execution_authorized`、注册/回滚/移除/Runtime 四门与 `dp1_u_acceptance_passed` 始终为 false。文件句柄保护只覆盖本次只读观察，返回后释放，不声称完整事务期间排除同 SID 替换或目录别名竞态。

## 仍需完成的真实执行链

1. 识别并批准可用隔离 x64 机器、同 SID 原生会话和精确候选；当前没有实际目标批准。批准摘要匹配只是对象绑定，仍缺独立身份认证、撤销以及持久 run-id 消费/防重放。
2. 将 DP1-T strict receipt 的完整来源链、payload 与真实执行安全审查接入新 provider。此处只绑定 receipt/package 原始字节，disabled/unsigned canonical receipt 仍不得执行，也没有解除 NSIS 硬阻断。
3. 构建完整事务期间的系统可见根身份/租约、保护快照和默认输入法保护基线；这里只取得固定保护注册不存在的初始观察，不是维护前后完整保留证明。
4. 接入同 SID 提升 worker 和非提升 Runtime 的独立原生观察，实作原生注册、失败回滚、精确卸载、Runtime 的 transaction providers，按受影响路径执行隔离验收。当前没有占位执行回调，也没有把合成事务模型称为真实事务。

## 实测与未测范围

[本批结果](../testing/dual-product/2026-09-08-dp1-u-native-readonly-probe.json)记录 PS5 5.1.26100.9278 和 PS7 7.6.5 各 **74/74** 通过：严格授权字段、过期/未来/目标/摘要拒绝、固定源身份、错误布尔类型、路径歧义、固定 HKU/注册坐标、Run 任意值类型存在拒绝、provider 错误、实际 Win32 自有测试进程事实、夹具文件字节/句柄身份、拒绝并发写和多硬链接、以及真实 MYCOMPUTER 入口早拒绝。

原生成功目标、实际 `StdRegProv` 正路径、完整祖先成功路径和 installed 四门没有运行；记录保持 false。最初一次回归暴露 schema GUID 必须小写的问题，修正为 schema 所要求的规范形式后重跑通过，没有放宽 schema。后续加入 Run 值类型保护后两套 74 项均通过。

三份执行/测试源码已接入 `contract.json`、baseline 来源清单与 PS5/PS7 CI，基线回归 68/68，157 个声明路径加 7 个锁定依赖共 164 个来源。baseline 只验证接线，没有执行原生探针或将 installed 门禁提升为 true。

仅回归命令如下；会创建新的仓内 `.tmp/dual-product/dp1-u-native-probe-*` 夹具/结果，不清理历史证据：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/dual-product/test-rime-pime-dp1u-native-probe.ps1
pwsh.exe -NoProfile -File tools/dual-product/test-rime-pime-dp1u-native-probe.ps1
```

原生 probe 没有默认目标，也没有可在当前开发机复制即执行的申请示例。其五个参数都是明确审阅的文件/摘要；未获得隔离目标前不生成实机批准 JSON。

## V2：接入真实 strict receipt 来源链及执行拒绝

V2 新增显式必填 `ReceiptEvidenceRoot`，共六个参数；输出升级为 `yime-rime-pime-dp1u-native-readonly-observation-v2`。MYCOMPUTER 早拒绝仍发生在任何调用者路径读取前，没有新增默认目标或执行入口。

内部 `Get-Dp1UNativeCandidateAssessment` 直接调用来源模块的 `Read-RimePimePackageBuildReceiptV2`，复用其严格 JSON/sidecar、retained object、plan/manifest/payload 关系、build/postbuild 语义、源码及 NSIS 原始摘要绑定检查。阅读器结果必须与仍持有的批准 package/receipt 文件租约摘要和长度一致，两个文件都须在显式 evidence root 内。它没有用 `schema_version` 与汇总布尔代替来源链，也没有复制一个可以单独漂移的弱化阅读器。

成功静态读取只关闭“尚未接入 strict receipt 来源链”的源码缺口。现有 v2 阅读器理解的 canonical schema 明确为 `canonical-static-closure-disabled`，因此返回 `strict_receipt_evidence_chain_verified=true` 时，可执行候选仍明确拒绝：`executable_candidate_safe=false`、`candidate_execution_admitted=false`。将 `delivery_admitted` 改为 true、伪造签名布尔、改未来 schema 或重封一份语义矛盾的 receipt，都由真实阅读器拒绝。受信可运行候选须有独立可执行 schema、签名和安全准入合同，不能把 disabled receipt 原位改字段放行。

这里的拒绝限定于**可执行发行准入**。DP1-R 已取得的独立派生 disabled 静态信任/闭包结果保持原义；canonical 原始 `delivery_admitted=false` 不否定该静态证据，也不授予安装、卸载或 Runtime 执行许可。

新 [strict candidate 回归](../../tools/dual-product/test-rime-pime-dp1u-native-candidate.ps1) 直接复用现有完整 receipt fixture factory，未 mock strict reader。默认 15 项只创建/验证合成来源链；包括缺附件、错误 sidecar、与来源矛盾的版本、已重封的 build 篡改、原始字段伪造、缺完整 schema、未知版本、重复 JSON 属性、NSIS 源码篡改及错误 evidence root。加 `-ReviewCurrentCanonical` 后再只读检查仓内当前 canonical 与其 retained sources，两套 PowerShell 各 17 项通过；当前 canonical 静态链通过且执行准入为 false。旧 native context 74 项也重新通过。

新结果见 [2026-09-08-dp1-u-native-strict-candidate.json](../testing/dual-product/2026-09-08-dp1-u-native-strict-candidate.json)。只读 canonical 审查不调用原生目标 probe、不打开 installed local.12 目录、不读取用户数据。native target、真实 registry/ancestry 成功路径和 installed 四门仍未执行，既有未完成字段不提升。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/dual-product/test-rime-pime-dp1u-native-candidate.ps1
pwsh.exe -NoProfile -File tools/dual-product/test-rime-pime-dp1u-native-candidate.ps1
```

来源链检查读取的证据租约遵循既有阅读器，只证明这次静态检查，返回后不为未来执行保留所有证据或目录租约；完整事务身份保护、防重放、worker/Runtime 原生观察及 mutation providers 仍待完成。
