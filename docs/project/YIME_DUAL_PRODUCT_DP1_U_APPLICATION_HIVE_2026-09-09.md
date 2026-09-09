# DP1-U 私有 application hive 的类型快照与恢复

影响产品：Rime/PIME。继按句柄删除普通文件之后，本批增加真正调用 Windows 注册表
API 的快照、写入与恢复原语。对象仅为新建仓内私有 hive，未接入安装器或真实 COM、
TIP、Run、卸载项；既有 fixture journal 的合成 JSON 结果及字段不改判。

## 本批操作

三个新增源文件为 `rime-pime-dp1u-application-hive.cs`、同名 `.psm1` 和
`test-rime-pime-dp1u-application-hive.ps1`。入口只接受本仓
`.tmp/dual-product/dp1-u-app-hive-*/private.hiv`。`RegLoadAppKeyW` 创建不存在的
私有 hive，全部操作相对于返回的私有句柄；不挂载系统命名空间，不需要备份/恢复
权限，也没有可传入的系统 HKEY 或任意根 override。

- Open 创建新 hive；Existing 入口仅重开明确文件 ID、字节数和 SHA-256 匹配的
  同范围文件。源码同流校验固定哈希，原生类型使用私有随机命名空间。
- Capture 保留固定六个逻辑值的存在性、类型和原始字节；公开快照只有类型、字节数
  和哈希。只有同一上下文保留的原对象可作为快照，JSON 复制品不能替代。
- Set 在首个写入前校验完整值集合和 expected-before 快照；Restore 使用原备份的
  字节与类型恢复，仅影响固定六值，保留外来值。部分写入失败单独报告，可重新捕获
  当前状态后恢复原快照，不能把多值更新当成原子事务。
- 类型范围为 Absent、String、ExpandString、DWord、MultiString。不会展开环境
  变量、裁剪或重新编码字符串。实测 Windows 会补写某些缺失的终止符，因此非空且
  不满足终止符要求的字符串在准备/快照阶段拒绝；零字节及受支持的完整原始值才进入
  精确恢复范围。Binary、QWord 和任意历史畸形值不属于本批已支持范围。
- 写后 flush 并严格读回；Close 释放句柄，测试用 fresh process 重开核对持久化。
  `REG_PROCESS_APPKEY` 的跨进程拒绝不等于对恶意同 SID 的完整隔离。

## 保留限制

`RegLoadAppKeyW` 没有 CREATE_NEW 语义；检查不存在到加载之间不是原子创建。
Existing 的加载前哈希检查、加载后文件 ID 复核也不关闭同文件内容的全部竞争窗口。
同进程代码仍可能持有其他 hive 句柄。连续保护、原子快照、多值原子性、目录 metadata
耐久、硬件断电和恶意同 SID 物理防止都不能据此标为已验证。

本批证明私有 hive 中固定值的实际 API 行为，不证明真实 32/64 位注册视图、HKU 系统
可见性、UAC/SID 交接或完整产品回滚。DP1-U 四个实际门禁、DP1/DP2/DP3 保持未完成。
没有运行安装器或触碰已安装 local.12、正式 Rime/PIME、默认输入法及生产用户数据。

## 本批验证

同源 Windows PowerShell 5.1 与 PowerShell 7.6.5 各 **43/43 通过**。覆盖全部受支持
类型、空值及存在性恢复、外来值保留、部分写失败恢复、原引用绑定、源码租约、路径
拒绝和模块释放；fresh child 真实重开六值成功，另一进程并发加载实际返回错误 32。

| 证据（相对仓库根） | SHA-256 |
| --- | --- |
| `.tmp/dual-product/dp1-u-app-hive-test-ps5-second-2df3968b/result.json` | `c702622eceafddeadbdce9c91c032e74356e9f7c0f0788b90fbc94345135d92a` |
| `.tmp/dual-product/dp1-u-app-hive-test-ps7-final-56500dda/result.json` | `751474d28543e1d91d620335e6c639676084e3ffb91e63db9991d6475f5cd66a` |

两份结果逐项绑定三份源码；C# 为 `4cf061813ae60f3d0f6d62606d6394388e40be1f4d07c52afe2a72217968694a`，
模块为 `ba5c98736032f22236cdd0be072a58bfc39f1ba9b75ae45f955982d3f6c00d91`，测试为
`b3f0a5260dfbb129f7e8508630845c18a0d716e4606259d1b2e5c9df5b47e9c1`。
字符串终止符及 PS5 子进程 ExitCode 夹具修正前的失败记录仍保留，不替换成 PASS。
新增脚本接现有 `contract-tests` 的双 shell 步骤，没有增加长矩阵腿。
新证据保留在仓内 `.tmp`，不称为仓外归档。

API 依据：[RegLoadAppKeyW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regloadappkeyw)、
[RegQueryValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)、
[RegSetValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw)。
