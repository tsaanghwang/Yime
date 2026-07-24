# 独立分段条使用与安装态验收计划

本文用于验收 Yime 自有候选窗中的鼠标组句纠错功能。该功能不监听、不修改宿主
编辑区的鼠标事件；所有点击都发生在 Yime 候选窗的“组句”分段条中。

## 1. 功能目的

用户在整句尚未上屏时，可以点击某个已识别分段，切换该段候选并局部改选，同时
保留其余未提交内容。它用于替代失败的“点击 Notepad/Codex 编辑区中的预编辑文字”
方案，避免宿主自行提交或终止 composition。

该功能不改变候选选择规则：

- 裸数字始终是组字编码。
- 候选序号仍显示为 `⇧1` 至 `⇧9`。
- 键盘降级路径仍为 `Ctrl+Left` / `Ctrl+Right`。
- 原生 Rime 会话继续拥有候选分页。

## 2. 界面语义

每个可点击单元必须同时显示预览汉字和对应编码，例如：

```text
组句  [幅  bjjj] [幅  bjjj]
```

实际预览汉字受候选排序和用户学习影响，不要求固定为“幅”；验收重点是两个
`bjjj` 分段各自都有对应汉字，而不是显示一条连续的 `bjjjbjjj`。

把第一段改选为“逼”后，分段条应保持稳定映射并更新为类似：

```text
组句  [逼  bjjj] [幅  bjjj]
```

当前活动段使用候选窗高亮色。显示文字不是 Rime cursor；点击请求使用该段保存的
原始 `{start, end}` 编码范围。

## 3. 安装前提

另一项正在运行的任务结束前，不安装、不停止 PIME、不重启 Windows。可以先完成
源码测试、构建和安装包校验。

准备安装态验收时：

1. 记录安装包的生成时间和 SHA-256。
2. 运行标准安装流程。
3. 重启 Windows，确保被宿主锁定的 x86/x64 TSF DLL 已替换。
4. 使用 `tools/verify-installed-runtime.ps1` 核对安装文件、注册表和运行进程。
5. 不以源码目录中的 DLL 或 `server.exe` 代替安装态验证。

## 4. x64 基本场景

先在 Notepad 中测试：

1. 切换到音元输入法。
2. 输入 `bjjjbjjj`，不要提交。
3. 确认候选窗顶部出现两个“汉字 + `bjjj`”分段单元。
4. 点击第一段。
5. 确认候选列表切换为第一段候选，宿主 composition 仍存在，没有文字提前上屏。
6. 用鼠标点击候选或按对应的 `Shift+1` 至 `Shift+9`，把第一段改为另一个候选。
7. 确认第一段汉字更新、第一段编码仍为 `bjjj`，第二段没有丢失。
8. 点击第二段，再点击第一段，确认可以在未提交整句时切换目标段。
9. 最后按正常流程提交整句，只允许此时整体上屏。

然后在 Codex IDE 中重复同一流程。Codex IDE 不需要、也不应发送宿主编辑区
composition 点击回调；候选窗分段条应独立工作。

## 5. x86 与降级场景

- 在 `C:\Windows\SysWOW64\charmap.exe` 的文本框中重复基本场景，验证 x86 DLL。
- 在 UI-less 宿主中，如果宿主要求自行绘制候选 UI，Yime 自有分段条可以不显示；
  此时必须保留 `Ctrl+Left` / `Ctrl+Right` 键盘改选，不得伪造一个不可点击的分段条。
- 多显示器或高 DPI 下，分段条与候选列表必须位于同一无激活弹窗内，不得抢走宿主
  焦点；超出工作区时应沿用候选窗现有的屏幕边界约束。

## 6. 失败判据

出现下列任一情况即判定安装态验收失败：

- “组句”后只有连续编码，没有每段对应汉字。
- 汉字存在，但点击使用汉字下标导致候选段错位。
- 点击第一段后有文字立即上屏，或 composition 下划线消失。
- 第二次点击结束 composition。
- 点击分段条误选了下方候选。
- 改选前段后，后段丢失、编码错配或整句立即提交。
- Notepad 可用而 Codex IDE 直接结束 composition。
- x64 可用但 SysWOW64 的真实 x86 宿主不可用。

## 7. 日志与证据

验收记录至少保存：

- 安装包、已安装 `server.exe`、x86/x64 DLL 的时间与 SHA-256。
- Notepad、Codex IDE、SysWOW64 charmap 的结果。
- 输入编码、分段条显示、点击目标、改选结果和最终提交结果。
- `%LOCALAPPDATA%\PIME\Logs\go_backend.log` 中对应的
  `selectCompositionSegment` 请求及响应。
- 若宿主退出或输入法失活，保存 TSF/应用事件和 CodeIntegrity 路径信息。

不得把 Smart App Control 针对未签名开发版 `server.exe` 的审计记录直接当作
Yime 崩溃；必须先核对事件中的实际文件路径。

### 安装态证据报告

完成 Notepad、Codex IDE 或 SysWOW64 charmap 的人工操作后，在仓库根目录运行：

```powershell
.\tools\capture-sentence-segment-evidence.ps1 -RequireComplete
```

脚本只读取安装目录、进程列表和
`%LOCALAPPDATA%\PIME\Logs\go_backend.log`；不会安装、停止、启动或重载 PIME。
唯一写入内容是 `.tmp\sentence-segment-evidence` 下带时间戳的 Markdown 报告。
报告包括：

- 已安装 `server.exe`、x86/x64 `PIMETextService.dll` 的时间、大小和 SHA-256，
  以及它们与当前仓库构建产物的哈希比对；
- `PIMELauncher` 和 `server` 的 PID、可执行文件路径及启动时间快照；
- 日志末尾的 `selectCompositionSegment` 请求，以及按 `client` 和 `seqNum`
  关联的响应。

`-RequireComplete` 会在安装文件缺失、构建产物缺失或哈希不一致时返回失败，但仍会
先保存报告。若日志很长，可通过 `-LogTailLines` 增大扫描范围；报告默认最多保留最近
50 组 RPC，可通过 `-MaxRpcTransactions` 调整。SysWOW64 charmap 验收完成后应立即
运行一次并把报告路径记入本节验收记录。

## 8. 2026-07-24 当前验收记录

本轮已完成标准安装、Windows 重启和安装产物核对：

- `server.exe`：`DCF55375093D16929FA22C8B53A28E292BF7754827A2E8E8EFECAAA2D54B1D99`
- x86 `PIMETextService.dll`：`EEAEFD1F052C706F169961D3698C42B218715914683C9B24F5A3CFFE65CB373B`
- x64 `PIMETextService.dll`：`648FC1D328075D4C4C1BF031B29092D144F9383B275FC1BE2CFF96D8DB0BF666`

三项均与对应构建产物一致。Notepad、Codex IDE 已完成初步试用，用户确认功能
暂时可见且“有点用”。由于该交互需要持续使用才能评价，本轮状态为“已安装，
进入观察期”，尚不宣告完整产品验收通过。

后续观察重点：

- 第一段、中间段、末段能否反复切换；
- 定位失败时 composition 与候选是否保持；
- 改选后后续分段和编码映射是否保持；
- 最终整句是否只在明确选择或提交时上屏；
- `C:\Windows\SysWOW64\charmap.exe` 的真实 x86 路径。
