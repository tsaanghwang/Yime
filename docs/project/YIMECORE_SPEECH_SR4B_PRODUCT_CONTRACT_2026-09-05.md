# SR4-B1：语流音变正常产品资源与构包契约

后续实施：[SR4-B2 默认关闭候选包与私有进程验证](YIMECORE_SPEECH_SR4B_PACKAGE_2026-09-05.md)已完成；下文保留 B1 提出的设计与验收要求，不是最新运行结果。可执行契约的状态与实际通过证据分开记录，不能由本设计推定安装通过。

日期：2026-09-05。影响面仅为 **YimeCore 版**；共同规则、24 条 Stage5C 准入范围与 Rime/PIME 产物不变。本文落实[双独立产品计划](YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)的下一源码批次，不是新安装候选或安装授权。

本轮目标是正常 Broker、Runtime 与显式设置的源码接口和合成验证闭合，默认关闭。本文及[机器可读设计契约](../../tools/yimecore/speech-product-contract.json)描述后续构包所需边界，**不被当前 builder 或 installer 消费**，也不证明构包、安装、宿主、重启、SR4 或 L5/L6 已通过。具体源码与测试结果另行记录。

当前 `tools/yimecore/local-product.json` 仍为 `0.1.0-local.12`。本轮不修改该文件、包版本、安装门禁或现有安装资源；旧包不因新接口而被要求具有语流目录。

## 1. 已约定的正常产品接口

`LoadCapability(installRoot)` 读取固定的 `<installRoot>/speech-capability.json`；不存在时返回无能力，继续原有无语流路径，不寻找另一输入法、源码仓库或 SR4-A 试验目录。存在但格式或绑定错误时不能当作“不存在”静默略过。

能力声明使用 `yimecore-speech-capability-v1`，显式 `default_enabled=false`，并固定 `product.path=speech/product.json` 及该文件 SHA-256。`OpenProduct(root, path, sha)` 使用独立的 `yimecore-speech-product-v1`：

- `module_id=third-tone-stage5c`，`approved_records=24`，显式 `default_enabled=false`。
- `layout_sha256` 绑定正向来源收据中的 `packaged_layout` 哈希。
- `admission`、`forward_source` 和完整三模式 `generation` 由已准入资料绑定；内部相对路径的根为 `<installRoot>/speech`。
- 每模式恰好一个 Stage5C 模块；三个核心索引与三个模块索引全部校验真实内容哈希、模式和条数，模块各恰好 24 条。关闭状态不是免验产品资源的理由。

启用时，产品绑定的三核心索引和布局必须分别等于正常 Runtime 实际使用的核心索引和布局；不能混用一个布局的规范码与另一布局的别名。关闭时允许原有新核心／替代布局正常工作，不加载语流模块，也不能因为旧包没有语流资源而中断输入。

该产品清单替代 SR4-A 的 `bundle-off.json`／`bundle-on.json` 双清单。显式启停属于本产品设置，不通过改写安装包清单实现。语流 generation 版本不能取代正常学习命名空间的 `modelSourceID + trialIndexVersion`；开关不迁移、清除或重建用户模型。

显示注释只能消费同一哈希绑定的审定记录：标准拼音保持规范读音，键位与可证明的音元序列反映别名实际编码，不将表层变调冒充标准拼音。该只读注释证据不随 `enabled=false` 移除，已学习的精确别名仍可显示本调；无完整真源／分段证据的已学习复合串允许标准拼音留空，不从整串键码猜读音。物理删除能力或回滚到旧二进制的兼容性属于后续维护门槛，不由开关测试推定。

## 2. 最小新增安装载荷：11 个文件

以下是未来正常产品包的精确新增集合，不是本轮已生成的安装产物。`speech/` 中有 10 个文件，另有包根能力声明：

