# 音元输入法 Windows 版

**音元拼音（Yime）**将有来源的拼音音节经正式音节分析映射为音元编码，提供变长、等长和省键三种输入模式。

[English](README.md) · [文档导航](docs/README.md) · [项目现状](docs/YIME_PROJECT_ASSESSMENT.md) · [开发路线图](docs/YIME_DEVELOPMENT_ROADMAP.md)

## 两个独立产品

| 产品 | 定位 | 运行链 | 开发入口 |
|---|---|---|---|
| **YimeCore** | 主要开发线 | 自研 Go 内核、Runtime/Broker、C++ TSF 与候选界面 | [源码构建与实验](tools/yimecore/README.md) |
| **Rime/PIME** | 独立稳定维护 | librime、Go 产品逻辑、Rust PIMELauncher、C++ PIME/TSF | [Go 后端](go-backend/README.md)、[Rime 集成](docs/YIME_RIME_INTEGRATION.md) |

用户可只安装任一套，也可同时安装。两套分别拥有安装目录、运行端点、注册身份、设置、学习及用户词库；维护一套不依赖或清理另一套，不自动迁移彼此数据。共同规范数据和离线工具在本仓维护，运行资产分别随包携带。详见[双产品计划](docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)和[架构](docs/YIME_ARCHITECTURE.md)。

## 当前进展

截至 2026-09-16，核对主线 `76376080`：

- `installer/simple/` 已实现单套/双套安装、卸载、重装和显式测试数据重置。
- 清理后源码候选包已完成开发机与“计算机”测试机所报告范围的验收；测试端两套产品在 Codex 和记事本重启前后输入正常，Word 未报告结果。见[验证记录](installer/simple/VALIDATION.md)。
- PR #57 的包完整性与卸载失败处理修复已合入并通过 CI；包含该修复的新完整包尚未交付，旧 ZIP 不代表最新源码已完成实机验收。
- 当前通用包面向 x64 Windows 与 WOW64 应用。ARM64 保持独立源码实验，尚无已交付的完整安装包和原生宿主验收。
- 正式可信签名发行、YimeCore 尚未通过的性能门槛及生产数据迁移等工作仍未完成，见[项目现状](docs/YIME_PROJECT_ASSESSMENT.md)。

## 安装与使用

开发与受控测试使用完整包，解压后从 Explorer 运行 `Install-Uninstall.cmd`，选择操作和产品。单产品包也可使用 `Setup.cmd`。使用端无需 Python、Git 或另一套已安装产品。

包 URL、大小、SHA-256、来源及是否有新测试任务以 [HANDOFF](installer/simple/HANDOFF.md) 为准。源码检出不是完整包交付，历史验收步骤不是新的安装指令。

安装前保存工作并退出使用目标输入法的应用；文件仍占用时重试或取消，必要时正常重启后维护。默认保留本产品用户数据；显式 `-ResetData` 会清空所选产品的整个用户数据目录，用于已授权的开发/测试重置。日志、退出码及详细操作见[安装器指南](installer/simple/README.md)。

## 编码与候选

