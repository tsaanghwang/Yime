# 贡献指南

感谢你对 Yime 项目的关注！本文档说明如何参与贡献。

## 先确定目标产品

按 [2026-09-05 双独立产品开发计划](docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，Yime 包含 Rime/PIME 版与 YimeCore 自研版。两版可各自单独安装或同时安装，运行、升级、卸载和用户数据互不依赖。YimeCore 是主要开发线；Rime/PIME 保持稳定维护和可选行为对照，不要求同步实现全部功能或绑定发布。

开始任务及提交 PR 时注明影响范围：共同规范源、Rime/PIME、YimeCore 或共存安装；列出受影响产品与必需回归。共享源码不表示需要安装另一版，比较结果不表示必须照抄另一版行为。共同规则变更仍须执行两版受影响的既有回归，独立运行验收则分别完成。

## 提交 Issue

- 描述问题时请包含：目标产品、Windows 版本、产品版本／包身份、宿主位数、脱敏复现步骤、预期行为与实际行为。
- Rime/PIME 问题可在获得用户许可后检查其 `%APPDATA%\PIME\Rime\go_backend.log`；这不是 YimeCore 日志入口。不要直接上传完整日志、用户正文、编码、候选或学习内容，优先记录合成夹具结果和必要的脱敏错误字段。

## 开发环境

详见 [README.zh-CN.md](README.zh-CN.md) 的"构建要求"章节。核心依赖：

- Visual Studio 2022（CMake + C++ TSF）
- Go 1.26.4（CI 和可复现构建版本；`go.mod` 的 1.21 是语言兼容下限）
- Rust（PIMELauncher）

上述 PIMELauncher／根构建入口属于 Rime/PIME 产品。YimeCore 构包与隔离测试入口见 [tools/yimecore](tools/yimecore/README.md)，从当前源码和显式数据构建，不依赖已安装 Rime/PIME 或 PIMELauncher；具体工具链和目标范围由各自构包描述约束。

## 代码风格

### Go

- 遵循 [Effective Go](https://go.dev/doc/effective_go) 和 `gofmt`
- 导出函数必须有 godoc 注释
- 错误处理使用显式 `if err != nil`，不使用 panic

### PowerShell

- 运行时工具、输入法服务和语言栏回调不得启动或嵌入 PowerShell
- PowerShell 仅用于开发、测试、构建、安装和维护脚本
- 函数名使用 `Verb-Noun`，变量名使用 camelCase
- 原生工具 UI 修改遵循 [原生 Win32 UI 规范](docs/YIME_NATIVE_UI_GUIDELINES.md)

### Commit 消息

使用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>(<scope>): <description>

[optional body]
```

类型：

| 类型 | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 错误修复 |
| `perf` | 性能改进 |
| `refactor` | 代码重构（不改变行为） |
| `docs` | 文档变更 |
| `test` | 测试新增或修改 |
| `chore` | 构建/依赖/CI 变更 |
| `ci` | CI 配置变更 |

范围示例：`yime`、`tools`、`ci`、`build`

## 分支策略

- `main`：Yime 稳定主分支和发布基线
- `yime-stable`：持续维护的集成分支
- `codex/**`：任务分支命名空间，push 时同样触发 CI
- `upstream` remote：EasyIME/PIME 上游历史，仅用于来源追踪和选择性同步

## Pull Request 流程

1. 从适用基线创建 `codex/**` 特性分支
2. 按影响范围选择 [测试与验证指南](docs/YIME_TESTING_GUIDE.md) 或 [YimeCore 测试入口](tools/yimecore/README.md)，保留 Go 稳定集 `go vet ./...` 和 `go test ./...` 等适用门禁；共同源变更覆盖两版受影响的产物，测试环境不得使用生产用户数据。
3. Rime/PIME 构包使用仓库根 `build.bat` 及其 Win32/x64、Go、PE 门禁；YimeCore 使用当前范围允许的 `tools/yimecore/build-local-product.ps1` 和对应隔离验证，不通过构建或启动另一产品来证明本版可用。仅文档调整执行链接、差异与一致性检查，不为此构建或安装产品。
4. 提交 PR，标题使用 Conventional Commits 格式
5. 等待 `core-build` 聚合门禁和 review 通过后合并

## 重要约束

修改以下区域前**必须**添加回归测试，详见 [AGENTS.md](AGENTS.md)：

- 语言栏命令 ID 或点击行为
- 候选分页逻辑
- `menu/page_size` 读写
- 子菜单命令解析（`data.id` 回退）
- TSF 回调行为

源码验证不等于已安装生效。需要宣称修复在安装版生效时，必须针对目标产品取得构包、安装和受影响宿主的证据；真实安装、停进程、默认切换和数据操作只在已获授权的范围执行：

- Rime/PIME 修复：依 [AGENTS.md](AGENTS.md) 核对安装版 `C:\Program Files (x86)\YIME\go-backend\server.exe` 等受影响二进制确已更新，以及本版 PIMELauncher／server 已按批准流程重启；不得凭源码测试推断旧安装已修复。
- YimeCore 修复：核对本版 manifest、安装根、Runtime／Broker 和实际宿主加载的当前身份 TSF DLL，按变更范围完成注册／人工宿主及必要重启验收；不启动、停止、重新安装或改写生产 Rime/PIME 来验证自研版。
- 未获安装授权时停在隔离验证和交接，明确“未安装／待实机验证”，不自行扩大任务。维护一版必须保护另一版和默认输入法，卸载也只能清理本版拥有的资源。

涉及版本、构建脚本、安装包或对外发布时，遵循 [发布与代码签名指南](docs/YIME_RELEASE_AND_SIGNING.md)。

## 许可证

提交贡献即表示贡献者确认自己有权提交相关代码、数据或其他材料，并同意按对应
组件现有许可证提供贡献：PIME 派生组件遵循其原有 `LGPL-2.0-or-later` 条款；
除非文件另有说明，Yime 新增软件采用 `LGPL-2.1-or-later`。第三方材料不得删除、
替换或弱化其原版权和许可证声明。

贡献者不得提交来源不明、无再分发授权或与目标组件许可证不兼容的代码、字体、
词库、语料或二进制文件。PR 必须说明新增第三方材料的来源、版本、许可证和修改
情况；适用时同步更新 `THIRD_PARTY_NOTICES.md` 与 `LICENSES/`。Git 提交作者信息
和仓库历史用于记录贡献归属，但不取代文件自身的版权与许可证声明。
