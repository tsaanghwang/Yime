# 音元输入法 Windows 版

**音元拼音** — 基于 [PIME](https://github.com/EasyIME/PIME) 框架和 [Rime](https://rime.im) 引擎的 Windows 中文音码输入法。

[English](README.md)

音元输入法将拼音音节映射到结构化的键盘编码，声母遵循易记的规律（zh/ch/sh → 7/8/9，j/q/x → 3/2/1，z/c/s → 6/5/4）。提供三种编码模式：变长模式（默认）、等长模式（每音节固定4键，无重码）、省键模式（最短编码）。

## 功能特性

- **三种编码模式** — 变长、等长、省键，可从语言栏切换
- **Rime 引擎驱动** — 表格式翻译器，每方案 468K+ 词条，加权频率排序
- **候选窗** — 每页 5–9 个候选，竖排或横排，一键切换
- **反查功能** — 候选旁显示标准拼音、音元编码或键位序列
- **用户词库** — 用数字标调拼音添加自定义词组，自动转换为音元编码
- **独立工具** — 设置、诊断、反查、词库管理、系统词库审查、用户屏蔽词表均以原生 Win32 可执行文件运行
- **语言栏** — 输入法列表名「音元」；切换按钮固定显示「中西 / 全半 / 横竖」，当前状态由图标表示

## 仓库结构

```
go-backend/              Go 后端：Yime 输入法逻辑、Rime 集成、独立工具
  input_methods/yime/    Yime 专用代码和数据
    yime.go              核心：按键处理、语言栏、候选窗
    librime.go           Rime DLL 加载和部署
    data/                方案、词典、编码映射、拼音表
    help/                用户帮助文档
PIMETextService/         TSF 文本服务宿主（C++/COM）
PIMELauncher/            进程启动器和监控（Rust）
installer/               NSIS 安装程序资源
libIME2/                 上游 IME 库
docs/                    开发文档
```

## 分支

| 分支 | 用途 |
|------|------|
| `main` | 稳定基线 |
| `yime-stable` | 活跃开发（CI 目标分支） |
| `yime-on-pime` | Windows 集成分支 |

编码体系、词典和实验性原型工作在独立的 `Yime-prototype` 仓库中。

## 构建要求

- [Visual Studio 2022](https://visualstudio.microsoft.com/vs/)，含 C++ 桌面开发工作负载
- [CMake](https://cmake.org/) 3.0+
- [Rust](https://rustup.rs/)，含 `i686-pc-windows-msvc` 目标
- [Go](https://go.dev/) 1.21+
- [Git](https://git-scm.com/)

## 构建

### 克隆和初始化

```powershell
git clone git@github.com:tsaanghwang/Yime.git
cd Yime
git submodule update --init libIME2
```

活动子模块 `libIME2` 指向 `tsaanghwang/libIME2` fork。若在主仓库中更新了子模块指针，请**先**将对应 commit 推送到子模块 remote，再推送 Yime，否则 CI checkout 会失败。

### 安装 Rust 目标

```powershell
rustup toolchain install stable-i686-pc-windows-msvc --profile minimal
```

这里必须安装完整的 i686 **主机工具链**，不能只在默认 x64 工具链上执行
`rustup target add i686-pc-windows-msvc`。根目录 CMake 已固定该工具链，以避免
Corrosion 将 x64 主机构建脚本和 i686 MSVC 库混用。如果命令行找不到 `cargo`，
但 `%USERPROFILE%\.cargo\bin\cargo.exe` 存在，应把该目录恢复到用户 `PATH`，
不要修改 CMake、Corrosion 版本或 `PIMELauncher/.cargo/config.toml`。

### 构建宿主（32 位）

```powershell
cmd /c build.bat
```

### 构建 Go 后端

```powershell
cd go-backend
cmd /c build.bat
```

Go 工具版本取自 `version.txt`，构建使用稳定哈希参数。正式发布时应设置 `YIME_SIGN_CERT_SHA1`，使用受信任提供商签发的 RSA 代码签名证书；仅有 VERSIONINFO 不能保证通过 Smart App Control。

### 构建 64 位文本服务

```powershell
cmake . -Bbuild64 -G "Visual Studio 17 2022" -A x64
cmake --build build64 --config Release --target PIMETextService
```

## 安装

### 开发重装

在管理员提示符下运行：

```powershell
.\Reinstall-PIME-Test.cmd
```

此脚本包含预检、DLL 锁检测和自动回退。请勿简化——参见 `AGENTS.md` 中的约束。

### 分发

验证 NSIS 安装包包含 Go 后端后，分发 `installer\YIME-*-setup.exe`。参见 [docs/dev-build-reinstall.html](docs/dev-build-reinstall.html)。

### 手动注册

```powershell
regsvr32 "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

注销：

```powershell
regsvr32 /u "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 /u "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

## 首次运行检查清单

- [ ] 克隆仓库，初始化子模块，确认工具链已安装
- [ ] 从仓库根目录运行 `cmd /c build.bat`
- [ ] 从 `go-backend` 目录运行 `cmd /c build.bat`
- [ ] 若 Rime 数据有变更，运行 `tools\deploy-yime-rime-data.ps1`（参见 [docs/YIME_RIME_INTEGRATION.md](docs/YIME_RIME_INTEGRATION.md)）
- [ ] 在管理员提示符下运行 `.\Reinstall-PIME-Test.cmd`
- [ ] 在文本应用中切换到音元输入法，验证：激活、候选窗、设置、反查
- [ ] 发布后端变更前，从 `go-backend` 运行 `go test ./input_methods/yime/...`

## 编码参考

### 声母→键盘映射

| 声母 | 键 | 声母 | 键 | 声母 | 键 |
|------|-----|------|-----|------|-----|
| b | q | p | p | m | h | f | [ |
| d | w | t | . | n | y | l | b |
| g | ] | k | ' | h | n | | |
| zh | 7 | ch | 8 | sh | 9 | r | 0 |
| z | 6 | c | 5 | s | 4 | | |
| j | 3 | q | 2 | x | 1 | | |
| w | % | y | $ | | | | |

### 候选选择键

| 按键 | 物理键面 | 候选窗标签 | 选择 |
|------|----------|------------|------|
| Space / Enter | Space / Enter | — | 第 1 个候选 |
| Shift+1 | `!` | `⇧1` | 第 1 个候选 |
| Shift+2…Shift+9 | `@ # $ % ^ & * (` | `⇧2`…`⇧9` | 第 2…9 个候选 |

候选窗不直接用标点键面作序号，因为连续标点不易辨认。与流行拼音输入法不同，Yime 有意不采用裸数字键选词：`1`…`9` 始终属于编码输入，候选出现时也不会切换含义；按序号选词统一使用 Shift+数字。

## 调试

带控制台窗口启动：

```powershell
PIMELauncher.exe /console
```

日志位于 `%LOCALAPPDATA%\PIME\Logs\go_backend.log`。

## 文档

| 文档 | 说明 |
|------|------|
| [项目综合评估](docs/YIME_PROJECT_ASSESSMENT.md) | 两轮全面评估结论、已完成修复、验证证据和剩余风险 |
| [架构文档](docs/YIME_ARCHITECTURE.md) | 系统架构、关键机制、数据文件 |
| [可用性评估](docs/YIME_USABILITY_ASSESSMENT.md) | 当前可用性问题及优先级 |
| [开发路线图](docs/YIME_DEVELOPMENT_ROADMAP.md) | 分阶段路线图、修复流程、AGENTS.md 约束 |
| [Rime 集成](docs/YIME_RIME_INTEGRATION.md) | Rime 数据流、pinyin_normalized.json 链、维护检查清单 |
| [工具策略](docs/YIME_TOOLING_STRATEGY.md) | 独立工具 vs. 语言栏 UI 设计 |
| [独立工具开发指南](docs/YIME_TOOL_DEVELOPMENT_GUIDE.md) | 如何添加新的独立工具 |
| [原生 UI 规范](docs/YIME_NATIVE_UI_GUIDELINES.md) | Win32 布局、对话框、用词、焦点与 UI 测试规范 |
| [测试与验证指南](docs/YIME_TESTING_GUIDE.md) | CI 分层、真实 Rime 测试和安装态验证 |
| [发布与代码签名](docs/YIME_RELEASE_AND_SIGNING.md) | 可复现构建、Authenticode、打包与回滚流程 |
| [数据文件格式参考](docs/YIME_DATA_FORMAT_REFERENCE.md) | TSV/JSON/YAML 数据文件格式规范 |
| [用户安装指南](docs/YIME_USER_INSTALL_GUIDE.md) | 面向最终用户的安装和使用说明 |
| [故障排除指南](docs/YIME_TROUBLESHOOTING.md) | 常见问题排查 |
| [变更日志](CHANGELOG.md) | 版本变更记录 |
| [贡献指南](CONTRIBUTING.md) | PR 流程、代码风格、commit 格式 |
| [安全策略](SECURITY.md) | 私密漏洞报告方式及项目安全边界 |
| [AGENTS.md](AGENTS.md) | AI 辅助开发约束 |

## 问题反馈

在本仓库提交 Issue。涉及上游 PIME 的框架级问题应同时交叉引用 [EasyIME/PIME](https://github.com/EasyIME/PIME)。

## 与 PIME 的关系

Yime for Windows 是从 [EasyIME/PIME](https://github.com/EasyIME/PIME)
派生并由 Yime 项目独立维护的下游发行版。Yime 复用并修改了 PIME 的 Windows
TSF 文本服务宿主、进程启动器、后端通信协议以及安装与注册基础设施，并保留相关
的上游 Git 历史、版权声明和许可证条款。音元编码体系、Rime 集成、词库、维护工具
及 YIME 产品配置由 Yime 项目新增和维护。

Yime 不是 EasyIME/PIME 的官方版本，与 EasyIME/PIME 及其原作者不存在隶属、
授权代理、赞助或背书关系。代码和安装目录中保留的 PIME 内部名称只用于技术兼容，
不代表产品或发布者品牌。完整说明见 [NOTICE.md](NOTICE.md)。

## 许可证

PIME 派生组件保留原版权声明及 `LGPL-2.0-or-later` 条款；除非另有说明，Yime
新增软件采用 `LGPL-2.1-or-later`。第三方引擎、数据、字体、库和安装器插件继续
适用各自许可证。详见 [LICENSE.txt](LICENSE.txt)、
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES](LICENSES)
目录。
