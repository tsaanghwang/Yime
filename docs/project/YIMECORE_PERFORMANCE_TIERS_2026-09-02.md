# YimeCore 主流/超前机台性能剖析、优化与模拟测试（2026-09-02）

## 结论

- 不需要因为原先的性能倍数把 YimeCore 全面改写为 C++。两轮 Go 优化后，无配额 full E1 p95 从 41.50 ms 降至 1.26 ms（约 32.9 倍提速），E2 从 129.16 ms 降至 6.64 ms（约 19.5 倍提速）；本轮 full E2 已低于同轮真实 Rime 的 7.23 ms。
- 当前正式门槛只保留主流档和超前档，两档模拟的功能正确性、暂定交互预算和进程私有内存预算全部通过：主流档 E1/E2 分别为 2.08–3.86 ms 和 25.65–28.14 ms；超前档分别为 2.00–3.75 ms 和 8.53–12.94 ms。老旧 Windows 10/SATA SSD 档自本决策起退出评测矩阵，不再构成发布或继续推进阻塞。
- E3 已从“中位数超过 1.10”改善为五轮中位数 full 1.077、variable 1.090、shorthand 1.063，15 个码制轮次中 12 个通过；最大绝对 p95 增量只有 1.50 µs。由于 full 仍有 1.114/1.126、variable 仍有 1.115，严格的“每轮都不超过 1.10”尚未稳定解除，阻塞已缩小为微基准尾部复现性，而不是用户可感知延迟。
- 下一步不再把“改成 C++”作为默认方案。先在普通实体机补冷启动和真实宿主数据，并评审 E3 的绝对增量条款；只有实体机绝对预算失败时，才考虑把剩余句子格热点小范围下沉到 C++。

## 实机与正式双档模型

测试宿主是高性能开发机：Intel Core i9-13900K（24 核、32 逻辑处理器）、128 GB RAM、Samsung 990 Pro 与 Crucial T700 NVMe、Windows 11 Pro build 26200、高性能电源方案、Go 1.26.4。它不能直接代表市面普通机器。

模拟器把目标进程固定到同一逻辑处理器，并通过 Windows Job Object CPU hard cap 将整个作业的 CPU 配额归一化到单个逻辑处理器的相应比例。Job Object 可以约束作业进程的 CPU 与内存等资源；CPU rate control 的 hard cap 由系统调度器执行。参考：[Microsoft Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)、[JOBOBJECT_CPU_RATE_CONTROL_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_cpu_rate_control_information)。

| 档位 | 工程参考机 | 单逻辑核配额 | 调度优先级 | Yime 私有内存预算 |
|---|---|---:|---|---:|
| 流行主流 | Windows 11 办公机、6–12 核、16 GB、NVMe | 65% | below-normal | 1024 MiB |
| 超前 | 新近高端 Windows 11、16 核以上、32 GB 以上、快速 NVMe | 100% | normal | 1536 MiB |

原“老旧但仍受支持”档（Windows 10、2–4 核、8 GB、SATA SSD、35% 单核配额）仅保留既有结果作为历史工程参考。`performance-tiers.json` 已删除该活动 profile，后续标准脚本不会再运行它，任何该档失败也不进入阻塞判定。

这不是完整硬件仿真：没有模拟另一种 CPU 微架构、缓存层级、内存带宽、磁盘冷缓存、固件和后台软件组合；RAM 档位是按实测私有字节作预算判定，没有从 Windows 真正移除物理内存。正式独立发布前仍需补主流和超前两档实体机复验。

## 本轮剖析结果与优化

初始 CPU profile 显示，短码主要时间落在不可变索引的重复全范围排名扫描；长句还重复构造路径字符串、复制句段并反复计算索引来源 ID。完成了以下优化：

1. 短前缀缓存从只保存 9 个可见候选改为保存 10 个记录，覆盖 9 个候选加 `HasNext` 探测记录，避免正常第一页绕过缓存。
2. 为不可变 FileIndex 增加有界的前缀结果与精确结果共享缓存；最多 4096 项、32768 条记录，避免无限增长。
3. FileIndex 打开时一次性计算来源 ID，不再在每次句子评分时重复 SHA-256 十六进制字符串转换。
4. 句子路径键改为增量构造并随路径缓存，去掉比较热路径中的 `fmt.Fprintf` 和重复全路径序列化。
5. 用户模型 generation 改为原子只读观察，并增加按 engine generation 失效的评分读缓存；外部学习或遗忘后，同一 engine 会在下一次 refresh 看到新 generation 并清空旧视图。
6. E3 测试改为静态/学习交错采样，并允许扩大 batch；在 CPU Job 配额下不再把调度周期等待错误归因给某一半。E3 相对门槛只在无配额本机进行，活动性能档限制用于 E1/E2 的用户可感知延迟。

