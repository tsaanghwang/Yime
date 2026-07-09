# 独立工具开发指南

本文档说明如何为 Yime 添加新的独立工具（如词库管理器、反查编码等）。

## 架构概览

Yime 的工具以独立 Win32 GUI 进程运行，不在 TSF 回调中嵌入 UI。工具通过工具箱（tool-hub.exe）统一启动，工具箱读取 manifest JSON 决定显示哪些工具。

启动链路：语言栏 → server.exe → tool-hub.exe → 具体工具.exe

## 添加新工具的步骤

### 1. 创建工具可执行文件

在 `go-backend/cmd/<tool-name>/main.go` 创建入口：

```go
//go:build windows

package main

import (
    "fmt"
    "os"
)

var version = "dev"

func main() {
    // 解析命令行参数
    // 构建并显示 Win32 窗口
    // 处理用户交互
}
```

工具通过命令行参数接收目录路径：

| 参数 | 说明 |
|------|------|
| `-SharedDir` | 共享数据目录（含 dict.yaml、TSV 等） |
| `-UserDir` | 用户数据目录（%APPDATA%\PIME\Rime） |
| `-Mode` | 当前编码方案（variable/full/shorthand） |
| `-HelpDir` | 帮助文档目录 |
| `-LogDir` | 日志目录 |

### 2. 注册到工具目录

编辑 `go-backend/input_methods/yime/yime_tool_catalog.go`，在 `buildToolHubManifest` 函数的 `Tools` 切片中添加条目：

```go
{
    ID:               "my-tool",
    Label:            "我的工具",
    Description:      "工具说明（可选，显示为 tooltip）",
    ActionType:       toolActionRunExecutable,
    TargetPath:       myToolPath,
    Arguments:        []string{"-SharedDir", sharedDir, "-UserDir", userDir},
    CloseAfterLaunch: true,
},
```

`ActionType` 两种选择：
- `toolActionRunExecutable`：启动可执行文件
- `toolActionOpenPath`：在资源管理器中打开路径

### 3. 添加路径解析

在 `go-backend/input_methods/yime/yime_tool_hub_windows.go` 中：

1. 添加 `IME.myToolPath()` 方法，返回工具 exe 的完整路径
2. 在 `ensureToolHubManifest()` 中调用该方法获取路径
3. 添加 `os.Stat` 检查确保文件存在

### 4. 集成到构建脚本

在 `go-backend/build.bat` 的 Step 3 中添加构建步骤：

```batch
echo [INFO] Generating Windows VERSIONINFO resources for my-tool ...
go-winres simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --file-description "My Tool Description" --original-filename "my-tool.exe" --manifest gui --out cmd\my-tool\rsrc_mytool
if errorlevel 1 (
    echo [WARN] go-winres failed for my-tool.exe, building without VERSIONINFO
    if exist cmd\my-tool\rsrc_mytool_windows_amd64.syso del cmd\my-tool\rsrc_mytool_windows_amd64.syso
)

echo [INFO] Building my-tool.exe ...
go build -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%PACKAGE_DIR%\my-tool.exe" .\cmd\my-tool
if errorlevel 1 (
    echo [ERROR] Failed to build my-tool.exe
    if exist cmd\my-tool\rsrc_mytool_windows_amd64.syso del cmd\my-tool\rsrc_mytool_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\my-tool\rsrc_mytool_windows_amd64.syso del cmd\my-tool\rsrc_mytool_windows_amd64.syso
```

关键参数：
- `-H=windowsgui`：隐藏控制台窗口
- `--manifest gui`：生成 GUI 应用 manifest（非 CLI）
- `go-winres` 生成的 `.syso` 文件放在 `cmd/<tool>/` 目录下，编译后立即清理

### 5. 添加测试

在 `yime_test.go` 中添加测试验证：
- 工具目录中包含新工具的条目
- manifest 验证通过（ID 唯一、Label 非空、TargetPath 非空）

## PowerShell 脚本工具（旧方式）

部分工具（反查编码、词库管理器）仍使用嵌入 Go 字符串常量的 PowerShell 脚本，通过 `tool-launcher.exe` 启动。新工具建议使用原生 Win32 可执行文件方式。

如果必须使用 PowerShell 脚本：
- 脚本嵌入在 Go 文件的原始字符串常量中（反引号包围）
- PowerShell 的反引号转义（`` `n ``、`` `r `` 等）不可用，用 `[char]13` + `[char]10` 代替
- 用 `[IO.File]::ReadAllLines()` 代替 `Get-Content` 以获得更好的 I/O 性能
- 用 `@()` 包裹函数返回值防止 PowerShell 拆包单元素数组
- 用变量插值代替 `-f` 格式化，避免词条中的花括号导致异常

## 已注册工具列表

| ID | 标签 | 类型 | 可执行文件 |
|----|------|------|-----------|
| lexicon-manager | 词库管理 | run_executable | lexicon-manager.exe |
| reverse-lookup-tool | 反查编码 | run_executable | reverse-lookup.exe |
| system-lexicon-audit | 系统词库审查 | run_executable | system-lexicon-audit.exe |
| user-blocklist-manager | 用户屏蔽词表 | run_executable | blocklist-manager.exe |
| settings-tool | 设置工具 | run_executable | settings-tool.exe |
| diagnostics-tool | 诊断工具 | run_executable | diagnostics-tool.exe |
| settings-data | 用户数据目录 | open_path | — |
| shared-data | 共享数据目录 | open_path | — |
| help-readme | 查看帮助 | open_path | — |
| help-trial-feedback | 反馈说明 | open_path | — |
