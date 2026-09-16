# 主流 x86-64 / ARM64 平台现状与恢复记录

## 当前范围与证据（2026-09-16）

已批准目标仍为主流 Windows x86-64、Windows ARM64，以及开发机 `MYCOMPUTER` 的 x64/x86 WOW64 表面。范围真源是 [development-scope.json](../../tools/yimecore/development-scope.json)；未列出的设备类别、云主机和硬件采购不在本轮范围内。

| 目标 | 可用机器与当前结论 | 证据边界 |
| --- | --- | --- |
| 开发机 x64/x86 | `MYCOMPUTER`；当前源码构建与简版维护均有记录 | x86 是 WOW64 应用中的 TSF 表面，Runtime/Broker 为原生 x64；[x86 历史专项](YIMECORE_X86_RESUMPTION_PLAN_2026-09-04.md)与后续包分开记证 |
| 主流 x64 | 已指定“计算机”，Intel Core i7-7820X；已有独立测试机维护与输入结果 | [简版维护记录](../../installer/simple/VALIDATION.md)覆盖其实际包和场景；源码候选包的两套产品在 Codex、记事本中重启前后输入获确认，Word 未报告，不外推为全部宿主通过 |
| ARM64 | 尚未指定可用实机；保留当前身份交叉构建证据 | 尚无本轮完整 ARM64 安装包、原生 Runtime/Broker 运行、安装态 registered-host 或实际应用输入验收 |

当前安装工程为 [installer/simple](../../installer/simple/README.md)，后续交付按[当前交接](../../installer/simple/HANDOFF.md)指定的提交、通过 CI 的完整包、下载地址和 SHA-256 执行。现有验收不自动覆盖后续源码或新包；已完成阶段不因文档改写而重跑。生产数据迁移与备份恢复仍另行规划。

## 源码实验入口

以下示例从仓库根目录经 checked 入口运行。将 JSON 保存为 UTF-8 的 `.tmp/platform-experiment-params.json`：

```json
{
  "Target": "mainstream_x64",
  "Action": "Plan"
}
```

```text
python -X utf8 tools/powershell/run_checked.py --script tools/yimecore/run-platform-experiment.ps1 --edition ps7 --params-file .tmp/platform-experiment-params.json
```

`Target` 可为 `mainstream_x64` 或 `arm64`。`Plan` 输出范围和机器描述，不构建；将 `Action` 改为 `Build` 才会在新的隔离目录构建源码产物，核对 PE 类型和保护快照，不执行目标 EXE、注册或安装。构建使用当前产品身份，不能执行或改名复用旧身份载荷。ARM64 使用 `-A ARM64 -DYIME_LOCAL_PRODUCT=ON` 和 `GOOS=windows GOARCH=arm64`；这些构建结果不等于 ARM64 可安装包。

`Package` 当前仅接入 `mainstream_x64` 的本机产品构建器；语流准入根及摘要参数以[源码工具说明](../../tools/yimecore/README.md)和脚本契约为准。ARM64 不能用独立交叉构建清单替代完整包交付。新目标的实际验证须记录设备、Windows 版本、原生架构、硬件条件、实际宿主及包身份；ARM64 仍需先确定可用实机。

## 2026-09-04 恢复阶段快照

以下表格及原始路径保留当时的进度和结果，不作为当前安装任务。当日用户批准恢复主流 Windows x86-64 与 Windows ARM64 试验，与本机 local.11 的 L5/D2、L6 同步推进，不覆盖日常安装。旧事务、恢复介质和 `local_product_ready` 退出条件已随安装器重写退役，不再要求为下列未完成项补跑旧链。

| 阶段 | 主流 x86-64 | ARM64 | 合格证据 |
| --- | --- | --- | --- |
| P0 范围及入口 | 已恢复 | 已恢复 | 当前 scope、Plan 输出及范围回归 |
| P1 当前身份源码构建 | 已通过本机源码构建 | 已通过 ARM64 交叉构建 | 新目录、源码记录、PE 机器类型与哈希；不代表运行通过 |
| P2 原生隔离契约 | 待指定实机执行 | 待指定实机执行 | 原生 Runtime/Broker、TSF 契约、三模式及学习/重启；不能用模拟替代 |
| P3 平台包与维护 | 待验收 | 待开发/验收 | 完整目标包、依赖、普通用户启动、COM/Profile、同 SID、升级/回退、数据与默认设置保护 |
| P4 实际宿主 | 待验收 | 待验收 | 目标上安装态 registered-host、常用应用实际 DLL 加载和人工输入 |
| P5 日常使用/封存 | 待确认 | 待确认 | 用户确认、恢复介质、已知限制；不自动准许公开发行 |

### 当时采样与构建条件

当时尚未指定新目标设备，开发机承担编排和源码构建。主流 x64 曾以 6–12 核、16 GB RAM、NVMe 作为采样参考，并非已经证明的最低配置。当前机器状态以上方表格和 scope 为准，不把采样参考变成硬件准入条件。ARM64 仍需记录实际设备规格，不以开发机性能外推。

### 原始证据解释

2026-09-04 执行记录：两个目标的完整 TSF 构建及描述符列出的 Go 工具均编译成功，PE 机器类型逐项核对，构建前后生产/冻结旧身份注册与默认设置保持不变。源码为当时工作树，`git_dirty=true`，不是正式发布候选。

- x64：`.tmp/yimecore-platform-experiments/mainstream_x64-20260904-210805-14300566/summary.json`。
- ARM64：`.tmp/yimecore-platform-experiments/arm64-20260904-210754-3ab01cca/summary.json`。
- 每目标 26 个 PE 产物，最终入口沿用本机描述符的 GUI/console 链接选项，清单逐项记录 `pe_machine`；先前构建目录保留为过程证据。
- 两次都未执行目标二进制、未注册或安装；`native_contracts_passed`、`target_package_passed`、`physical_host_passed` 均为 null。
- 范围回归 88 项、平台入口契约 15 项、本机构建契约 68 项、原始 local.11 包维护契约 37 项及 `go test ./cmd/yimecore-independence-audit` 通过。范围回归使用合成夹具，不能作为 P2–P5 证据。
- 包维护契约初次误用已安装目录作迁移夹具，原安装路径标记在复制后被审计器正确拒绝；未绕过保护。改用 manifest 相同的原始完整包重验后 37 项通过，证据为 `.tmp/yimecore-local-product/platform-package-contract-dd5219c520464bbebffb327624b58a2f/summary.json`。不是本轮新目标运行回归。
- 当时安装的 local.11 的 74 项文件匹配原 manifest，12 项默认语言/生产/旧身份注册指纹相对 D1 基线不变，见 [保护核对](../testing/platform-resumption/2026-09-04-protection.json)。

当时的 P1 通过没有关闭 P2–P5。E7 本机报告中的 `resumed_target_checks` 为 `pending_target_evidence`，目标发布就绪为 false；这些历史字段保持原样。后续简版维护和测试机结果分别链接至新的报告，不回写旧 JSON、D1/D2 记录或回滚包哈希。`.tmp` 路径仅作原始证据定位，不能作为新一轮说明或包交付地址。
