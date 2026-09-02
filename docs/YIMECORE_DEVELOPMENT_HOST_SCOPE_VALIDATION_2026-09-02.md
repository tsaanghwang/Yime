# 本开发机 x64 范围收敛验证

日期：2026-09-02。范围依据：[本开发机优先阶段](project/YIMECORE_DEVELOPMENT_HOST_SCOPE.md)。

后续状态：本文保留最初的范围收敛结果。此后已安装更新包并完成真实停写恢复和安装故障回退，当前进展见[本机闭环记录](YIMECORE_LOCAL_CLOSURE_2026-09-02.md)；不要把本文的“新包未安装”当作当前状态。

本轮只更新默认构建、升级、性能和验收流程，并执行本机 x64 隔离验证/安装态只读审计。没有安装新包、重启 Windows、操作 Word 或修改生产 Rime/PIME 注册。x86/ARM64 均未编译或执行测试。

## 已验证

- 范围回归：66 项在 PowerShell 7 和 Windows PowerShell 5.1 均通过。覆盖外部机器/ARM64/x86/WOW64 拒绝、Go 交叉目标拒绝、默认 x64 路径、停止分档模拟、旧证据拒绝、冻结不记通过，以及本机安全要求保留。
- 自启动契约：9 个 mock 案例通过；E7 哈希关联自启动证据的 8 个回归案例通过，无真实注册写入。
- E6-C：新 x64 DLL 构建、契约、隔离 TSF composition、64 个英文 Shift 组合、三种编码模式、12 个动态句子、Broker 恢复及打包门禁通过。只有 `text-service-build-x64` 构建目录；6 个 x86/ARM64 基包文件按原哈希留存，明确标注 `tested=false`。
- E6-D：当前安装包 `45b389e530c0-944e300e` 的完整性、独立依赖、活动 x64 COM/runtime、自启动和生产注册保护通过。仍是之前安装的包，不将新暂存包误报为已安装。
- 新自然性能测试：E1/E2 各 100 次，E3 每模式 100 次、batch size 5000；只有本机自然调度，不施加 CPU 配额或固定亲和性。

| 模式 | E1 p95，9 个探针整组 | E2 p95，5 个探针整组 | E3 p95 学习/静态比值 | E3 绝对增量 |
|---|---:|---:|---:|---:|
| full | 1.518 ms | 7.742 ms | 1.1100 | 1.357 µs |
| variable | 3.049 ms | 8.487 ms | 1.1098 | 0.647 µs |
| shorthand | 2.979 ms | 8.448 ms | 1.0529 | 0.337 µs |

正确性、50/100 ms 交互预算及内存预算通过；E1/E2 进程 private bytes 约 66.46–69.46 MiB。这不是每键延迟或全部安装组件的合计内存。E3 full/variable 超过 1.10 比值线，原始 `latency_gate_passed=false` 保留；按已有决定仅告警，不修改测量值，也不扩大为必须改写实现语言的结论。

## 未宣称完成

E7 当前范围、E6-C/E6-D 功能门禁和本机性能门禁均通过。ARM64、x86、其他主流/超前实体机、老旧 x64、分档模拟以及签名均列为 `deferred_checks` / `passed=null`，不在当前阻塞清单。

本机里程碑仍未全部完成：当前工作区未提交形成 clean 源码证据、新暂存包尚未安装、更多本机原生 x64 宿主验收及回退演练/保留方案审批尚缺。E7 因这些如实返回未就绪；不是硬件冻结失败，也不是新的实时宿主故障。下一次正常重启后仍需复核自启动；本轮未再次重启。

签名证书正在申请，等候审批，暂缓相关事项。

## 证据索引

以下路径相对于 `C:/dev/Yime`，测试夹具不可代替真实验收。

- 暂存包及 x64 隔离验收：`.tmp/yimecore-experiment/e6c/development-host-x64-20260902/summary.json`，manifest SHA-256 `9e4faf2aabf3b2f9f538ab7ad583206beedb13e1063be4f10a350eed7da5e04a`。
- 安装态只读审计：`.tmp/yimecore-experiment/e6d-independence/development-host-x64-20260902/summary.json`。
- 本机自然性能：`.tmp/yimecore-tier-performance/development-host-x64-20260902/summary.json`。
- 当前就绪性：`.tmp/yimecore-experiment/e7-readiness/development-host-x64-20260902/summary.json`。
- 范围测试 PS7：`.tmp/yimecore-experiment/e7-readiness/scope-regression-9ee9315516fc42b98b4be4e55b58a990/summary.json`。
- 范围测试 Windows PS：`.tmp/yimecore-experiment/e7-readiness/scope-regression-7d79829330614dbc8874cd5d44ac941a/summary.json`。
- E7 自启动证据回归：`.tmp/yimecore-experiment/e7-readiness/autostart-regression-cd7e50289fb54e5c9bd33c678ea8de72/summary.json`。
