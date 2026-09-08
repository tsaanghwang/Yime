# YimeCore local.13 终态候选与读取器

精确来源、工件身份和 63 份原始证据的哈希见[结构化复核记录](../testing/l6/2026-09-08-local13-outcome-candidates.json)。

2026-09-08，影响产品：YimeCore。普通候选 `yimecore-local-0.1.0-local.13-3687a998fda0` 已从干净提交 `73228cf5da8f7ff6d900b42ce497938f6109ebca` 的独立工作树重建，通过隔离构包与保护检查。包内控制器现在包含结构化终态协议 `yimecore-native-desktop-rehearsal-outcome-v1`。本记录继续保留 local.12 的有效 L5 用户确认，不新增日用时长或实际维护通过结论。

普通包 manifest 为 `1fd54730bffe9b986249cdeaedbd7c8807b255da36e75c6463ff983e378275a9`，85 个成员全部核对；源码 manifest 为 `3687a998fda0b17124b5a02198e0b295b375a2bd37139d61657718ad347d03d5`，源码 ZIP 中 787 项逐项验证。构包根为 `.tmp/w13o/.tmp/yimecore-local-product/outcome13`，独立复核见 `.tmp/local13-outcome-rebuild-20260908/normal-review.json`。该候选固定于上述提交，不声称包含本轮随后新增的仓内终态读取器。

控制器仍精确绑定 `9f69d9aba12e4c50c8aa06edb945375dc72a721cd208791ffab2e4207442f39d`。普通维护入口 `manage-local-product.ps1` 在干净工作树按仓库属性检出为 CRLF，实际哈希是 `ec206153c53d96b98aa43cd522167bb55eef83b7d7acedf745f8f966c6851479`；旧候选 LF 字节的哈希 `b0d85e48…` 仍属于旧工件。两者规范化后的源码相同，新包、准备入口及归档必须使用新字节的精确哈希。

| 构包检查 | 本次实际结果 |
| --- | --- |
| 新鲜连读准入 | 580 个来源；499 PASS、0 FAIL、3 SKIP；24 条已评审记录、72 行三模式别名 |
| 原生与 Go | x64/x86 合同与焦点取消通过；五个 Go 包通过；28 项自有注册表夹具通过 |
| 三模式索引 | 各 1,166,753 条；每份独立生成两次，字节一致 |
| 包及隔离 Runtime | 37 项包合同，12 个句子用例、三模式合成恢复、私有 Broker 重启及最终停止通过 |
| 直接 TSF | x64/x86 组合检查通过；`text_extent_anchor=false` 原样保留 |
| 保护 | 包独立性复核通过，正式注册和默认输入法前后保护一致 |

新故障候选 `yimecore-local-0.1.0-local.13-3687a998fda0-rollback-failure-5ae5a75eb47a` 的 manifest 为 `7a70ba727e0cc157358680213ea5e4cbb52b711631c74d0d2182b5029cc141ef`。85 个列明成员中仅 `bin/YimeCoreTrialRuntime.exe` 替换为新编译的退出探针，派生 manifest 另行更新。控制器与维护入口保持普通包的精确字节。`expected_probe_exit_code=86`、`probe_exit_observed=false`：本轮没有运行该故障探针。

两份候选及公开来源介质已复制到 `%USERPROFILE%\YimeCore Recovery Archives\local13-maintenance-candidates-20260908-7a42bbe7efe245d89f6faae080d8f4ea`。182 个公开输入、910,740,777 字节通过仓外副本校验，archive manifest 为 `1d74e0d714231e36f2300eca534de60165c2c3d94492d35f08a831962ff8af4e`。归档只有程序、源码和公开构包/准备证据，不是用户状态备份；独立 Explorer 系统可见性仍未验证。旧 `e65…` 候选和归档均保留，未追加新协议或新结论。

连读准入的三项符号链接 SKIP 沿用原始记录，不计为通过。首次准入在沙箱内因只读 `StdRegProv` 拒绝访问而停止，失败根保留；经工具审批执行同一检查后通过，没有放宽保护条件。构包只运行新输出中的隔离工具及其合成状态，正式产品只做公开载荷和必要注册元数据的只读保护检查。

新增 `Read-YimeCoreNativeRehearsalOutcome` 读取器对文件内容、阶段顺序、来源/attempt/SID/PID/创建时间/目录绑定以及传入的实际退出码做严格核对。同一文件流完成原生最终路径、单链接、字节哈希和解析；拒绝重复 JSON 键、字符串真值、数组冒充、缺失/倒序阶段、自然退出与强制终止混淆，以及完整 JSON 搭配实际退出码 26。原生辅助源码使用固定哈希与每模块独立类型，已有同名类型不能替代本次编译。

参数 `ExpectedSourceManifestSha256` 及更明确的别名 `ExpectedNormalPackageManifestSha256` 都指故障包派生来源的**普通包 package-manifest.json**，对应 producer 的 `source_manifest_sha256` 字段；它不是 `build/source-manifest.json` 的源码清单哈希。

PS5/PS7 读取器各通过 224 项检查，包括 10 种实际 producer 终态函数的序列化与分类兼容。测试只提取并运行这些函数，未调用完整维护控制器。返回的 `record_consistent` 只表示内容与给定绑定一致；调用方提供的退出码、producer、加载代码及原生执行真实性仍未认证。独立恢复、启动、Runtime 就绪、L6 和产品发布就绪均保持 false。

固定输入提供程序已切换到新归档；两版 PowerShell 实际 Open/Close 均核验 184 个文件、33 个目录并释放租约。它仍只提供列明成员的读取保护与快照检查，`continuous_membership_protection=false`；不能据此声称阻止了同 SID 瞬态未列明成员。

本机执行了 CI 七脚本的原始组合：外部 PS5 与同一进程中的 PS7，各通过准备 57、注册表合成 79、上下文 48、输入租约 52、进程合成 47、producer 99、reader 224 项。此处进程 47 项是 CI 的合成默认范围，不借用此前 53 项原生夹具结果。来源基线已更新为 176 个声明路径加 7 个锁定依赖，183 项哈希一致，68 项测试通过，8 个 pending 保持。来源数量断言遗漏已修正，首次失败没有生成通过回执。

尚待完成的是原生维护动作编排、用户数据备份与恢复保护、独立系统可见性及退出事实采集、注册/进程/配置/延期删除核对，再按维护窗口取得实际双架构回退、恢复、卸载重装与宿主证据。本轮不执行安装器，不改变已安装 local.12、生产 Rime/PIME、默认输入法或用户状态。Rime/PIME 的可信候选、独立目标、DP1-U 实际事务及 DP2/DP3 仍按各自证据推进。
