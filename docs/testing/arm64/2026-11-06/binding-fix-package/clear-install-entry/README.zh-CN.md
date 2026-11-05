# 更明确的本机安装入口与实际诊断

**后续入口修正：** 实际执行 CMD 时发现原 UTF-8/LF 文件解析失败，Python 未启动。已仅将行尾转为 CRLF，并按桌面快捷方式的完整命令实跑通过：开始日志和新 Python 报告均产生，无解析错误；仍因三个宿主占用而在 Install 前停止。详见 [CMD 入口实测及修复](cmd-repair/README.zh-CN.md)。下方原 `raw/entry` 和 07:29–07:30 记录是修正前的历史证据；它们的 Python 检查通过不等于原 CMD 曾通过。

2026-11-06。本目录记录对固定 `.5` 完整包新增的**本机辅助入口**，没有改变包版本、产品算法或原有安装流程。原 `Install-18u-ARM64.cmd` 及其历史证据保持原样；没有改写完整 ZIP 或 `package` 下的 1156 个文件。

固定包为 `0.2.0-18u-arm64.5`，源码 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`。ZIP SHA-256 仍为 `e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c`。本目录的本机辅助脚本不属于该固定源码包，也未将修改后的脚本冒充重新发布的产品版本。

## 新入口

交付目录：`C:\dev\Yime-deliveries\18u-binding-636cef68-20261106`。

- 用户入口：`开始安装18u修复版.cmd`。打开即追加 `18u-entry-start.log` 并显示中文状态，没有初始按键等待；结束才暂停供用户查看。入口调用固定路径的本地 Python；触摸键盘不是这个入口的检查或安装界面，成功安装后标准维护程序仍可正常启动本产品后台与键盘。
- 执行脚本：`run_18u_binding_install.py`。无参数是正常安装入口：立即创建独立日志，确认普通用户令牌，核对固定 helper / plan / installed-manifest 哈希，调用标准 `YimeMaintenance.exe -action Check`，然后只读查询已安装 18u TIP DLL 的 Restart Manager 使用者。
- 有 DLL 使用者或查询错误时，安装不启动，本产品后台也不停止。该预检只覆盖 TIP DLL；无使用者时仍由标准安装器检查全部文件，未绕过其检查。
- 只有 DLL 查询成功且无使用者，才调用标准 `YimeMaintenance.exe -action Install`；没有内部提权或 SID 参数，不终止宿主、不改默认、不请求 Restart Manager 关闭或重启应用。
- 第一次实际调用 Install 前以独占文件记录尝试。成功、失败或中断后均保留，不自动重试。仅因占用而停止的诊断不会消耗安装尝试；用户正常释放宿主后可以再次运行诊断入口。
- `--check` 明确为包校验模式：核对完整 ZIP、身份文件、1156 个展开文件及标准原生 Check，不检查用户令牌、不查询已安装宿主、不调用 Install。正常入口不重复全 ZIP 检查，阶段反馈即时显示。

源码与 CMD 的逐字节副本在 [raw/entry](raw/entry)。此处是证据副本；实际使用交付目录入口。

## 已完成的检查

北京时间 07:29:53–07:29:59，只运行了一次真实 `--check`，返回 0。固定 ZIP、身份文件、1156 个展开文件全部匹配，标准原生 Check 通过；`restartManagerQueried=false`、`installLaunched=false`。原始 [JSON](raw/check/18u-check-20261105T232953Z-5dddb2b7.json)、[阶段日志](raw/check/18u-check-20261105T232953Z-5dddb2b7.log)及[原生输出](raw/check/18u-check-20261105T232953Z-5dddb2b7-native-check.log)均保留。

随后完成五项隔离控制流验证：`--check` 不进入令牌/RM/Install；DLL 占用阻止安装；RM 错误阻止安装；Check 错误阻止 RM 和安装；首次安装失败的独占标记阻止第二次调用。测试将原生调用和 subprocess 全部替换为内存假对象，仅在新建隔离目录记录模拟结果；没有真实采样或安装。测试及模拟记录在 [raw/mock](raw/mock)。其中 `native-install` 和失败报告是**模拟控制流证据**，不是一次真实安装或产品失败。

## 实际正常入口诊断

北京时间 07:30:37–07:30:40，主代理从普通用户执行了一次无参数 Python 入口。标准 Check 通过，之后只读 RM 查询发现同一旧 DLL 仍由 Explorer `20092`、Codex `39152`、Notepad `11912` 使用，各 PID 创建标识保留在 [JSON](raw/diagnostic/18u-start-20261105T233037Z-32afd51e.json)。

结果为 `blocked-by-dll-users-install-not-started`、`exitCode=3`、`installLaunched=false`。工具外壳显示的非零结果不应标为“新版安装失败”；该入口没有进入 Install，也没有停止产品后台。[阶段日志](raw/diagnostic/18u-start-20261105T233037Z-32afd51e.log)和[原生 Check 输出](raw/diagnostic/18u-start-20261105T233037Z-32afd51e-native-check.log)已保留。

本轮没有新版安装成功、真实记事本绑定成功或中文正文提交成功的结论。安装后的版本/载荷/普通用户进程核验及真实记事本测试仍待完成；鼠标或隔离测试不替代真人手指/笔验收。此入口沿用既有安装授权，没有新增历史票据或重复许可要求。

桌面 **安装 18u ARM64 .5 修复包** 快捷方式已创建，回读确认目标为系统 `cmd.exe /d /c` 加固定中文 CMD，工作目录为本次完整交付目录，未设置以管理员身份运行或直接启动键盘。创建时未执行该快捷方式，见[回读记录](desktop/desktop-shortcut.json)和[桌面证据索引](desktop/evidence-index.json)。本目录各索引分别覆盖其列出的归档文件。
