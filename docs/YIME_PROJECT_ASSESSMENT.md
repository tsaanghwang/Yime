# Yime 项目综合评估与收口报告

> 评估日期：2026-07-10
>
> 适用基线：`yime-stable` 分支及本轮待提交修改
>
> 相关文档：[架构](YIME_ARCHITECTURE.md) | [测试](YIME_TESTING_GUIDE.md) | [发布与签名](YIME_RELEASE_AND_SIGNING.md) | [原生 UI](YIME_NATIVE_UI_GUIDELINES.md)

本文汇总近期两轮全面评估及连续修复的结果，用于回答三个问题：当前项目是否完整、已处理哪些系统性风险、正式发布前还缺少哪些验证。专题实现细节仍以各专项文档为准，本报告只维护结论、证据和未闭环事项。

## 1. 总体结论

Yime 已从“功能基本可用但工具链和安装态边界不稳定”进入“开发版可持续验证、正式版具备明确发布门禁”的阶段。输入法核心、原生工具、用户词库、反查、语言栏命令、异步部署、构建和 CI 均已有回归保护。

当前不应把“CI 绿色”等同于“正式发布完成”。开发包允许未签名；公开发行仍必须完成可信签名和安装态 TSF 冒烟测试。

| 领域 | 当前状态 | 结论 |
|------|----------|------|
| 输入法核心与 Rime | 稳定 | 原生分页权、候选数回读、方案切换和用户词库链路有守卫 |
| Win32 工具 UI | 基本完整 | 设置、反查、词库、诊断和工具箱已脱离运行时 PowerShell |
| 活动会话刷新 | 已完成 | 设置、词库和 redeploy 使用独立累积修订号，不再互相覆盖 |
| 语言栏 | 已清理 | 保留静态标签和稳定命令 ID；高风险点击路径有回归测试 |
| 构建与打包 | 稳定 | 8 个 Go EXE 可复现、统一图标、包内不携带 Go 源码 |
| CI 与测试 | 完整度较高 | Go、Rust、CTest 和发布守卫均进入流水线 |
| 正式签名发布 | 流程已具备 | 尚需真实受信任证书和签名产物验证 |
| 安装态验证 | 部分完成 | 本轮未执行真实安装后的 TSF/语言栏人工冒烟测试 |

## 2. 两轮评估已处理事项

### 2.1 工具与用户体验

- 词库管理补齐连续添加、编辑、删除、权重步进、系统词重复拒绝和用户词库应用链路。
- 统一原生对话框中文按钮和居中布局，消除残留的 `OK`、`Yes/No`。
- 反查工具重新排列查询控件，统一横排宽度并让内部布局撑开主窗体。
- 设置、词库和反查等工具改为 Go + Win32；PowerShell 只保留在开发、测试、构建、安装和维护路径。
- 设置和词库部署移到后台 goroutine，通过 `WM_APP` 回到 UI 线程，避免窗口卡顿和控制台闪烁。

### 2.2 输入法与宿主集成

- 用户词库重新接入三种 Rime 方案，并在应用后通知已存在的输入会话。
- `yime_runtime_change.json` 从单一 scope 改为设置、词库和 redeploy 的独立累积修订号。
- 通知写入增加跨进程锁、旧格式迁移、损坏文件备份、Windows 文件替换重试和多会话独立消费。
- 语言栏实验性动态移动、排序和固定 GUID 逻辑已清理；命令解析继续兼容宿主通过 `data.id` 上报子菜单点击。
- 保持 Rime 拥有原生候选分页，不使用 Go 侧切片绕过候选数配置。

### 2.3 构建、CI 与发布

- Go 构建默认使用仓库内 `GOCACHE`/`GOTMPDIR`，降低临时目录被策略阻止或无权限的概率。
- 8 个 Go EXE 使用稳定版本、`-trimpath -buildvcs=false` 和统一 Yime 图标；连续构建哈希一致。
- 打包脚本递归清理复制目录中的 `.go` 文件，避免发布包泄露源码并防止 `go test ./...` 重复执行打包副本。
- CI 增加反查测试、根包测试、Rust 格式检查和 CTest 实际执行。
- 标签发布强制导入可信签名证书；临时 PFX 在导入后删除。
- 签名前检查私钥、有效期、RSA 和代码签名 EKU；签名后检查签名者指纹及时间戳。
- CI 明确区分 `YIME-unsigned-test-installer` 和 `YIME-signed-installer`。
- 修复 Win32 剪贴板写入失败路径中的 `HGLOBAL` 泄漏，以及 Rust 集成测试临时目录泄漏。

