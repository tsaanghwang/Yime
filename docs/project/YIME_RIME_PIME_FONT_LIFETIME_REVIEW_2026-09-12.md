# 字体归属与恢复失败清查

影响产品：Rime/PIME、YimeCore；2026-09-12。本文记录清查和用户确认的设计边界，不代表旧事务恢复通过。

## 用户确认的字体边界

- 两款产品即使使用相同字体，自带副本也应分别放在各自安装目录，分别打包、升级、卸载和恢复。不得从另一产品目录加载字体，不得删除、覆盖或回滚另一产品的副本。
- 如果用户另行预装系统字体，该字体作为独立资源管理；输入法的卸载与恢复不拥有该系统副本。系统字体不是自带字体的唯一方案，也不应隐式变成另一输入法的依赖。
- 字体源文件按用户要求迁往明确的未跟踪资源目录，并固定内容校验；这与安装后两款产品各自持有副本是两个层次。当前字体仍受 Git 跟踪，迁移尚未实施。不得用另一仓库或已安装产品作为隐式构包来源。
- 文件归属不等于随时可删除：必须处理本产品私有字体的宿主加载与释放。不能为删除字体强杀宿主、修改权限或停止另一产品。

## 已确认的加载生命周期

`PIMETextService/PIMETextService.cpp` 在 TSF 对象构造时从本产品 `go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf` 调用 `AddFontResourceExW(..., FR_PRIVATE, ...)`。匹配的卸载在析构中；`onDeactivate` 只关闭客户端，不释放字体。因此后台进程停止或输入法注销不保证宿主中字体映射已经释放。

`YimeTextServiceExperiment/CandidatePopup.cpp` 独立加载其产品根目录下的 `data/fonts/YinYuan-Regular.ttf`。修复 Rime/PIME 不得卸载或删除此副本。

## 隔离复现

开发机仅复制封存候选字体到新的 `.tmp/dual-product/font-map-probe-*` 目录，在当前测试进程私有加载，使用实际 `Remove-CandidateExactFiles` 删除器。未安装系统字体，未改动注册产品。

字体 SHA-256：`d0d881aca381b7fd220ba34cc84c4ec8d2f3e6a2f72d64390507d6569bf00d0d`。

| 条件 | 状态 | 原生错误码 | 标记删除 | 已删除 |
| --- | --- | --- | --- | --- |
| 私有加载后 | preserved-error | 5 | false | false |
| 匹配释放后 | removed | 2 | true | true |

第二行的错误码 2 来自删除后路径不存在的检查，不是删除失败。[原始隔离结果](../testing/platform/2026-09-12-private-font-lifetime/result.json)与带断言的[复现脚本](../../tools/dual-product/test-rime-pime-private-font-lifetime.ps1)已保存；脚本经 checked PowerShell 5 执行通过。

复现时向脚本传入 `SourceFont`（上述候选字体的完整路径），使用 UTF-8 JSON 参数文件和 `python tools/powershell/run_checked.py --script tools/dual-product/test-rime-pime-private-font-lifetime.ps1 --edition ps5 --params-file <参数文件>`。脚本只操作新建目录中的副本，并在 finally 中释放自身私有字体。

## 测试端结论与下一步边界

[测试端报告](YIME_RIME_PIME_RECOVERY_FONT_ACCESS_DENIED_2026-09-12.md)中第一项字体同样是错误码 5，后续 184 项未尝试。本地复现确认私有字体映射足以产生完全相同的失败，源码提供了持续持有的生命周期路径；尚未识别测试端具体持有进程，也未单独排除该机 ACL 因素。

旧事务 `9fe7f28d-0889-4828-85b5-1f481431b43a` 仍未恢复，TIP 修复未到达。保持现有证据、授权和原始清单，不重新 Apply，不修改历史包中的字体条目。

后续恢复须先明确实际宿主释放方式，再验证剩余文件删除及 TIP 恢复。不能从另一进程调用字体卸载来替代原持有进程释放，也不能直接要求注销或重启后复用旧进程基线：现有保护包含 PID 和创建时间，跨会话恢复必须先处理基线有效性。

新包应实现并验证各自字体副本的正常生命周期，覆盖宿主仍存活时的停用、升级、卸载、失败恢复及另一产品继续使用字体的情况。当前回归约束中对私有字体打包的检查仍保留；若改变加载策略，应同步调整具体回归并重新构包验收。此次清查没有宣称这些维护场景已通过。
