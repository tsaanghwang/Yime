# DP1-E：Rime/PIME 构建输入闭集与禁用包收口

日期：2026-09-06。影响产品为独立的 Rime/PIME；YimeCore 仅作为必须保持不变的另一产品。本批证据严格限于源码、构建接线、已编译产物的静态分析、隔离文件系统夹具和纯内存事务模型。没有运行 native registration probe、安装器、卸载器、已安装 Runtime 或真实应用，也没有提升、注册表／Profile 读写、真实进程启停或用户数据访问。

## 结论与证据等级

当前 Rime/PIME 包装链已把签名、验签、NSIS 编译、build receipt、build manifest 和 StaticOnly smoke 绑定到一份密封 package plan。当前唯一获准的 package profile 是有序架构集 `x86,x64`；这里的 x86 是 WOW64 应用面。plan 的机器可读范围固定为 `declared-packaged-product-pe-inputs-only-not-installed-payload`：它只声明并哈希当前产品的 PE 构建输入，校验实际 machine、普通／delay import 的动态 CRT 禁止项，以及递归打包的 Go 树中没有计划外 PE。

这不是完整 payload 闭包。plan 不声明所有数据文件、许可证、目录、安装后生成项、卸载器自映像、持久 journal 或恢复介质，也没有通过打包后解包来证明安装器中的每个字节都来自 plan。当前 installer/receipt 的 digest 关联只确认安装器全字节中出现 package-plan digest 的 ASCII 或 UTF-16 字节；它没有解析名为 `PackagePlanSHA256` 的 VERSIONINFO，也不证明嵌入 payload 的来源。独立的 `rime-pime-payload-closure.ps1` 目前只在隔离夹具上验证闭树、special uninstaller 身份、reparse／hardlink／ADS、大小／哈希和第二遍竞态拒绝；它尚未接入实际安装包或卸载路径，不能把其 29/29 结果写成真实 payload closure 已完成。

[`installer.nsi`](../../installer/installer.nsi) 仍是禁用开发包：`.onInit` 和 `un.onInit` 的第一项动作均为用户可见提示与无条件 `Abort`，安装 Section 和卸载 Section 入口还有第二层无条件阻断。直接调用 `makensis` 缺少密封 plan 定义时也会编译失败。tagged release job 在构包前保持硬阻断，等待可信卸载器与精确 removal／recovery 闭包。因此，本批可能生成或分析的任何 unsigned disabled package 都不可交付、不可安装、不可运行，也不是 daily-use 或 release candidate。

## 已闭合的具体构建回归

1. 旧做法可由 ARM 文件是否恰好存在决定 NSIS 内容，且签名、manifest、smoke 和 NSIS 各自的 ARM 开关可能漏传或互相漂移。现在这些消费者只读取同一 package plan；磁盘上的未选择 ARM 残留不会自动进入当前 `x86,x64` 包。
2. plan 行中的架构文字原本可能只是声明。当前 reader 在哈希匹配后调用同一 PE machine／CRT gate；即使攻击者重算 plan 与 sidecar，wrong-machine 和 delay-loaded `vcruntime` 负例仍被拒绝。
3. NSIS 对 Go 后端树使用递归收集，固定 PE 清单可能漏掉残留或伪装扩展名的可执行文件。当前 reader 以 MZ／PE 头递归枚举该树，要求规范路径集合与声明 PE 集完全相等；额外 `.bin` PE 负例已固定。
4. plan／receipt 的 JSON 与 `.sha256` sidecar 现在分别受仓库边界、大小、规范路径和 reparse 检查；缺 sidecar、越界输出、超大 sidecar、改包后旧 seal、缺 receipt 或 digest 不一致均拒绝。
5. 内层 PE 签名会改变哈希，不能沿用签名前的 plan。可信签名入口在内层签名后重新密封 plan，再由唯一 build wrapper 驱动 NSIS；外层安装器签名后刷新 receipt。CI 跨 job 显式传递 plan、sidecar、receipt 和 sidecar。
6. build manifest 已升为 schema 3。生成器先要求环境提交与当前 `HEAD` 完全一致，不一致即拒绝；当前工作树有未提交修改时，必须记录 `sourceIdentity.kind=working-tree`、`treeDirty=true`、`commitIsCompleteSourceIdentity=false`。此时顶层 `commit` 只是基线引用，不能被描述为完整源码身份，也不能把该 manifest 当作可复现发布证明。`signedRelease` 仍是受保护 CI 顺序中的期望状态，必须与独立 Authenticode 验签成功证据配对，不能把单独生成的 manifest 当成签名证明。
7. 根构建原已拒绝继承的证书、签名器和时间戳环境；唯一 NSIS wrapper 现在同样在读取 plan 或调用 `makensis` 前拒绝这四类进程变量。专门负例逐项验证直接调用 wrapper 不会意外使用证书或访问时间戳服务。
8. 受信签名源码原先留在主源码树下的 `.trusted-signing`，会污染或掩盖 clean-tree provenance。两个签名 job 现在都在证书进入 runner 前把完整受信 checkout 移到 `$RUNNER_TEMP/yime-trusted-signing`；工作流中的 PowerShell 调用改用 YAML block scalar，源码门禁明确拒绝会被解析成 YAML anchor 的 `run: & (...)` 写法。
9. 实际执行签名的 `sign-file.ps1`、证书导入器和相应 CODEOWNERS 规则已进入精确源码哈希闭集；不能再只哈希外层 orchestrator 而遗漏签名叶节点。

