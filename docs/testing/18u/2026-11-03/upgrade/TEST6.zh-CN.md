# test.6 正常维护交付与执行

## 最新结果：10:21 本机卸载续行及安装通过

MYCOMPUTER 从已核实的部分卸载状态续行，正常 Uninstall 和 Install 均退出 0。
Uninstall 的 `unregister-tip`、新进程 `unregister`、`verify-absent` 全部通过，
旧目录/COM/卸载项均确认不存在后才安装。test.6 的全部 16 个载荷哈希、COM 路径、
版本卸载项、1 个 profile 和 5 个 category 已核验。
标准 YimeCore/Rime 的文件及注册、独立用户数据和默认覆盖基线完全一致。
默认输入法仍为微软拼音，没有更改默认选择。

实际通过范围为**从部分卸载状态完成正常卸载，再安装 test.6**；
不将本次扩大为完整旧 profile 尚在场时的升级实测，也不继承旧 test.2 的输入结果。
重启和 test.6 输入尚待各自验证，暂不分发其他三台。

必要原始证据已按字节纳入 [raw](raw/)，索引见 [inventory.json](raw/inventory.json)。
保留 test.5 首失败、其后新进程只读状态、test.6 现场前提、卸载/安装输出及退出码、
安装状态和保护基线。体积较大的原生 stderr 未复制，其原路径/大小/SHA-256 留在索引中。

正常重启后接续入口（只读，必须确认 boot time 晚于 10:21:49）：
`python -X utf8 C:\dev\Yime-evidence\18u-upgrade-20261103\test6\verify_after_reboot.py`。
之后对固定 test.6 的已安装入口单独验证输入；不要调用旧 test.2 手动检查脚本。

以下保留固定包身份与此前 UAC 取消历史。

源码：[5367accdb6f18bb298f2282df67d4cc6d342aa5e](https://github.com/tsaanghwang/Yime/commit/5367accdb6f18bb298f2282df67d4cc6d342aa5e)。
这是包含文件访问诊断、TIP/COM 分进程注销和 PR #95 宿主修复的完整包。

- 专用构建：[41563052934](https://github.com/tsaanghwang/Yime/actions/runs/41563052934)，通过。
- 通用构建：[41563052675](https://github.com/tsaanghwang/Yime/actions/runs/41563052675)，通过。
- 18u 契约：[41563052745](https://github.com/tsaanghwang/Yime/actions/runs/41563052745)，通过。
- 完整包：[artifact 13198347201](https://github.com/tsaanghwang/Yime/actions/runs/41563052934/artifacts/13198347201)。
- 文件：`YimeCore-18u-0.1.0-18u-test.6-windows-amd64.zip`；92,394,419 字节。
- SHA-256：`df03629e0bc1512e265beb43b80c58c7d53ada21b1ee3776b6b73bdbfeaa7282`。
- 包证据 SHA-256：`64c5996cfc3ab71ff0ffe7df54bd8ee0786d0ed0226816329cfbf37bde8c31a6`。
- installed descriptor SHA-256：`096920dfaf62178fbbf3bd049a0057237dbe360ad04bed9364f947d315392880`。

本地完整交付：`C:\dev\Yime-deliveries\18u-test6-5367accd`。
artifact 外层摘要 `5834bf583b12048c3c436a4dd36b03b3770b509f52b93a71d6acc5e08aaab002`
已匹配；内层 ZIP 与 CI 独立 receipt 一致，包成员全部一致；Action Check 通过。
旧 test.2/test.5 包与失败证据保留，未就地修改或冒充新包。

## 续行范围

用户已授权整个正常卸载/升级/重启，不需再确认。
执行器：`C:\dev\Yime-evidence\18u-upgrade-20261103\test6\maintain.py`。
只对独立 18u 执行正常 Setup Uninstall 和 Install，不传 ResetData。
续行前要求旧 test.2 marker、COM 路径仍匹配，独立新进程确认旧 TIP/profile/category 已无，
即 test.5 失败留下的已核实状态，不是盲目重复旧失败命令。
完成后核对程序载荷、维护入口、注册、标准产品及用户数据基线。

原第一次 `maintain.py` 和全部证据保持原样；test6 使用新子目录和新输出。
该目录 `maintenance-complete.json` 只代表卸载/安装完成。
正常重启后运行同目录 `verify_after_reboot.py`，只读核实启动时间、test.6 载荷/注册及保护基线，
`reboot-verified.json` 存在且内容通过才是重启核验完成。此过程不重跑旧 test.2 输入用例。

## 首次系统提权阶段（历史，后续已获准并完成维护）

10:04 发起 test.6 维护的 UAC；Windows 后来返回“操作已被用户取消”，启动器退出 1。
`maintain.py` 未启动，没有 test.6 卸载、安装或重启结果。没有自动重新弹出或绕过 UAC。
现状仍为 test.2 文件/COM 保留，原 TIP 已由第一次正常卸载移除。
`test6/elevation-attempt1.json` 保存此次结果；后续须用户确认是否重新弹出这次系统提权窗口，
这是取消后的操作衔接，不是重新要求整个维护任务授权。
