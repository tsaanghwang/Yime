# 华硕 ProArt ARM64：第一轮实机测试

2026-10-26（Asia/Shanghai）。用户确认 ARM 笔记本到位并要求启动测试。本轮在该笔记本直接执行，已完成设备识别及桌面原型的原生无输入检查；YimeCore 安装产品的原生构建、安装和实际输入尚未完成。

开发与证据分支：`codex/arm64-native-test-20261026`，从当前 main `f488ce25ce72decfdca159d2a223ab3f7387d3d0` 建立。此报告不写入既有 x64 测试分支 `perf/i7-7820x-local`。

## 设备与执行环境

| 项目 | 实测 |
| --- | --- |
| 计算机 | `HuashuoNotebook`（环境计算机名为 `HUASHUONOTEBOOK`） |
| 厂商 / 型号 | ASUS / ProArt P16 H7607BA |
| 处理器 | NVIDIA RTX Spark N1X；系统报告 20 个逻辑处理器 |
| Windows | 26H1，build `28000.3231`；注册表 ProductName 仍保留旧名称，原值保存在基线 |
| 可见物理内存 | 58,780,475,392 bytes（约 54.74 GiB），不是安装内存规格断言 |
| 原生架构 | `IsWow64Process2.nativeMachine = 0xaa64`，ARM64 |
| 编排进程 | Python EXE PE 为 `0x8664`；环境及 `platform.machine()` 均显示 AMD64，`processMachine=0` |
| 工具链 | PATH 和明确标准目录未发现 Go、CMake、MSVC ARM64 或 Windows SDK；未递归搜索或推断自定义安装不存在 |

[机器原始基线](host-baseline.json)记录 API、环境、PE 和工具发现范围。ARM 原生判断采用 Windows API 和待执行 EXE 的 PE 类型双重核对；环境字符串及 `processMachine=0` 均不能替代这两项证据。Python/Git 使用 Codex 自带运行时，不改全局 PATH。

## 已执行的桌面原型测试

受测对象为 18u/CN134 实验室的完整 ARM64 便携包，使用包内实验词典。不是已安装 YimeCore 或 Rime/PIME 产品。

