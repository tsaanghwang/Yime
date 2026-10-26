# PR #78 冲突处理与复查

本轮将最新 `main` 的 `9adc3cdd9634e0258b58c9a8945b3497fc8777ad` 合入 ARM 分支，并处理复查发现的两项 ARM64 制包问题：原生验收来源校验和 Go 持久配置隔离。复查覆盖 ARM64X 构建、双 ABI 导入审计、安装维护、连读验收与标准产品/键盘实验室隔离。这不等同于实机稳定性封版。

## 冲突处理

原 PR head 为 `934126ff03c3583f9a119a17c10cd43eb16e8b56`。唯一文本冲突在 `.gitattributes`：ARM 原始证据规则与 main 新增的触摸笔原始日志规则追加到了同一位置。合并保留双方规则，并为本轮安装及复查证据保留原始字节。

安装证据先独立提交，再在 PR 分支合并 main。合并检查确认 main 的 86 个非冲突文件与 main 对应 Git blob 相同，原 PR 中 311 个非 Markdown ARM 证据文件也保持相同 Git blob。没有重写历史失败或将其他机型的物理验收继承为 ARM 结果。

## 发现及修复

**P2：ARM64 制包入口可接受 x64 admission。** 通用连读输入校验为了兼容旧产品允许有效 x64 验收记录，ARM builder 原先未进一步限定来源。具有正确 summary/source-inventory 固定哈希的 x64 记录因此可能进入 ARM 制包，缺少该平台的原生验收前置。

`build-arm64-product.ps1` 现在显式传入 `-ExpectedTarget arm64`。共享 helper 在创建输出及编译之前，检查已固定 summary 中的 ARM scope、机器 API 观察和原生 Go 身份。未指定目标的旧 x64/历史无 scope 路径保持兼容；Go exporter 原有独立严格校验保持。

新增回归先在旧 helper 上复现失败，再验证拒绝 x64、缺失 scope、缺失或不符的原生字段，以及接受完整 ARM 记录。独立复核还发现 `ValidateSet` 与区分大小写比较不一致；现已改为不区分大小写比较，并覆盖 `ARM64`、`Arm64` 参数。中间一次 null 字段错误消息失败、修正后的 43 项结果和第一阶段 47 项结果均分别保留。随后补齐原生 Go helper 的 ARM 参数规范化及分支回归，总计 53 项；全局目标 allowlist 仍严格匹配，旧行为对大写目标原本会提前拒绝，未将它报告为实际校验绕过。

**P2：清空进程 GOFLAGS 仍可能继承持久 Go 配置中的源码 overlay。** 独立临时 GOENV 文件内设置 `GOFLAGS=-overlay=...` 后，原生 Go 在进程 GOFLAGS 为空时仍使用模块外的替换源码。标准库依赖检查与仓库原文件哈希无法发现这种替换。复现仅使用合成模块，没有改用户 Go 配置，也没有构建或安装产品。

ARM builder 现在以可恢复的进程环境作用域执行：在首次 Go 调用之前设置 `GOENV=off`、清空 GOFLAGS，并明确 `GOTOOLCHAIN=local`、`GOWORK=off`；成功或异常退出均恢复原进程值。原生架构和 admission 校验仍在创建输出及编译之前。默认 x64 构建入口不变。

回归真实执行合成模块的 `go env` / `go list`，验证外部替换源码不再被读取、临时配置字节不变、成功和前置失败后的恢复，以及不存在/空/非空三种调用方变量状态。两次中间失败均保留：先修正 Go 在 `GOENV=off` 时返回空配置文件路径的测试预期，再修正 PowerShell 将普通 `$null` 绑定为空字符串的问题；删除原先不存在的变量时现使用 `[NullString]::Value`。最终 35 项通过。新增测试所需 Go 已在安装器 CI 中按仓库现有版本固定为 1.26.4。

原 R2 包的 `build/build-inputs.json` 记录实际有效 GOFLAGS 为空，文件 SHA-256 为 `520ca8d3fdefd5a4482238b57a01969c3e99cfe4246ba58e0d219930ddf02204`。此次合成 overlay 复现没有推翻该固定包的原有来源记录，也没有重制 R2。

## 验证

| 范围 | 结果 |
| --- | --- |
| 新 ARM admission/制包前置合同，PS7 | 53 项通过；第一阶段 47 项原日志保留 |
| Go 持久配置隔离，原生 Go＋PS7 | 35 项通过 |
| ARM 构建范围及平台合同，PS7 | 21＋24 项通过 |
| 旧连读制包合同，PS5 | 21 项通过 |
| ARM64X 安装器合同，PS5 | 37 项通过；双产品调度及旧产品包校验通过 |
| 合并 main 后的原生 ARM64 touch-keyboard Go 回归 | 106 个 test/subtest 通过，1 个需显式完整语料根的用例跳过 |
| 宿主架构采集及便携包执行门禁 Python 回归 | 7＋10 项通过；被合并的 main 未改动这些文件 |
| 独立 Go independence-audit、SpeechProductExport 与平台合同复查 | 通过；仅有工具输出的部分明确标注转录，未伪称原始日志 |
| 原 R2 固定 admission 对新增前置校验 | 只读检查通过，原 summary 与 source-inventory pins 保持 |

完整日志及失败过程见[复查索引](pr78-review/evidence-index.json)，R2 只读核验见[补充索引](pr78-review/evidence-index.r2-supplement.json)，Go 配置隔离见[独立补充索引](pr78-review/goenv-isolation/evidence-index.json)。首个补充批次还误选了只供固定 AMD64 机器使用的 `test-development-scope.ps1`，它在 ARM 机器按预期拒绝；原失败保留，最终批次使用 ARM/platform 入口，不将该拒绝算作通过。安装器测试脚本在旧目录为 LF、新 worktree 为 CRLF；归档保留两者真实哈希，并确认对应 tracked blob 相同，没有把换行差异报告成功能修改。

## 包与实机结论边界

固定 R2 Release、ZIP、已安装载荷及原始 CI 记录未替换。其安装/输入结论仍绑定原实现 `0d5d7808`，不自动覆盖此次合入 main 与新增制包门禁后的源码。新前置校验通过原 R2 记录，不代表该历史 source inventory 已按当前源码重新验收；未来重制包仍须新一轮有效输入、构建和 CI。

原生 Notepad 的 8 项受控检查和两项用户实键确认已归档。registered-host 首轮仍为 8/9，失败单格两次复测通过但根因未明；候选注释显示问题仍待修。x64/x86 真实应用、重启与日用稳定性未完成，详见[包与安装记录](PACKAGE-AND-INSTALL-TEST.md)。用户已说明此前实体 Esc 是记事本取消测试造成的意外自动化停止，本轮转为 PR 冲突处理与复查。
