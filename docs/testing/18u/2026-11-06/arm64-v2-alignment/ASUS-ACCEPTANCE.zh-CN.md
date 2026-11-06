# ASUS ARM64 .7 现场接续步骤

**本轮结果已归档：**华硕已从原 `.5` 正常升级到固定 `.7`，部分记事本现场项目通过，浏览器可输入为用户反馈；完整结果与未验证范围见[本轮升级与验证记录](ASUS-UPGRADE-RESULT.zh-CN.md)。键盘高度遮挡光标列为 ARM7-UI-01 待处理，按用户要求暂不修改、不继续交互验收。本页保留执行前方案，以下 `NOT_RUN` 表格及命令不是当前结果或新的执行指令，不要求重复已通过步骤。

执行前状态（历史）：**接续方案准备完成，以下现场项目均为 NOT_RUN**。接续版本为 ARM `.7`，源码固定为 `9636eaffef79d57e6eb1005101ba81a9a70f8130`；只使用[整合交付记录](INTEGRATED-DELIVERY.zh-CN.md)指定的完整包、artifact 和 SHA-256。方案编写时华硕 `.5` 尚未升级；`.6` 保留为历史未安装包，不作为本次安装或回退维护入口。其他同名候选包及 x64 包不代替 `.7`。包检查结果与现场验收分开记录；下方 `Check` 命令的列出不代表其执行结果。

## 正常维护与安装核对

1. 确认设备仍为 `HUASHUONOTEBOOK` / ASUS ProArt P16 H7607BA、原生 ARM64。记录当前 `.5` 的源码及安装 descriptor 哈希；保留原完整交付、失败历史、校准和用户数据，不把候审 `.5` 认作当前安装。
2. 核对最终 ZIP 与解包文件，先按下方命令执行 `Check`。检查通过后，保存工作并正常关闭使用独立18u的正文窗口、触控前端，再明确执行 `Install` 升级；不得强杀文档宿主。运行的是**最终完整包内的 `Setup.ps1`**，不是仓库 `installer/simple/Setup.ps1`。`Setup.ps1` 默认就是 Install，不能把无参数调用或双击 `Setup.cmd` 当只读检查。UAC 交互由用户完成。
3. 只维护 `YimeCore 18u Touch`，不改变标准 YimeCore、Rime/PIME、默认输入或用户数据。失败停止并保存日志，不改权限强行覆盖、不自动补注册、不删除异常现场。
4. 安装后核验 `.setup`、39 项产品载荷、`native-arm64`、`arm64/YimeTextService18u.dll`、`frontend/` 与同源 v2 标记。确认旧 `bin/YimeTouchKeyboard.exe` 和精确匹配的旧 Run 值按正常维护移除。校准文件保留；新前端从 `frontend/Start Installed Touch Keyboard.cmd` 显式启动，无开机常驻承诺。
5. 通过任务栏明确选择独立18u profile；记录实际激活/加载的新 DLL。进程存在、静态文件正确或输入指示器外观不能单独证明当前宿主已经激活新 TIP。若需重启，保存工作后另行执行，不自动重启。

### 分开执行包检查与升级

本次 `.7` 持久交付目录中的完整包根为 `C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\package`，其中应同时包含 `Setup.ps1`、`Product.psm1`、`product-package.json` 和 `payload/`。保留 ZIP 和目录结构，不混入其他版本。仓库 `C:\dev\Yime-arm64-v2-20261106` 只提供 `run_checked.py` 检查入口，不作为待安装包。

在包根**之外**的 `C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\params` 中准备两个 UTF-8 JSON 文件；该目录用于保存本次操作参数，不使用共享 `.tmp`，也不向 `package/` 或 `payload/` 添加文件。

`check.json`：

```json
{"Action":"Check"}
```

先执行产品只读检查。它核验包文件及原生系统架构，不安装、不停止产品、不更改注册；会新增安装器诊断日志。此命令不带 `--check-only`，因为需要实际执行 `Action=Check` 的包校验，不能用语法预检代替它。

```powershell
& "C:\Users\tsaan\AppData\Roaming\uv\python\cpython-3.15-windows-aarch64-none\python.exe" "C:\dev\Yime-arm64-v2-20261106\tools\powershell\run_checked.py" --script "C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\package\Setup.ps1" --params-file "C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\params\check.json" --edition ps5
```

确认 `Check` 返回 0 后，再准备 `install.json`：

```json
{"Action":"Install"}
```