- 固定 [PR #77 ARM64 artifact](https://github.com/tsaanghwang/Yime/actions/runs/39751192421/artifacts/12414405688)，[CI run](https://github.com/tsaanghwang/Yime/actions/runs/39751192421)。此次查询时未过期，原到期时间为 2026-11-05。
- ZIP：98,399,550 bytes；SHA-256 `80d747a55c26ab56c729a7db5b20e7e1ddc6a2ba17ff4f5da931f6d193f21108`。
- 包源码：`f2e1a03659bc6b90b9bcc8ec1acba4c5ba63cf6c`（PR 测试合并提交），运行时 head `ceed533ff98796deb4003e2020aa8cf1ee23dd2b`。
- EXE：SHA-256 `65d9298f24959ff9f6316f061efbdde6fba85114b60495c6882cbc5f365abb9e`，PE `0xaa64`；manifest：SHA-256 `c51840da78a382181e2fea40603457ed5462923b13c3a38d32e73c1f29ea0dfd`。
- 本地完整下载位于 `.generated/arm64-native-20261026/`；它是本轮本地副本，交付身份以上述 GitHub URL 和 SHA 为准。

原包 29 个 manifest 载荷均验 hash，原 manifest 未改。检查器将包复制到仓库外含中文/空格的临时目录，从空 cwd 执行，隔离 TEMP/TMP/APPDATA/LOCALAPPDATA 并清除 YIME_* 覆盖。结果见[完整执行 JSON](portable-package-check.json)。

| 检查 | 结果 |
| --- | --- |
| Windows ARM64 + ARM64 EXE 匹配并执行 | PASS |
| variable / full / shorthand 内存会话确认“你” | 3/3 PASS；每模式索引 2,457,604 条 |
| 默认 18u / 100 键 | PASS |
| 显式双侧数字区：24.75u / 134 键 | PASS；只验证已有兼容参数，未另开冻结几何路线 |
| 清单、私有字体、盘面、编码清单、词典损坏拒绝 | 5/5 PASS |
| 字体缺失、外部 root、外部 data-dir 拒绝 | 3/3 PASS |
| OS 宿主输入 / UI / 自有 EDIT | 未执行；`hostInputSent=false` |
| 手指、笔、屏幕毫米校准、真实应用及性能预算 | 未验收 |

首次受沙箱限制返回 `Access is denied.`，未作为产品失败或通过。取得允许后以同一固定包在隔离目录重跑成功；没有通过改包或放宽架构判断避开限制。旧包 manifest 的 `arm64NativeAcceptance:false` 保留，新报告仅声明原生诊断执行通过，`hardwareAcceptance` 和完整 `arm64NativeAcceptance` 仍为 false。

使用既有 out-of-process `StdRegProv` 采集器比较[执行前](registration-before.json)与[执行后](registration-after.json)的 19 个产品注册、默认语言/输入、启动项路径摘要，全部相同。报告仅保存 hash，当前用户 SID 已替换为占位符；这些既有路径的保护比较不代替未来 ARM 注册视图专项验收。没有安装、注册输入法或改动用户学习数据。

## 本轮工具与回归

- 新增 `tools/yimecore/collect_arm64_host.py`：只读 Windows API/注册表和工具路径，输出新基线文件，拒绝覆盖旧证据；不执行工具或产品。
- 扩展 `tools/check_touch_keyboard_package.py`：仅允许包架构与原生系统、EXE PE 三者匹配，保留 x64 CI 路径；执行记录独立于原包。
- 新回归：设备探测 7 项、便携执行门禁 10 项，均 PASS；覆盖本机实际出现的“AMD64 环境 + ARM64 系统”、检测失败和错误 PE。
- 现有平台契约 22 项、CI 工作流契约 3 项 PASS。架构工具和测试已接入 touch-terminal CI；两次推送均返回 `Recv failure: Connection was reset`，本机代理未启用。本轮修改尚未推送成功，远端 CI 未运行，结果保存在本地独立分支。

## YimeCore 接续任务

当前影响产品以 YimeCore 为主；Rime/PIME 继续保持独立稳定产品。桌面实验结果不得回填成任一产品的安装或输入通过。

| 阶段 | 下一项具体工作 | 当前状态 |
| --- | --- | --- |
| A0 实机识别 | 登记型号、系统、可靠原生架构和工具链 | 已完成 |
| A1 当前身份原生构建 | 配置 ARM64 Go、MSVC/Windows SDK、CMake；新增目标专用 Build 范围，保留 MYCOMPUTER x64/x86 门禁 | 工具链和入口待补齐 |
| A2 隔离原生契约 | ARM64 Runtime/Broker、ContractTests、FocusCancellationTests；随后隔离 Broker + TsfCompositionTests | 尚未执行 |
| A3 完整目标包 | 更新 ARM64 包契约、载荷架构/依赖和维护边界；本地验证、提交 CI、完整包 URL + SHA-256 | 尚无可安装 ARM64 产品包 |
| A4 安装态和真实宿主 | ARM64 注册视图、实际 DLL、registered-host；再分别记录 ARM64 应用及已有 x64/x86 仿真应用 | 待 A3；不预先声称兼容 |
| A5 输入、维护和封存 | 真实输入、独立安装/卸载/重装、重启后输入及用户确认；另一产品和默认输入保持 | 尚未执行 |

必须先处理的代码缺口：`development-scope.ps1` 的 ARM Build 仍进入 MYCOMPUTER guard；`build-local-product.ps1` 及 `local_contract.go` 仅接受现有 x64/x86 产品包；简版 `Build-Package.ps1` 无 arm64 载荷契约，`Setup.ps1` 的环境变量 AMD64 判断不能证明系统为 x64。本轮不放宽这些保护，也不在本机运行旧 x64 安装包。

复查设备可执行 `python -X utf8 tools/yimecore/collect_arm64_host.py --output <新的报告JSON>`。重跑固定便携包用 `python -X utf8 tools/check_touch_keyboard_package.py --package <完整解压目录> --report <新的报告JSON>`。默认命令无窗口、无宿主输入；报告路径必须在原包之外且不存在。PowerShell 工作仍统一经 `tools/powershell/run_checked.py`，不调用历史维护链。
