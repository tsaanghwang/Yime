# ARM64 合成文件句柄与加载对象探针

此项目与产品构建、安装器和注册器完全分开。它只生成合成脚本、模块、工具和 DLL；标记 A/B 仅用于辨认受控合成对象，不是任意程序的安全证明。ARM64 安装和卸载拒绝门保持关闭。

## 源码阶段

在独立输出目录使用 Visual Studio 2022 ARM64 工具集、Windows SDK 和 CMake 配置：

```text
cmake -S tools/yimecore/arm64-handle-probe -B <新构建目录> -G "Visual Studio 17 2022" -A ARM64
cmake --build <新构建目录> --config Release
python tools/yimecore/arm64-handle-probe/test_source_contract.py
```

核对五个 Release PE 均为 `Machine=ARM64 (0xAA64)`：`YimeArm64HandleProbe.exe`、`YimeSyntheticToolA.exe`、`YimeSyntheticToolB.exe`、`YimeSyntheticModuleA.dll`、`YimeSyntheticModuleB.dll`。源码阶段不启动探针。静态合同只约束源码结构；不证明运行时共享冲突、身份绑定或安全性。

## VM 环境及入口

使用从快照启动的可丢弃原生 Windows ARM64 VM，固定本地 NTFS 卷。需要已核验官方系统级原生 ARM64 `pwsh.exe` 的绝对路径、MSVC ARM64、Windows SDK 和 CMake。无需管理员权限、额外账户、ACL 修改或链接创建。五个构建产物放在同一受控目录；每次调用使用一个**不存在**的本地 NTFS `probe-*` 输出目录，且其已存在的父目录及所有路径祖先不能是重解析点。命令只允许以下形状：

```text
<探针绝对路径> --pwsh <pwsh.exe绝对路径> --output <新probe-*目录绝对路径> --case <share|replace|script-module|tool|dll>
```

必须先独立核验测试包来源与五个 PE 哈希；测试程序自身只检查 ARM64 PE，不提供发布来源核准。每个场景仅运行一次，首个非预期结果即停止、保留快照和输出，不自动重试。不得在 ASUS 运行路径替换或加载场景。

## 场景与期望

先在同一可丢弃 VM 的另一个新输出根运行 `test_probe_vm_negative.py --probe <探针绝对路径> --pwsh <PS7绝对路径> --root <不存在的新目录>`。它首先以 `directory-contract` 仅创建目录，不启动子进程；从预期路径以 `CreateFileW` 的不跟随末端重解析点选项独立重开，保存第二个句柄的原始字段，并与创建句柄记录的卷号、完整 128 位文件 ID 和最终路径比较，同时检查 `FILE_CREATED`、目录属性及重解析标志。失败即停止。之后才核对被拒绝的已有目录及原有 `failure.txt` 完全不变，并用 `timeout-child`、`timeout-actor` 两个仅供故障注入的场景检查私有 Job 终止、回收和 PID 停止。故障注入的非零退出是预期结果；脚本仅在全部检查成立时报告成功。离线 `test_directory_identity_contract.py` 覆盖匹配对照、卷号与文件 ID 两半不一致、路径不一致及异常字段；它不执行探针，也不替代 VM 结果。此脚本不在 ASUS 运行。

目录创建使用 `NtCreateFile` 的 `FILE_CREATE`、`FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT` 和 `SYNCHRONIZE`。微软发布的目录选项兼容列表没有 `FILE_OPEN_REPARSE_POINT`，故创建调用不再组合该选项。相对创建所用的父目录句柄先由另一次 `NtCreateFile` 取得，并与先前不跟随末端重解析点打开的父目录句柄比较卷号和文件 ID。`FILE_CREATE` 对已存在名称应拒绝，但链接和文件系统筛选器的具体结果仍需在 VM 观察；编译通过不算运行证据。

| 场景 | 期望 |
| --- | --- |
| `share` | 主进程持 `GENERIC_READ` 且只分享读取句柄；同步后的独立 ARM64 子进程写入、请求删除权限和同路径移走均失败；前两项错误为 `ERROR_SHARING_VIOLATION=32`。 |
| `replace` | 先满足 `share`；释放句柄后将同字节 B 文件换入原路径。重新打开后 SHA-256 相同、卷号与 128 位文件 ID 组合不同。 |
| `script-module` | 每次新原生 ARM64 PS7 进程以 `-NoProfile -NonInteractive -File` 执行合成脚本，脚本显式导入合成 `.psm1`；A/B 各输出对应脚本和模块标记。 |
| `tool` | 每次新原生 ARM64 工具进程从同一路径返回对应 A/B 编译标记。 |
| `dll` | 每次新原生 ARM64 工具进程加载同一路径的合成 DLL，返回对应 A/B 导出标记，并记录模块路径和映射路径。 |

已创建并持有目录句柄的输出目录保留 `events.jsonl`、原始 `.stdout.bin`、`.stderr.bin`、`.exit.txt` 和合成文件。失败写入已打开的日志句柄中的 `case-failed`；在目录创建或持有前失败时仅写标准错误，不按未经核准的路径创建 `failure.txt`。`events.jsonl` 记录句柄所得卷序列号、文件 ID、最终路径、SHA-256、进程架构、退出码与标记；应对照原始字节、文件 ID 和标记，不仅看路径字符串。程序成功结束写入 `case-passed`。运行者还应记录 VM 快照 ID、Windows/PS7/工具版本、探针及五个 PE 的哈希。A/B 文件 ID 是执行前从路径打开的快照，标记是进程返回的可观察结果；两者的对应关系是受控实验的推断，并非从 PowerShell 或 DLL 加载器内部取得同一文件对象句柄。

## 停止与结论边界

拒绝非本地 NTFS、重解析点、非 ARM64 PE 或进程、参数或输出目录不合约、文件 ID/哈希与标记不一致、超时及任一意外 Win32 错误。每个子进程先在挂起状态加入本轮私有 Job，随后才运行；超时或启动后异常时只终止该 Job 并限时核实进程退出。无法确认停止时明确报告 `STOP UNCONFIRMED` 并保留现场，不操作无关进程。停止后不要清理或继续其他场景。VM 用完后按预先批准的流程丢弃快照。

结果只能说明该 VM 上合成文件的句柄共享、替换后的对象身份和可观察加载结果。持有输出目录句柄并不固定所有祖先目录：创建时使用的父目录句柄在返回后释放，后续日志、合成文件和子进程仍有按绝对路径打开的步骤。现有负例尚未覆盖祖先目录被替换；受控 VM 应另设同步点，在目录句柄持有期间尝试替换可写祖先，记录是否被拒绝及后续绝对路径实际解析到的文件 ID，首个异常即停。完成该试验前，不能声称探针已保护整条路径，更不能据此声称产品级路径保护完成。它也不能证明 Yime 未来维护入口加载了已核准对象，或消除 PowerShell 按路径重开、既存可写映射及特权进程造成的窗口。真实 NTFS ACL 与不同账户、重解析点攻击、UAC、设置页卸载和实机输入仍需独立验证。
