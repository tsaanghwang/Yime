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
- Node.js（McBopomofoWeb，可选）

## 代码风格

### Go

- 遵循 [Effective Go](https://go.dev/doc/effective_go) 和 `gofmt`
- 导出函数必须有 godoc 注释
- 错误处理使用显式 `if err != nil`，不使用 panic

### PowerShell（嵌入 Go 字符串常量）

- 函数名使用 `Verb-Noun` 格式
- 变量名使用 camelCase
- 在 Go 原始字符串（反引号）中，PowerShell 的反引号转义（`` `n `` 等）不可用，需用 `[char]13` + `[char]10` 代替

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

- `yime-stable`：主开发分支，所有 PR 合并目标
- `main`：上游 PIME 主分支，不直接修改

## Pull Request 流程

1. 从 `yime-stable` 创建特性分支
2. 确保通过所有测试：`go test ./...`（在 `go-backend/` 目录）
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

## 许可证

贡献的代码将按照项目现有许可证（LGPL 2.0）授权。
