# YimeCore 测试机多宿主矩阵报告

测试时间：2026-09-10 至 2026-09-11（Asia/Shanghai）。影响产品：**YimeCore**。目标机器：`计算机`，Intel Core i7-7820X，Windows x64；x86 指 WOW64 应用表面。报告分支：`perf/i7-7820x-local`。

## 结论及适用范围

四个必需真实宿主均完成三模式、每模式三轮行为测试，人工报告无异常；每个宿主均有当前已安装产品 DLL 路径和哈希证据。共覆盖 12 个“宿主 × 模式”组合，每组合三轮。人工操作结果和模块加载证据分别保存，未用自动化或合成 registered-host 结果替代人工验收。

**通过的是已安装 local.13 的本轮多宿主行为验收。完整保护对照及封存未通过，不能据此宣称 L6、公开发布或新非法码元修复的安装态验证完成。**

## 被测安装包

- 版本：`0.1.0-local.13`。
- 安装元数据源码提交：`e346a1dad76d58f50652a2dd665c64ec8aeef49e`，不是报告分支当前 HEAD。
- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-e346a1dad76d-133c91fe`。
- manifest SHA-256：`133c91fe205fcae911fa701a278465dad040e7dadce006b541697b656e50405a`。
- x64 DLL SHA-256：`32e71c5082fccb07a0041649a89401aaada65523b301ac93a67399d6cb43e1c7`。
- x86 DLL SHA-256：`d6e64406e300869582ee1324f4decaa21b37c584169cbb1c4f9eb4c47cd4f864`。

## 宿主及结果

| 宿主 | 架构 / 版本 | 等长候选数 | 省键候选数 | 变长候选数 | 行为结果 |
| --- | --- | ---: | ---: | ---: | --- |
| Windows 记事本 | x64 / 11.2607.14.0 | 7 | 9 | 5 | 三模式各三轮通过 |
| Microsoft Word | x64 / 16.0.20326.20132 | 9 | 5 | 7 | 三模式各三轮通过 |
| Mozilla Firefox | x86 / 155.0.1 | 9 | 5 | 6 | 三模式各三轮通过 |
| Notepad++ | x86 / 8.9.8.0 | 9 | 7 | 9 | 历史三模式三轮记录及本轮补测通过 |

候选数为用户报告的测试时观察值；没有固定同一编码、逐项验证菜单设置读回，不能据此推断跨应用页大小差异或设置同步缺陷。Notepad++ 数值来自 2026-09-10 历史测试，不是本轮补测重新测量。

覆盖的矩阵行为包括：空格提交、Shift 候选序号选词及标签、裸数字继续编码、前后翻页及方向键选词、失焦取消未确认组合且不自动上屏、已提交文本保护、切回恢复输入、语言栏模式切换与菜单、关闭重开后的输入恢复。记事本、Word、Firefox 还明确记录了 Esc 取消和 Backspace 删除末尾单个码元。未将不存在候选的序号按键行为推断为通过。

Notepad++ 历史逐项记录不足的项目已通过用户补测闭合：等长/省键空格提交及 Shift 标签、三模式失焦/文本保护/恢复、语言栏左键、等长/省键右键菜单、三模式重开恢复。用户在各三轮结果确认问题后回复“未见异常”。历史原始记录保持原样。

## 模块核验与取证边界

记事本实际执行映像为 WindowsApps 中的新版 Notepad，而不是将 `System32\notepad.exe` 启动入口当作执行映像。记事本及 Word 重开后均观察到新进程；Firefox 重开后也观察到加载正确 x86 DLL 的新进程。Notepad++ 补测后再次核对当前 x86 DLL。包清单与相应架构 DLL 哈希均匹配安装基线。

Firefox 使用多进程：原始全进程枚举因部分进程未加载 TIP DLL 而含 `passed=false`。该原始结果保留；单独的 assessment 说明已在实际加载 TIP 的 Firefox 进程核对路径及哈希，未把其他进程不加载 DLL 单独认定为输入法故障。DLL 加载不证明每次物理操作结果；行为通过依据用户逐批确认。

取证没有读取文档正文、窗口标题、剪贴板、命令行或学习数据，也没有执行安装、卸载、注册或默认输入法变更。已有两个 C++ 文件的本地改动不属于本报告提交范围。

## 保护对照及暂缓事项

用户说明：安装前为微软拼音和其他键盘布局，此机从未安装 PIME/Rime。该说明是用户回忆，不是注册表快照。当前本地矩阵证据没有可用的测试前注册/默认输入法快照，不能用当前 DLL 哈希或用户回忆倒推前后保护对照通过。

用户决定暂时不提供对照数据，等待开发端提出要求。因此保护对照标为 `deferred_pending_development_side_request`，不再追加本轮人工测试；四宿主行为通过保持有效，`entire_matrix_sealed=false`。未认定机器存在 PIME/Rime，也未认定发现产品保护异常。

新非法码元局部拒绝修复的源码测试是独立证据，本轮没有升级被测安装包，`new_invalid_code_fix_installed_validation=false`。后续开发端如更换 DLL/包，应按变更范围安排新的安装态验证，不能继承本报告作为新包通过证明。

## 可读取证据

- [证据索引及 SHA-256](../testing/platform/2026-09-11-multi-host-matrix/index.json)
- [最终本地汇总](../testing/platform/2026-09-11-multi-host-matrix/matrix-summary-20260911-080543.json)
- [记事本验收](../testing/platform/2026-09-11-multi-host-matrix/notepad-acceptance-20260910-224402.json)
- [Word 验收](../testing/platform/2026-09-11-multi-host-matrix/word-acceptance-20260910-235453.json)
- [Firefox 验收](../testing/platform/2026-09-11-multi-host-matrix/firefox-acceptance-20260911-074134.json)
- [Notepad++ 验收](../testing/platform/2026-09-11-multi-host-matrix/notepadpp-acceptance-20260911-080027.json)
- [用户对保护证据的处置决定](../testing/platform/2026-09-11-multi-host-matrix/protection-disposition-20260911-080543.json)
- [Notepad++ 历史矩阵](../testing/platform/2026-09-10-real-host-matrix.json)

26 份本轮本地 JSON 按原始字节导出，包括阶段性待确认结果，未覆盖或追改历史。原始 `committed=false` / `pushed=false` 字段描述当时记录状态，不表示本次报告未发布。裸文件名引用在证据目录中解析，`docs/testing/...` 引用相对于仓库根目录解析。最终判定以本报告及最后一份汇总为准，不能将较早待确认记录独立当作最终结论。
