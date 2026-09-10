# i7-7820X 测试机 YimeCore 构包交接（2026-09-10）

## 结果

**状态：两次安装尝试暴露的预清理与冷启动健康检查缺陷均已修复；最新修复包已成功安装，x64/x86 已注册宿主测试通过，真实应用与重启登录验收尚未执行。**

最终安装包目录：

`C:\dev\Yime-localtest\.tmp\yimecore-platform-experiments\mx64-package-20260910-150412-f3a06643\package`

完整构建与测试证据：

`C:\dev\Yime-localtest\.tmp\yimecore-platform-experiments\mx64-package-20260910-150412-f3a06643`

用户第一次手动安装时，预清理因“产品本来完全未注册”仍强制执行 TSF 反注册而中止；修复后，预清理会先查询 x64/x86 精确产品身份。第二次手动安装已越过该阶段并完成暂存，但在这台较旧机器冷加载三个大索引期间，单次启动健康探测过早超时，事务按设计回退。最新修复仅对真实 `TimeoutException` 在既有总时限内重试；进程身份、父子关系、文件哈希、健康管道归属、协议或随机数回应异常仍立即失败。第三次安装于 2026-09-10 15:17 成功完成。没有修改默认输入法，也没有读取、迁移或修改 Rime/PIME 用户设置及学习数据。

## 当前已安装验收

- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-e346a1dad76d-133c91fe`；安装元数据绑定清单 SHA-256 `133c91fe205fcae911fa701a278465dad040e7dadce006b541697b656e50405a`。
- x64 与 x86 当前身份 COM/Profile 注册均存在，分别注册 5 个 TSF 类别；状态查询退出码均为 0。
- Runtime PID 38644 与 Broker PID 12336 均从该安装根运行；Broker 父 PID 为 38644，状态为 `running`，重启计数为 0。
- 通过进程外 `StdRegProv/HKEY_USERS` 核对：当前用户 Run 值指向该 Runtime，已安装应用条目的名称为“音元拼音”且安装位置一致。
- x64 与 x86 `YimeRegisteredHostTests.exe` 均退出 0；注册键接管、候选提交、Shift 直通、候选方向/翻页、焦点取消、延迟及失败异步写入恢复、语言栏释放后回调保护均通过。
- 上述是合成注册宿主验收，不替代 Word、记事本、Firefox/Notepad++ 等真实应用的人工输入，也不替代重启和重新登录后的自启动证据。

## 目标机器与源码

- 计算机名：`计算机`；范围身份：`mainstream_x64` 实体测试机；使用者/所有者：开发者本人。
- 系统：Microsoft Windows 11 家庭版，版本 `10.0.26300.9445`，64 位。
- CPU：Intel Core i7-7820X @ 3.60 GHz；16 个逻辑处理器。
- 内存：102,731,558,912 字节（约 95.68 GiB）。
- 检出：`C:\dev\Yime-localtest`；Git worktree 元数据位于本机 `C:\dev\Yime\.git\worktrees\Yime-localtest`，不是 UNC 共享路径。
- 分支：`perf/i7-7820x-local`。
- 基础提交：`e346a1dad76d58f50652a2dd665c64ec8aeef49e`，已包含要求的 `e346a1dad`。
- 构建包含未提交的测试机专用补丁；精确补丁在证据目录的 `working-tree.patch`，SHA-256 为 `7a16753637c3820c68cf7e0912419263839cb18af1b7a4469c491ed8108ae3f1`。
- 源码快照：`source-snapshot.zip`，SHA-256 为 `b5d197b6d50287b21784b15d90d036c4f783193f136532a3b6ede40f4d1fa26b`。

## 工具链

- Visual Studio 2026 Community，MSVC `19.51.36257.0` / tools `14.51.36231`。
- CMake `4.3.1-msvc1`，生成器 `Visual Studio 18 2026`。
- Go `1.27.1 windows/amd64`，`CGO_ENABLED=0`。
- PowerShell `7.6.5`；语流离线工具使用 Codex 工作区自带 Python。
- Rust i686、NSIS、7-Zip 未参与本次 YimeCore Runtime/Broker 与双架构 TSF 目录包构建。

## 包身份与完整性

- 产品：音元拼音 YimeCore；版本：`0.1.0-local.13`。
- 包 ID：`yimecore-local-0.1.0-local.13-71bbe62def6f`。
- 目标：x64 Runtime/Broker；x64 TSF；x86 TSF（仅 64 位 Windows 的 WOW64 应用兼容面）。
- 源码清单 SHA-256：`71bbe62def6f026a47c857df980b52d1dcf5656bbb18e04bc0ce3eef032f8946`。
- `package-manifest.json` SHA-256：`133c91fe205fcae911fa701a278465dad040e7dadce006b541697b656e50405a`。
- 清单载荷 90 个文件；含清单共 91 个文件，445,002,618 字节。
- 三种索引各含 1,166,753 条记录并两次重建为字节一致：
  - full：`81a27bfb8fda165d0f753e4a83313272433e10533ca602ce18a414629b81ffb1`
  - variable：`159a873c85d6784740568100b2af1fa0be1b8101d82402d95609050011d6aada`
  - shorthand：`b735b96bbf72f6195274d0d16078f1d1ad6043b9248f302e31e2ce2db59045ec`
- 包含独立生成资产和维护依赖；独立性审计在测试前、重定位后和测试后均通过，未使用另一产品的已安装文件，也未执行历史 x86/ARM64 载荷。

## 已通过

- `mainstream_x64` 平台实验入口 24 项合约；MYCOMPUTER 默认本地产品通道保持独立限制。
- 注册表/默认输入法保护回归 28 项。
- 当前源码绑定的 Stage5C 语流准入：24 条已审记录、72 条三模式别名；定向测试通过数分别为 45、6、182、33、123、3、107，失败均为 0；3 项符号链接夹具在本机明确记录为跳过，未计作通过。
- x64 与 x86 TSF 原生合约、焦点取消合约均通过；额外 x86 重复验证 12/12 通过。
- Go 设置工具、独立性审计、Trial Runtime、Core、Broker 测试通过。
- 包内维护与恢复边界 37 项合约通过，包括带空格的重定位目录、真实 CMD 只读 `Plan`，以及完全未注册机器上的幂等预清理保护。
- 启动健康检查 48 项专门回归通过；仅冷启动健康端点暂不可达的真实超时允许重试，其他安全校验失败继续 fail-closed。
- 独立 Runtime/Broker 启动、Broker 失败后恢复、12 条动态句子回归、恢复克隆以及 x64/x86 直接 TSF 组合模拟通过；验证会等待真实 Broker 输入管道就绪，不再仅凭子进程 PID 抢跑；所有状态均在一次性 TEMP/APPDATA 夹具中。
- 最终 `summary.json`：`passed=true`、`installable=true`、`registration_and_default_preserved=true`。

## 尚未执行，不能据此宣称通过

- 实际安装、升级、卸载与回退事务。
- Windows TSF/输入法注册及 x64/x86 已注册宿主测试。
- Word、记事本、32 位 Firefox/Notepad++ 等真实应用输入。
- 任务栏手动选择“音元拼音”、真实候选窗和语言栏点击。
- 重启、重新登录、自启动与日常使用/L5-L6 封存。
- ARM64 原生构建或执行、签名和正式发布。

因此 `local_product_ready=false`、`public_release_ready=false`；交叉编译与直接 TSF 模拟均不替代已安装真实宿主证据。

## 后续获授权后的安装命令

不要从 Codex/打包应用的祖先进程中直接执行安装。关闭 Codex 中启动的终端，从 Explorer 打开独立的普通 Windows PowerShell（同一开发者账户），先只读查看计划：

```powershell
Set-Location 'C:\dev\Yime-localtest\.tmp\yimecore-platform-experiments\mx64-package-20260910-150412-f3a06643\package'
.\Maintain-YimeCore-Local.cmd -Action Plan
```

核对计划的产品名、x64/x86 注册架构、安装根和当前用户 SID 后，只有在另行明确授权安装时才运行：

```powershell
Set-Location 'C:\dev\Yime-localtest\.tmp\yimecore-platform-experiments\mx64-package-20260910-150412-f3a06643\package'
.\Install-YimeCore-Local.cmd
```

安装入口会自行处理 UAC，要求发起与提升后的 Windows SID 相同，并拒绝 packaged-app 祖先进程。不要绕过该保护，不要手工调用 `regsvr32`，也不要把 YimeCore 设为默认输入法来强行通过验收。

## 恢复/回退前提与安装后验收

- 安装前保留本报告、整个最终包目录和完整证据目录；若机器已有当前身份 YimeCore，先在独立 Explorer PowerShell 中制作并核对 `%USERPROFILE%\YimeCore Recovery Archives` 下的原生恢复归档。
- 升级事务必须先完整暂存新包；只有新注册与 Runtime 启动成功后才能删除旧根。失败时应由包内事务恢复 COM/Profile、TIP、Runtime 配置、Run、卸载键、用户 TIP 子树及原运行状态。
- 安装后先核对包清单和运行进程路径，再分别运行已安装 x64/x86 registered-host 验证。
- 真实宿主验收时，通过任务栏输入法按钮手动选择“音元拼音”；分别验证 64 位应用和 32 位 Firefox/Notepad++ 的输入、Shift+1..Shift+9 候选选择、数字继续参与编码、候选翻页、焦点丢失取消和语言栏菜单。
- 最后重启并重新登录，核对同一用户的自启动、当前 PID/镜像路径、启动时间与 Shell-Core 登录证据；此前的隔离 Runtime 结果不能替代这一项。
