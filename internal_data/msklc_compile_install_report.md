# MSKLC Compile And Install Report

日期：2026-04-08

归档说明：这是一份历史调查记录，用来保存当时那台机器上的 MSKLC 编译、GUI 打包与安装试验现象。

它不应再作为当前键盘布局发布链的操作手册。当前有效入口应以：

- `docs/MSKLC_RELEASE_QUICKSTART.md`
- `docs/REBUILD_KEYBOARD.md`
- `docs/windows-klc-workflow.md`
- 外部 `Yime-keyboard-layout` 仓库

为准。

## 数据库与查表

- 默认视图：`vw_klc_layout_observation`
- 全量视图：`vw_klc_layout_observation_all`
- 当前状态：默认视图显示标准 48 键，自动排除 `DECIMAL`
- 验证结果：
  - `vw_klc_layout_observation` = 48 行
  - `vw_klc_layout_observation_all` = 49 行
  - `DECIMAL` 仅存在于全量视图

## 可视化对照表

- 文件：`internal_data/klc_layout_visual_table.md`
- 来源：`internal_data/manual_key_layout.resolved.json`
- 内容：
  - base 四排表
  - shift 四排表
  - 首音单表
  - 乐音单表

## 本机工具状态

- 已安装：`Microsoft Keyboard Layout Creator 1.4`
- 主程序：`C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe`
- 编译器：`C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\bin\i386\kbdutool.exe`
- 打包相关库：`C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\bin\i386\KbdMsi.dll`
- 本地帮助文件：`C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\msklc.chm`

命令行能力结论：

- `kbdutool.exe` 提供的命令行参数只覆盖 `x86/IA64/AMD64/WOW64` 编译与源文件生成，不包含 setup/package/install 参数。
- `MSKLC.exe` 表现为 GUI 程序，未确认到可稳定调用的命令行打包入口；当前调查中它不会像 `kbdutool.exe -?` 那样返回 CLI 帮助文本。

## 本机架构

- CPU：`13th Gen Intel(R) Core(TM) i9-13900K`
- OS Architecture：`X64`
- Process Architecture：`X64`
- 当前终端是否管理员：`False`

## 编译验证结果

### canonical SPUA-B 版结论

对直接使用 `internal_data/key_to_symbol.json` 的 canonical SPUA-B 版 `yinyuan.klc`：

- `kbdutool.exe -n -v -u -m yinyuan.klc`
- 退出码：`1`
- 主要现象：大量 `Warning 1015`
- 关键报错：
  - `Warning 1001`: `The 'KBD' keyword appeared multiple times.`
  - `Error 2009`: `Unable to read keyboard name or description.`

根因判断：

- canonical 版 `LAYOUT` 段使用 `U+100000` 起的 SPUA-B 码点，即 `1000xx` 形式的 6 位 token。
- `kbdutool` 对这些 token 的兼容性不足，会把它们错误地卷入重复检测，因此 canonical 版不能直接作为 Windows 试装 KLC 编译输入。

### BMP 试装投影版结论

现已把 KLC 试装链切到：

- `internal_data/bmp_pua_trial_projection.json`
- `tools/generate_klc_from_manual_layout.py --symbol-mode bmp-trial`（默认即 `bmp-trial`）

对当前 BMP 投影版重新执行：

- `kbdutool.exe -n -v -u -m yinyuan.klc`

结果：

- 退出码：`0`
- 旧的 `Warning 1015` / `Error 2009` 已不再出现
- 先前持续出现的 `Error 2028: A ligature entry found without an actual LIGATURE table.` 已解决

### MSKLC GUI verify 额外限制

在 `MSKLC.exe` 的 GUI 流程里继续执行 `Build DLL and Setup Package` 时，发现它的 verify 逻辑比 `kbdutool` 更保守：

- 纯 PUA 输出布局会被它误判为“除了空格和小键盘小数点外没有定义任何键位”
- 它还会额外要求 `VK_DECIMAL` 必须显式定义

为通过 GUI verify，当前生成器额外加入了两条仅用于 Windows GUI 打包兼容的规则：

