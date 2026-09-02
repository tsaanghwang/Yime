# YimeCore 三档机台性能剖析、优化与模拟测试（2026-09-02）

## 结论

- 不需要因为原先的性能倍数直接把 YimeCore 全面改写为 C++。当前 Go 实现经针对性优化后，全码 E1 p95 从 41.50 ms 降至 2.01 ms（20.68 倍提速），E2 从 129.16 ms 降至 11.27 ms（11.47 倍提速）。
- 三档模拟的功能正确性、暂定交互预算和进程私有内存预算全部通过。最弱档三个码制的 E1 p95 为 29.62–42.70 ms，E2 为 52.23–54.80 ms；主流档分别为 3.05–25.64 ms 和 34.25–36.60 ms；超前档分别为 3.30–7.52 ms 和 15.76–18.26 ms。
- E3 学习相对开销仍不能正式解除阻塞。四轮当前实现复测的 p95 比值中位数约为 full 1.15、variable 1.13、shorthand 1.11，仍略高于 1.10；但绝对 p95 仅约 6–15 µs，原先单轮 1.619 已不再代表当前性能。
- 下一步应先继续优化 Go 句子格和学习评分读路径；只有在代表性普通实体机上仍达不到绝对交互目标时，才考虑把句子格搜索热点做成小范围 C++ 内核，而不是整体重写。

## 实机与三档模型

测试宿主是高性能开发机：Intel Core i9-13900K（24 核、32 逻辑处理器）、128 GB RAM、Samsung 990 Pro 与 Crucial T700 NVMe、Windows 11 Pro build 26200、高性能电源方案、Go 1.26.4。它不能直接代表市面普通机器。

模拟器把目标进程固定到同一逻辑处理器，并通过 Windows Job Object CPU hard cap 将整个作业的 CPU 配额归一化到单个逻辑处理器的相应比例。Job Object 可以约束作业进程的 CPU 与内存等资源；CPU rate control 的 hard cap 由系统调度器执行。参考：[Microsoft Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)、[JOBOBJECT_CPU_RATE_CONTROL_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_cpu_rate_control_information)。

| 档位 | 工程参考机 | 单逻辑核配额 | 调度优先级 | Yime 私有内存预算 |
|---|---|---:|---|---:|
| 老旧但仍受支持 | Windows 10 办公机、2–4 核、8 GB、SATA SSD | 35% | below-normal | 768 MiB |
| 流行主流 | Windows 11 办公机、6–12 核、16 GB、NVMe | 65% | below-normal | 1024 MiB |
| 超前 | 新近高端 Windows 11、16 核以上、32 GB 以上、快速 NVMe | 100% | normal | 1536 MiB |

