# 测试机共存准备失败：StdRegProv COM 参数转换

影响产品：Rime/PIME 候选准备和维护；YimeCore 仍是保护对象。测试分支 `perf/i7-7820x-local`，本次固定候选安装器 SHA-256 `4bd0d4f3a63a97c857f422813d79f19eb8310f9ac75c1c65afd9d428f4f82c98`。

## 实际失败

测试机“计算机”从资源管理器运行准备入口。交付完整性通过（6 个 artifact），但准备阶段抛出 `System.InvalidCastException`，中文消息“指定的转换无效”。安装器未启动。

错误链：`prepare-rime-pime-coexistence-test.ps1` 第 67 行 → `Get-RimePimePeerProtectionSnapshot` → `Test-YimePimeSystemRegistryKeyExists` → `Invoke-YimePimeSystemRegistryMethod` → `Invoke-YimePimeStdRegProvMethod` 原第 214 行。

失败语句为 `$input.Properties_.Item([string]$entry.Key).Value=$entry.Value`。PS5 中直接将动态哈希表参数值赋给 COM WMI 属性出现转换失败。固定参数类型的另一条原生 registry reader 在本机通过；新增真实只读回归也在修复前复现相同异常。没有将 provider 错误降级为进程注册视图读取。

原始错误日志留在用户仓库外的 `Yime Rime-PIME Test Archives` 中，文件名 `prepare-error-2e32b81cf09a4b459167ce5f149cedc2.txt`。不提交机器身份、用户状态、approval 或恢复文件。

## 源码修复与验证

对 COM 输入边界的 `hDefKey` 显式转换为 `uint32`，`sSubKeyName`、`sValueName` 显式转换为 `string`。其他参数保留原有路径。另抑制两个 context.Add 的返回对象，确保函数输出只有 registry reply。

新增 `tools/dual-product/test-rime-pime-stdregprov-native-read.ps1` 使用真实 StdRegProv，读取 Windows 公共配置键：分别覆盖 32/64 位 provider 的 key existence 与 GetStringValue，并断言只有一个返回对象。不写注册表，不读取产品学习数据，不输出读取的值。

- 修复前：PS5 原生回归失败，`Specified cast is not valid`。
- 修复后：PS5、PS7 两种 shell 均通过 Registry32/Registry64 原生只读回归。
- 既有 PS5 registration ownership 夹具：22 checks，0 failed。
- 本地夹具路径：`.tmp/dual-product/dp1-registration-stdregprov-fix-20260911`；属于源码测试，不是安装验收。

## 下一步与限制

`rime-pime-ownership.ps1` 同时在固定候选包内；仅修改仓库准备工具不足以修复旧安装器中的维护路径。开发端须合入修复，重制候选和对应 manifest/receipt/静态核对/PIN，通过相应 CI 后重新交接。不得修改旧候选字节、旧 PIN 或绕过哈希检查，也不能用旧包继续安装。

截至本记录，修复后的完整准备流程尚未在资源管理器原生上下文重跑；候选安装、回滚、双产品保护、真实宿主和重启验收仍未执行。本次修复未停止或修改 YimeCore，未修改默认输入法或注册表。
