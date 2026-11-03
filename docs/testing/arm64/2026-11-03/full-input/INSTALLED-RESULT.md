# 本机安装执行记录

本机：HUASHUONOTEBOOK / ASUS ProArt P16 H7607BA，Windows 11 ARM64 build 28000。
原始执行记录在 `installed-final/`。本文随实际执行追加，不把构建或源码测试当成安装结果。

## 当前结果（2026-11-04）

三套独立产品已完成本机安装并保留普通用户运行状态，准备进入真人实测。最后一轮安装后 69 + 366 + 20 个产品文件全部匹配；默认输入 override 保持原值，标准版及 18u 的已运行进程在 Rime 最终安装前后完全相同。没有重置已有学习或用户词库，也没有自动重启。

| Windows 输入法条目 | 当前固定组件 | 已完成的本机验证 |
| --- | --- | --- |
| 音元拼音 | 标准 YimeCore main64a785a7 运行时 + 6c1c0122 maint.1 | 69 文件、普通权限；三模式/三架构注册宿主 9/9，加维护修复后 ARM64/full 定向通过 |
| 音元 | Rime/PIME defbf9f8 维护包 | 366 文件；原普通父进程 x86/ARM64 双 verify-present 全部通过后启动 Launcher |
| 音元拼音·18u触摸 | 46dd5896 完整触摸包 | 20 文件、普通权限；已安装 DLL/GUI/Broker 的真实 TSF 输入检查 18/18 |

固定 ZIP、SHA-256、CI 和下载入口见 [交付索引](FINAL-DELIVERY.md)及 [Rime 最终交付](RIME-USER-VERIFY-DELIVERY.md)。三套组件按各自已验证版本保留，无须同步重制。系统应用列表中的独立维护入口已只读核对，见 `installed-final/final-maintenance-entries.json`；本轮没有实际执行卸载。

真实 Rime 后端三模式和加载检查属于已记录的源/独立运行证据；本轮尚未完成 Rime 在真实文档应用中的人工输入验收。18u 当前只确认原生 ARM64 宿主；x64/x86/ARM64EC 应用兼容性、真人手指/笔、物理尺标、重启与长期日用仍需分别记录。

## 标准 YimeCore maint.1

已从固定 6c1c0122 交付包完成安装，安装器返回 0。安装路径 `C:\Program Files\YimeCore`，版本 `0.1.0-local.13-main64a785a7-arm64-maint.1`。
69 个安装载荷全部匹配，ARM64X 64 位与 x86 COM 注册指向自己的产品目录。

Win32 实际进程/令牌核对：Runtime PID 19916、Broker PID 21076、Toolbar PID 7952 均为 Medium（IL 8192）、非提升令牌。
这些是运行时观测，而非仅依据 `runtime-status.json`。已修复先前管理员子进程启动造成的 High 令牌。
随后唯一一组 ARM64/full 注册宿主回归通过，包含真实候选提交、失焦取消、异步失败编辑恢复和保留语言栏释放检查。
测试使用独立普通用户 Broker，完成后清理；默认输入和另外两个产品的保护比较通过。

此前相同 69 个运行时载荷的三模式 × ARM64/x64(ARM64X)/x86 共 9 组注册宿主检查结果保留于 `standard-registered-host/`，未用维护修复名义重复全部矩阵。
当前重装与定向验证证据在 `installed-final/standard/`。

## Rime/PIME 首次安装的已定位问题

6c1c0122 包首次安装返回 1，原始日志为 `installed-final/rime-first-failure/`。
当时 366 个文件、两架构 COM、用户启动项及卸载项已写入；失败在安装末尾调用 x86 `PIMERegistrationStatus.exe verify-registered`。
原生维护程序为 PowerShell 构造的固定环境未包含 `PATHEXT`，导致 `& exe | Out-Host` 将 `.exe` 识别为文档并报 `CantActivateDocumentInPipeline`。
父维护入口因此没有启动 Launcher。不能将这次失败记为安装成功。

最初工具沙箱内的只读 TSF 枚举报告 profile=0；同一已安装探针在普通本机权限下运行，两架构均返回 0、exact profile=1、description/enabled=true、6 类注册全部匹配。注册表及包内配置也一致。
这是沙箱观察限制，不是第二个注册故障；没有通过手工注册补洞。
标准版的 69 个载荷、三个普通权限进程、默认输入设置和未安装的 18u 状态保持不变。

18u 的注册程序也经过同一 PowerShell 原生调用函数，因此没有运行旧 6c1c0122 18u 安装入口；后续使用通过 CI 和发布校验的 46dd 修复包。

## Rime/PIME 第二次安装与验证阶段调整

46dd 包已解决 `.exe` 调用问题，但第二次安装在管理员阶段的 x86 `verify-registered` 返回 7：profile 为 0，六项类别完整。原始失败及对照见 `installed-final/rime-second-failure/`。
随后普通/管理员、继承/固定环境、同 protected ARM64 PowerShell 管道共十项只读对照全部通过。因此不能把原因定性为管理员不可见、环境缺失或 PowerShell 不能启动；具体即时可见性原因未确定。

