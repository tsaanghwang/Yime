# ASUS ARM64：正文焦点绑定修复完整包

后续完整包已发布并在本地完整展开；当前旧 DLL 的宿主占用仍阻止安装。最新交付与安装前状态见 [DELIVERY.zh-CN.md](DELIVERY.zh-CN.md)。以下构包原始记录保留，不代替安装和输入验收。

2026-11-06。本记录仅证明构建和完整包验证；不证明已安装或记事本真实输入修复成功。
固定运行源码为 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`，对应[源码 CI 记录](../../../18u/2026-11-05/arm64-binding-focus/ci-receipt.json)。
所有本产品程序均在该提交的全新、干净 detached 工作树重新构建，不复用已安装产品或旧构建中的二进制。

## 固定包

| 项目 | 值 |
|---|---|
| 版本 | `0.2.0-18u-arm64.5` |
| 完整 ZIP | `yime-yimecore-18u-windows-arm64-636cef681ee9.zip` |
| 大小 | 219933775 字节 |
| ZIP SHA-256 | `e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c` |
| 外部 identity SHA-256 | `d94ac9817f5e4c6b2090ec64bad6ff79a124efe9d71c086876c348207287ceb1` |
| 安装载荷 manifest SHA-256 | `d536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be` |
| maintenance plan SHA-256 | `60f1ea319de814858086dd1383a521389bb1cc7aa57870005f0f37ccd6b55180` |
| 原生维护程序 SHA-256 | `36d655beca9f5bcca485ee9d143ce9a7c2d8c9fb79218a4506f516000832b2b9` |

本地完整 ZIP 为 `C:\dev\Yime\.wt\bindfix\.generated\package-binding-636cef68\complete\yime-yimecore-18u-windows-arm64-636cef681ee9.zip`，相邻 `.identity.json` 记录全部成员。
完整展开目录为同一构包根下的 `simple\package`；其中已经附加原生维护程序和固定 PowerShell。
`simple` 目录中较早生成的中间 ZIP 没有完整维护依赖，不用于安装交付。
远端发布及安装状态由本轮后续交付记录另记；本构包步骤没有发布或安装。

固定源码中的 `FRONTEND_VERSION` 常量仍为 `.4`。本轮经批准通过构包 wrapper 的进程内参数将有效版本设为 `.5`，用于区分新包；未修改该源码文件或编译后程序。
[版本参数](raw/version-configuration.json)及[构包脚本](raw/build_package.py)明确保留这一差异，不声称源码常量本身已经变成 `.5`。

## 构建与验证

- 原生 ARM64 MSVC 构建：专用 DLL、注册工具、正式宿主、已安装前端宿主和异步回归程序，共五个目标；仅异步回归程序在本构包任务中执行。
- 原生 ARM64 Go 1.25.14 重建：Broker、触摸前端及专用 Runtime；同源重新编译 `YimeMaintenance.exe` 并绑定本次维护计划。使用进程内 `GOENV=off`、`GOTOOLCHAIN=local`、`GOPROXY=off` 和独立缓存，没有全局 Go 配置修改。
- 词库严格匹配固定源码的 `resources.lock.json`，使用既有内容锁缓存；完整 PowerShell 使用既有锁定的 ARM64 离线缓存，逐文件复核。它们不是已安装 Yime 产品的运行依赖。
- 新构建的 `YimeDedicatedAsyncTests.exe` **17 组通过**：真实自有子进程管道、Win32 查询替身和内存 TSF；没有注册或真实应用输入。包含正文线程与顶层线程不同的查询正例、焦点控件/根/归属变化的延迟写入拒绝。
- 组装器及最终独立核验均通过：**1156 个 ZIP 成员和展开文件逐 SHA-256 一致，20 个产品载荷全部匹配；7 个本产品 PE 均为 ARM64 `0xaa64`**。维护计划覆盖其余全部文件；`YimeMaintenance.exe -action Check` 成功，仅检查绑定、哈希和原生维护壳，不启动 PowerShell或执行产品维护。
- 签名观察：7 个本产品 PE 为 `NotSigned`；包内原生 `pwsh.exe` 为 Microsoft `Valid`。哈希与 Microsoft 运行时签名不等于本产品取得可信发布者签名。

入口如下，详细绝对命令与各阶段退出码见原始 command JSON 和[构建回执](raw/build-receipt.json)：

```text
python -B -X utf8 .generated/package-binding-636cef68/build_package.py build
python -B -X utf8 .generated/package-binding-636cef68/build_package.py package
python -B -X utf8 .generated/package-binding-636cef68/verify_package.py
```

PowerShell 均经固定源码的 `tools/powershell/run_checked.py --edition ps7`，复杂参数使用 JSON 文件。
本轮未执行注册器、已安装宿主测试、安装/卸载，不停止产品或文档进程，不修改默认输入法、校准文件或用户词库。
真实记事本绑定和中文正文仍须在匹配新包安装后另行观察；不能由上述隔离结果代填通过。

[完整包回执](raw/complete-package-receipt.json)、[独立验证](raw/independent-verification.json)、[原始证据哈希索引](raw/evidence-index.json)保留本轮来源、边界与逐字节证据。
