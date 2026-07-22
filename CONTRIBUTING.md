# 贡献指南

感谢你对 Yime 项目的关注！本文档说明如何参与贡献。

## 提交 Issue

- 描述问题时请包含：Windows 版本、Yime 版本（语言栏帮助菜单查看）、复现步骤、预期行为与实际行为
- 附带 `%APPDATA%\PIME\Rime\go_backend.log` 日志有助于定位问题

## 开发环境

详见 [README.zh-CN.md](README.zh-CN.md) 的"构建要求"章节。核心依赖：

- Visual Studio 2022（CMake + C++ TSF）
- Go 1.21+
- Rust（PIMELauncher）

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
- `yime-stable`：Yime 集成分支；变更经验证后通过 PR 合入 `main`
- `upstream` remote：EasyIME/PIME 上游历史，仅用于来源追踪和选择性同步

## Pull Request 流程

1. 从 `yime-stable` 创建特性分支
2. 按 [测试与验证指南](docs/YIME_TESTING_GUIDE.md) 运行统一验证入口；Go 稳定集必须覆盖 `go vet ./...` 和 `go test ./...`
3. 确保通过构建：`build.bat`（在 `go-backend/` 目录）
4. 提交 PR，标题使用 Conventional Commits 格式
5. 等待 review 后合并

## 重要约束

修改以下区域前**必须**添加回归测试，详见 [AGENTS.md](AGENTS.md)：

- 语言栏命令 ID 或点击行为
- 候选分页逻辑
- `menu/page_size` 读写
- 子菜单命令解析（`data.id` 回退）
- TSF 回调行为

源码修改后**必须**验证安装效果：确认 `C:\Program Files (x86)\YIME\go-backend\server.exe` 时间戳已更新，并重启 PIMELauncher 和 server.exe 进程。

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
