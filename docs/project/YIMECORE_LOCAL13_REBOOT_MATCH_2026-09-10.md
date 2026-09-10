# YimeCore 新安装重启身份复核（2026-09-10）

影响产品：YimeCore。本次由用户确认已重启，并要求核对后提交、推送。

## 安装和登录启动

- 产品版本为 `0.1.0-local.13`；`local16-20260910-transaction-repair` 是构建目录名，不是产品版本。
- 清单 SHA-256：`f8dea89ddc04c49af733d99b6dab23afad92857287150f42d6404f458339649b`。
- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-e8b0432ae625-f8dea89d`。
- 安装时间：2026-09-10 10:26:39（UTC+8）；开机晚于安装。安装清单、构建清单和安装元数据一致，90/90 文件大小和 SHA-256 通过。
- Runtime PID 29812 于 10:30:29 启动，Broker PID 30024 随后启动。当前进程路径、父子关系、所有者 SID、运行状态元数据及本次开机时间匹配。
- Shell-Core 9708 于 10:30:30 记录同 SID、Runtime PID 29812 的登录启动。事件 Command 只含程序名；完整路径由当前进程映像和独立系统 Run 值交叉确认，不要求事件包含完整路径。
- `StdRegProv/HKEY_USERS` 的 Run、卸载路径、DisplayVersion、维护 SID 和 StateRoot 均匹配新安装；`StdRegProv/HKEY_LOCAL_MACHINE` 的 x64/x86 COM 路径均匹配。
- 当前包 x64/x86 注册工具只读 `status` 均报告 COM/Profile 存在、5 个类别、查询 HRESULT 0、`mutation_performed=false`。

## 保护范围和限制

与本次构建前的系统哈希相比，Rime/PIME、冻结历史产品的机器及用户注册和 Keyboard Preload 均未变化。历史注册引用包 `8d48953a…` 的 62/62 文件静态 SHA-256 通过；未执行历史二进制。

`Control Panel\International\User Profile` 整棵树的哈希与安装前不同，不能记为整树保持不变。本次独立系统读和 Windows 默认输入法查询均显示默认仍为微软拼音，语言列表中存在当前 YimeCore profile；没有安装前逐值快照，未断言整树差异的具体成因。

此次没有安装、重启运行时、改注册或默认输入法、读取学习内容，也没有补做真实宿主输入、恢复或失败升级演练。身份和登录启动通过不代替这些独立验收。

## 提交前回归

- 普通主令牌启动合同：57 项通过。
- `go test ./input_methods/yime/yimebroker -run TestServeNamedPipe -count=1` 通过。
- 安装合同在 Windows PowerShell 5.1 和 PowerShell 7 均通过。
- 本次修正安装合同的单参数数组展开，并按包合同区分本机 x64/x86 与旧 ARM64 要求；旧包 ARM64 检查保留。安装器和已安装包字节未因这项测试修正改变。
- `git diff --check` 通过。

本机原始观察位于 `.tmp/local16-reboot-20260910/`，包括初次观察、最终 `summary.json` 和两种 PowerShell 的合同 JSON；构建前保护哈希位于 `.tmp/yimecore-local-product/local16-20260910-transaction-repair/protection-before.json`。初次观察中完整路径事件假设不成立，整语言树保持不变也不成立；最终结论按上述证据范围分别记录，未修复被观察系统。
