# 主流 x86-64 / ARM64 平台试验恢复

2026-09-04 用户批准，状态：活动。目标只有主流 Windows x86-64 与 Windows ARM64；与本机 local.11 的 L5/D2、L6 同步推进，不覆盖日常安装。按白名单管理目标，不设其他机型的待办、恢复条件或发布检查项。

| 阶段 | 主流 x86-64 | ARM64 | 合格证据 |
| --- | --- | --- | --- |
| P0 范围及入口 | 已恢复 | 已恢复 | 当前 scope、Plan 输出及范围回归 |
| P1 当前身份源码构建 | 已通过本机源码构建 | 已通过 ARM64 交叉构建 | 新目录、源码记录、PE 机器类型与哈希；不代表运行通过 |
| P2 原生隔离契约 | 待指定实机执行 | 待指定实机执行 | 原生 Runtime/Broker、TSF 契约、三模式及学习/重启；不能用模拟替代 |
| P3 平台包与维护 | 待验收 | 待开发/验收 | 完整目标包、依赖、普通用户启动、COM/Profile、同 SID、升级/回退、数据与默认设置保护 |
| P4 实际宿主 | 待验收 | 待验收 | 目标上安装态 registered-host、常用应用实际 DLL 加载和人工输入 |
| P5 日常使用/封存 | 待确认 | 待确认 | 用户确认、恢复介质、已知限制；不自动准许公开发行 |

## 立即可用的入口

```powershell
& tools/yimecore/run-platform-experiment.ps1 -Target mainstream_x64
& tools/yimecore/run-platform-experiment.ps1 -Target arm64
# 独立源码产物，不执行目标 EXE、不装包：
& tools/yimecore/run-platform-experiment.ps1 -Target mainstream_x64 -Action Build
& tools/yimecore/run-platform-experiment.ps1 -Target arm64 -Action Build
```

本开发机只作为编排/源码构建机。ARM64 当前身份构建使用 `-A ARM64 -DYIME_LOCAL_PRODUCT=ON` 和 `GOOS=windows GOARCH=arm64`，禁止拿旧身份 ARM64 载荷充数。独立构建清单不是可安装包，不能交给本机维护器安装到目标。

## 实机开始前需要的信息

每个目标应明确可用设备、Windows 版本、CPU/原生架构、RAM、存储、访问方式及可安排的人工维护窗口。当前没有指定新设备；不自动创建云主机或采购。首次目标维护先核对默认输入法、生产组件、独立恢复介质及回退，再另行生成匹配平台的完整包。

主流 x64 参考 6–12 核、16 GB RAM、NVMe；这是试验采样参考，不是已经证明的最低配置。ARM64 记录实际设备规格，不以开发机性能外推。默认本机性能预算不改，实机试验 profile 与历史模拟分开。

## 证据解释

本轮执行记录：两个目标的完整 TSF 构建及描述符列出的 Go 工具均编译成功，PE 机器类型逐项核对，构建前后生产/冻结旧身份注册与默认设置保持不变。源码为当前工作树，`git_dirty=true`，不是正式发布候选。

- x64：`.tmp/yimecore-platform-experiments/mainstream_x64-20260904-210805-14300566/summary.json`。
- ARM64：`.tmp/yimecore-platform-experiments/arm64-20260904-210754-3ab01cca/summary.json`。
- 每目标 26 个 PE 产物，最终入口沿用本机描述符的 GUI/console 链接选项，清单逐项记录 `pe_machine`；先前构建目录保留为过程证据。
- 两次都未执行目标二进制、未注册或安装；`native_contracts_passed`、`target_package_passed`、`physical_host_passed` 均为 null。
- 范围回归 88 项、平台入口契约 15 项、本机构建契约 68 项、原始 local.11 包维护契约 37 项及 `go test ./cmd/yimecore-independence-audit` 通过。范围回归使用合成夹具，不能作为 P2–P5 证据。
- 包维护契约初次误用已安装目录作迁移夹具，原安装路径标记在复制后被审计器正确拒绝；未绕过保护。改用 manifest 相同的原始完整包重验后 37 项通过，证据为 `.tmp/yimecore-local-product/platform-package-contract-dd5219c520464bbebffb327624b58a2f/summary.json`。不是本轮新目标运行回归。
- 当前安装 local.11 的 74 项文件仍匹配原 manifest，12 项默认语言/生产/旧身份注册指纹相对 D1 基线不变，见 [保护核对](../testing/platform-resumption/2026-09-04-protection.json)。

范围解冻不是兼容承诺；P1 通过不能填写 P2–P5。E7 本机报告单列 `resumed_target_checks` 为 `pending_target_evidence`，目标发布就绪保持 false。当前包、D1 记录、D2 学习样本和原始历史证据保持原状；不为新 scope 重写旧 JSON 或回滚包哈希。