Windows 11 的最低要求只有双核和 4 GB RAM，不能当作输入法的良好体验目标；本测试因此把“老旧档”定义为仍有现实办公价值的 8 GB Windows 10 级机器，而不是系统能启动的绝对下限。参考：[Windows 11 system requirements](https://support.microsoft.com/en-us/windows/windows-11-system-requirements-86c11283-ea52-4782-9efd-7674389a7ba3)。

这不是完整硬件仿真：没有模拟另一种 CPU 微架构、缓存层级、内存带宽、磁盘冷缓存、固件和后台软件组合；RAM 档位是按实测私有字节作预算判定，没有从 Windows 真正移除物理内存。正式独立发布前仍需补三档实体机复验。

## 本轮剖析结果与优化

初始 CPU profile 显示，短码主要时间落在不可变索引的重复全范围排名扫描；长句还重复构造路径字符串、复制句段并反复计算索引来源 ID。完成了以下优化：

1. 短前缀缓存从只保存 9 个可见候选改为保存 10 个记录，覆盖 9 个候选加 `HasNext` 探测记录，避免正常第一页绕过缓存。
2. 为不可变 FileIndex 增加有界的前缀结果与精确结果共享缓存；最多 4096 项、32768 条记录，避免无限增长。
3. FileIndex 打开时一次性计算来源 ID，不再在每次句子评分时重复 SHA-256 十六进制字符串转换。
4. 句子路径键改为增量构造并随路径缓存，去掉比较热路径中的 `fmt.Fprintf` 和重复全路径序列化。
5. 用户模型 generation 改为原子只读观察，并增加按 engine generation 失效的评分读缓存；外部学习或遗忘后，同一 engine 会在下一次 refresh 看到新 generation 并清空旧视图。
6. E3 测试改为静态/学习交错采样，并允许扩大 batch；在 CPU Job 配额下不再把调度周期等待错误归因给某一半。E3 相对门槛只在无配额本机进行，三档限制用于 E1/E2 的用户可感知延迟。

微基准还显示：短码热回放从约 2.93–3.01 ms 降至约 0.011–0.013 ms；长句热回放从约 16.64–16.82 ms 降至约 4.4 ms，长句分配从约 12.71 MB/次降至约 7.62 MB/次。完整探针的复测如下：

| 阶段（full） | 优化前 p95 | 优化后 p95 | 提速 | 私有内存变化 |
|---|---:|---:|---:|---:|
| E1，完整 9 组探针 | 41.50 ms | 2.01 ms | 20.68x | +3.21 MiB |
| E2，完整 5 组长句探针 | 129.16 ms | 11.27 ms | 11.47x | +4.91 MiB |

## 三档正式模拟结果

以下数字为每次完成整个探针集合的 batch-amortized p95，不是单按键延迟。每档每码制 100 次，YimeCore 与真实 librime 1.17.0 均在相同档位约束下运行。

| 档位 | E1 p95（三码制范围） | E2 p95（三码制范围） | Yime 私有内存 | 正确性 | 暂定绝对预算 |
|---|---:|---:|---:|---|---|
| 老旧但仍受支持 | 29.62–42.70 ms | 52.23–54.80 ms | 68.5–72.6 MiB | 全通过 | 通过（E1 ≤50 ms；E2 ≤100 ms） |
| 流行主流 | 3.05–25.64 ms | 34.25–36.60 ms | 63.1–72.5 MiB | 全通过 | 通过 |
| 超前 | 3.30–7.52 ms | 15.76–18.26 ms | 68.7–72.8 MiB | 全通过 | 通过 |

Job hard cap 按调度周期兑现，所以很短的 Rime/Yime 批次会在约束档位出现量化尾部：例如同一档的某一码制可能刚好跨过一个配额周期。三档判定因此以绝对交互预算为主，约束环境中的 Yime/Rime 瞬时倍数只作诊断。无 Job 配额的同机 full 复测为 E1：Yime 2.01 ms、Rime 7.26 ms（0.28x）；E2：Yime 11.27 ms、Rime 6.02 ms（1.87x）。E2 相对 Rime 仍有差距，但已不是原先 14.88–30.22 倍的数量级。

## E3 阻塞判定

当前代码进行了 4 轮、每轮 100 个交错样本、每样本 5000 次回放：

| 码制 | p95 比值范围 | p95 比值中位数 | 判定 |
|---|---:|---:|---|
| full | 1.12–1.20 | 1.15 | 未稳定通过 1.10 |
| variable | 0.96–1.22 | 1.13 | 未稳定通过 1.10 |
| shorthand | 1.03–1.23 | 1.11 | 未稳定通过 1.10 |

这个阻塞不证明必须改 C++。优化后静态和学习路径只有约 6–15 µs，1–2 µs 的固定稀疏映射/上下文评分成本就会让纯比例门槛明显波动。当前应保留“E3 相对门槛未稳定通过”的准确结论，同时增加一个经过评审的绝对开销上限或最小分母规则；在规则正式修改前不能把该门槛写成通过。

## 决定的后续改进顺序

1. **P0：继续优化 E2 Go 句子格。** 用紧凑 backpointer/索引替代每条路径复制完整 `[]Segment`、文本和路径键；先以 full E2 无约束 p95 接近 Rime 1.10 倍、老旧档不超过 75 ms 为目标。
2. **P1：批量化用户模型评分读取。** 为一个 refresh 构造按 code 和 previous-context 索引的只读稀疏评分视图，避免每个候选分别做复合字符串 map 查找；之后重复四轮 E3。
3. **P1：评审 E3 门槛。** 保留 1.10 相对目标，同时讨论加入例如“相对 ≤1.10，或绝对 p95 增量 ≤5 µs”的稳定性条款。未经评审不改现有门槛。
4. **P2：补真实普通机与冷启动。** 至少覆盖 8 GB Windows 10/SATA SSD、16 GB 主流 Windows 11/NVMe、32 GB 以上新平台；采集冷启动、首键、长句、连续输入、后台负载和 Word/浏览器/Excel 宿主数据。
5. **C++ 决策点。** 若 backpointer 与批量评分完成后，实体老旧/主流机仍无法满足绝对预算，再只抽取句子格搜索内核做 Go/C++ A/B；目前不批准整体 C++ 重写。

## 证据与复现

- 正式三档证据：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-20260902-v3\summary.json`，SHA-256 `5bb1e21a2acbabeef660d0946f3caf15257ad5b56ca1aa3f2a5ed7d60d01c07c`
- 宿主证据：`C:\dev\Yime\.tmp\yimecore-tier-performance\final-20260902-v3\host.json`，SHA-256 `a943b3164c9d6573a79542113a37343185d87a1ca7e9beb708b9f1e56bbeff54`
- 优化后 E1/E2：`C:\dev\Yime\.tmp\yimecore-tier-performance\optimized-current\`
- 无配额 Rime 对照：`C:\dev\Yime\.tmp\yimecore-tier-performance\rime-native-current\`
- CPU profiles：`C:\dev\Yime\.tmp\yimecore-tier-performance\profiles\`
- 可重复执行：`powershell -ExecutionPolicy Bypass -File C:\dev\Yime\tools\yimecore\run-yimecore-tier-performance.ps1 -Iterations 100 -LearningIterations 100`

测试只读取已安装试验版 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-1059d259498a-c4c2c860\indexes`，没有安装、卸载或改写生产 Rime/PIME 注册。签名事项状态保持为：**签名证书正在申请，等候审批，暂缓相关事项**。