| 相对安装根路径 | 内容与来源 |
| --- | --- |
| `speech-capability.json` | 默认关闭，固定 `speech/product.json` 和哈希 |
| `speech/product.json` | 正常产品清单；只生成外层契约，不重算、手抄或改写别名 |
| `speech/admission.json` | 原始准入收据，保持字节与哈希 |
| `speech/forward-source.json` | 原始 56 项正向来源闭包收据，保持字节与哈希 |
| `speech/admitted-records.json` | 原始 24 条审定记录及来源、范围、排除，保持字节与哈希 |
| `speech/indexes/full-core.yidx` | 已准入等长模式核心索引 |
| `speech/indexes/full-stage5c.yidx` | 已准入等长模式 24 条别名索引 |
| `speech/indexes/variable-core.yidx` | 已准入变长模式核心索引 |
| `speech/indexes/variable-stage5c.yidx` | 已准入变长模式 24 条别名索引 |
| `speech/indexes/shorthand-core.yidx` | 已准入省键模式核心索引 |
| `speech/indexes/shorthand-stage5c.yidx` | 已准入省键模式 24 条别名索引 |

正常 `indexes/full.yidx`、`variable.yidx`、`shorthand.yidx` 保留当前独立构建路径。首次接入宁可保留上述三个只读核心副本，也不以硬链接、目录联接或跨根引用节省空间；导出时要求其实际 SHA 与正常包独立构建的三个核心索引逐模式一致。

新增安装载荷不得包含 SR4-A 的 `YimeBroker-speech.exe`、`YimeSpeechAdmission.exe`、试验开关清单、`sources/`、Python 文件、旧试验结果、模型、journal、私有环境或缓存。产品继续从当前源码构建正常的 `bin/YimeBroker.exe`、`bin/YimeCoreTrialRuntime.exe` 和正常工具；不重命名 fixture 程序冒充产品程序。

56 项来源文件、完整准入报告和构建日志保留在安装包之外的构建证据／来源归档内。安装包携带收据与哈希，不在安装或运行时执行 Python、重做准入或回读源码；这不取消构包前对 56 项实际来源文件的验证。

## 3. 新鲜准入与构包绑定，不能仅凭 PASS 文本

后续构包必须显式接收一个完成的、当前源码生成的独立 admission 根及预先固定的 summary SHA-256，不自动挑选“最新”目录，不使用已安装包或 SR4-A 封存副本作为构建来源。

不可省略的导出前检查：

1. 固定 summary 的字节哈希、阶段、24 条／72 条模式别名范围、全部要求的通过字段、失败和 SKIP 明细。旧 PASS 不推定新源码已验证。
2. 将准入时的源码清单摘要纳入固定证明；逐文件比较当前源码／明确输入集合，并校验本次准入工具与 Broker 哈希。不能只固定 summary 而把未绑定的 `source-hashes-after.json` 当作可替换的信任依据。
3. 验证完整 56 项正向来源闭包的角色、路径和实际哈希，以及固定 review／decisions／sources 审定输入；不存在从生成词典反推上游或另造中间码表的导出步骤。
4. 验证原始收据链、24 条记录、所有模式非增码、完整六索引，以及正常包核心和布局的实际 SHA 一致性。新源码或来源变化后须重新准入，不“补哈希”替代重验。
5. 新建不重叠且原先不存在的导出根；只复制上述精确输入，用独占创建写入，拒绝未知／缺少／重复文件、路径逃逸、ADS、符号链接与联接。生成新产品清单和能力声明，不改原准入资料。
6. 写构包导出映射：每个原始相对路径、SHA、大小到产品相对路径的对应关系，以及 admission summary、源码清单、收据、布局和生成的产品清单摘要。证据归档保留在包外；需要随包核对的固定摘要进入 `build/build-inputs.json` 和外层 `package-manifest.json`。
7. 导出、合成运行之后分别复验原准入根与产品载荷，失败保留独立证据，不修补原输出或覆盖旧封存结果。

## 4. 最小扩展点与明确待办

