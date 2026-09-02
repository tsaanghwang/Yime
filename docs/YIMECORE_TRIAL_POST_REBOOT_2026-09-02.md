# YimeCore 手动升级重启后核验（2026-09-02）

## 已确认的活动安装

- 用户已人工运行升级并重启；本轮没有再次安装、注销或改动生产 PIME 注册，也没有改默认输入法。
- 活动包：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-45b389e530c0-944e300e`。
- 包源码身份：`45b389e530c02d12924beeadcc5b8fd9543a3821`，构建时工作区干净。
- manifest SHA-256：`944e300e5aef44205584df34c38d7347d32cd7c3291a53b1babe1d0a801b7570`。
- 对应的实际升级构建证据是 `.tmp/yimecore-experiment/e6c/local-29572-30426/summary.json`，不是另一个同提交但 manifest 时间戳不同的 staging。
- 62 个载荷文件和 29 个 PE 通过安装态独立性审计；x64/x86 试验 COM 均指向该活动包。生产 COM 仍分别指向 `C:\Program Files (x86)\YIME\x64\PIMETextService.dll` 和 `x86\PIMETextService.dll`。
- 核验时 runtime PID `23076`、Broker PID `17156` 的实际进程路径来自新包，三模式管道探针与安装态 12 项动态整句回归通过。

## 自启动陈旧值：已修复当前值，根因未确认

首次只读复核失败：真实 HKCU Run 的 `YimeCoreExperimentalTrial` 仍为旧包
`yimecore-e6c-1059d259498a-c4c2c860\bin\YimeCoreTrialRuntime.exe -no-toolbar`（实际命令的 EXE 路径有引号）。
当前 SID 的 HKU 与 HKCU、32/64 位读取结果一致，因此不能将失败归因于只检查了错误注册表视图。

保留原值后，使用已有修复脚本只更新当前用户的试验 Run 项。多次延后只读复核通过，新 runtime SHA-256 为
`cd25a3cbcb0e8368af3906f7b68c6c70373ef24268464b8882e25463770dcfb2`。
尚未再次重启，不能据此宣布“重启后陈旧值复现”的根因已消除。

下一次正常重启后，在原 Windows 用户终端执行只读复核（不需要现在为此再次重启）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\dev\Yime\tools\yimecore\repair-e6c-trial-autostart.ps1 -ValidateOnly
```

本轮源码补强：

- 修复/只读验证输出实际值、注册表类型、修复前后快照、SID、时间与包身份；失败时也保存证据。
- E6-D 在审计前后只读核对 Run；E7 要求哈希关联的只读证据，并交叉比较活动 runtime 的预期命令。
- 升级入口在全部宿主测试后再次只读校验，失败时不再输出整体成功。
- 9 个隔离注册表契约用例在 PowerShell 7 和 Windows PowerShell 均通过；8 个 E7 证据回归通过。不为测试而改坏真实 Run 项。

这些维护脚本改动尚未重新打包安装；本轮安装态 DLL/runtime 仍是上面的 `45b389e5` 包。补强版 E6-D 是工作区脚本对该包的只读审计，证据如实标记 `git_dirty=true`，不是新的干净发布构建。

## 宿主验收边界

Word 关闭时，直接执行活动安装目录中的 x64/x86 `YimeRegisteredHostTests.exe`，两者均通过：英文 Shift 透传、语言栏回调、物理鼠标选候选、默认候选键、提交、退格恢复、方向/分页、延迟异步 edit session、失败写入恢复和停用后保留 COM 对象等回归。

新开 Word PID `19852` 时，最初未确认试验 profile 激活或试验 DLL 加载。Computer Use 的 `Alt+Space` 实际打开 Word 系统菜单；可操作窗口列表没有独立任务栏窗口，Word 可访问性返回空。已关闭系统菜单并请求用户物理选择试验输入法。

