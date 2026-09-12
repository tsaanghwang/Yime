# 给“计算机”AI：执行当前状态只读采集

> 本轮已完成，报告 `ec65e00c` 已接收并通过副本核验。不要重复执行采集；转见 [审阅与恢复安排](YIME_RIME_PIME_CURRENT_STATE_REVIEW_2026-09-12.md)，等待开发端恢复实现。

影响产品：Rime/PIME、YimeCore。已接收 `a4cb204a`、`2641668f`，4 个仓库证据副本的大小和 SHA-256 均核对通过。阶段关联是依据原文件时间和错误日志的推定：Register 前有 TIP、Register 后缺失、Remove 前后均缺失。接受这一限定结论；它没有定位具体写入者，也没有证明当前状态已恢复。

此前补证只整理旧档案，缺失的当前观察不能再用旧快照代替。本轮已提供可运行采集器，不需测试端自行编写。唯一目标事务仍为 `9fe7f28d-0889-4828-85b5-1f481431b43a`。

## 操作

拉取开发分支最新提交后，请用户在“计算机”上以原 Golde 用户，从资源管理器启动**非管理员 Windows PowerShell 5**，在当前测试仓库目录执行：

```text
python tools/powershell/run_checked.py --script tools/dual-product/collect-peer-failure-current-state.ps1 --edition ps5
```

本轮只读，无需等 CI，不安装新包、不生成授权、不恢复、不重启。若 AI 当前运行在打包应用内，不能从该上下文启动采集代替 Explorer 原生窗口。把上述命令交给用户执行；若上下文或原授权文件检查失败，原样回报错误，不绕过检查。

脚本读取原授权核对当前 SID 和 MachineGuid，通过既有 Explorer 祖先进程检查；不要求 Rime/PIME 注册为空。它只读系统 StdRegProv：控制面板 User Profile 及直接子键的名称/种类、含 Rime CLSID 的名称对应的必要字符串、固定 YimeCore COM/Profile/TIP 的存在性与用户 Enable。提供程序异常与缺失分开保存。不会调用 InstallLayoutOrTip、regsvr32、注册探针、恢复或输入设置命令。

输出位于新的 `%USERPROFILE%\Yime Rime-PIME Test Archives\current-peer-<随机ID>`，包含 current-private.json、current-redacted.json、index.json。不覆盖旧证据。输出“Collection finished”仅代表采集完成，必须检查每项 error，不能当作产品恢复成功。

## 回传

提交 current-redacted.json 的检查后副本及其大小/哈希、外部原件索引和简短结论。脚本替换 SID；提交前另检查可能出现在引用值中的用户路径或个人信息，必要时脱敏并重新计算仓库副本哈希。保留产品 GUID、完整输入法引用名称和类型，不 trim 或归一化。原授权、current-private.json 留在 Git 外。

明确报告：触发旧解析拒绝的名称候选原文；当前两视图的机器注册/用户 TIP 存在性、Enable、提供程序错误。若用户方便，在取证后物理选择当前 YimeCore，在空白记事本试输入，分别报告 YimeCore 与 Rime/PIME；没有手工测试则写未测，不阻塞 JSON 回传。不要再追溯档案中已确认不存在的逐步日志。

开发端已完成 PS5 静态检查及模拟提供程序测试（准确名称保留、不读取无关值内容、区分访问失败与缺失），未在开发机执行真实采集，也未修改任何已安装产品。当前仍不具备可验证的恢复条件，旧 defaultstring 包继续停用；收到当前状态后再制定限定恢复步骤。