第二轮继续针对 CPU/分配 profile 中的句子格热点做了以下改进：

1. 句子路径改为持久化 backpointer，扩展路径时只新增一个节点，不再为每个分支复制整条 `[]Segment`；只在最终候选、纠错或超长比较回退时物化段列表。
2. 路径键改为增量 FNV-1a 摘要，只有同表面、同摘要的去重比较才构造完整精确键；哈希只用于快速排除，碰撞仍由完整键校验，未改变候选等价性。
3. 缓存前 8 个段的字数形状，常见路径排序不再重复计算 UTF-8 字符数；超过 8 段仍回退到原始精确比较。
4. 句子 beam 和未完成尾部候选改为有界插入，并在同表面替换后只向上恢复顺序，去掉每次替换后的全量排序。
5. 用户分数和 previous-context 分数合并为一个按 generation 与当前上下文失效的 engine 读缓存，把候选评分的两个复合 map 查询合并为一个；`ClearContext`、外部遗忘及 generation 变化仍由现有回归覆盖。

第一轮微基准显示：短码热回放从约 2.93–3.01 ms 降至约 0.011–0.013 ms；长句热回放从约 16.64–16.82 ms 降至约 4.4 ms。第二轮长句热回放进一步稳定在 2.52–2.57 ms，分配从第一轮约 7.62 MB/次降至 2.36 MB/次、分配次数降至约 3.49 万次。完整探针的复测如下：

| 阶段（full） | 优化前 p95 | 优化后 p95 | 提速 | 私有内存变化 |
|---|---:|---:|---:|---:|
| E1，完整 9 组探针 | 41.50 ms | 2.01 ms | 20.68x | +3.21 MiB |
| E2，完整 5 组长句探针 | 129.16 ms | 11.27 ms | 11.47x | +4.91 MiB |

第二轮相对第一轮结果：

| 阶段（full，无配额） | 第一轮 p95 | 第二轮 p95 | 第二轮相对提速 | 同轮真实 Rime p95 |
|---|---:|---:|---:|---:|
| E1，完整 9 组探针 | 2.01 ms | 1.26 ms | 1.59x | 9.17 ms |
| E2，完整 5 组长句探针 | 11.27 ms | 6.64 ms | 1.70x | 7.23 ms |

## 当前双档正式模拟结果与老旧档历史留档

以下数字为每次完成整个探针集合的 batch-amortized p95，不是单按键延迟。每档每码制 100 次，YimeCore 与真实 librime 1.17.0 均在相同档位约束下运行。

| 档位 | E1 p95（三码制范围） | E2 p95（三码制范围） | Yime 私有内存 | 正确性 | 暂定绝对预算 |
|---|---:|---:|---:|---|---|
| 流行主流 | 2.08–3.86 ms | 25.65–28.14 ms | 68.3–73.7 MiB | 全通过 | 通过 |
| 超前 | 2.00–3.75 ms | 8.53–12.94 ms | 63.2–72.2 MiB | 全通过 | 通过 |

老旧档最后一次历史结果为 E1 19.92–38.59 ms、E2 46.55–48.01 ms、私有内存 68.4–72.7 MiB，功能和当时预算均通过；它不再属于正式表格或阻塞集合。

Job hard cap 按调度周期兑现，所以很短的 Rime/Yime 批次会在约束档位出现量化尾部。活动档判定仍以绝对交互预算为主，约束环境中的瞬时 Yime/Rime 倍数只作诊断。无 Job 配额同机复测的 E2 为：full 6.64/7.23 ms（0.92x）、variable 8.14/7.28 ms（1.12x）、shorthand 8.06/5.50 ms（1.47x）。full 已达到 1.10 相对目标；变量码和简码仍有局部差距，但绝对 p95 均低于 8.2 ms。

