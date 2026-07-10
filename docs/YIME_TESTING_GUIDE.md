# Yime 测试与验证指南

本文档说明 Yime 的测试分层、CI 稳定集、真实 Rime 测试和安装态验证。测试强度应随修改风险增加，TSF/语言栏、候选分页和部署路径不能只依赖单元测试。

## 1. 测试层级

| 层级 | 目标 | 运行环境 |
|------|------|----------|
| 纯逻辑单元测试 | 词库、设置、反查、布局、构建脚本 | 普通 Windows 开发环境 |
| Go 根包关键回归 | 语言栏命令、分页权、工具启动、用户词库应用 | CI 与本地 |
| 真实 Rime 集成测试 | librime 会话、方案、部署、候选页大小 | 本地显式启用 |
| C++/Rust 测试与构建 | TSF 宿主、启动器、注册组件 | VS/Rust 工具链 |
| 安装态测试 | Program Files 中的真实二进制、进程、注册表和 Code Integrity | 管理员测试环境 |

## 2. CI 稳定集

在 `go-backend` 目录运行：

```powershell
go vet ./...
go test . ./cmd/lexicon-manager ./cmd/reverse-lookup-tool ./cmd/settings-tool `
  ./input_methods/yime/reverselookup `
  ./input_methods/yime/runtimechange `
  ./input_methods/yime/settings `
  ./input_methods/yime/systemlexicon `
  ./input_methods/yime/toolhub `
  ./input_methods/yime/userblocklist `
  ./input_methods/yime/userlexicon
go test ./input_methods/yime -timeout 60s
```

根包使用与 `.github/workflows/ci.yaml` 一致的关键测试正则。修改 CI 守卫时，应同步更新 [架构文档](YIME_ARCHITECTURE.md)。

CI 当前重点保护：

- 原生 Rime 保有候选分页权
- 语言栏双字标签稳定
- 部署命令和用户词库三方案应用
- 原生工具可执行路径
- 词库重复拒绝、权重边界和中文对话框布局
- 反查顶部单排布局与内容尺寸
- 可复现构建和签名入口

## 3. 全量根包门禁

`go test ./input_methods/yime -timeout 60s` 已进入 CI。普通单元测试通过可替换后端工厂、独立用户目录和语义化 YAML 断言与真实 librime 隔离；不得删除断言、放宽候选分页守卫或默认跳过普通测试来制造绿色结果。

独立工具通知活动会话的文件协议由 `runtimechange` 包测试，必须覆盖连续通知、并发写入、旧格式迁移、损坏恢复和多个 IME 会话独立观察；设置/词库工具还必须覆盖“成功后通知、失败不通知”。Win32 长任务应把外部部署放在 goroutine，并通过 `WM_APP` 返回 UI 线程。

运行 `go test ./...` 前后都不应发现 `go-backend/build/go-backend/input_methods` 下残留 `.go` 文件；发布包不得携带复制来的 Go 源码或测试。

普通 IME 测试不得消费开发者真实 `%APPDATA%` 中的 `yime_runtime_change.json`。测试会话应把现有修订号作为基线；只有通知协议专用测试从零修订开始观察，避免候选测试在选择前意外触发 redeploy。

## 4. 真实 Rime 集成测试

真实测试默认跳过，显式设置环境变量：

```powershell
cd go-backend
$env:YIME_RUN_REAL_RIME_TESTS = "1"
go test ./input_methods/yime -run TestReal -v -count=1
```

运行前确认 `input_methods/yime/data/` 完整，且没有其它测试或输入法进程同时操作相同 Rime 全局状态。测试结束后删除环境变量：

```powershell
Remove-Item Env:YIME_RUN_REAL_RIME_TESTS
```

## 5. 原生 UI 测试规则

Win32 UI 应把可计算布局抽成纯函数并测试：

- 控件顺序和无重叠
- 同排左右边界一致
- 内容边界决定客户区尺寸
- 标签按文字宽度收紧
- 按钮组居中且间距一致
- 最长中文标签不会被截断
- 取消、窗口 X 和确认返回值一致

现有示例：

- `TestBuildUILayoutPlacesSearchControlsInOneRow`
- `TestBuildUILayoutUsesEqualRowWidthsAndContentSizedWindow`
- `TestCenteredButtonRectsCentersGroupAndPreservesGaps`
- `TestWeightAdjustmentRectsFillContentRow`
- `TestNoticeTitleForFlags`
- `TestExecuteApplyNotifiesActiveSession`
- `TestNativeLanguageBarLeavesToggleIdentityAndSortToHost`

C++ RPC 回归测试通过 `ctest --test-dir build -C Release --output-on-failure` 执行，CI 不得只编译测试程序。

UI 修改还必须构建对应 EXE，并在安装目录中实际打开一次；源码测试通过不代表 Smart App Control、焦点和模态行为正常。

NSIS 守卫还必须确认默认安装目录不会被空注册表值覆盖、必装主组件包含 `go-backend`、标准安装不选择旧 Python Chewing，以及开发卸载会删除新旧卸载项。

## 6. TSF 与语言栏高风险测试

修改下列区域前先添加具体失败路径的回归测试：

- 语言栏命令 ID、子菜单 `data.id` 回退
- 动态按钮增删、排序、GUID 或 `GetInfo`
- Rime 激活、点击和会话重载
- `menu/page_size` 读写与回读链
- 候选分页所有权

必须遵守 `AGENTS.md`：原生 Rime 会话保持 `UsesBackendCandidatePaging() == true`，不得用 Go 侧候选切片掩盖配置问题。

## 7. 构建验证

```powershell
cd go-backend
cmd /c build.bat
```

连续构建哈希验证见 [发布与签名指南](YIME_RELEASE_AND_SIGNING.md)。`go-backend/build.bat` 在变量未设置时会把 `GOCACHE` 和 `GOTMPDIR` 指向仓库 `.tmp`；手工运行 `go test` 遭 Application Control 阻止时也应使用这两个工作区目录。这只解决本地执行位置，不替代发布签名。

## 8. 安装态验证

标准重装：

```powershell
.\Reinstall-PIME-Test.cmd
```

验证顺序：

1. 比较构建与安装 EXE 的 SHA-256
2. 确认安装文件 VERSIONINFO 与 `version.txt` 一致
3. 重启 PIMELauncher 和 `server.exe`，不需要注销 Windows
4. 复现原始失败路径
5. 检查 `%LOCALAPPDATA%\PIME\Logs\go_backend.log`
6. 检查 CodeIntegrity Operational 日志

语言栏或 TSF 问题必须在安装态至少复现一次；不能用源码目录中的临时 EXE 代替。

2026-07-11 的未签名开发包已完成一次真实安装验证：安装到 `C:\Program Files (x86)\YIME`，输入响应正常，用户词“云笺试码”和“笺砚验码”应用后可在活动会话直接出词。该记录证明核心路径，不替代重启、自启动、全部工具和三模式的完整清单。

## 9. 修改类型与最低验证

| 修改类型 | 最低验证 |
|----------|----------|
| 文档 | 链接、命令和当前行为核对，`git diff --check` |
| 纯 Go 逻辑 | 目标包测试 + 相关边界测试 |
| 原生工具 UI | 目标包测试 + EXE 构建 + 安装态打开 |
| Rime 配置/部署 | 设置与 Rime 测试 + 用户目录文件核对 + 安装态重载 |
| 语言栏/TSF | 具体点击回归 + C++ 构建 + 安装态宿主验证 |
| 发布构建 | CI 稳定集 + 可复现哈希 + 签名验证 + 安装烟雾测试 |
