# 本轮连接会话的只读复核

2026-11-06 北京时间 07:20:39–07:20:45，当前连接的华硕电脑 `HUASHUONOTEBOOK` 仍安装 **0.2.0-18u-arm64.4 / 6cea24bc665a4ded31e083a42bebd5d2d039832d**。本轮连接会话未观察到相对前轮的新系统启动或 `.5` 升级，尚不能进行 `.5` 的记事本绑定/中文输入验收。用户报告的重启操作单独保留为陈述，不记录为已验证事实，也不推测未升级原因。

当前安装的 20/20 载荷匹配自身 `.4` 清单；与交付 `.5 / 636cef681ee995a21a9c45fd750f8cb4b0acb4a1` 比较，12 项相同、8 项不同，包括 Runtime、Broker、GUI 和原生 DLL。

| 观察项 | 对比前轮 prepared-state / prepared-dll-users |
| --- | --- |
| YimeCore / Rime-PIME / 18u 载荷 | 69 / 366 / 20 项均匹配自身清单，全部哈希未变 |
| 三产品注册路径、启动项 | 未变 |
| 默认输入法覆盖项 | 未变（空值） |
| 三产品进程 | PID、路径、精确 startUtc 均未变 |
| 当前 18u DLL 使用者 | Explorer 20092、Codex 39152、Notepad 11912，PID 和 creationTicks 均未变 |
| 系统 LastBootUpTime | 2026-11-01 14:40:29 UTC（北京时间 22:40:29），早于前轮快照 |
| 校准文件 | 本轮未重哈希；仅保留历史 calibration-before，不宣称当前未变 |

18u Runtime 37804、Broker 15988、GUI 14292 均运行于 `C:\Program Files\YimeCore 18u Touch\bin`，`elevated=false`；创建时间分别为 2026-11-05 05:15:22.7633888 / 05:15:24.6147512 / 05:15:44.8076506 UTC。

采样通过仓库 `run_checked.py --edition ps7` 入口执行，完整参数在 `raw/snapshot-tool-provenance.json`。`raw/comparison.json` 提供逐文件和进程比较；`raw/status.json` 记录范围与未完成项。`baseline/` 保存本轮使用的历史基线，`raw/` 保存本轮原始输出。`evidence-index.json` 记录每个归档文件的 SHA-256、字节数与源路径，复制后逐字节检查。

收到用户正在操作界面的通知后停止进一步采样，因此校准未做本轮复核。本子任务未安装、注册、停止进程、修改默认输入法、操作记事本、修改源代码或执行物理指笔验收。后续状态变化需新快照，不能由本记录推断。
