# YimeCore：本机 x86 应用宿主解冻与同步封存计划

日期：2026-09-04。用户明确批准恢复 `MYCOMPUTER` 上 WOW64 32 位应用的 x86 TSF 工作，并与 x64 L5 日常使用、L6 本机封存同步推进。ARM64、其他实体机、老旧 x64 和硬件模拟仍冻结。

## 边界

- 核心 Runtime/Broker 继续只有原生 x64 一份；x86 只是可由 32 位应用进程加载的 TSF DLL、注册工具和注册宿主测试。
- 活动产品继续使用“音元拼音”以及当前 CLSID/Profile。旧包 x86 文件属于历史 CLSID/Profile，只读保留，不执行、不改名、不作为新通过证据。
- 不改变默认输入法，不卸载或改写生产 Rime/PIME，不以本次解冻批准签名、ARM64 或公开发行。

## 与 x64 同步的门禁

| 阶段 | x64 主线 | x86 同步线 | 共同退出条件 |
| --- | --- | --- | --- |
| S1 | local.9 继续日常使用 | 当前源码和身份的 Win32 构建、隔离契约 | 构建不改注册、默认输入法或用户数据 |
| S2 | 记录长文本、切换应用、设置/学习持久化 | 双架构包、WOW64 注册、升级失败回退契约 | x64 现有安装可回退，旧 x86/生产注册保持不变 |
| S3 | 汇总 L5 真实使用结论 | x86 installed registered-host；确认实际加载新 x86 DLL | 自动测试与实际进程证据均通过 |
| S4 | L6 本机包和恢复介质封存 | Firefox 32 位、Notepad++ 32 位人工验收与 x86 证据封存 | `local_product_ready` 明确覆盖本机 x64+x86；公开发行仍独立 |

## 当前状态

- [x] 用户批准本机 x86 应用宿主解冻。
- [x] Firefox 155.0 32 位和 Notepad++ 8.9.8 32 位宿主已准备。
- [x] S1 当前身份 Win32 构建与隔离契约。证据：`.tmp/yimecore-experiment/x86-local-surface/20260904-100339-4da4b1ea`；PE 均为 I386，原生契约通过，注册和默认输入法前后快照一致。
- [x] S2 双架构包、注册事务与回退实现及隔离回归。`local.11` 干净提交候选证据：`.tmp/yimecore-local-product/20260904-102616-bf7a7a1a`；commit `f435f463bfd0a0647d0d9ef9f5711c7ef55a698e`，构建时 `dirty=false`，74 文件，manifest SHA-256 `5a3f847a3136fd2198f7dc9aba22dc017ed7439d8447435e8752eb379a4a5cd8`。2026-09-04 已通过资源管理器入口安装为当前版本。
- [x] S3 安装态 x64/x86 registered-host 在三模式下 6/6 通过；Firefox PID 4968 和 Notepad++ PID 33112 均机械确认加载当前安装根的 x86 DLL。证据：`.tmp/yimecore-experiment/local11-installed-x64-x86-host-20260904` 与 `.tmp/yimecore-experiment/local11-x86-live-host-20260904`。
- [x] S4 的 x86 分支：Firefox 155.0 与 Notepad++ 8.9.8 均由用户确认组合提交、裸数字组字、`Shift+1` 首候选三项通过；见 [local.11 x86 验收记录](../YIMECORE_LOCAL11_X86_ACCEPTANCE_2026-09-04.md)。
- [ ] S4 共同退出：x64 L5 日常使用结论及 L6 本机包/恢复介质合并封存仍待完成，故 `local_product_ready` 仍为 false。

任何单项成功只关闭对应门禁，不提前宣称整个 x86 工作流或公开发行完成。
