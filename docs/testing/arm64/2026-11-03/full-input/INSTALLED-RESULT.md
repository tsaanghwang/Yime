# 本机安装执行记录

本机：HUASHUONOTEBOOK / ASUS ProArt P16 H7607BA，Windows 11 ARM64 build 28000。
原始执行记录在 `installed-final/`。本文随实际执行追加，不把构建或源码测试当成安装结果。

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

18u 的注册程序也经过同一 PowerShell 原生调用函数，因此本轮没有运行旧 6c1c0122 18u 安装入口。
待维护入口修复、适用回归、固定源码 CI 与更新包交付后，再重试 Rime/PIME 并安装 18u。

## 真人实测边界

不自动重启或关闭用户文档，不更改默认输入法，不重置已有学习/用户词库。
手指、触控笔、重启后启动和长期日用仍需实际观察，受控宿主不能替代这些结果。
当前只检测到 3840×2400 内置屏；18u 主区设计键距为 19.05 mm/u，宽 342.90 mm。目标触摸屏及尺标校准尚未确认，未通过缩放或修改几何冒充实际尺寸验收。
