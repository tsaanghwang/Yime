# ASUS ARM64 .7 升级验证归档

2026-11-06，华硕已通过固定完整包的正常安装流程从 ARM `.5` 升级到 `.7`。安装退出码为 0，安装后 14 项只读核对及原生 `status`、`check-owned` 均通过。真实记事本已观察到自动跟随；用户确认手指、鼠标、笔均可完成本轮短文本输入，并确认浏览器可输入。本轮按已完成范围归档；完整输入、手指／笔矩阵、跨应用旧组合取消和回退验收仍未完成。笔记本上的键盘高度遮挡问题单列待处理，按用户决定暂不修改。

本记录更新本轮现场结果；此前[接续步骤](ASUS-ACCEPTANCE.zh-CN.md)中的 `NOT_RUN` 是执行前状态。完整包身份以[整合交付记录](INTEGRATED-DELIVERY.zh-CN.md)为准；本轮未安装历史 `.6`，也未使用同名候审 `.5`。

## 固定包与安装过程

| 项目 | 本轮记录 |
| --- | --- |
| 产品 | 独立 `YimeCore 18u Touch`，原生 ARM64 |
| 已安装版本 | `0.2.0-18u-arm64.7` |
| 固定源码 | `9636eaffef79d57e6eb1005101ba81a9a70f8130` |
| CI run / artifact | `42174743553` / `13483101764` |
| ZIP SHA-256 | `78f4492c561bf91d81adab5d2ddb1a07ab6bee5fcbab6416359b44bcfeb1bfc9` |
| 完整包目录 | `C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\package` |
| 安装前核对 | ZIP 及 46 个解包文件一致；原已安装 `.5` 的 20 项载荷匹配 |
| 成功安装日志 ID | `8958deed47f74d3c878e247e39cc9e6a` |
| 第二次安装时间 | 16:53:16–16:53:38（北京时间），退出码 0 |

首次尝试在 UAC 提升阶段以退出码 1 结束，系统错误文本为 `The operation was canceled by the user`。用户随后说明当时不在现场，因此不能据此推断用户主动取消。该次未进入管理员安装阶段；取消后的 10 项只读对比全部通过，旧 `.5` 载荷、校准、默认输入及已捕获的其他产品状态保持。

用户要求重新发起后，第二次使用同一固定包执行正常 `Install`，未传 `ResetData`。管理员日志记录旧 `.5` 的 20 项载荷所有权核对，以及 `unregister-tip`、`unregister`、`verify-absent`、新 `register` 完成。此次成功结果不抹去首次 UAC 未完成的记录。

## 安装后核对

安装后比对为 **14/14 通过**，覆盖以下边界：

| 核对范围 | 结果 |
| --- | --- |
| 安装身份 | `.7` 标记、固定源码、`native-arm64` 一致 |
| 文件完整性 | 39 项载荷、5 项 `.setup` 维护文件逐项匹配已验证包；实际所有权文件清单精确一致 |
| 前端迁移 | 旧 `bin/YimeTouchKeyboard.exe` 已移除，`frontend/YimeTouchKeyboard.exe` 存在 |
| 启动项 | `EnumValues` 证实旧独立18u Run 值已移除；其他两产品启动项保持 |
| 默认与其他产品 | 升级阶段的默认输入注册快照、标准 YimeCore 与 Rime/PIME 的已捕获注册及身份文件保持 |
| 用户文件 | 原用户文件保持；唯一旧校准文件仍为 425 字节且哈希一致 |

校准 SHA-256 为 `463d624053325f98146cf6458b5782ed518e377a209cb9cb3e3961ef2c7ff01b`。文件保留不代表新前端已通过物理尺寸或手指／笔验收。上述默认与用户状态结论限于升级前后已捕获的范围和时间点，不扩展为后续现场操作的永久保证。

安装后的原生只读查询均退出 0：`status` 返回 `com_registered=true`、`tip_registered=true`、`profile_count=1`、`categories_registered_count=5`；`check-owned` 返回 `owned=true`。两次查询均记录 `mutation_performed=false`，COM 路径指向安装目录的 `arm64\YimeTextService18u.dll`。

只读比对首次读取已删除的 Run 值时，`GetStringValue` 返回 1，采集停止并保留失败日志；随后使用 `EnumValues` 证明该值不存在，完整比对通过。此采集修正未执行注册写入。

前态模块扫描的“无异常”与空模块集合不能证明所有进程均可读，其 `complete` 字段不能作无占用证明。安装器对所属文件的实际访问门禁才是安装占用判断依据；原始快照保持不改。

## 已观察的真实宿主行为

本机记事本 `11.2607.14.0`，PID `26140`，已核对为原生 ARM64，并实际加载 `C:\Program Files\YimeCore 18u Touch\arm64\YimeTextService18u.dll`。其文件哈希与本次安装载荷一致。共享前端从安装目录的 `frontend` 入口运行。

在新的空白记事本页中已观察到前端自动跟随；诊断记录包含对应正文的 `auto-bound`。切换页过程也保存了短暂拒绝及后续自动绑定记录。此观察只能确认当次发现／绑定，不能代替旧候选、迟到请求或全部编辑行为的验收。

自动化工具对前端的点击出现 `focuschange`，该次未形成正文输入。该观察保留为自动化交互受限，不据此判定实体触控失败。

