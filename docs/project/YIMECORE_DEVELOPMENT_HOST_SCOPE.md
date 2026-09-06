# YimeCore：本机产品与主流 x64 / ARM64 试验范围

更新：2026-09-04。用户已明确批准主流 Windows x86-64 和 Windows ARM64 试验恢复。本文与 `tools/yimecore/development-scope.json` 优先于历史阶段的冻结描述。

## 两条独立执行路线

- 本机产品：MYCOMPUTER 原生 x64 Runtime/Broker，x64 与 WOW64 x86 TSF；继续当前 local.11 的 L5 日常使用和 L6 封存。x86 是 32 位应用表面，不是独立硬件/Windows 目标。
- 平台试验：白名单仅列 `mainstream_x64`、`arm64`，使用 `run-platform-experiment.ps1`，不以 L6 完成为启动前置条件。可在本开发机源码构建，实机阶段需指定可用目标。
- 不自动采购、租用或创建云机器。硬件配额模拟与额外高端实体机分支不在本次批准范围。
- 签名事项继续等待审批，公开发行及生产替换不因范围恢复而获准。

## 入口与保护

`Get-YimeCoreDevelopmentScope` 仍保护 MYCOMPUTER 本机安装/编排路线；不能把本机包直接装到新目标。`Get-YimeCoreExperimentTarget` 校验独立试验白名单，目标架构必须与 Go/CMake 映射一致。

`run-platform-experiment.ps1 -Target mainstream_x64` 或 `-Target arm64` 默认为只读 Plan；加 `-Action Build` 才在 `.tmp/yimecore-platform-experiments` 的新子目录从当前身份源码构建 TSF 与 Go 工具，记录源码/PE 哈希并验证机器类型，不安装、不注册、不执行目标二进制。旧身份 x86/ARM64 载荷保持只读，不能重命名或当作新产物。

后续顺序：源码构建 → 目标原生隔离契约 → 目标完整包/升级回退 → 安装态 registered-host → 实机常用应用 → 日常使用与封存。每级单独留证，交叉编译不等于原生运行，本机高配测量不等于主流实机测量。具体见 [恢复计划](YIMECORE_PLATFORM_RESUMPTION_2026-09-04.md)。

默认性能脚本仍仅测 `development_host_x64`，自然调度、无 CPU 配额或亲和性强制；`experiment_profiles` 描述主流 x64/ARM64 的实机测量，历史模拟不复制成新证据。E7 的 `resumed_target_checks` 明确列活动但待目标证据的项目，不再列为冻结；它们与本机就绪分开，公开切换仍为 false。

保护不变：不改默认输入法、生产 Rime/PIME、真实用户学习/词库；不覆盖当前安装或原始恢复介质。安装/备份/恢复仍须 Explorer 启动的非打包维护上下文，原子 staging、同 SID、系统注册表独立核验及回退规则不能弱化。

## 回归

`test-development-scope.ps1` 验证本机编排边界、目标白名单、目标映射、当前 x86 路线、E7 未测不误报通过，以及自然调度性能入口。测试夹具不是实机验收。