## E3 阻塞判定

合并评分读缓存后的当前代码进行了 5 轮历史复测、每轮 100 个交错样本、每样本 5000 次回放。其中两轮随当时的三档脚本生成（含一次提交后干净复跑），另三轮独立重复：

| 码制 | p95 比值范围 | p95 比值中位数 | 通过轮次 | 最大绝对 p95 增量 | 判定 |
|---|---:|---:|---:|---:|---|
| full | 1.038–1.126 | 1.077 | 3/5 | 1.50 µs | 中位数通过，单轮尾部未稳定 |
| variable | 1.032–1.115 | 1.090 | 4/5 | 0.68 µs | 中位数通过，单轮尾部未稳定 |
| shorthand | 1.045–1.098 | 1.063 | 5/5 | 0.61 µs | 通过 |

这个结果不证明必须改 C++。优化后静态和学习路径只有约 6–14 µs，不到 1.5 µs 的差值就会让纯比例门槛跨线。当前可解除“中位性能不达标”阻塞，但仍须保留更窄且准确的告警：**full/variable 的逐轮 1.10 门槛尚未稳定复现通过**。在门槛规则正式评审前，不能把全部 E3 严格门槛写成稳定通过。

## 决定的后续改进顺序

1. **P0：补活动档实体机与冷启动。** 覆盖 16 GB 主流 Windows 11/NVMe 和 32 GB 以上新平台；采集冷启动、首键、长句、连续输入、后台负载和 Word/浏览器/Excel 宿主数据。老旧 Windows 10/SATA SSD 不再要求。
2. **P1：评审 E3 门槛。** 保留 1.10 相对目标，同时讨论加入“相对 ≤1.10，或绝对 p95 增量 ≤5 µs”及最小分母条款。未经评审不改现有门槛。
3. **P1：继续优化简码/变量码 E2。** 以无配额真实 Rime 对照定位剩余 12%/47% 差距，优先检查未完成尾部扩展和码制特有候选数量，不改变候选语义或 Rime 分页归属。
4. **P2：评估节点 arena。** 当前最大长句分配热点已变为 backpointer 节点；只有实体机或冷启动预算显示必要时，才用 compose-local arena/索引减少每节点堆分配。
5. **C++ 决策点。** 若上述工作后主流或超前实体机仍无法满足绝对预算，再只抽取句子格搜索内核做 Go/C++ A/B；目前不批准整体 C++ 重写。

## 证据与复现

- 第二轮历史三档证据：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-round2-clean-20260902\summary.json`，SHA-256 `93071b4f20d1650460519327e6422b4be135cab7c6a742ea1b39889e917d6e14`
- 第二轮干净提交宿主证据：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-round2-clean-20260902\host.json`，SHA-256 `854f516b15d53505dc5778fdf3d23890b583395aa97dd5b679658510a2853647`
- 第二轮历史三档配置快照：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-round2-clean-20260902\performance-tiers.json`，SHA-256 `06e6cb9a118b12aa66081554d31bccb57565c9f1d69e89df8ed50df3b8ea605b`
- 当前双档配置：`C:\dev\Yime\tools\yimecore\performance-tiers.json`，SHA-256 `895f76e09a6b2df6ce49b7b4141f65fe2b19e9b7f2c2a67a6bf253b65490c353`
- 第二轮被测源码哈希清单：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-round2-clean-20260902\source-hashes.json`，SHA-256 `76abaa086391ae949218280e72a9e635ed8a1e6314a80ea92b4102727c30b93d`
- 第二轮无配额 E1/E2 与真实 Rime 对照：`C:\dev\Yime\.tmp\yimecore-round2-native\`
- 第二轮 E3 独立重复：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-round2-e3-repeat-20260902\`
- 第二轮 CPU/内存 profile：`C:\dev\Yime\.tmp\yimecore-round2-profile\`
- 可重复执行：`powershell -ExecutionPolicy Bypass -File C:\dev\Yime\tools\yimecore\run-yimecore-tier-performance.ps1 -Iterations 100 -LearningIterations 100`

测试只读取已安装试验版 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-1059d259498a-c4c2c860\indexes`，没有安装、卸载或改写生产 Rime/PIME 注册。签名事项状态保持为：**签名证书正在申请，等候审批，暂缓相关事项**。