用户随后明确确认：手指、鼠标、笔三种方式均可输入“你好”；前端自动跟随，没有点击重连。按本轮要求输入 `ni` 后出现候选“你”，正文实际出现“你”。这是**用户确认的三种输入方式及单词／短文本初步通过**；不扩展为全键、所有编码模式、完整编辑项或完整手指／笔验收通过。

用户进一步现场确认了以下两个操作序列，证据来源为用户实际操作后的反馈：

- **F4 标签切换取消：**保留待选 `ni`，切到另一空白记事本标签后返回，旧组合已清空，两页均没有意外新增文本。本轮序列通过；迟到结果的专门注入仍未执行。
- **F5 设置往返取消与恢复：**保留待选 `ni`，进入键盘设置，返回键盘并回到正文，旧组合已清空；重新输入时自动跟随正常。本轮序列通过；诊断分支及其他暂停／恢复组合仍未执行。

浏览器方面，已在 Edge 打开本机静态 `textarea` 测试页；自动化工具不能可靠确认浏览器 URL，因此停止继续读取。此前只读文件核对得到 Edge `156.0.4314.58`、PE `AA64`；这不是运行进程架构或加载 TIP 的证明。用户随后反馈浏览器可输入。该反馈仅确认浏览器输入可用，不能推导 F3 跨应用切换时旧组合取消、无旧输入转移的完整序列通过。

| 现场项 | 当前结果 |
| --- | --- |
| F1 无手动绑定 | 新空白页自动跟随有观察；用户确认未点重连；完整适用场景待验 |
| F2 输入与编辑 | 用户确认三方式短文本及 `ni`→“你”初步通过；全模式／完整编辑项 NOT_RUN |
| F3 跨应用与旧组合取消 | 用户反馈浏览器可输入；跨应用旧组合取消完整序列仍未验证，NOT_RUN |
| F4 同窗口文档身份／迟到结果 | 同 HWND `6490118` 新空白标签自动绑定有观察；用户现场确认待选 `ni` 切页返回后旧组合清空、两页无意外新增，本轮序列通过；迟到结果专门注入 NOT_RUN |
| F5 设置／诊断暂停与恢复 | 用户现场确认待选 `ni` 经设置往返后清空，重新输入自动跟随正常，本轮序列通过；诊断分支及其他组合 NOT_RUN |
| F6 profile／只读／失焦拒写与恢复 | 完整项 NOT_RUN；仅保留本次自动化失焦观察 |
| F7 权限／会话边界 | NOT_RUN |
| F8 未知结果与失败注入 | NOT_RUN |
| 手指、笔分别验收 | 用户确认本轮短文本输入可用；完整矩阵 NOT_RUN |
| 毫米校准、旋转、跨屏、显示变化 | NOT_RUN |
| 正常卸载、重装、回退 | NOT_RUN；未自动执行 |
| 重启后使用及其他宿主／架构 | 仅增加用户确认浏览器可输入；重启、其他宿主完整矩阵及其实际架构核对 NOT_RUN |

## 待处理项 ARM7-UI-01

**键盘高度遮挡焦点光标。**用户原话：

> 浏览器能输入，只是键盘高度在笔记本上几乎完全遮挡焦点光标，影响交互。暂不处理，等等看怎么处理。

状态为**待处理，暂不修改**。记录的是本机现场可用性反馈；本轮未确定根因或解决方案。按用户决定保留当前界面，未为此修改源码或设置。此问题与“浏览器能输入”的结果分别保留，不将输入成功记为遮挡问题已解决。

## 本机证据与保留范围

本轮持久归档根固定为 `C:\Users\tsaan\Documents\Codex\2026-11-06\task\ASUS-ARM7-UPGRADE-20261106-1653`。本轮原始证据保存在其 `evidence/`，以归档根的 [index.json 校验清单](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/index.json>) 核对文件路径、大小和 SHA-256；既有 `1636` 归档继续保留。

原始用户快照只保留在华硕本机，不复制到 Git；SID、用户注册内容和完整本地文件快照不进入本记录。关键证据如下：

- [安装尝试 2 结果](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/install/attempt-2/install-result.json>) 与同目录 `8958deed47f74d3c878e247e39cc9e6a.user.log` / `.admin.log`。
- [UAC 未完成后的对比](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/after-uac-cancel/comparison.json>)。
- [14 项安装后只读对比](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/postflight/verified/comparison.json>)。
- [原生只读查询结果](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/native-registration-check/result.json>)。
- [宿主架构与已加载模块](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/live-host/process-before-profile/processes.json>)、同轮 `live-host` 下原始观察及诊断。
- [应用文件版本与架构](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/live-host/installed-app-architectures/applications.json>)，仅作已保存的文件证据。
- [用户现场反馈摘录](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/user-feedback.json>)，从本轮对话整理，单列用户确认与工具限制，不作为额外的自动采集证据。
- [不含用户快照的升级摘要](<C:/Users/tsaan/Documents/Codex/2026-11-06/task/ASUS-ARM7-UPGRADE-20261106-1653/evidence/upgrade-summary-no-user-data.json>)，SHA-256：`6fab1039627065677220f9a48dc857420914761c7fa9612fea9392d9d622629d`。

本轮以以上已执行结果和未验证边界归档。后续若处理 ARM7-UI-01 或继续验收，应记录新的执行范围与证据，不继承旧 ARM、x64、模拟输入或其他设备的结论。
