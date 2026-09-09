# YimeCore 启动健康检查接入维护事务

本批将现有健康适配器接入实际维护启动路径。新候选在 `local-product.json` 显式声明
`maintenance_health.protocol=yimecore-maintenance-health-v1` 和布尔
`required_on_start=true`；缺少声明的历史包保持原有合同。声明存在但为 null、未知
协议、错误类型或 false 都不能降级为旧包。

`Start-TrialRuntime` 在当前包通过验证后启动，并在返回 `running` 前完成检查；
`Start-LocalProductRuntime` 的备份/恢复重启路径执行相同检查。保留本次 Runtime
原始 `Process`，从状态 PID 取得 Broker 引用后，由原生观察器核对实际父子关系、
创建时间、SID、映像及包清单哈希，再对两个服务完成 nonce 挑战。
共享观察模块不使用 `-Force`，本次租约在成功或失败后均关闭。

健康失败由原启动函数抛出并清理本次未获准 Runtime；安装调用进入既有回滚路径，
不会进入旧根清理。声明必需健康检查的新候选在 staging/preinstall 之前拒绝
`NoLaunch`。回滚时重新验证实际旧根的包，以旧包自己的能力声明启动，不能把新包
的健康要求强加给 local.12。

## 包与兼容性

新声明要求六个包内帮助文件，其中 `maintenance/local-product-runtime.ps1` 原已
存在，另外五个是现有原生观察器、健康客户端及 C# 帮助源码。固定的共享事实源码
显式复制到包内 `dual-product/rime-pime-dp1u-native-facts.cs`，满足观察器既有相对
路径。运行不读仓库、不依赖已安装 Rime/PIME；原健康模块及其字节 pin 没有修改。

Builder 在输出目录创建及构包前校验声明和六条精确 source/path。Go 独立性审计
对声明者要求相应普通文件、精确清单路径、大小及 SHA-256；旧描述符仍使用旧文件
集合。没有改写历史候选、归档、版本身份或已经安装的 local.12。

## 证据边界

新启动回归执行生产 AST 函数及其成功返回、catch 清理和异常传播，使用自有隐藏
进程与包内提供程序替身。timeout、错误 nonce 和子进程退出是本次提供程序故障
夹具；原生管道协议由现有独立回归覆盖，本次不能冒称真实安装或完整原生回滚。
构建入口另有双 shell 纯函数回归，Go 审计使用私有目录。

## 本批验证

| 范围 | 本轮结果 |
| --- | --- |
| 实际启动函数及安装前策略块，包内提供程序替身 | PS5/PS7 各 47/47；每轮 29 个自有进程全部清理 |
| Builder 健康声明/目录纯函数 | PS5/PS7 各 15/15 |
| 既有 native rehearsal outcome 回归 | PS5/PS7 各 99/99；仅自有进程/临时文件 |
| Go 独立性审计测试包 | 23 个顶层测试通过，含子测试共 151 个 PASS 事件；2 项缺少 Windows 符号链接权限而 SKIP，未记为通过 |
| 按描述符复制六个 helper 后的布局夹具 | PS5/PS7 各进程 103/103、健康协议 73/73；每轮 22 种自有管道情形，未留挂起 I/O |

启动回归发现并修复了 PS7 将 JSON PID 解析为 Int64 的兼容问题；现在只接受
1 到 Int32.MaxValue 范围内的 Int32/Int64，字符串、数组、浮点及溢出都在入口拒绝。
两项 Go SKIP 分别为 `TestLocalMaintenanceHealthRejectsIndirectHelper` 和
`TestLocalSpeechContractRejectsIndirectResources`（Windows 错误 1314）。

| 证据（相对仓库根） | SHA-256 或绑定范围 |
| --- | --- |
| `.tmp/local-startup-health-tests-20260909/ps5-final-v2.json` | `e6d5be6396cc3af830499edeb54eaf4f9135b1021b8d1f9f457fe6708a483813` |
| `.tmp/local-startup-health-tests-20260909/ps7-final-v2.json` | `1b6e6878890878290589667cd4349ebc404d3f978f81fd8a832e94c928cd4f97` |
| `.tmp/local-health-capability-20260909/summary.json` | 描述符、builder、Go 审计三文件的逐项 SHA-256；同目录保留 Go JSONL、双 shell builder 结果 |
| `.tmp/startup-health-rehearsal-20260909/ps5.json`、`ps7.json` | 既有 99 项 outcome 回归；首次调用因未创建结果父目录而退出 1，创建专用目录后重跑两轮均退出 0 |
| `.tmp/hll-98b89a6b/summary.json` | `a1da69fdbf0f465b096f73e35abc6a8156f5a937b94f95243c7b0874a2c5107e` |

启动结果绑定生产 helper `5063f4925188d9966f1242325d30587179d285aaeb974636c2f18225d05ba24f`、
安装控制器 `c4585051463c18b1164a4bf5eeb624f232fcc4b2c4177180feebe2e3c4448d75` 和测试
`f46b3382d8e571a56e27aed312a46e671f1480f77ba37d6ba728e96e85d62323`。
布局夹具包含两个未修改测试脚本及一个同目录描述符测试副本，明确不是完整候选；
六个实际 helper 均以原始字节复制到包内声明路径，原生类型和管道客户端从包内加载。
本批新增启动测试接入已有双 shell CI，不增加长矩阵腿。仓内证据不称为仓外归档。

健康应答仍仅证明服务响应及进程绑定，不代表
引擎可用、登录启动或 E7/L6 验收；适配器中的 `runtime_ready`、`E7_accepted`、
`L6_sealed`、`local_product_ready`、`public_release_ready` 继续为 false。
本次不构建/安装新候选，不执行实际备份恢复，不读取生产用户状态。