以上是源码／构建链及合成夹具中发现并关闭的回归；不是已安装 local.12、生产 Rime/PIME 或用户日用行为的异常报告。

## 当前静态与合成证据

| 门禁 | PS 5.1 | PS 7 | 证据边界 |
| --- | --- | --- | --- |
| installer static、plan／receipt／manifest 负例 | 40/40 | 40/40 | 合成 PE 与禁用安装器字节；包含环境提交／HEAD 不匹配及 wrapper 继承签名环境拒绝；`installer_executed=false` |
| 注册／构建完整性 | 35/35 | 35/35 | 源码与构建接线扫描；不执行 native probe |
| PE machine、normal／delay import 与 ARM 成对显式静态验证 | 9/9 | 9/9 | 合成 PE；不执行任何映像 |
| 精确 payload 闭树模型 | 29/29 | 29/29 | 隔离文件系统夹具；未接入实际包 |
| DP1-D 24 阶段／10 维／96 故障事务模型 | 9/9 | 9/9 | 纯内存事件，不是安装器事务 |

最终统一批次实际包含 11 个套件，PS 5.1／PS 7 各 281/281，除上表外还覆盖注册归属 22、用户清理 12、目标 SID 25、维护 31、定向退出 17 和事务隔离 52 项。精确路径、SHA-256、布尔边界及当前源码基线见[结构化记录](../testing/dual-product/2026-09-06-dp1-e.json)。当前源码基线固定 91 个明确来源并通过 37/37 纯合同测试；新增闭集包含签名叶脚本、证书导入器和 CODEOWNERS。该基线不运行 PowerShell／Rust／Go/native 测试，也不读取已安装状态。

根构建入口已在不安装的条件下完成；其后只改了 manifest／wrapper／签名 provenance 的防误用守卫、相应测试和文档，没有改变这 20 个产品 PE 输入。当前 plan、receipt、manifest 和安装器已在最终源码修改后重新做 StaticOnly 绑定检查，但没有再把整套根构建重复一遍。`go test ./...`、固定 i686 Rust `--locked` 26 项、x86／x64 CTest 各 4/4、runtimechange 回归，以及含两项 ARM64 交叉构建映像的 22 个实际 PE 静态检查在 PS 5.1／PS 7 均通过。当前 `ci.yaml`（SHA-256 `ee0528ce341e93277a923051f8ce290d8817471c543de132319c954ac8035b1a`）还经 Red Hat YAML Language Server 1.24.0 独立解析为 0 diagnostics；结果只输出到 stdout，没有持久诊断收据，也仍不是 hosted workflow 实际运行证据。后续如重写 plan，必须严格按 plan → wrapper 重编 installer → receipt → manifest → StaticOnly 的全链重做，不能单独刷新 plan 使现有绑定失效。

