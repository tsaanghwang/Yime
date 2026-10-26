# ProArt 创 16 RTX Spark：ARM64 源码构建与隔离测试

2026-10-26，接续[首轮设备/便携原型报告](TEST-RESULT.md)。用户确认商品名为“华硕 ProArt 创 16 RTX Spark”，系统型号仍记录 ASUS ProArt P16 H7607BA。受影响主线为 **YimeCore**；本轮完成当前身份原生产物构建和源码隔离运行，未安装输入法，未执行 installed registered-host 或实际应用输入验收。

## 结果

| 检查 | 本机结果 | 原始证据 |
| --- | --- | --- |
| ARM64 目标范围与旧路径保护 | 21 项 ARM 门禁 + 23 项平台契约 PASS；CI 工作流契约 3 项 PASS | `test-arm64-build-scope.ps1`、`test-platform-experiment.ps1` |
| Go 原生测试 | 6 个包全部通过；305 个 test/subtest pass，0 fail、0 skip | [汇总](native-go/summary.json)、[JSONL](native-go/go-test.jsonl) |
| 当前产品身份源码构建 | 27 个 EXE/DLL 全部为 PE `0xaa64`；源码和注册保护检查通过 | [构建摘要](native-source/summary.json)、[完整源码 hash](native-source/source-hashes.json) |
| DLL/COM 与语言栏/候选契约 | PASS | [ContractTests](native-source/native-contract-arm64.txt) |
| 失焦取消隔离 Fake COM | 32 checks，0 failures | [FocusCancellationTests](native-source/native-focus-cancellation-arm64.txt) |
| full / variable / shorthand 直接 TSF | 三模式全部 PASS；标准产品字典每模式 1,166,753 条，索引验证通过 | [汇总](native-source/tsf-three-modes/summary.json)、[full](native-source/tsf-three-modes/full/tsf-arm64.txt)、[variable](native-source/tsf-three-modes/variable/tsf-arm64.txt)、[shorthand](native-source/tsf-three-modes/shorthand/tsf-arm64.txt) |
| 测试后保护 | 构建、C++ 契约、三模式直接 TSF 的注册保护比较均保持；3 个私有 Broker 均按 image/启动时间匹配后退出 | 各阶段摘要与 `.fixture.json` |

直接 TSF 检查涵盖候选页键、非法码拒绝与退格恢复、Esc、键盘及文档失焦取消、跨上下文隔离、保留已提交正文、标点原子提交、长段、宿主终止恢复、64 个英文 Shift 组合及中英文语言栏转换。所有文档和候选窗口属于本轮测试进程，存在短暂自有窗口；没有向用户实际文档发送输入。日志的 `text_extent_anchor=false` 保持原样，不能据此声称真实宿主的候选定位通过。

## 工具链与源码归属

- 原生 [Go 1.25.14 Windows ARM64 ZIP](https://go.dev/dl/go1.25.14.windows-arm64.zip) 的 [官方校验清单](https://go.dev/dl/) SHA-256 为 `96fb31ae26b288b5311bd31d8252d4a62c8a661e4dbb64d504cc646e4d10a57f`，实下载匹配；解压于独立 `.generated/arm64-toolchain/`，实执行报告为 `windows/arm64`。见[下载收据](native-source/toolchain/go-download.json)。
- Microsoft 签名有效的 [VS Build Tools 2022 bootstrapper](https://aka.ms/vs/17/release/vs_BuildTools.exe)，下载 SHA-256 `4aad1082e180f558598c346eb105b465b4908148cb9f7f0511aa1105620e0c30`。按[官方组件目录](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?view=visualstudio)安装 C++ Build Tools、ARM64、Windows SDK 26100、CMake；不添加 Recommended/Optional 工作负载。退出码 0，无需重启，没有自动重启。见[安装收据](native-build-toolchain-install.json)。这是开发依赖安装，不是输入法产品安装。
- 本轮编译器实际路径为 `Hostarm64/arm64/cl.exe`，MSVC `19.44.35229.0`；CMake `3.31.6-msvc6`，Windows SDK `10.0.26100.0`。见[配置日志](native-source/configure.txt)。Go 的缓存、临时目录和测试状态均限于本轮隔离目录，PATH 与 Go 环境仅修改子进程，没有执行 `go env -w`。
- 源码构建时 HEAD 为 `14cc75190db1e0d64ccfffa3d9c26a86d288728b`，包含尚未提交的本轮平台入口修改，因此原摘要明确为 `git_dirty=true`。以保存的源码 hash 识别实际输入，不把本轮产物称为通过 CI 的可安装候选包。Go 原生测试针对同一工作树的未改动产品源码，未使用实验室 overlay 或词典。
- [证据索引](native-source/evidence-index.json)记录原始文件 SHA-256。保留的 `runner-source/` 是执行当时脚本的审阅副本，原位置在本轮本地 `.tmp`；不要在归档位置直接执行。未提交 EXE/DLL、生成索引、安装包缓存或用户数据。

## 本轮修正及保留限制

`development-scope.ps1` 使用 `IsWow64Process2` 验证原生架构。只有登记的 `HUASHUONOTEBOOK` 可进入 ARM64 本机源码 Build；MYCOMPUTER 的历史 ARM 交叉构建和 x64/x86 本机产品门禁保留，主流 x64 的生成器仍固定。ARM 本机须显式选择已安装的 VS2022/VS2026 生成器。ARM `Package` 在创建输出或构建前明确拒绝，防止把源码产物误当安装包。

首次三模式测试在数据边界 helper 的 `FileInfo.Parent` 严格模式兼容处停止，尚未启动 Broker/TSF；[失败摘要](native-source/tsf-first-attempt/summary.json)保留。按已有 `test-focus-cancellation.ps1` 的调用约定，仅对该 helper 的调用关闭 StrictMode 后，在新的输出目录执行通过；未修改或削弱数据来源边界函数。三份输入均来自当前仓库产品标准字典，仍经边界检查及索引器 allowlist 验证。

后续源码 Build 使用 `tools/yimecore/run-platform-experiment.ps1`，参数 JSON 为 `{"Target":"arm64","Action":"Build","NativeGenerator":"Visual Studio 17 2022"}`，经 `python -X utf8 tools/powershell/run_checked.py --script tools/yimecore/run-platform-experiment.ps1 --edition ps7 --params-file <参数文件>` 执行。子进程须能找到本轮 Go、Git 和 VS 随带 CMake；入口创建新的隔离输出。C++ 测试继续使用 `Invoke-LocalProductIsolatedTestTool`，不得把已安装或历史二进制作为 `Tool`。

下一阶段为 ARM64 完整产品包和安装/卸载边界：更新包契约、注册视图、依赖及宿主架构策略，完成本地验证、提交 CI 和完整包 URL/SHA-256 交付后，再执行安装态 registered-host、真实应用和重启输入。Rime/PIME 保持独立产品。手指/笔、真实宿主、仿真 x64/x86 应用、日用和发行就绪均没有从本轮继承通过结论。
