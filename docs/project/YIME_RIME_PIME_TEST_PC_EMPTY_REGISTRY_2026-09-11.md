# 测试机重交付准备失败：空注册表枚举

影响产品：Rime/PIME 候选准备和维护，YimeCore 为保护对象。

测试机“计算机”从资源管理器运行 `-stdreg` 重交付准备入口，6 个交付文件完整性通过，随后在 peer 保护快照失败。候选安装器未启动。候选 SHA-256 为 `6301c6611edb7f1b55623be82a0f5c2c42072475fd80865eef0bf4f66a064e7b`；包含该交付的 `ae38fbee` CI 已成功，但没有覆盖本次实际空注册表枚举情形。

## 原始失败及原因

`Get-YimePimeSystemRegistryValueRecord` 原第 274 行将 `$types[$index]` 转为 int，抛出“对象不能从 DBNull 转换为其他类型”。上游为 `Get-PeerRegistryTree`、`Get-RimePimePeerProtectionSnapshot` 和准备脚本第 67 行。

空键的 StdRegProv 枚举可返回标量 DBNull/null。原来的 `@($values.sNames)` 和 `@($values.Types)` 把它们视为一个元素，空名称比较又把该元素误认作默认值，然后尝试转换 DBNull 类型。不能通过跳过整个保护键或吞掉 provider 错误修复。

原始日志保留在用户仓库外 `Yime Rime-PIME Test Archives/prepare-error-c91f9547eff44ca6921317f8ea01bb39.txt`。未提交机器身份、设置、学习或 approval。

## 修复及证据

在统一 registry method reader 中，将成功 EnumValues/EnumKey 的标量 null/DBNull 集合规范为零元素数组。真实默认值名 `''` 保留；名称/类型不配对、数组中的 null/DBNull、非法名称/类型仍拒绝，provider 错误继续失败且不回退进程注册视图。

- 新增空枚举回归：修复前 PS5 失败 `Empty key produced phantom names`；修复后 PS5/PS7 均通过。覆盖空集合、真实默认值、畸形名称/类型对和拒绝访问。
- 本机 PS5 真实只读观察：当前 YimeCore 的 HKLM TIP 树在 Registry32/Registry64 两视图递归读取通过。未输出注册值，未写注册表。该检查不代替完整原生准备上下文。
- PS5 注册所有权回归：22/22，证据 `.tmp/dual-product/dp1-registration-dbnull-20260911133131`。
- Python 来源合同回归 77/77；CI 工作流合同回归 12/12。
- 新增回归已接入 CI PS5/PS7；来源清单新增这一项后为 267 路径、含依赖 receipt 为 274 项，固定数量断言同步增加一项。
- peer 合成测试尝试被其“不能在原生验收目标运行”的守卫拒绝，未继续、未改目标身份或放宽守卫；本机不宣称该测试通过，留给合适开发/CI 环境。

## 交接

该 reader 同时打包在候选中。开发端需合入修复、完成适用回归和 CI，并重制新的固定交付。现有两个候选目录及 PIN 保持原样，不修改包或复用旧执行参数。重交付后须从资源管理器重新准备，完整 peer 文件/设置/进程保护与安装、双产品宿主、重启仍待执行。

本次没有执行安装器、注册变更、停止 YimeCore 或改变默认输入法；准备失败和历史原始证据不被新测试通过覆盖。
