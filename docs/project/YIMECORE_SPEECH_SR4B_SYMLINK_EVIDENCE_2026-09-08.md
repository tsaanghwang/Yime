# SR4-B：符号链接夹具与证据边界

2026-09-08；影响产品：YimeCore 未安装 local.13 的构包／审计测试链。生产路径拒绝逻辑未放宽，Rime/PIME 不受影响。完成的是夹具、严格判定和报告接线；**当前 Windows 权限下四项真实拒绝仍未执行，不能宣称四项 OS 证据已闭合**。

结构化结果见 [2026-09-08-sr4b-symlink-evidence.json](../testing/connected-speech/2026-09-08-sr4b-symlink-evidence.json)，包含原始 JSONL、收据路径及 SHA-256。历史 B1/B2/B3/B4 的 SKIP 不改判。

| 真实负例 | PS5 / PS7 普通模式 | 严格模式 | 尚缺证据 |
| --- | --- | --- | --- |
| `TestSpeechPackageRejectsSymlinkPayload` | SKIP / SKIP | FAIL / FAIL | 文件链接载荷触发包 reparse 拒绝 |
| `TestSpeechProductExportRejectsIndirectSources` | SKIP / SKIP | FAIL / FAIL | 源码树文件链接触发导出 reparse 拒绝 |
| `TestLocalSpeechContractRejectsIndirectResources` | SKIP / SKIP | FAIL / FAIL | 能力文件链接触发包审计 symlink 拒绝 |
| `TestSpeechManifestRejectsOutsideAndIndirectPaths/symlink` | SKIP / SKIP | FAIL / FAIL | 目录链接祖先触发 runtime 路径拒绝 |

实际版本为 Windows PowerShell **5.1.26100.9278**、PowerShell **7.6.5**。四项都在 `os.Symlink` 返回 Windows **1314**，没有夹具可用或已执行拒绝标记。普通模式每版 1 个分类合同 PASS、4 SKIP；`passed=true` 仅表示运行及如实报告有效，OS 状态是 `all_four_rejections_exercised=false`、`exercised_rejection_count=0`。严格模式每版 4 FAIL、0 SKIP、退出码 1，是预期的前置条件红灯，不是拒绝测试通过。

两版各通过 8 个合成报告合同，覆盖有证据的 PASS、权限 SKIP、严格模式拒绝 SKIP、无解释 SKIP、无拒绝标记 PASS、测试缺失、重复终态和失败终态。Go 分类合同覆盖错误 1314、access denied、缺少父目录、重名、文件系统不支持、非 Windows 和成功结果；仅 Windows 1314 可触发权限 SKIP。这些合成合同不计入四项 OS 通过数。

相关源码回归 **260 个命名节点 PASS、4 SKIP、0 FAIL**（含父／子节点），四个包只运行 `TestSpeechProductExport|TestSpeechPackage|TestLocalSpeech|TestSpeechManifest|TestUnavailableClassification`。普通文件、路径字符串、junction 或合成报告不替代符号链接证据。

## 安全复跑与权限前置条件

独立入口只运行源码测试，在仓库 `.tmp/sr4b-symlink-<唯一编号>` 创建新目录，拒绝既有输出与 reparse 祖先；TEMP、APPDATA、LOCALAPPDATA、Go 缓存均隔离，网络依赖获取关闭，退出恢复进程环境。`t.TempDir` 创建和回收自有合成数据，不接收任意外部链接、不读取真实用户设置或学习文件。

从仓库根分别运行（默认允许真实权限 SKIP）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\yimecore\test-speech-symlink-evidence.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\yimecore\test-speech-symlink-evidence.ps1
```

补齐 OS 证据的前置条件是**单独授权且已具备文件／目录符号链接创建能力的 Windows 测试进程**，例如具备适当链接权限的进程，或已经允许非提升创建的开发者环境。入口不自动提升、不修改策略／Developer Mode、不启用权限、不安装产品、不预制外部链接。“管理员账户”不能替代实际创建成功证据。

满足前置条件后，两条命令都追加 `-RequireFixtures`。验收要求退出码 0、四项均 PASS、逐项有 `SYMLINK_FIXTURE_READY` 与精确 `SYMLINK_REJECTION_EXERCISED` 诊断、`exercised_rejection_count=4`、`skipped_count=0`、`all_four_rejections_exercised=true`。创建成功后以 `Lstat`／`Readlink` 核对真实链接及目标；普通夹具先通过校验，负例只接受具体拒绝原因，其他错误不能冒充拒绝。此次未取得该权限，成功路径仍待执行。

完整构包 runner 已接入两版独立收据，保留 SKIP 和已执行数；导出固定来源闭包包含新入口及回归守卫。本次未运行完整 runner，因为它会读取已安装基线并启动正常产品流程。接线只经静态检查，完整构包集成仍待获准验证。

## 包与剩余门槛

没有重建、安装或修改已有 local.13 包。B4 `yimecore-local-0.1.0-local.13-dbfab0b45dd2` 保留历史身份，不能代表修改后的来源闭包。后续仍需新鲜准入、构包、静态载荷完整性及生产注册保持检查；不重用旧包哈希宣称当前源码已封包。

没有读取或触碰 local.12、生产安装、注册表、默认输入法、用户数据或历史回滚载荷，没有执行安装／维护／Runtime／Broker／registered/live host、提升、重启或权限变更。遵守禁止访问 local.12 的边界，本轮未采集安装基线／生产注册保持证据，也未重跑旧包完整性审计。

本轮关闭“无差别 SKIP、任意错误冒充拒绝、缺少独立 PS5/PS7 入口及分项报告”的源码／报告缺口；四项 Windows 实际拒绝、完整构包集成及既有安装／宿主门槛继续开放，SR4、DP1、L5、L6 均不提前完成。
