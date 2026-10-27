# PR #80 固定 CI 包与 ASUS ARM64 本机开发记录

2026-10-27。影响范围为未安装的桌面触摸键盘实验。本轮在 `HuashuoNotebook` / ASUS ProArt P16 H7607BA 完成完整 ARM64 包的原生开发检查，同时固定 x64 包的下载身份。未修改运行时代码、布局、词典或几何。

## 固定来源与本地交付

来源为 [PR #80](https://github.com/tsaanghwang/Yime/pull/80) 的[成功 CI run 40425817549](https://github.com/tsaanghwang/Yime/actions/runs/40425817549)，事件 `pull_request`、attempt 1。包源码为 `590bf95d8af929bdefdafddf2e34a3a7443200a4`，PR head 为 `67f33761bb76f4b3a30e1975f93b7c8ccb3120ff`，最终 main 合并为 `8845aa3db8f44e227551aa8eea537d456f43b2fb`。#79 提供任务栏最小化/恢复与笔兼容事件去重修复，#80 仅修改测试夹具。包内 `sourceChanges:false`；后续文档提交产生的构建不自动替换本记录。

| 架构 | GitHub artifact | ZIP SHA-256 | exe SHA-256 |
|---|---|---|---|
| ARM64 | [12698964634](https://github.com/tsaanghwang/Yime/actions/runs/40425817549/artifacts/12698964634) | `60ab4a717e31b3505e240f46a2014658cbc675e71fda01d16bc9b6f9a6b8b85e` | `50d61c15ca0bec0af608240209abc6a684c1604ba738e73569e63902d69e2e3c` |
| x64 | [12699094492](https://github.com/tsaanghwang/Yime/actions/runs/40425817549/artifacts/12699094492) | `5d5c74a5a9887ca60e6ed873bf0e4dc380262d82a305978eba6959dec7f2518e` | `bf0d666fbc0632634733f3ceb5431352dda03f5a57bd81f76feb6d85e3c86a64` |

两份 ZIP 均已实际下载，SHA-256 与 GitHub digest 一致；ZIP CRC、精确文件集合及各自 manifest 中全部29个载荷哈希通过，PE 分别为 ARM64 `0xaa64` 和 x64 `0x8664`。manifest、载荷哈希、下载时间和本地路径见[包身份](package-identity.json)。CI 原始验证 artifact 12699483891 的 ZIP 也已核验，并原样保存 [x64 CI 包检查报告](ci-amd64-package-check.json)。已核对 CI 包源码与最终 main 合并的 Git tree 相同，执行后原始 ZIP/包载荷仍保持原哈希，见[一致性核对](evidence-audit.json)。

本机持久交付目录为 `C:\dev\Yime-deliveries\touch-keyboard-pr80-20261027`，其中 `arm64` 与 `amd64` 是独立完整解压目录，ZIP 在父目录保留。本机预览入口为 `arm64\Start Preview.cmd`，显式目标绑定入口为 `arm64\Start Keyboard.cmd`；这两个入口未由本轮自动启动。包外 `records` 目录放置本轮空结果模板及100键覆盖表。包内文件保持原始哈希。

## 本机身份与原生验证

[本机基线](host-baseline.json)使用 `IsWow64Process2` 确认原生 ARM64，系统读取为 Windows build 28000.3231 / 26H1。注册表产品名称原值也保留，不据该字符串推断系统代际。系统报告最多10触点；这只说明 API 报告的能力，不证明手指或笔已验收。显示 API 的尺寸可能受 DPI 虚拟化影响，未当作物理尺寸或真实面板分辨率。

此前 PR #80 的本地测试使用 Go 1.26.4 `windows/amd64`，现通过原工具 PE 和本机原生架构将其明确归类为 **ARM64 主机上的 x64 仿真测试**。该结果保留，不标为原生 ARM64；GitHub Windows x64 runner 的结果仍单独归属 CI。本轮增加以下原生证据：

| 开发检查 | 本轮结果与证据 |
|---|---|
| 原生工具链与测试程序 | 复用已有 Go 1.25.14 `windows/arm64`；Go 与编译所得测试 EXE 的 PE 均为 ARM64。测试源码为 main 合并 `8845aa3d`，执行前确认 `go-backend` 相对该提交无变化 |
| 桌面包完整回归 | 原生测试 EXE 执行 `cmd/yime-touch-keyboard` 全部默认测试通过；需显式完整语料路径的可选测试未启用，完整词典由下行独立包检查覆盖 |
| 任务栏与消息泵压力 | taskbar、minimize ticket、navigation cancellation 三项，`-test.count=20 -test.shuffle=on -test.cpu=1,2,4`，共60轮配置组合通过；shuffle seed 和原始输出保留 |
| 共用包回归 | `internal/touchkeyboard`、`internal/keyboardlab` 原生测试通过 |
| 完整 ARM64 CI 包 | 在仓库外含中文/空格路径、空工作目录、进程内隔离临时状态下执行；三模式各2,457,604条索引，分别确认内存文本“你”，默认18u/100键通过 |
| 可选全盘兼容与资源拒绝 | 显式 both 保持24.75u/134键；5项篡改、缺失字体及2项外部资源入口共8项拒绝通过 |
| ARM64 预览渲染 | 使用包内私有字体渲染成功；已检查顶部最小化入口、辅助导航及完整主区图像。此图不证明真实屏幕上的尺寸、可读性或触控结果 |

原生命令、环境、时间、退出码、PE 和输出哈希见[原生回归记录](arm64-development-tests.json)；完整词典、资源拒绝及架构匹配见[ARM64 包报告](arm64-package-check.json)。预览图见 [portable-preview.png](portable-preview.png)。`GOENV=off`、`GOTOOLCHAIN=local`、`GOARCH=arm64`、空 `GOFLAGS` 和独立 Go 缓存均仅对验证进程设置，未修改全局 Go 环境。

包检查命令（仓库根目录，Python 路径按本机运行环境选择）：

```text
python -X utf8 tools/check_touch_keyboard_package.py --package C:/dev/Yime-deliveries/touch-keyboard-pr80-20261027/arm64 --report docs/testing/touch-keyboard/2026-10-27/ci-delivery/arm64-package-check.json --render
```

报告为本次实际执行的固定文件；重跑需选择新报告目录。x64 包本轮只做静态下载核验，其原生执行证据来自随包下载的 CI 报告。本轮未运行 `--native-edit`，未发送 OS 宿主输入，也未做安装、注册、默认输入法、系统字体或用户数据变更。

## 后续实际输入准备

本机准备使用[当前验收步骤](../../../../../prototypes/touch-terminal/desktop/ACCEPTANCE_18U.zh-CN.md)和[新结果模板](RESULT_TEMPLATE.zh-CN.md)。P01 先记录本机实际显示、驱动、笔和物理量尺，再执行 P10 四层100键、P06翻页/旧触点及其余预览与宿主分支。包外100键表沿用[既有空模板](../../2026-10-20/p6/key-coverage-template.csv)，其相关盘面、主区 profile 和编码元数据哈希与本次包一致；逐项观察仍待填写，复用核对见[准备记录](preparation-check.json)。

本机不套用 MSI 16英寸设备的 `58.8` 校准或约97 mm参考尺。MSI 的手指/双笔及 Word/Edge 结果仍按[原设备汇总](../../2026-10-25/taskbar-minimize/STAGE_RESULT_2026-10-26.zh-CN.md)保留，不能填入 ASUS 新记录。H05 已改为最小化、任务栏恢复、核对旧绑定失效后明确重绑。真人手指、纯笔、真实宿主、精确尺寸和自然发送异常均未在本轮新增通过结论；18u几何保持，17u/23u继续冻结。