完成上文保存工作、正常关闭宿主的步骤后，单独执行正常升级；不把两条命令串联为自动检查后安装。仅提供完整参数名 `Action`，不传 `ResetData`，不手填由安装器管理的 `InitiatingSid` 或 `LogId`。

```powershell
& "C:\Users\tsaan\AppData\Roaming\uv\python\cpython-3.15-windows-aarch64-none\python.exe" "C:\dev\Yime-arm64-v2-20261106\tools\powershell\run_checked.py" --script "C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\package\Setup.ps1" --params-file "C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\params\install.json" --edition ps5
```

以上 Python 路径是本轮已验证入口；若路径已变化，先确认可用的 Python 完整路径再替换，不跳过 PowerShell 检查入口。记录命令退出码，保留 `%USERPROFILE%\Yime Setup Logs` 下本次 `.user.log` / `.admin.log`；失败即停止，不把部分完成记成升级通过。

### 回退安排（未验证，不自动执行）

正常回退尚未在本机验证。保留旧完整包不等于已经具备通过验收的一键回退；不要用旧 `.5` 安装器直接覆盖 `.7` 的 `frontend/` 及新清单。

如需回退，先保存本次日志和失败现场，再另行安排：使用**本次 `.7` 完整包自身的 `Setup.ps1`**，以包外 UTF-8 JSON `{"Action":"Uninstall"}` 经上述检查入口执行正常卸载；也可使用 `.7` 成功安装后注册的正常卸载入口。卸载成功并核对结果后，才按原交付说明安装第 1 步确认的**原已安装 `.5` 对应完整包**。同名候审 `.5` 不能替代它。整个顺序不使用 `ResetData`，保留校准及用户数据；任何所有权、占用、注销或清单检查失败均停止，由开发端处理，不手工删文件或补注册。

## 先观察真实宿主自动跟随

在可丢弃的新空白文档中执行。首选本机原生 ARM64 记事本；其他应用逐个记录名称、版本和实际架构，不由此外推 ARM64EC、仿真或 x86。

| 项目 | 操作与预期 | 结果 |
| --- | --- | --- |
| F1 无手动绑定 | 选择专用 profile 后在正文点光标；前端自动显示当前正文可输入，不需点绑定，不抢正文焦点 | NOT_RUN |
| F2 输入与编辑 | 分别记录三种编码模式的实际按键、所选候选及正文读回；另测 EN 小写/Shift 大写、标点、退格、选区替换和取消 | NOT_RUN |
| F3 跨应用 | 有未确认组合时切到另一原生正文；旧组合/触点取消，新正文不收到旧输入 | NOT_RUN |
| F4 同窗口文档 | 同 HWND 下切换文档/context；必须重新确认目标身份，不能沿用旧候选或迟到结果 | NOT_RUN |
| F5 暂停与恢复 | 打开设置/诊断时暂停自动发现；关闭后发现新会话，不恢复旧触点或自动提交 | NOT_RUN |
| F6 profile/只读/失焦 | 切换输入法、只读控件或离开正文时拒写；恢复可写独立18u正文后重新发现 | NOT_RUN |
| F7 权限边界 | 低/高权限和不同会话分别记录拒绝行为；不通过提权前端规避边界 | NOT_RUN |
| F8 未知结果 | 只有在明确的失败注入安排下执行；切换目标不能解除“需要核对”，核对后只接受新输入，旧请求永不重放 | NOT_RUN |

F8 不通过随意杀产品/宿主制造故障；延迟写锁、失败写入和回包丢失须按各自隔离测试及现场安排记录。源码/内存测试不能代填此表。

## 分开记录手指、笔与显示

每种输入工具单独执行 F1–F6 的适用项，记录操作者、时间、笔型号、模式、触点组合、期望/实际文本及误触或取消。鼠标、程序化触摸和受控 EDIT 结果单列，不提升为手指/笔通过。

记录屏幕分辨率、DPI、方向、有效尺寸和 profile。先验默认适应屏幕、靠底居中、翻页键位置与任务栏避让，再进入毫米校准测100 mm标尺。旋转/跨屏/显示变化应取消旧触点与会话；实测尺寸模式和自动适应分开评分。旧 `.5` 校准文件保留不等于新前端物理结果通过。

每项保留原始成功/失败；未执行继续填 NOT_RUN，自动化受限单列，不能归因成产品故障。所有报告绑定最终包 SHA-256，不继承 x64 test.11/test.12、旧 ARM 或其他设备的结论。
