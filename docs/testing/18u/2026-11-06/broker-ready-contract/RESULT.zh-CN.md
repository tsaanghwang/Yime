# ASUS 原生 ARM64：Broker READY 启动合同离线补充

本轮在 **HuashuoNotebook / ASUS 原生 ARM64** 完成源码回归。最终原生验证器要求的 **12 项顶层测试全部通过，无跳过**；其中新增 READY 编排回归 4 项、27 个子案例。实际 Broker 服务、命名管道、TIP 和真实宿主均未启动，没有安装、注册、默认输入法或用户数据变更。**这不是 ARM64 现场验收，也不是已安装 Broker 的 READY 观察。**

## 基线与范围

- 原工作区：`C:\dev\Yime`，分支 `codex/arm64-native-test-20261026`，仅观察到既有未跟踪 `.wt/`，未修改其源码或切换分支。
- 独立工作树：`C:\dev\Yime-broker-ready-arm64-20261106`；分支 `codex/18u-arm64-broker-ready-20261106`，从 PR #113 head `591cc4229915b0c1b481d0e61001df7d63260671` 创建。
- 核对 main 为 `45be140e528c4a4e818a2bca6717f187a0fcd2b5`，已包含在 PR 基线内；PR 当时 open、可合并。
- 截至北京时间 2026-11-06 18:56:29，main 的 4 个 push 工作流成功（16 个成功 job、3 个条件跳过）；PR head 的 8 个 PR/push 工作流成功（37 个成功 job、6 个条件跳过）。两轮原生 amd64/ARM64 初始化 job 均成功。见 [GitHub 快照](evidence/source-status.json)及 [PR 工作流](https://github.com/tsaanghwang/Yime/actions/runs/42202154370)。这是基线 CI，**不代表本地新增改动已通过远端 CI**。
- 原始 Copilot [ARM64 启动评论](https://github.com/tsaanghwang/Yime/pull/113#discussion_r4489774161)尚未关闭，但对应问题已由 `ac326cba` 修复。未再次修补旧问题，也未修改 review 状态。

用户确认采用两条开发线一致的合理流程。本次保持 **x64 与 ARM64 相同的现有 READY 语义**：平台、专属 endpoint/PID、原生架构、生产产品/资源描述符检查成功，再由传输的 retained-listener 回调输出 `READY yimebroker-18u`。字典实际加载及内容身份验证仍在首次 `open` 执行；READY 不宣称完整字典已加载。没有 ARM64 专属预加载、跨架构描述符回退或标准词典回退。

## 修改与覆盖

`cmd/yimebroker-18u` 仅提取私有启动编排与真实依赖工厂。命令入口继续使用编译时平台、真实原生门禁、`touchbroker.NewProduction` 和既有命名管道实现；没有新增命令行或环境变量绕过入口。启动次序、READY 文本、2/2 连接限额、same-logon 要求、PID 允许列表和错误返回保持原合同。

新增的四项回归均使用内存输出与传输替身，不建立实际管道：

| 回归 | 补充的启动合同 |
| --- | --- |
| `TestBrokerStartupReadyOrder` | x64/ARM64 相同的检查顺序；进入传输还不能输出 READY，回调后准确输出一次；传输配置、绑定 handler 与后续错误保持 |
| `TestBrokerStartupRejectsBeforeReady` | 不支持平台、空/外来/无后缀 endpoint、零/溢出 PID、原生查询/生产构造/监听失败均中止后续步骤且无 READY |
| `TestBrokerStartupNativeIdentity` | 两种原生身份允许；仿真、异构 native machine、非零 process machine、查询失败均不得进入构造或监听 |
| `TestBrokerStartupProductionIdentity` | 共用命令真实依赖，仅替换传输/输出；正确选定描述符才到 READY；错误产品、布局/字典摘要、外架构描述符和回退尝试均不得监听或输出 READY |

PR 已有的 `NewProduction` 完整描述符矩阵、首次 `open` 资源拒绝、完整锁定词典会话检查保持原样。新测试选少量生产身份案例，新增断言在于这些结果如何控制监听与 READY，并不复制完整构造器/首次 open 测试。

离线验证器把四项新回归加入两个原生 CI 目标共同使用的必需集合；缺失、失败、跳过、重复结果或仿真观察均不能冒充原生通过。两个 CI 目标仍使用原有原生 runner；本轮只更新工作流源码，未触发新远端任务。

## 验证结果与边界

- [最终原生 ARM64 报告](evidence/native-arm64-final/result.json)：Go 1.25.14，`GOHOSTARCH=arm64` / `GOARCH=arm64`；实际 Windows API 观察 `processMachine=0`、`nativeMachine=0xaa64`、`accepted=true`。12 项必需测试通过，其中新回归 27 个子案例。
- 资源来自显式指定的同仓库隔离输出 `C:\dev\Yime\.generated\arm64-native-20261026\package\data`，四个文件全部通过当前资源锁核验；未重新生成词典，也未读取已安装产品数据。完整资源的首次 open 检查仍通过，不能据此宣称 READY 前已加载资源。
- [x64-on-ARM64 拒绝报告](evidence/amd64-on-arm64-rejection.json)：最终源码交叉编译所得测试 PE 为 AMD64，实际运行两个门禁测试，观察 `GOARCH=amd64`、`processMachine=0`、`nativeMachine=0xaa64`、`accepted=false`，默认启动在原生门禁中止。这是本机异构拒绝证据，**不是原生 x64 通过结果**；新增改动仍需原生 x64 CI 执行。
- 最初的外部证据整理脚本假定仿真 x64 必返回 `processMachine=0x8664`，与本机返回的零不同；两个 Go 测试本身当时均通过且正确拒绝。保留 [首次实际观察](evidence/amd64-observation-initial.log)，把 `amd64 / 0 / 0xaa64` 补入回归后重新记录最终原生结果；[首轮 26 子案例结果](evidence/native-arm64/result.json)亦保留，没有改写为最终结果。
- Python 证据验证器 10 项、CI 工作流合同 9 项测试通过；`gofmt` 和 `git diff --check` 通过。独立源码复核未发现需修改的问题。

本轮本地验证基于上述 PR head 的未提交源码修改执行，报告明确 `sourceChanges=true`；[验证索引](evidence/validation-index.json)记录最终变更源码的 SHA-256 和证据摘要，其中 `committed/pushed=false` 保留验证时快照，不代表之后的发布状态。用户随后授权将补充提交并推送到 PR #113；提交身份与远端检查结果以 PR 最新提交及其 CI 为准。没有将本地结果继承给已安装 `.7`/`.8` 或任何其他版本，本轮不安装、注册或运行真实 TIP/宿主。

## 复现入口

在对应的原生 Windows 架构、已有 Go 工具链与完整锁定 CN134 数据下运行（x64 将 `arm64` 改为 `amd64`）：

```text
python -X utf8 tools/yimecore/verify_18u_broker_offline.py --architecture arm64 --data <完整锁定数据目录> --output <新的证据目录> --go <原生Go工具路径>
python -X utf8 -m unittest discover -s tools/yimecore -p test_verify_18u_broker_offline.py -v
python -X utf8 -m unittest discover -s tools/ci -p test_installed_18u_workflow.py -v
```

第一条入口仅执行点名的离线测试，输出中不会把传输替身当作真实 Broker READY。原生 x64/ARM64 使用同一组必需测试与同一结果校验；不允许用 x64 仿真结果替代 ARM64，也不允许用上述本机 x64 拒绝测试替代原生 x64 结果。