三模式从同一规范记录与布局派生。等长模式使用首音、呼音、主音、末音四元结构；变长模式按规则合并干音内相邻相同音元，省键模式再省略符合条件的干音中调音元。首音与虚首音边界保留，详见[数据格式与三模式规则](docs/YIME_DATA_FORMAT_REFERENCE.md#首音干音与三模式派生)。

- 裸数字 `0`—`9` 始终是编码键，即使候选窗可见也不切换为选词键。
- 按序号选择候选使用 `Shift+1`—`Shift+9`，候选标签显示 `⇧1`—`⇧9`；`Shift+0` 不选词。
- 具体菜单和工具以所选产品随包帮助为准；[用户指南](docs/YIME_USER_INSTALL_GUIDE.md)的详细工具说明针对 Rime/PIME，不代表两套功能完全相同。

## 开发与验证

工具链以 [tools/toolchain.lock.json](tools/toolchain.lock.json) 和 [CI 配置](.github/workflows/ci.yaml) 为准。主要依赖为 Windows C++ 构建工具、CMake、Go、Python 离线工具环境；Rime/PIME Launcher 另需完整的 `stable-i686-pc-windows-msvc` Rust **主机工具链**与锁定的 Corrosion。当前 CI 使用 Go 1.26.4，`go-backend/go.mod` 的最低版本为 1.25。

在仓库根目录执行 PowerShell 工作时，统一使用 checked 入口；默认选择 PS7，兼容检查明确选择 PS5。复杂参数用 UTF-8 JSON 文件传入，见[调用说明](tools/powershell/README.md)。

```text
python tools/verify_toolchain_lock.py
rustup toolchain install stable-i686-pc-windows-msvc --profile minimal
python tools/powershell/run_checked.py --script Build.ps1 --edition ps7
```

最后一条构建并制作 **Rime/PIME** 包。YimeCore 使用 `tools/yimecore/build-local-product.ps1` 构建当前身份的独立载荷，再由 `installer/simple/Build-Package.ps1` 制包；构建范围、语流准入参数及隔离结果按 [YimeCore 工具说明](tools/yimecore/README.md)与脚本参数准备。

验证按影响面选择 Go、真实 Rime、race、离线工具、原生 TSF 或安装器回归，命令和 CI 覆盖见[测试指南](docs/YIME_TESTING_GUIDE.md)。源码检查、CI、安装态输入是不同层级；本地文档工作不会自动执行安装或改变默认输入法。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `go-backend/input_methods/yime/` | 两产品相关 Go 包、Rime 适配、YimeCore/Broker、工具与生成数据 |
| `YimeTextServiceExperiment/` | YimeCore 原生 TSF 源码及测试，目录名保留历史命名 |
| `PIMETextService/`、`PIMELauncher/`、`libIME2/` | Rime/PIME 原生宿主、启动器与库；libIME2 已纳入仓库 |
| `installer/simple/` | 当前构包、安装、卸载与交接入口 |
| `syllable/`、`yime/`、`tools/lexicon/` | Python 离线编码、词库与审查工具，不进入输入法运行时 |
| `internal_data/`、`external_data/` | 仓内规范数据、来源快照与元数据；大型外部输入另有内容锁归档 |
| `tools/yimecore/` | 当前身份的源码构建、语流准入与平台实验 |
| `docs/`、`docs/testing/` | 当前文档导航与带身份的历史证据 |

`internal_data/manual_key_layout.json` 是唯一可编辑布局真源。不得手工修补生成码表，也不得直接或间接读取其他 Git 仓库的数据；外部输入规则见[仓库数据边界](docs/project/YIME_REPOSITORY_DATA_BOUNDARY.md)。

## 协作与发行

后续任务从最新 `main` 建立目标明确的 `codex/*` 分支；`perf/i7-7820x-local` 用于测试端报告。已结束的 `codex/yimecore-replacement-experiment` 阶段保留在 Git 历史。新包先在开发端验证，再提交推送并通过 CI，最后按交接交付完整包。

[贡献指南](CONTRIBUTING.md) · [工程约束](AGENTS.md) · [发布与签名](docs/YIME_RELEASE_AND_SIGNING.md) · [安全策略](SECURITY.md) · [变更日志](CHANGELOG.md)

Rime/PIME 版由 [EasyIME/PIME](https://github.com/EasyIME/PIME) 派生并独立维护，不是上游官方版本。相关上游历史、版权与许可证保留；YimeCore 是独立运行产品。关系说明见 [NOTICE.md](NOTICE.md)。

PIME 派生组件保留原版权和 `LGPL-2.0-or-later` 条款；除非另有说明，Yime 新增软件采用 `LGPL-2.1-or-later`。第三方引擎、数据、字体和库适用各自许可证，见 [LICENSE.txt](LICENSE.txt)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [LICENSES](LICENSES)。
