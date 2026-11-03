# Rime 46dd 第二次安装失败：只读上下文对照

对象：`46dd58967266edcab3f0d3bb131015d81dc4b951`、`0.1.0-rime-arm64.1`。第二次安装的管理员日志是 `C:\Users\tsaan\Yime Setup Logs\79d72165c1d9409896f00eea816c8828.admin.log`，结束于 `2026-11-03 23:30:33` 本地时间。

PATHEXT 修复已使安装末尾的 x86 `PIMERegistrationStatus.exe verify-registered` 实际执行；它输出 0 个 service/exact profile、6 个精确类别并返回 7。Setup 因该错误退出，普通父进程没有启动 Launcher。安装后快照显示 366 个 payload 哈希均匹配，文件、COM、启动值已存在。

## 控制结果

只读控制始终使用已安装探针，执行前确认其字节与 46dd 最终包相同。没有调用安装、注册、激活或输入宿主。

| 上下文 | UTC | 架构 | 结果 |
| --- | --- | --- | --- |
| 普通本机权限，继承环境，原生 CreateProcess | 15:33:29 | x86、ARM64 | 均 exit 0，exact profile 1 |
| 普通本机权限，维护入口精简环境，同 protected stage 工作目录 | 15:33:29 | x86、ARM64 | 均 exit 0，exact profile 1 |
| 同账号管理员，继承环境，原生 CreateProcess | 15:38:45 | x86、ARM64 | 均 exit 0，exact profile 1 |
| 同账号管理员，维护入口精简环境，同 protected stage 工作目录 | 15:38:45 | x86、ARM64 | 均 exit 0，exact profile 1 |
| 同账号管理员、精简环境、protected ARM64 PS7、checked preflight、`& probe verify-registered \| Out-Host` | 15:43:01 | x86、ARM64 | 均 exit 0，exact profile 1 |

各组均同时看到正确 description、enabled=true 和 6 个精确类别。`ordinary.json` 与 `administrator.json` 记录同一 SID、TokenElevation=false/true、命令、探针 SHA、环境变量名和原始输出文件。PS 组记录具体 protected PSHOME、ARM64 架构及管理员状态；PS 初始化会把自己的目录加入 PATH、把 `.CPL` 加入 PATHEXT，输入环境本身仍来自与 helper 相同的固定白名单。

## 结论与边界

管理员权限、精简环境、PowerShell 管道这三个静态条件都不能单独解释安装时的 profile=0，因为事后 10 项控制全部通过。此结果也不支持“只有普通父进程才能可靠枚举该 profile”的结论。

注册后的 TSF 读取收敛、缓存或当时会话状态差异是待验证假设；本轮没有重新注册去复现时序，不能把缓存归因写成已经证实的根因。Microsoft 对 `EnumProfiles(0)` 的合同是枚举所有语言的 profile，不是仅当前 HKL：<https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfinputprocessorprofilemgr-enumprofiles>。

若安装链增加有界收敛检查，应继续要求精确 profile、描述和类别终态，使用新进程观察并保留每轮输出，超时仍失败；不能把注册表键存在、API 返回 S_OK 或事后一次成功作为当时安装成功的替代。当前仍未启动 Rime runtime 或进行真实输入验收。