## 3. 固化的架构约束

以下约束不得为了局部问题而绕开：

1. 真实 Rime 会话继续拥有候选分页权，`nativeBackend.UsesBackendCandidatePaging()` 保持为 `true`。
2. Go 的 `candidatePageSize` 必须通过 `rimeState.PageSize` 与 Rime `menu.page_size` 回读同步。
3. 语言栏菜单 ID、反查 ID 或宿主点击解析发生变化前，先增加具体点击路径的回归测试。
4. 用户工具运行时不得调用 PowerShell；耗时工作不得阻塞 Win32 UI 线程。
5. 活动会话通知是广播状态，不是单消费者队列；每个 IME 会话独立记录已处理修订号。
6. 开发包和发行包必须明确区分，未签名开发包不得作为公开正式版本上传。
7. 源码修复只有在重新构建、安装并重启相关进程后，才算完成安装态验证。

## 4. 验证基线

本轮已通过：

```powershell
cd go-backend
go vet ./...
go test ./... -shuffle=on -count=2 -timeout 120s

cd ..\PIMELauncher
cargo fmt --check
cargo test --verbose

cd ..
ctest --test-dir build -C Release --output-on-failure
git diff --check
```

验证结果：

- Go 全量测试通过，运行时通知并发压力测试连续 20 轮通过。
- Rust 11 个单元测试和 2 个集成测试通过。
- CTest 3/3 通过。
- 8 个 Go EXE 连续两次构建 SHA-256 一致。
- NSIS 开发安装包构建成功，包内未发现 `.go` 源码。
- 上一轮远端 GitHub Actions 构建成功。

未纳入本轮完成证明：

- `go test -race`：本机缺少 GCC，Windows Go race 构建无法执行。
- 可信签名验证：本机没有用于本次构建的正式发布证书。
- 安装态 TSF 冒烟测试：本轮没有安装新包并重启 PIMELauncher/server。

## 5. 开发版与发行版边界

| 场景 | 是否必须购买/使用公开受信任证书 | 要求 |
|------|----------------------------------|------|
| 开发者本机源码构建 | 否 | 标记为开发包，不公开发布 |
| 受控测试机 | 否 | 可使用未签名包、内部 PKI 或显式部署的测试信任 |
| GitHub 分支/PR 构建 | 否 | 产物名保持 `YIME-unsigned-test-installer` |
| 面向普通用户公开发布 | 是 | RSA Authenticode、时间戳、全文件签名验证 |
| GitHub `v*` 标签发布 | 是 | 缺少证书时 CI 必须失败 |

公开发布可选择受信任 CA 证书、Microsoft Artifact Signing，或在满足条件时申请 SignPath Foundation 开源签名。自签名证书只适用于开发和受控环境，不能作为公开分发方案。

## 6. 剩余风险和下一步

### 发布前必须完成

- 使用可信签名服务或证书生成一次完整签名安装包，并运行 `tools/verify-release-signatures.ps1 -IncludeInstaller`。
- 通过标准 `Reinstall-PIME-Test.cmd` 安装，核对构建与安装文件哈希。
- 在记事本等真实 TSF 宿主中验证激活、组字、选词、三个语言栏按钮和所有工具入口。
- 检查 CodeIntegrity 日志没有新增 3033、3077 或 3118 阻止事件。
- 验证设置“应用并重建”和用户词库应用后，已有输入会话无需注销即可刷新。

### 可接受的开发期限制

- 未签名开发包可能被 Smart App Control 或企业 Application Control 阻止。
- 缺少 GCC 时不运行 Go race detector，但不得删除现有并发压力测试。
- 真实 Rime 集成测试继续显式启用，避免普通测试共享本机 librime 全局状态。

## 7. 文档维护规则

- 行为和进程边界变化：更新 [架构文档](YIME_ARCHITECTURE.md)。
- 新增或调整测试门禁：更新 [测试指南](YIME_TESTING_GUIDE.md)。
- Win32 布局、按钮或模态行为变化：更新 [原生 UI 规范](YIME_NATIVE_UI_GUIDELINES.md)。
- 打包、签名或 CI 产物变化：更新 [发布与签名指南](YIME_RELEASE_AND_SIGNING.md)。
- 用户数据格式变化：更新 [数据格式参考](YIME_DATA_FORMAT_REFERENCE.md)，并说明迁移兼容性。
- 本报告只更新结论、验证状态和剩余风险，不复制专题文档的实现细节。
