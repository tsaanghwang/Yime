# ASUS 与 MSI：18u 真实应用绑定问题汇总

2026-11-05 接续：远端 main `36ca828b` 已包含 MSI test.8 重开记事本后绑定与输入成功的用户反馈。下方两机失败为 11-04 原始汇总，不能继续当作 MSI 当前状态。ASUS Broker 路径已完成[正文焦点线程源码修复与隔离验证](../../2026-11-05/arm64-binding-focus/README.zh-CN.md)，尚无新版安装或真实应用通过记录。

2026-11-04。用户最新回报：“参考尺：100mm. 还不能绑定，微星那台也不行，是不是要汇总一下？”

**ASUS 本屏 100 mm 参考线的长度检查通过，记事本绑定仍失败。MSI 也有记事本绑定失败记录，应放在同一问题下对照，但目前不能认定两机属于同一根因。** 安装及受控宿主检查通过的结论保留，真实应用手指正文输入未通过；不再把它写成单纯“等待首次实测”。

## 两机状态

| 项目 | ASUS 本机 | MSI 微星 |
| --- | --- | --- |
| 机器 | HUASHUONOTEBOOK，ASUS ProArt P16 H7607BA | WIN-JTKUT7KBVN7，Micro-Star Prestige 16 Flip AI+ C3MTG；不是 MYCOMPUTER |
| 系统架构 | ARM64 | 原生 x64/AMD64 |
| 最后核实的安装 | `0.2.0-18u-arm64.4`，来源 `6cea24bc665a4ded31e083a42bebd5d2d039832d`，20 项载荷匹配 | `0.1.0-18u-test.7`，来源 `33b7113c8b76d6c95447856c2d5cca374b542507`，39 项载荷/45 项总文件哈希匹配 |
| 参考尺 | 本次用户实测 **100 mm**；此前 57.5 mm，已保存校准 | 已有报告约 **99.5 mm**，用户认可；不是本次在 ASUS 上重新测量的结果 |
| 记事本 | 复测前核实 PID 28936、原生 ARM64、普通权限；本次用户报告仍不能绑定 | 既有报告为选择 18u 后仍不能绑定、正文空；宿主版本与实际进程架构未核实，不能从系统 x64 推定 |
| 其他真实应用 | 本批未扩展 | Word 仅报告“能绑定”，尚未确认中文正文提交；不能扩大为输入通过 |
| 软件证据 | 新版已安装 GUI→Broker→TSF 的 18/18 受控检查通过 | test.7 的 CN/variable 自有宿主单次检查通过；不能替代 Notepad/Word/手指验收 |
| 最新候选 | 当前已安装 `.4` | test.8 来源 `1060e7a787b395484cf51df47d3583b9a20bc620`，完整包已交付；现有记录明确未安装、未替换 test.7，也未运行包内宿主 |
| 本次停止点 | 绑定失败；最新消息未另报实际正文和完整错误文字 | 用户确认仍不能绑定；本次消息未补充版本或失败原文 |

表中安装/进程信息来自各自最近一次已有核验，并非本轮新采集；最新用户消息只新增 ASUS 尺量值和两机绑定反馈。本轮未重绑、重放输入、安装、启停产品或改变默认输入法。ASUS 此次只确认参考线长度，未补报整盘完整性，也不扩大为全部尺寸、触摸精度或手指输入验收。

ASUS 的[用户原文及结构化记录](../../../arm64/2026-11-04/binding-calibration/raw/user-retest-20261104.json)、[本机安装与软件结果](../../../arm64/2026-11-04/binding-calibration/README.md)、[真人复测结果](../../../arm64/2026-11-04/binding-calibration/human-retest.md)分别保留。MSI 的[机器与安装说明](raw/msi-preparation.md)、[真实应用失败](raw/msi-finger-notepad-result.md)、[test.7 安装回执](raw/msi-test7-install-result.json)、[test.8 交付边界](raw/msi-test8-delivery.md)为固定 Git blob 的逐字节副本，原提交、路径与 SHA-256 见 [manifest](raw/manifest.json)。不把 MYCOMPUTER 的历史成功转记到 MSI。

## 为什么软件通过仍会在记事本绑定失败

ASUS 的 18/18 使用受控宿主：在同一 STA 创建顶层窗口与 TSF context，设置焦点并显式激活 Windows profile，再核对实际 DLL 和正文读回。它验证了真实安装链在这些受控条件下工作，但未覆盖记事本的真实窗口/正文线程关系、用户选择输入法和手指点击绑定按钮的完整路径。

对 ASUS 已安装来源 `6cea24bc` 的只读代码核对发现：

1. GUI 绑定已有的 TIP 连接，不负责代替目标应用激活输入法。TIP 登记要求前台窗口属于本进程、顶层窗口线程等于 TIP 激活线程，并具有 TSF focus/top context。Broker 再筛选前台身份与有效连接。没有符合条件的连接不等于已证明用户未选择输入法。
2. `installedPreviewSessions.Open` 把底层错误保存在响应中，但 `preview.switchMode` 将失败统一改为“无法创建 … 预览会话”。**错误提示丢失具体原因是已确认的诊断缺口**；目前无法仅凭“不能绑定”区分激活、正文上下文、线程条件、管道或握手失败。
3. 顶层窗口与正文线程不同是需要核对的方向，尚无本次失败瞬间的线程证据，不能写成根因。MSI test.8 已包含相关焦点/线程检查调整，但未安装，且两机前端接入实现不同，不能直接把候选修复结论套给 ASUS。

对应源码：[错误保存](../../../../../go-backend/cmd/yime-touch-keyboard/installed_windows.go)、[提示泛化](../../../../../go-backend/cmd/yime-touch-keyboard/preview.go)、[TIP 前置条件](../../../../../YimeTextServiceExperiment/InstalledTouchFrontend.cpp)、[Broker 连接筛选](../../../../../go-backend/internal/touchbroker/desktop.go)、[受控宿主](../../../../../YimeTextServiceExperiment/tests/Formal18uHost.cpp)。分析基于 `6cea24bc`，不把该实现当作 MSI test.7 的二进制证明。

## 合并排查的下一步

先把“绑定失败”拆成可识别阶段并保留原始错误，再对照两机的一次失败记录。两机沿用各自固定版本，任何新包分别核对源码、交付和安装身份。

| 一次记录所需字段 | 用途 |
| --- | --- |
| 产品版本、来源、manifest；宿主 EXE/PID/创建时间/实际架构；GUI/Broker PID | 防止混用机器、包和进程 |
| 点击前后完整提示、底层原始 HRESULT/Win32/诊断原因 | 区分失败阶段，避免笼统提示掩盖原因 |
| 前台顶层 HWND/PID/TID、正文 focus HWND/PID/TID、最小化状态 | 核对顶层与正文线程、焦点条件 |
| 目标线程活动 profile、DLL 是否加载、TIP 线程及 TSF focus/top 结果 | 区分注册存在、实际激活和可编辑上下文 |
| GUI/TIP/engine 到达阶段、可用 TIP 连接数量和拒绝条件 | 定位发现、筛选或握手失败 |

现有 GUI 不能完整提供内部 TIP/连接信息，缺少的字段应记为未知，不能要求用户靠反复点击补齐。先补诊断并核对 MSI test.8 的实现差异，再安排明确的新一轮真实应用验证；当前尺标结果无需重复，前两次安装失败和所有软件通过证据保留。