后续修复只调整受保护的 ARM64 Rime 安装阶段：确有普通父进程的内部提升链完成管理员维护后，原普通父进程锁定并校验所有安装载荷及 manifest，再依次运行固定 x86、ARM64 探针 `verify-present`，两者全部成功才启动 Launcher。任一失败返回非零，禁止启动。
移交绑定父进程 PID、创建时间、同用户 SID、非提升令牌、同 helper 镜像及存活句柄；直接管理员入口仍保留原强检查且不启动运行时。旧 x64/PS 入口、18u、检查与卸载不改变。
修复保留完整 profile 检查，未增加等待重试；安装结论以下方新固定包的实际重装结果为准。

**defbf9f8 已完成实际重装复验。** 安装返回 0；原普通父进程中 x86、ARM64 均报告唯一正确 profile、描述匹配、当前用户已启用、六类注册精确匹配、所有 HRESULT 为 0，随后才启动 Launcher PID 39884。安装后观察到 Launcher 及直接子进程 39884、38684 均为普通权限。最终记录在 `installed-final/rime-success/`；前两次失败和十项只读控制均保留。

## 18u 46dd 完整安装

46dd 完整包已正常安装，返回 0。目录 `C:\Program Files\YimeCore 18u Touch`，版本 `0.2.0-18u-arm64.1`；20 个产品载荷全部匹配，原生 ARM64 COM 及独立用户启动项正确。输入法条目的实际描述为“音元拼音·18u触摸”。
初始 Runtime 34768、Broker 39328、GUI 38228 均已实际核对为同一普通用户、Medium/非提升、同登录及会话。GUI 在 Runtime 后约 15.44 秒启动，安装后约 2 秒的第一份快照尚无 GUI，不将该快照误报为 GUI 故障。
默认输入、标准版和 Rime 前后保护快照完全相同。安装原始记录见 `installed-final/18u/`。

首轮 18 检查点控制器在开始时遇到 Job 成员路径不在预定列表，主动停止；当时 0/18，未宣称输入通过或产品输入失败。自有测试 Job 已清空，普通 Runtime 13308/Broker 29732/GUI 24268 已恢复并重新核对。失败日志保留，控制器诊断与后续输入验收另记。

无输入诊断确认，`CREATE_NO_WINDOW` 下仍出现两个系统 `conhost.exe`；Python 路径别名假设被实际 file ID、hash 和无 reparse 记录排除。控制器改为 `DETACHED_PROCESS` 配合原有显式管道后，无输入启动仅剩预期进程，严格白名单保持。没有修改已安装产品或包。
随后全新 r2 单轮完成 **18/18**：实际激活 Windows profile、加载已安装 DLL、GUI→Broker→TIP→编辑会话完整通路、三模式预编辑读回、候选提交、语言/字面输入、编辑和失焦取消全部通过，已提交文字及另一上下文受保护。`sendInput=false`、`physicalAcceptance=false`。
测试 Job 清空后已恢复 Runtime 29648、Broker 6744、GUI 29520，三者再次确认同普通用户、Medium/非提升、20 文件全匹配。完整成功与首失败原始证据在 `installed-final/18u/`，目录 README 和 archive-manifest 保留来源/hash。
Computer Use 窗口列表已看到“音元拼音18u — 已安装TSF触屏键盘”；画面读取返回 app approval timed out，未完成视觉检查，也未发送 UI 输入。

## 真人实测边界

不自动重启或关闭用户文档，不更改默认输入法，不重置已有学习/用户词库。
手指、触控笔、重启后启动和长期日用仍需实际观察，受控宿主不能替代这些结果。
当前只检测到 3840×2400 内置屏；18u 主区设计键距为 19.05 mm/u，宽 342.90 mm。目标触摸屏及尺标校准尚未确认，未通过缩放或修改几何冒充实际尺寸验收。
Win32 只读能力报告为 0xC5（集成触摸、集成笔、多点、就绪）、最大 10 点、1 个显示器、非 RDP；这只是系统声明，仍不构成手指/笔事件、命中或尺度验收。

## 实测入口

在准备使用的文本应用中，通过任务栏输入法菜单明确选择上表对应条目；当前默认输入法没有代为更改。标准两版本的数字仍参与编码，候选使用 Shift+1 到 Shift+9 的当前页序号。

18u 先在原生 ARM64 应用中选择“音元拼音·18u触摸”，使用已运行的触屏键盘；先以实体尺核对 100 mm 校准线，再评价键距和误触。手指与笔分别记录中文确认、英文/数字、退格/选区编辑、未确认组合失焦取消，以及连续输入的宿主空间和手部负担。重启后启动另按用户方便的时间验证，不能继承本轮未重启的结果。
