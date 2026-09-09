# Rime/PIME 真实维护接线与受限可执行候选

影响产品：Rime/PIME。YimeCore local.12、生产 Rime/PIME、默认输入法和实际用户数据未改动。本记录承接 DP1-U 私有原生事务；旧 disabled installer、旧 canonical receipt 及历史回滚载荷不改判、不替换。

## 本轮实现

独立入口 `installer/rime-pime-candidate.nsi` 只解包固定清单并调用随包 PowerShell 控制器。新 manifest / build receipt 使用独立 schema；旧收据不能被自动升级成可执行授权。候选只接受明确批准的干净、独立 x64 Windows 目标，包含 x64 / x86 WOW64 TSF。`MYCOMPUTER` 在读取调用者路径、解包或启动维护前被拒绝；现有 peer 注册也阻止准入。ARM64、覆盖升级、共存安装顺序和公共发布不在本候选的执行准入内。

控制器完整复制来源闭合的包，先创建自己的 StateRoot/Roaming、StateRoot/Local，写入强制 Runtime 配置，再发布带文件 ID、长度、SHA256、根目录身份和默认输入法基线的不可覆盖 prepared 记录。原始 PreparedSha256 在任何注册前以 CreateNew + Flush 导出到原授权文件同目录的 `candidate-recovery-<run_id>.json`。操作者需独立保留这份原始 ticket；恢复不得从当前 journal 重算一个“原始可信哈希”。

真实注册提供器复用 x64/x86 `regsvr32`、双架构 `PIMERegistrationStatus`、`InstallLayoutOrTip` 与独立 `StdRegProv`。固定 36 棵注册树按原始类型和值检查，拒绝不属于当前包的值或子项；x64 负责共享 TSF 注册，x86 负责 WOW64 COM。实际注册期间持有安装载荷读锁。Run 指向本候选 Launcher；卸载标记指向恢复目录中的同哈希候选 EXE，避免执行正在删除的安装目录副本。

Launcher 的 `dp1-candidate` Cargo feature 在每条启动路径强制读取候选自己的状态配置，缺失或不匹配即失败，不退回生产 AppData。普通产品构建不启用此 feature。维护就绪检查验证管道服务端 PID、SID、映像、创建时间、父子拓扑，以及完成初始化后的真实 native Rime session/schema；发布维护标记前后各检查一次。Resume 优先接管已经验证的当前 Runtime；停止只针对精确归属的进程和定向协议。

完整维护区间由固定的跨用户产品协调门排他保护。父进程、委托 worker 和注册子进程均保留门句柄；不能靠另一审批 run_id 并发维护同一产品。注册子进程先挂入 kill-on-close Job 再恢复执行，只继承明确列出的协调门句柄。超时必须等 Job 中全部进程退出后才返回失败，不能在旧注册器仍运行时开始回滚。

安装 commit 前失败走持久回滚；commit 后仅前进验证。每个原始 install plan 只有一个固定 removal history，新批准的 run_id 不创建平行决定。已有 removal intent 优先于较早的 install commit，防止卸载中断后重新启动 Runtime。移除先确认停止、注销和默认输入法未变，再按原始句柄身份精确删除已批准文件；部分删除后按实际缺失继续，保留学习目录、恢复资料和未知文件。未知注册内容、已改变文件、损坏记录或 pending-delete 均拒绝冒充完成。

## 证据范围与限制

本轮执行源码构建、静态 PE / NSIS 提取核验、PS5/PS7 自有文件与进程/管道夹具，以及注册/Runtime 边界 mock 回归。未执行候选 EXE、安装器、卸载器、系统注册或产品 Runtime，也未进行已安装宿主验收。构建目录、哈希及最终回归数量在后续本记录的构包结果段给出。

新编译范围为本仓 x86/x64 TSF 与注册探针、带 feature 的 Launcher、Go 工具。仓内没有相应 C/C++ 源码的 `rime.dll`、`rime_deployer.exe`、`rime_dict_manager.exe` 按既有 `rime_runtime.lock.json` 作为锁定依赖打包，不称为本轮源码编译产物。不读取另一个 Git 仓库或任何已安装产品作为依赖。

prepared 发布前的暂存中断会保留已创建目录；尚无完整原始 ticket 时不自动认领或清理。removal 目录建立后、prepared 发布前的中断同样失败关闭，保留现场。这些仍需独立目标恢复流程验证，不能描述成任意指令点或断电恢复已经完成。目录 metadata durability、硬件断电、恶意同 SID 的物理阻止能力均未验收。

首次实际 Rime 部署的耗时也待独立目标验证：现有 Launcher 后台响应 watchdog 为 15 秒，外层就绪等待预算不延长该内部期限。本轮没有启动新产品，因此不声称冷启动部署已通过；不得为制造通过而关闭 watchdog 或跳过真实 native session 就绪检查。