18:23:50 的后续读取首次确认 Word 已加载活动包的 `x64\YimeTextServiceExperiment.dll`，随后按键确实显示试验候选窗。DLL SHA-256 为 `fe76fb8c63b8d5c846d6718a3b2604eae5226f6bdcac9dbc15f2b650d1bf2176`。最初加载观察保留于 `word-activation-observation.json`，后续完整按键证据见 `word-key-acceptance.json`。

本次新 Word 会话已观察并保存以下证据：

- 输入 `t` 有候选，随后裸数字 `2` 形成 `t2`，没有提交第二候选；退格后恢复原候选。
- 逐键输入 `tf-cN`，候选标签保持 `⇧1` 等 Shift 序号；按 `Shift+1` 后“它们”实际写入文档且候选窗关闭。
- 单独 Shift 切英文，按 `Shift+t` 后继续输入 `h`、`e`、`y`，没有再次按 Shift，也没有回到中文组合。状态读回 `ascii_mode=true`。
- 保留原 `full_shape=true` 设置，所以保存文档第二段实际是全角 `Ｔｈｅｙ`（`FF34 FF48 FF45 FF59`），不是半角 ASCII `They`。文档 XML 与截图一致，没有为验收更改全/半角设置。

保存文档为验收目录内 `word-acceptance.docx`，附 `word-bare-digit.jpg`、`word-tf-cN-candidates.jpg`、`word-shift1-commit.jpg` 和 `word-english-shift-they.jpg`。

用户物理操作后的跟进（北京时间 18:32–18:33）已补齐真实任务栏证据，事件全部属于同一新 Word PID `19852`，且 `hresult=0`：

- 18:32:02.932、03.841、04.621、05.297 共 4 次 `left_click`，`ascii_mode` 依次为 true、false、true、false，确认左右语言状态正常切换。
- 18:32:54.259 出现 `right_click_open`，确认右键菜单打开。
- 18:33:04.669 出现 `right_click_command`，命令 `27728`（`0x6C50`，中文标点）执行成功，`ascii_punctuation=false`。这是用户的物理菜单选择，未自动恢复或覆盖该设置。

原始事件、宿主 PID、已加载 DLL 路径和哈希保存于 `word-language-bar-physical-followup.json`；此前尚未取得事件的快照不回写为通过。该项现已完成，不再列为本轮未验证事项。Computer Use 独立任务栏输入限制仍是工具能力边界，不是 Yime/Word 产品阻塞。

本轮 Word 未逐一按 `Shift+2` 至 `Shift+9`，不能将注册宿主键契约覆盖冒充逐键 Word 实测。跟进期间自启动项再次只读验证通过，仍需下一次正常重启后的复核。

## 独立化进展与仍待事项

修改源码前，在当前干净 HEAD 上用匹配的构建、安装与双档性能证据重跑 E7：“活动包不等于 staged 包”的阻塞已解除。剩余七项为签名、ARM64 真机、主流实体机、超前实体机、更广第三方宿主、实际回退演练和保留方案审批。

签名证书正在申请，等候审批，暂缓相关事项。

已准备[首版保留与回退方案草案](project/YIMECORE_INDEPENDENT_RELEASE_RETENTION_PLAN.md)，尚未审批、尚未演练，不改写 E7 外部证据中的 false 字段。

## 本地证据索引

- 原始重启后核验、修复前 Run、两种注册宿主输出与契约测试：`.tmp/yimecore-experiment/installed-acceptance/post-reboot-45b389e5/`。
- 干净 HEAD 安装态审计：`.tmp/yimecore-experiment/e6d-independence/post-reboot-45b389e5/summary.json`。
- 干净 HEAD E7 预检：`.tmp/yimecore-experiment/e7-readiness/post-reboot-45b389e5/summary.json`。
- 增加 Run 门禁后的工作区审计：`.tmp/yimecore-experiment/e6d-independence/post-reboot-autostart-guard/summary.json`。
- E7 证据回归：`.tmp/yimecore-experiment/e7-readiness/autostart-regression-10160572262c45f5adaa1184388f820e/summary.json`。
- 安装态运行探针：`%LOCALAPPDATA%\YimeCore Experimental Trial\evidence\live-runtime-verification.json`。
