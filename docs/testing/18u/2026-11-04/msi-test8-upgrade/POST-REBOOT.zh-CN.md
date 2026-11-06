# MSI：重启后已完成 test.8 正常维护

日期：2026-11-04，时间为 UTC+08:00。范围仅为独立 18u 测试产品。此前[单次卸载失败](RESULT.zh-CN.md)及[首次记事本失败](../msi-finger-notepad/RESULT.zh-CN.md)保留不变。

## 已完成

- 用户回复“已重启”后，核对系统实际启动时间为 **13:37:56.500**，晚于 13:37:28 的重启请求及上次启动；机器和交互用户与维护前一致。
- 重启后的 Restart Manager 查询覆盖 45 个安装文件，未发现占用者。随后在同一用户的管理员上下文逐文件以 `Open/ReadWrite/None` 独占打开，45/45 成功；仅打开并关闭句柄，没有写入文件内容。
- 按既定正常维护入口，经 `tools/powershell/run_checked.py --edition ps5` 与独立参数文件执行一次 `Setup.ps1 -Action Uninstall -Silent`，**13:44:54 返回 0**。TIP、COM 注销及缺席核验成功，产品目录移除。未强制结束文档宿主、Explorer 或 Codex。
- 随后单次 `Setup.ps1 -Action Install -Silent`，**13:45:09 返回 0**；新产品注册返回 `hresult=0x0`。安装标记为 **`0.1.0-18u-test.8`**。
- 39 项产品载荷逐项匹配固定完整包，5 项维护文件逐字节匹配，连同安装标记共 45 个文件。用户数据、受保护产品文件及快照列入的注册表项前后相同，包括默认输入法相关项。

固定源码为 `1060e7a787b395484cf51df47d3583b9a20bc620`；完整产品 ZIP 的 SHA-256 为 `b02c65ba6458299cc3d5e98a2aa991b886dbf41992eb3d1a6b847d93a0d58f0b`。来源、CI 和公开下载见[交付记录](../test8-development/DELIVERY.zh-CN.md)。原 test.7 ZIP 与历史证据仍保留。

## 当前停留位置

以原交互用户、非管理员身份启动匹配的已安装触屏前端，参数为 `--touch-ui --theme dark --key-sound click`。旧记事本工作文件保留在原标签页，另建“无标题”标签页，观察到 0 个字符；自动化仅点击正文放置光标。前端显示“先在正文点光标，再点绑定”，尚未绑定、组码、显示候选或向正文提交。

准备过程中的工具限制单独记录：记事本启动工具没有及时返回可操作窗口，随后重新枚举确认该窗口已打开，没有重复启动；前端启动前哈希检查因本机 PS5 未解析 `Get-FileHash` 停止，尚未启动程序，改用 .NET SHA-256 后核对成功并启动一次。上述情况不记为输入法绑定或正文提交失败。

后续只按[最小复验](../test8-development/RETEST.zh-CN.md)继续：在记事本选择独立 18u 输入法、正文放光标，显式绑定一次；成功后由用户手指在触屏前端完成一次中文组码、候选选择及正文核对。失败即停止，保留“设置→最近诊断”的 JSON，不自动重绑或补发。

本轮未重跑自有宿主验收，也未登记真人手指输入通过。Word 仍仅有旧绑定报告，中文提交未确认。约 99.5 mm 是上次运行的历史测量，本次启动未继承该校准值，也未自动调整比例。

## 证据

[安装核验摘要](installation-verification.json)和[安装阶段原始证据哈希索引](installation-evidence-index.json)固定本次结果；索引对应的原始文件留在本机 `C:\dev\Yime\.generated\installed18u-test8-msi-upgrade-r2\evidence\`，并非公开下载链接。完整安装日志包含本机身份与路径，不纳入此摘要。

关键文件为 `post-reboot-observation.json`、`admin-exclusive-access.json`、`uninstall-result.json`、`install-result.json`、`before-maintenance.json`、`after-uninstall.json`、`after-install.json` 和 `installation-verification.json`。执行入口有单次尝试标记；不得为接续输入测试重新运行维护脚本。