`installed_acceptance_passed`、`dp1_u_acceptance_passed`、`public_release_admitted` 与签名完成状态继续为 false。下一步是在指定独立目标、绑定候选/收据/原始审批摘要和发起 SID 后，运行干净安装 → 实际注册/就绪 → 回滚/卸载/恢复验收，再进入 DP2 两种安装顺序和 DP3 三选一入口。代码接入与可执行文件生成本身不提升这些结论。

## 本地回归与来源封存

| 套件 | PS5 | PS7 | 本轮实际执行范围 |
| --- | ---: | ---: | --- |
| 候选包读取与来源流边界 | 19 | 19 | 自有文件、读锁、ADS、篡改拒绝 |
| 构包收据 | 26 | 26 | 合成收据与原始摘要绑定 |
| 维护编排与恢复 | 13 | 13 | 原生文件/journal/精确删除，注册和 Runtime 边界 mock |
| 注册提供器 | 29 | 29 | 23 项注册逻辑 mock，6 项自有进程/Job/句柄继承 |
| Runtime 提供器 | 37 | 37 | 就绪合同、受控私有管道与进程引用；未启动产品 |
| 跨进程协调门 | 19 | 19 | 自有随机门、真实父子进程退出与继续排他 |
| 合计 | 143 | 143 | 不等同于已安装产品验收 |

各原始结果路径、长度和 SHA256 见[回归证据索引](../testing/dp1/executable-candidate-regressions-20260909.json)。另有 Go server 包回归、Rust candidate feature 回归、PE 架构/静态 CRT/import 核验通过。Python 来源基线覆盖 262 项来源，77/77 测试，8 项 pending 保持未关闭；原始记录为 `.tmp/dual-product/dp1-executable-delivery-source-20260909/baseline.json`。

原生、Go 和 Rust 的来源记录绑定提交为 `2c4cb250f79f652bbd86b1fda3f2575d371881c7`。源码编译输出位于 `.tmp/dual-product/dp1-source-payload-build-20260909/payload`，包含 168 项来源载荷、162,016,520 字节；17 个 PE 本轮编译，另 3 个为上述锁定第三方依赖。全部 2352 项来源记录和 168 项产物按主数据流长度/SHA256 重新核对不变后，库存绑定该提交，库存 SHA256 为 `3d99f531b75603fe0b0d26f56bf4732393e909a2968946a2b86be616dd8c3fe7`。此前 HEAD 库存和失败构建记录均保留。

首次构包在创建 stage 前拒绝了来源图片携带的 Windows `Zone.Identifier`。修复后只有来源证据租约核验主流及原生文件身份，保留且不读取/删除该标记；实际包载荷和 NSIS 编译输入仍使用原严格拒绝 ADS 的租约。来源校验通过不宣称额外流属于已核验编译输入闭包。

## 可执行候选构包结果

最终候选：`.tmp/dual-product/dp1-package-build-stage-executable-20260909-3/YIME-RimePime-1.4.0-dev.1-candidate.exe`，41,404,929 字节。

- EXE SHA256：`3096da82a02e78b1d411ea554fcc9eeaddb45e6c6c746be64b803a261d2b65fa`。
- `executable-build-receipt.json` SHA256：`a86cf1112c3b947bd3b3cbc0c2e962d05dddf50b3002193d9f9dff333fdf037c`。
- bundle manifest SHA256：`689d8252d79587e5f9880405f746ac810ab48016966b82e9a413959e45ed3928`。
- 189 个归档成员经固定 7z 的原始 stdout 流逐一比较，长度与 SHA256 全一致；静态索引 SHA256：`ff26da68e808e36b1efbdf88039cffefa284b8049b8c4e46f164a1eb15bc8c33`。
- makensis 前已启用监视，退出后完成屏障，异常成员事件为 0。物理阻止、完整非 OS/全部工具链闭包等四个保守字段保持 false。

最终实际 bundle 和原始收据在 PS5 / PS7 均通过只读核验，并从包内成功加载控制器所需的读取器、协调门、注册及 Runtime 模块；四份原始结果及摘要纳入交付索引。该检查未调用公共维护入口或注册/Runtime 提供器，未执行候选 EXE。

完整路径和摘要见[交付证据索引](../testing/dp1/executable-candidate-delivery-20260909.json)。第二次实编译发现生成的 NSIS `/oname` 参数引号位置不正确，修复并通过带一个 inert 成员的实编译后才生成本候选。该构包修复的实际字节由 receipt 的 `build_sources` 绑定，并在后续提交中保存；不能仅凭较早的 Runtime 来源提交重建整个构包实现。前两次拒绝/失败与第三次成功分别留存，不改写失败为成功。

候选提供 `Install / Remove / Resume` 三种模式，但只有显式授权的独立目标、原始审批摘要、边界文件和该收据同时匹配时才进入维护。Remove/Resume 还必须携带独立保留的原始 PreparedSha256。双击无参数、在 MYCOMPUTER 上运行或缺少绑定均拒绝。没有授予开发机安装或修改 local.12 的权限，本轮未执行候选。
