# ASUS ARM64 `.5`：完整包交付与安装前状态

2026-11-06。用户已明确授权制作、安装同源完整 ARM64 修复包并复测 ASUS 记事本。本轮完整包和本地安装入口已准备好；**安装尚未启动，记事本绑定和中文正文尚未对新版复测**。

## 固定交付

- 源码：`636cef681ee995a21a9c45fd750f8cb4b0acb4a1`，四条精确源码 CI 工作流通过，21 个成功任务、3 个既有手动任务跳过。
- 版本：`0.2.0-18u-arm64.5`；全部本产品二进制重新构建，前端、Broker、TIP 和维护程序同源。版本构包参数与源码常量的差异见[构包记录](README.zh-CN.md)。
- 完整 ZIP：`yime-yimecore-18u-windows-arm64-636cef681ee9.zip`，219933775 字节。
- SHA-256：`e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c`。
- 本地交付：`C:\dev\Yime-deliveries\18u-binding-636cef68-20261106`。`package` 是已展开完整包，1156 个文件逐项复核，并在此最终目录运行原生 `YimeMaintenance.exe -action Check`，退出 0。该操作只读，不执行安装或 PowerShell。
- 点击入口：本地交付目录中的 `Install-18u-ARM64.cmd`。入口先 Check，再从普通用户调用标准 `YimeMaintenance.exe -action Install`；Windows 正常提升、安装保护和原用户启动流程保持。入口未运行。

完整包已发布为固定开发预发布：[Release](https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-18u-binding-636cef68-20261106)、[完整 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-arm64-18u-binding-636cef68-20261106/yime-yimecore-18u-windows-arm64-636cef681ee9.zip)。六个远端附件的大小和 SHA-256 均与本地一致，tag 指向精确源码，未标记为最新稳定版。见[发布回执](release/delivery-receipt.json)。源码 checkout 或 CI 预览包不能替代本完整包。

首次发布工具在创建空草稿后，用尚未生成的 tag 查询草稿而收到 HTTP 404；已保留[该工具错误](release/first-draft-lookup-failure.json)，改为核对准确 tag/source 后按 release ID 读取同一草稿，之后上传和发布通过。没有重复创建、覆盖资产或安装失败。

## 安装尚未启动的原因

两次只读 Restart Manager 查询均发现旧版 `C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll` 被以下当前宿主加载：

| 宿主 | PID | 当前边界 |
|---|---:|---|
| Windows 资源管理器 | 20092 | 安装指南禁止结束 Explorer/System 或强删文件 |
| Codex | 39152 | 承载当前会话，不能在保留会话的同时保证卸载其 DLL |
| Notepad | 11912 | Computer Use 观察到已有未保存文档；未编辑、保存或关闭它 |

固定源码 `go-backend/cmd/yime-maintenance/rime_validation.go` 的标准维护参数使用 `Silent=true`。安装顺序会先停止本产品后台，再进入文件占用检查；当前条件下启动 Install 会失败并造成不必要的后台停机。因此本轮没有发起这次已知被占用的安装，亦没有结束任何占用宿主、强制卸载或单独替换 DLL。这里是实际宿主占用，不是缺少用户授权，也不是新包已安装失败。

依据为 `installer/simple/README.md`：“不要结束 Explorer/System 或强删文件”。正常支持的继续方式是保存文档、退出相关宿主；资源管理器继续占用时，正常重启 Windows 后先完成安装。固定版本未实现延迟到重启替换或自动关闭宿主。

## 已安装状态保持

准备前后完整快照逐项一致：标准 YimeCore 69 个载荷、Rime/PIME 366 个载荷和当前 18u `.4` 的 20 个载荷全部匹配各自清单；注册、启动项、进程 PID/创建时间/普通用户状态及默认输入覆盖值一致。校准目录唯一 425 字节文件的 SHA-256 仍为 `463d624053325f98146cf6458b5782ed518e377a209cb9cb3e3961ef2c7ff01b`。未调整默认输入法、屏幕标尺、产品学习或用户词库。

[状态回执](pre-install/status.json)、[准备后占用者](pre-install/prepared-dll-users.json)、[原生包检查](pre-install/native-package-check.log)和[证据哈希索引](pre-install/evidence-index.json)保留原始观察。不存在新版安装或输入通过的结论。

## 用户离开当前会话后继续

1. 保存现有文档；正常重启 Windows。登录后，先不要重开 Codex、记事本或选择 18u。
2. 在本地交付目录双击 `Install-18u-ARM64.cmd`，按正常 Windows 提示继续。只调用标准完整包安装器，不重置用户数据。入口保留首次 `installation-output.log`，不会自动重试；完整安装日志在 `C:\Users\tsaan\Yime Setup Logs`。
3. 若仍提示占用，保留日志停止，不结束 Explorer/System 或强制复制。成功后回到当前对话，先核对 `.5` 版本、完整载荷和普通用户进程，再做真实 Notepad 复测。
4. 复测须使用新的空白记事本标签，确认当前已安装 18u profile 和 DLL 实际激活，观察绑定结果及诊断，然后通过概念键盘输入并将中文候选提交到正文。原文档不改动；切换正文焦点和再次绑定也应实际观察。鼠标自动化、隔离 TSF 或 Unicode 直接填字都不能代替真人手指/笔验收。

下一步仍沿用本次已给出的安装和复测授权，不需要重新索取安装许可；需要用户完成的是保存文档并正常退出相关应用，必要时正常重启。