- 给空闲键 `6/base` 注入一个 ASCII canary：`0061`
- 强制把 `DECIMAL` 行定义为 ASCII 句点：`002E`

这两条兼容位已固化到 `tools/generate_klc_from_manual_layout.py` 中，因此后续重新生成 `yinyuan.klc` 时不会丢失。

说明：

- 这两条规则的目标是骗过 `MSKLC.exe` 的 GUI verify 阶段
- 它们不改变 canonical SPUA-B 运行时编码层，只影响 Windows 试装用的 GUI 编译投影层

本次为了让 `kbdutool` 接受文件，除了切换到 BMP PUA 投影外，还同时修正了几项 KLC 结构问题：

- 生成器改为默认输出 BMP PUA 码位，而非 canonical SPUA-B 码位
- UTF-16 输出改为稳定的 `CRLF` 写法，避免双空行
- `KEYNAME` / `KEYNAME_EXT` / `DESCRIPTIONS` / `LANGUAGENAMES` 尾部区段恢复为旧版可接受模板
- 旧版 `LIGATURE` 表被保留为编译兼容层

### 关于当前 DLL 产物

- 本轮成功编译后，工作区根目录下的 `Yinyuan.dll` 已刷新为最新时间戳
- 随后通过 `MSKLC.exe -> Build DLL and Setup Package` 成功生成了完整 GUI 打包产物，原始输出位置为：`C:\Users\Freeman Golden\OneDrive\文档\yinyuan`
- 当前已整理并同步到仓库内：
  - `releases/msklc-package/`
  - `releases/msklc-amd64/Yinyuan.dll`
  - `releases/msklc-wow64/Yinyuan.dll`

GUI 打包输出包括：

- `setup.exe`
- `Yinyuan_amd64.msi`
- `Yinyuan_i386.msi`
- `Yinyuan_ia64.msi`
- `amd64/Yinyuan.dll`
- `i386/Yinyuan.dll`
- `ia64/Yinyuan.dll`
- `wow64/Yinyuan.dll`

### 当前结论

- canonical SPUA-B 版仍不适合作为 Windows 试装编译输入
- BMP PUA 投影版现在已经可以通过 `kbdutool` 编译
- 因此“Windows 试装链”与“canonical 运行时编码”应继续保持两层分离：
  - 运行时编码：canonical SPUA-B
  - Windows 试装编译：BMP PUA 投影版

## 安装结论

这次会话里已经完成 GUI 打包，并且对系统级安装失败原因做了进一步定位。

当前状态：

1. `MSKLC.exe` 的 `Build DLL and Setup Package` 已成功输出 setup / MSI / 多架构 DLL。

1. 管理员安装实测中，MSKLC 生成的 MSI 在这台机器上持续失败，错误模式稳定为：

- `MSI 2755`
- `unexpected error 110`
- 服务端在缓存 `C:\Windows\Installer\*.msi` 阶段失败

1. 这个失败模式已经在多个路径下复现：

- 原始 OneDrive 工作区路径
- `%TEMP%` 本地转存路径
- `%ProgramData%` 整包本地转存路径

1. 因此当前最可信的结论是：这台机器上的 Windows Installer 对 MSKLC 生成包存在稳定失败，不应继续把“修复 MSI”作为唯一安装路径。

补充事实：

- 当前 `releases/msklc-package/` 已保存完整 GUI 打包产物。
- 当前 `releases/msklc-amd64/` 与 `releases/msklc-wow64/` 已同步为这次 GUI 打包输出对应版本。
- 当前已补充一个手工安装回退路径：
  - `releases/msklc-package/install-amd64-manual.cmd`
  - `releases/msklc-package/install-amd64-manual.ps1`
- 该回退路径直接复制 `amd64/wow64` DLL 到系统目录并注册 `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts`，绕过 MSI。

当前最可信的下一步候选是：

1. 优先尝试 `releases/msklc-package/install-amd64-manual.cmd`，确认手工注册路径是否能让布局出现在当前用户输入法列表中。
2. 如果手工安装成功，立即试打 BMP 投影字形和键位是否符合预期。
3. 如果布局已注册但未立即显示，先注销并重新登录，再确认输入法列表。
