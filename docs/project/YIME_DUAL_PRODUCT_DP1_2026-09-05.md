# DP1 首批：双产品源码基线与纯隔离合同

日期：2026-09-05。影响面为两版源码基线／共存维护合同；依据[双产品计划](YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，与 YimeCore SR4 独立构包并行。此次只新增工具与文档，没有修改或执行现有安装／维护入口。

后续更新：[DP1-B 静止状态维护保护](YIME_DUAL_PRODUCT_DP1_B_2026-09-05.md)已完成源码接线与隔离回归，新的基线不再把已修复的三处旧分支列为当前缺口。本文仍记录首批时点；原收据与下文历史结果保持不变，完整 DP1／DP2 尚未通过。

## 已完成及证据等级

新增 [DP1 工具入口](../../tools/dual-product/README.md)，从当前源码提取、交叉核对两版产品身份及主要运行／维护资源；固定 22 个输入的 SHA-256，包括 15 个被审阅的原有源码／描述文件、3 个新增合同工具文件及 4 个锁定生成数据。没有读取私人观察、用户正文、真实编码、学习库或当前生产状态文件。

最终运行收据：`.tmp/dual-product/dp1-20260905-a2/baseline.json`。

- 收据 SHA-256：`6d05ae9fe1241b0e7933f420eae914979b5b82eb92bd3578c7267fac1b4da86b`。
- 源码提取、来源一致性与锁定输入哈希通过；读取前后来源未变化。
- 19 个测试通过，0 失败、0 错误、0 跳过；含双向跨产品路径／注册／端点／停进程拒绝、精确映像与 SID、Run 只允许本版值、错误路径、来源哈希错误、批次拒绝不部分写入，以及两种“对方不存在”的纯内存场景。
- 安装顺序场景仅是模型中的集合和资源写入，未执行安装、注册或宿主输入。模拟 reparse 属性不是创建真实 Windows 符号链接，不能关闭此前因权限未完成的真实负例。
- `dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`。纯模型尚未接入现有安装器；不把测试成功扩大为运行维护互不影响的实机结论。

## 从实际源码得到的基线

| 资源 | Rime/PIME 版 | YimeCore 版 |
| --- | --- | --- |
| CLSID | `{35F67E9D-A54D-4177-9697-8B0AB71A9E04}`，由 C++ GUID 初始化值与 NSIS TIP 交叉核对 | `{E40FA752-BB96-461D-A51D-F40EB437EC65}`，来自当前 local-product 描述与维护器校验链 |
| Profile | `{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}`，`ime.json` 与 NSIS 一致 | `{126F54C6-E9B1-4E22-8652-03224CBD49F9}` |
| 包根 | `ProgramFiles32\YIME` | `ProgramFiles\YimeCore Experimental Trial` 中的当前包根 |
| 主要进程 | `PIMELauncher.exe`、`go-backend\server.exe` | `bin\YimeCoreTrialRuntime.exe`、`bin\YimeBroker.exe` |
| 输入通信端点 | 按用户名构造的 `\\.\pipe\<username>\PIME\Launcher` | `\\.\pipe\YimeBroker.YimeCoreTrial.v1` |
| 可写状态及日志 | `APPDATA\PIME\Rime`；`LOCALAPPDATA\PIME\Logs` | `LOCALAPPDATA\YimeCore Experimental Trial` 及其 `logs` 子目录 |
| Run 归属 | HKLM 的 `PIMELauncher` 值 | 发起用户 HKU/SID 的 `YimeCoreExperimentalTrial` 值 |
| 卸载归属 | HKLM 下 `Uninstall\YIME`；另有历史 PIME 清理路径 | 发起用户 HKU/SID 下 `Uninstall\YimeCoreExperimentalTrial`；历史机器级同名项另受维护器约束 |

同名的 Windows `Run` 父键不是共享产品资源：只能操作自己的值。根目录、注册视图和 SID 都是合同的一部分。该收据捕获的源码描述版本为 `0.1.0-local.12`；后续候选改动须生成自己的新快照。这不是对安装中的映像、进程或本次登录状态重新验收，也不将历史封存的 Core 身份当成另一产品。

共同构包输入固定为现有三模式生成词典和布局投影的锁定路径／哈希；只读取仓内明确来源，不读取另一个产品的安装目录。此次是首批来源基线，不是完整可复现构包／PE 依赖审计；SR4 及两版后续包验收仍分别提供自身完整载荷证据。

## 确认的待处理维护边界

以下是源码中实际存在、尚未接入新合同的路径，不是本轮观察到用户数据受损或当前 Core 被停止的运行回归：

1. `DP1-PIME-STOP-01`：`installer/installer.nsi:158` 的停止路径仍按 `PIMELauncher.exe` 全局映像名执行 taskkill，没有精确安装根与 SID 限定。
2. `DP1-PIME-STOP-02`：`tools/dev-install.ps1:171` 在 stop helper 不存在的后备分支仍按进程名选取后强制停止。正常 helper 已按路径前缀过滤，不能由正常路径推断后备分支安全。
3. `DP1-PIME-LEGACY-03`：`tools/dev-uninstall.ps1:109` 起的根目录收集接收调用方路径及历史注册值，没有在该收集函数验证产品标记。后续清理需要补上精确目标／所有权拒绝与相应负例；不能将另一个产品的根或无关目录作为旧产品清理目标。

Core 的进程名与上述 PIME 映像名不同，因此前两项不等于“当前 Core 会被这些命令杀掉”。这里记录的是尚未满足完整产品所有权证明的入口；本轮没有执行它们，也没有改写它们。后续须对既有安装／恢复事务接入可复用的精确所有权校验，覆盖实际分支后，才能推进 DP2 的隔离安装维护矩阵。

## 本轮未做及下一步

未运行 Rime、生产或历史封存二进制；未安装、卸载、变更注册／默认输入法、停止已安装进程或读取用户状态。没有创建新宿主、登录或重启证据。既有 L5、SR4、签名、正式发布、默认切换批准及 DP2 实机门禁保持各自状态。

下一步先对上述维护边界建立具体源码／事务负例，再经独立审查接入现有入口；仅在获准的隔离环境执行单装、双向安装顺序、分别升级／失败回退／卸载／恢复矩阵。未通过前不实现会把现有入口组合成实机操作的“三选一”安装器。