当前已编译树的静态绑定如下；这里只说明文件身份，绝不授权执行安装器：

| 产物 | 大小（字节） | SHA-256 |
| --- | ---: | --- |
| `installer/package-plan.json`（20 个声明 PE 输入，`x86,x64`） | 7,259 | `b5bcfe3ead26478129621cec7ea376ad028db86500d209d74572be16b04445ad` |
| `installer/package-build-receipt.json` | 903 | `15a5bc34cfcd558690f24229f44ebabca53c1017aeb6d971558869b19e0e0b2e` |
| `installer/build-manifest.json`（schema 3，`working-tree`） | 5,552 | `d7369de9cb06912871668dcfc87d9748fcdea8c00ff84ecd7492ed4182ed1e95` |
| `installer/YIME-1.4.0-dev-setup.exe`（`NotSigned`、硬阻断） | 40,728,260 | `83624a05190e40f7622b9f4b43ced78f14e1e8be6903e1b110f494d0a5b8d83a` |

## ARM64 边界

ARM64 在本批只有本机交叉构建和显式、成对的 PE machine／normal-import／delay-import 静态验证。它没有进入密封 package plan；保留的 `x86,arm64x` profile仍为 fail-closed，当前 package architecture 只有 `x86,x64`。本批没有 ARM64／Arm64X 安装包、原生执行、注册、Runtime、registered-host 或 live-host 证据。交叉构建和静态通过不能替代可用 ARM64 设备上的物理验收。

## 尚未完成的阻塞项

1. 从实际 staged package 生成包含全部文件、目录和特殊自映像的可信 payload manifest，并在构包后解包复核实际嵌入字节；把 digest 检查升级为命名 VERSIONINFO 解析或更强的结构化来源证明。当前 package plan 只能证明声明的产品 PE 输入，字节出现检查不能证明完整嵌入来源。
2. 建立独立签名且可验证的卸载器自映像，完成精确 payload ownership、removal journal、恢复介质和删除后闭集核验；在此之前不得解除四处运行时硬阻断或 tag 阻断。
3. 把 DP1-D 的完整暂存、持久 prepared／commit journal、崩溃／重启重放、逐维真实回滚及 rollback-failure continuation 接入安装／升级／卸载执行路径。
4. 在干净、可复现的源码身份上重建签名候选；schema 3 对 dirty tree 的诚实标记不是完整源码身份，也不使 unsigned disabled package 可交付。
5. 解除 tag 阻断前，只解析一次受保护的签名工具提交并在两个签名 job 间固定、核对和写入 release provenance；同时用源码门禁锁定 `sign → verify → manifest → upload` 顺序，并对外层签名后的 clean、`signedRelease=true` manifest 再跑 StaticOnly。当前两个 job 各自读取可变默认分支，尚不能称为同一签名实现的可重放来源。
6. 在获准隔离目标完成同 SID UAC、COM／TIP／Profile、x64／WOW64 x86 registered-host、仅装一种产品与两种共存顺序、升级／失败回退／卸载／恢复／重启矩阵，并证明另一产品、默认输入法、设置和学习不变。
7. 建立 Arm64X package profile 与有明确可用设备后的 ARM64 原生安装、注册、进程、registered-host 和 live-host 证据。
8. 完成 legacy 身份迁移事务，再评估 DP3 的薄三选一入口；不得把比较 Rime/PIME 行为当作 YimeCore 的运行依赖或验收替代。

因此，本记录不宣称 DP1、DP2、DP3、L5 或 L6 完成。`dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`、`dp3_selector_acceptance_passed=false`、`l5_final_confirmation_complete=false` 和 `l6_sealing_complete=false` 均保持不变。

## 已安装状态

本批没有触碰当前日用 YimeCore local.12；local.13 未安装。生产 Rime/PIME、默认输入法、用户正文、设置、学习、历史冻结载荷和真实进程均未读取、启动或修改。