| 现有入口 | 后续最小修改；本轮均不接通构包 |
| --- | --- |
| `local-product.json`／`Get-LocalProductDescriptor` | 后续候选才声明可选语流能力；缺字段保持旧包契约。当前 local.12 不变，不把 11 文件无条件加入所有版本必需集合 |
| `build-local-product.ps1` | 正常三个索引双写确定性验证后、外层清单生成前，增加显式 opt-in 的 build-only 导出阶段；不默认扫描 trial 根 |
| `cmd/yimecore-speech-admission` | 可提取现有校验逻辑给独立 build-only stage 工具使用；不调用整个 69 文件 SR4-A 克隆，不把 stage 工具加入 `go_binaries`。仅建议，尚未实现 |
| `cmd/yimecore-independence-audit/local_contract.go` | 现有 installable 包白名单会拒绝 `speech/`。按可选能力条件增加恰好 11 个路径并调用产品资源验证；旧包原集合继续通过，未声明能力却带语流载荷必须拒绝 |
| `local-package-contract.ps1` 与包测试 | 继续外层全文件 SHA／大小审计、独立 auditor、重解析拒绝及安装身份检查；不能删除白名单来容纳新文件 |
| 正常 Runtime／Broker／Settings | 使用正常具名管道、注释、用户词库、屏蔽、学习与模型命名空间；显式启停只改变模块选择。不使用 fixture trusted-client 或试验状态根 |
| `manage-e6c-trial-install.ps1::Write-RuntimeConfiguration` 及启动／恢复入口 | 这是当前正常维护事务的配置写入点。后续按已审计能力描述派生路径并保持设置／回退语义；不要新增第二套部署器。本轮不执行或修改安装事务 |

仓内没有 `build-e6c-trial-runtime.ps1`。名称相近的 `deploy-e6c-trial-runtime.ps1` 硬编码旧 CLSID／Profile，并有语言列表、Run 和启动修改，不是本轮扩展或执行入口。`local-product-runtime.ps1` 是正常维护启动／校验 helper，本身不是配置生成器。

## 5. B1 可执行验证范围与不能外推的门槛

以下命令是新合成测试加入后的定向范围，不是本文执行记录。先设置全新私有 `TEMP/TMP/APPDATA/LOCALAPPDATA/GOCACHE/GOMODCACHE/GOPATH`，使用明确本地 Go，固定 `GOTOOLCHAIN=local`、`GOPROXY=off`、`GOSUMDB=off`、`GOWORK=off`、`GOENV=off`、`CGO_ENABLED=0`，清除 Rime／TSF／安装及旧试验 opt-in 环境。环境精确恢复，JSON 日志只含固定夹具结果。

```powershell
go test ./input_methods/yime/speechruntime -run '^Test.*(SpeechProduct|SpeechCapability)' -count=1 -json
go test ./cmd/yimebroker ./cmd/yimecore-trial-runtime ./cmd/settings-tool -run '^Test.*Speech' -count=1 -json
go test ./cmd/yimecore-trial-runtime -run '^TestBrokerArguments(PinMultiIndexDurabilityAndTransactionalControl|AdoptPublishedTrialLayoutGeneration)$' -count=1 -json
go list -deps ./cmd/yimebroker ./cmd/yimecore-trial-runtime
```

运行前须对照实际落盘测试名，拒绝匹配 0 项；不能把 package PASS、编译、跳过或 AST 检查说成该新接口已实测。所选新测试须只用 `t.TempDir`／合成状态，不启动已安装程序或连接日用端点；若需要真实私有进程矩阵，应单独安排下一层证据，不能混入 B1 合成计数。

至少覆盖：旧包无能力／无资源可运行；默认关闭；显式启用三模式；缺失、伪造、超范围与非增码证明错误；全部六索引坏哈希；关闭时正常替代布局兼容；启用时核心或布局不匹配拒绝；开关不改变学习命名空间和模型代数；坏配置在打开持久状态前拒绝；设置重开与重启后的明确读回；用户词库、屏蔽和注释路径仍进入正常引擎包装链。

后续实际 stage／builder 接线另补导出合成负例、旧／新可选描述与包白名单测试；再运行正常包构建、包内维护 Plan、私有正常 Runtime/Broker 七阶段和 x64／x86 受影响源码合同。完整构包后仍须另行交接安装、注册／真实宿主、必要重启和用户日用确认，不能用 SR4-A 七个 fixture 进程顶替。当前不运行 builder、安装器、注册程序、Rime、冻结载荷或用户状态读取。
