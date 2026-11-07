# ASUS ARM64 .8 现场验收接续稿

**2026-11-06：仅文档审阅，本页现场步骤未执行。** 本轮只读核对 PR、制包回执和安装源码，未执行包内 `Check`、安装、注册、卸载、真实宿主或物理测试。下文供将来另行明确执行范围后使用，不解除 **ARM7-UI-01 键盘高度遮挡光标、暂不修改且不继续交互验收** 的现有决定。

修订基线为 [PR #113](https://github.com/tsaanghwang/Yime/pull/113) 的 `591cc4229915b0c1b481d0e61001df7d63260671`（本次核对时仍开放），它在 `ac326cba…` 后仅增加文档归档。**`.8` 构建源码仍是 `ac326cbae438fc129e2e2a493b0342a8b8dbd479`**，不能把文档 head 写入包身份；后续 PR 更新也不自动替换固定交付。

## 1. 固定候选与已验证边界

唯一候选为独立 `YimeCore 18u Touch` / `yimecore-18u` 的 **`0.2.0-18u-arm64.8`**。下载 [run 42185512418、attempt 2、Artifact 13487852082](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13487852082)，对应[制包回执 13487872109](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13487872109)；[制包 job 日志](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/job/127788030899)记录了下列固定身份。

| 对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| GitHub artifact 外层 ZIP | 191294504 | `4ba850f34fc34416ee8399805c163301fedf2623f35f9c3a107a720585582d02` |
| `YimeCore-18u-0.2.0-18u-arm64.8-windows-arm64.zip` | 191253784 | `85191b5c9926c5090ddabc5117fe7e1d43e3981527903c68f3051906cfb50a6c` |
| 内层包 `payload/installed-18u-product.json` | 7397 | `fef42e83a536f48f4c1c01f4e0a212bde38b7c3b607787fddd6e8534a556e474` |

身份按文件分别核对，不混淆安装描述符 schema 与通信协议版本：

- `product-package.json`：版本 `.8`，`format=yime-simple-package-18u-1`、`target=windows-arm64`、`host_architecture=arm64`、`tsf64_architecture=arm64`。
- `installed-18u-product.json`：`schema=installed-18u-product-v1`、`product=yimecore-18u`、`sourceCommit` 为上述完整 `ac326cba…`、`architecture=native-arm64`。CLSID `{6DFACE1F-562E-4773-A9D6-D5753A314711}`，profile `{1BD904AC-3194-4419-B70A-5574100F18B3}`。版本号在维护元数据核对，不向描述符补写字段。
- `frontend/manifest.json`：`schemaVersion=2`、同源 `sourceCommit`、`architecture=windows-arm64`、`sourceChanges=false`、`sendInputFallback=false`、`defaultMode=installed-tsf-auto-focus`；`frontendProtocol.version=2`、`pipePrefix=Yime18u.Frontend.v2.`，前端与 TIP 二进制配套。

保留既有结果，不为编写本页重复测试：

- Broker 架构入口、原生机器身份与生产资源描述符选择已修复。[原生 x64](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13486749398)与[原生 ARM64](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13486919151)各 8 项生产初始化/资源测试通过，无跳过。这不是 ASUS Broker READY、注册宿主或物理验收。
- PR 已记录最终包静态核验：46 个文件、39 项载荷、六个 ARM64 PE、源码/资源身份及前端/TIP v2 配对通过。本页引用原记录，并以 Actions 元数据和制包日志交叉确认三项哈希；未重新执行这些测试。包由 x64 CI 交叉编译，原生执行证据来自独立原生 runner。
- attempt 1 Artifact `13487322860`、源码 ZIP、x64 包、同名重制包及旧 `.6/.7` 均不能替代固定 attempt 2。固定 artifact 过期或无法取得时停止，重新确认交付，不自行换包。

## 2. 保留历史，重新确认当前 ASUS 前态

| 历史证据 | 可保留的结论 | 不能推导的结论 |
| --- | --- | --- |
| [`.5` 只读文件记录](evidence/arm7-9636eaff/installed-arm5-readonly.json)，2026-11-06 06:31:50 UTC（14:31:50 北京时间） | 当时版本 `0.2.0-18u-arm64.5`，源码 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`，描述符 `d536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be`，20 项载荷匹配 | 此后仍为 `.5`、当前无占用、注册或输入正常 |
| [后来归档的 `.7` 升级与现场结果](ASUS-UPGRADE-RESULT.zh-CN.md)，16:53:16–16:53:38 北京时间安装 | 固定 `9636eaff…` 包安装退出 0；14/14 安装后核对和原生只读注册查询通过；记事本自动跟随/短文本及 F4/F5 特定用户序列有证据 | 当前仍是 `.7`，或 `.8` 已安装/已通过；浏览器可输入不等于 F3 完整通过 |

`.7` 的已知 Broker 启动缺陷不抹去已归档观察，观察也不使 `.7` 成为已修复候选。不重跑旧轮次通过项，不把它们改成失败或 NOT_RUN；`.8` 将来所需证据另起记录，绑定 `.8` 哈希。旧执行前方案见[固定历史版本](https://github.com/tsaanghwang/Yime/blob/591cc4229915b0c1b481d0e61001df7d63260671/docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)，其中命令不再作为当前指令。

后续开始前，由 ASUS 本机重新记录时间/时区、设备名/型号和原生系统架构。历史目标为 `HUASHUONOTEBOOK` / ASUS ProArt P16 H7607BA，不因旧记录存在就视为本次已确认。只读核实实际安装根、`.yime-product.json`、`.setup` 清单/维护文件、描述符、源码、载荷、注册路径及当前产品进程/已加载 TIP。读不到的项目记为未确认；空模块集合不证明无占用。

按新观察分支，不能预填“从 `.5` 升级”：

- **仍为原 `.5`：**须匹配上述源码、描述符及 20 项载荷，并确认对应原完整包的固定身份。其旧 `installed-18u-product-v2` 描述符兼容仅用于严格维护，不放宽新包校验；同版本号的候审 `.5` 不可替代。
- **为归档 `.7`：**核实当前维护标记、描述符、载荷是否仍匹配旧固定包；不能沿用 `.5` 的 20 项检查，也不为补齐顺序重装 `.7`。
- **已为固定 `.8`：**先核实固定身份和安装文件，查找已有本轮记录；不为了执行本页而重复安装或覆盖已有结果。
- **其他版本、部分完成、混合文件或身份不明：**停止套用方案，先明确实际维护状态；不自动卸载、补注册、强行覆盖或改清单使其通过。

`.5 → .8` 和 `.7 → .8` 都按**当前旧安装自己的清单**核实所有权与全部文件，不用 `.8` 哈希要求旧文件匹配。将来 Install 的所有权/占用门禁仍需通过。同步确认本次下载/解包位置、Python 完整路径、仓库 `run_checked.py` 位置、64 位 PowerShell 5.1、日志位置和实际可用宿主。默认输入、其他两产品及校准/用户文件如需升级前后对比，须保存本轮实际采集范围；旧快照不是本轮前态，用户快照和 SID 不上传 Git。

## 3. 明确废止的旧路径、命令及恢复假设

| 旧内容 | 本轮处理 |
| --- | --- |
| `C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106\package` 及其包外 `params/check.json`、`install.json` | 仅属 `.7` 历史交付；不得用于 `.8` Check、Install 或恢复，不覆盖旧目录 |
| 旧文档写死的 Python、`C:\dev\Yime-arm64-v2-20261106` 与旧 `Setup.ps1` 命令 | 不整行复制；本机重新确认工具和 `.8` 包路径后填写下节模板。本页不指定未经确认的 `.8` 本机目录 |
| `.7` Check 已通过、旧前端/Run 已移除、校准保持 | 仅为旧结果，不代表本轮候选包或当前安装状态 |
| “用 `.7` 卸载再装原 `.5`”、保留旧包等于一键回退 | 不继承到 `.8`；根据失败阶段、实际版本和匹配维护入口另定恢复方案 |
| `.7` 有现场记录所以可作默认恢复目标 | 不成立：`.7` 有已知启动缺陷，不是新候选或默认恢复目标；正常回退尚未验收 |

## 4. 包内 Setup 的只读检查模板（本轮未执行）

未来先依次核对外层 ZIP、内层完整包和 `payload/installed-18u-product.json`，三项均须匹配第 1 节。保留原 ZIP，在本机确认的独立目录解包，不混入旧文件。包根应有 `Setup.ps1`、`Product.psm1`、`product-package.json`、`package-evidence.json` 和 `payload/`；按固定包清单逐文件核对，不只数文件。

在包根和 `payload/` **之外**的本轮专用参数目录准备 UTF-8 `check.json`，不使用共享 `.tmp` 作为交付或证据路径：

```json
{"Action":"Check"}
```

下面是待填路径模板，尖括号内容须由 ASUS 实际确认后替换，不可原样执行：

```text
"<已确认的 Python 完整路径>" "<已确认的仓库根>\tools\powershell\run_checked.py" --script "<已核验的 .8 完整包根>\Setup.ps1" --params-file "<本轮包外参数目录>\check.json" --edition ps5
```

`run_checked.py` 一次完成预检和执行，不重复同一预检。这里**不加 `--check-only`**：它仅做静态预检，不能代替实际 `Action=Check`。从 PowerShell 启动上述带引号的程序路径时使用调用运算符 `&`；该外层仅启动 Python，其他 PowerShell 工作仍走检查入口。

必须运行**下载完整包根的 `Setup.ps1`**，不是仓库 `installer/simple/Setup.ps1`，也不是安装根 `.setup/Setup.ps1`（后者仅支持 Uninstall）。包入口省略 Action 默认是 **Install**；无参数调用或双击 `Setup.cmd` 不得称为只读检查。

源码中 `Action=Check` 在包验证/主机架构检查后即返回，不进入安装/卸载分支。它不安装、不停止产品、不改注册、不启动 Broker/前端、不触发安装 UAC；会在 `%USERPROFILE%\Yime Setup Logs` 新建诊断日志，所以是对产品只读，并非零文件写入。保存退出码和本次日志。

Check 校验候选包身份/载荷、前端一致性/PE、原生 ARM64 系统及 64 位 PowerShell 条件；**不检查旧安装的所有权、占用、注册、Run 值，也不证明 Broker 原生进程门禁、READY 或输入能力**。退出 0 不替代第 2 节；非 0 即停止，不接着 Install。

## 5. 将来单独升级与安装后核验

本节没有执行授权。将来明确现场范围、完成前态和包检查后，先保存工作，正常关闭使用独立18u的正文宿主及触控前端，不强杀、不自动重启。只维护 `YimeCore 18u Touch`，不改变标准 YimeCore、Rime/PIME、默认输入和用户数据；UAC 由在场用户处理。

届时另准备包外 `install.json`，与 Check 分开执行：

```json
{"Action":"Install"}
```

```text
"<已确认的 Python 完整路径>" "<已确认的仓库根>\tools\powershell\run_checked.py" --script "<已核验的 .8 完整包根>\Setup.ps1" --params-file "<本轮包外参数目录>\install.json" --edition ps5
```

不串联自动检查后安装，不传 `ResetData`，不手填安装器管理的 `InitiatingSid`、`LogId`。保存 `.user.log` / `.admin.log`、退出码和实际阶段；UAC 未完成不等于升级通过，也不能自行推断用户主动取消。安装不是事务回滚，中途失败不保证已恢复旧版。

安装成功也**不自动启动 Broker/前端，不承诺开机常驻，不执行宿主验收**。分别记录：

1. **静态身份和全部文件：**`.yime-product.json` 与 `.setup/product-package.json` 版本为 `.8`、target 一致；安装根 `installed-18u-product.json` 匹配第 1 节哈希及身份。39 项载荷（含描述符自身，其内部清单覆盖另外 38 项）和 `.setup` 五项维护文件逐项匹配固定包/清单及实际文件集合；五项为 `Setup.ps1`、`Setup.cmd`、`Product.psm1`、`product-package.json`、`native/arm64/Yime18uProductRegistration.exe`。另核对根 `.yime-product.json`，不把它或维护文件混算为载荷。确认 `arm64/YimeTextService18u.dll`、`bin/YimeBroker18u.exe`、完整 `frontend/` 同源及 v2 配对，不用旧 `.7` 的 14/14 代填。
2. **迁移与保留边界：**若前态是旧 `.5`，确认旧 `bin/YimeTouchKeyboard.exe` 及精确匹配旧描述符的 Run 命令按正常维护移除；前态已不存在则记录保持不存在，不伪造再次迁移。Run 值通过进程外 `StdRegProv` 核实，provider 失败记为未确认；以枚举证明不存在，不以一次读值失败替代。按本轮前态对比校准/用户文件、默认输入及其他产品已捕获范围。
3. **原生注册只读查询：**后续使用已核验安装根的 `arm64/Yime18uProductRegistration.exe`，分别执行 `status` 和 `check-owned <实际安装根\arm64\YimeTextService18u.dll>`。除退出码，还应核实 `com_registered=true`、`tip_registered=true`、`profile_count=1`、`categories_registered_count=5`、`com_path` 指向该 DLL，以及 `owned=true`、`mutation_performed=false`；保存程序路径/哈希。`status` 返回 0 本身不证明注册完整；失败不自动补注册，成功不等于宿主激活。
4. **共享前端/TIP 实际连接：**获准进入现场后，从实际安装根 `frontend/Start Installed Touch Keyboard.cmd` 显式启动；通过任务栏选择独立18u profile，记录正文宿主版本/进程架构、加载 TIP 的路径/哈希、当前前端路径及 v2 会话关联。保留真实连接/拒绝诊断，不以进程存在或持久状态文件代替。该前端在自身引擎内处理组合，通过 TIP v2 写入正文，**不以 Broker READY 为 F1–F7 的启动前提**，也不以输入成功证明 Broker 链通过。
5. **独立 Broker/自有宿主阶段：**这是另行明确执行范围的安装后验收，不随前端启动自动算完成；本轮 NOT_RUN。记录实际运行的 `bin/YimeBroker18u.exe` 路径/哈希、启动方式、原生机器检查、READY/连接与对应自有宿主会话。ARM64 门禁应为 `processMachine=0`、`nativeMachine=0xaa64`；未实际观测的值不能用 PE/离线测试代填。进程存在或 `runtime-status.json` 不是就绪证明；失败停止该阶段，不能给出完整包通过结论。两条链不共享会话，见[共享前端能力边界](../../../../../prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md)；均不得混入旧二进制或其他产品资源。

安装/注册身份及共享前端/TIP 实际连接相符才进入下节；注册不符、前端断连、加载旧模块均先停止。Broker 独立阶段未执行或失败，单列保留，不能由 F1–F7 结果补齐。

## 6. 自动跟随真实宿主 F1–F7（.8 未执行）

使用可丢弃的新空白文档。首选重新核实为原生 ARM64 的记事本；其他应用逐个核实实际进程架构和加载 TIP，不能仅用磁盘 PE 推断。记录实际键序、候选、期望正文及操作后读回，不只截图“已连接”，不外推 ARM64EC、仿真、x86 或其他设备。

| 项目 | 将来操作与通过条件 | 保留的 `.7` 历史边界 | `.8` 结果 |
| --- | --- | --- | --- |
| F1 无手动绑定 | 选专用 profile 后正文点光标；自动发现当前正文，无需绑定/重连，不抢正文焦点 | 空白页自动跟随有观察，用户确认未点重连；非全场景通过 | NOT_RUN |
| F2 输入与编辑 | 在共享触控前端切换变码/全码/简码，分别记键序/候选/读回；另验 EN 小写/Shift 大写、标点、退格、选区替换、取消，无漏字/重复/意外提交 | 三方式短文本、ni→“你”有用户确认；完整模式/编辑未验 | NOT_RUN |
| F3 跨应用 | 未确认组合时切到另一已核实正文；旧组合/触点取消，新正文无旧输入，返回不重放 | 仅浏览器可输入的用户反馈，完整取消序列未验 | NOT_RUN |
| F4 同窗口文档 | 同 HWND 切文档/context，重新确认目标身份，不能沿用旧候选，两边无意外文本 | 待选 ni 切标签返回清空的用户序列通过；迟到结果注入未验 | NOT_RUN |
| F5 暂停与恢复 | 设置、诊断分别往返；暂停发现，恢复后重新发现当前会话，不恢复旧触点/组合，不自动提交 | 设置往返取消和恢复通过；诊断/其他组合未验 | NOT_RUN |
| F6 profile/只读/失焦 | 切输入法、进入只读、离开正文分别拒写，取消前端未确认组合/触点，已确认正文不变；回到可写独立18u正文重新发现 | 完整项未验；自动化 focuschange 单列 | NOT_RUN |
| F7 权限/会话边界 | 在另行明确且实际可用的低/高权限、不同会话场景记录拒绝及正文未变；不提权前端绕过边界，不为补矩阵创建新用户/会话 | 未验 | NOT_RUN |

本切片的专用 TIP 放行实体按键，中文组码须通过共享触控前端；直接用实体键盘敲 `ni` 只能得到 ASCII，不能作为 F2 中文通过证据。F4 迟到结果、延迟写锁、失败写入、F8 未知结果/回包丢失仍需单独明确的失败注入安排，不随意杀产品或宿主。切换目标不能解除“需要核对”，旧请求永不重放；`TF_S_ASYNC` 或请求已发出不代表文档写入成功，必须看实际完成及正文读回。已有离线回归只引用，不为本页重跑，也不替代现场。

## 7. 手指、笔与显示分别记录

继续保留 ARM7-UI-01 暂停决定。将来明确恢复范围后，手指和笔分别覆盖 F1–F6 适用项，逐项记录操作者、时间、工具/笔型号、模式、触点组合、期望/实际正文、误触/取消及证据。`.7` 短文本反馈保持历史结论，不能代填 `.8` 完整矩阵；鼠标、程序化触摸、受控 EDIT、自动化受限单列。

先记录分辨率、缩放/DPI、方向、有效尺寸和实际盘面 profile，观察默认适应屏幕、靠底居中、翻页键位置、任务栏避让及光标遮挡。`.8` 修复 Broker 不代表遮挡已解决；遮挡妨碍可靠操作就停止该项，不未经安排修改界面/设置。

毫米校准、100 mm 标尺、实测尺寸模式与自动适应分开记分；旧校准文件保留不代表新前端物理尺寸通过。旋转、跨屏、显示变化仅在实际设备和后续范围允许时记录旧触点/会话取消，不承接其他设备结果。未执行记 NOT_RUN，环境不可用单列原因，不虚构显示器或笔。

## 8. 失败停止与恢复条件

哈希、包/安装身份、架构、所有权或占用门禁不符，或 UAC 未完成、维护非 0、注册不符、前端断连、错误目标收到输入、未知结果未核对，均停止后续阶段。若已安排独立 Broker 检查而未就绪，停止该阶段并保留失败，不能宣称完整包验收通过。保存退出码、日志、包身份、实际正文和完成阶段；不自动重试写入，不强杀、不改权限强盖、不手工删文件/补注册，不清除校准/用户数据。必要重启先保存工作并另行明确执行。

恢复按实际阶段决定：

- **仅 Check 失败或未进入管理员安装：**先只读确认原安装是否完整，不因此运行 Uninstall；旧轮次“UAC 后状态未变”不保证本次。
- **安装中断/混合状态：**核实当前 `.setup`、载荷、注册和占用的归属，由开发端给匹配状态的正常维护方案；没有匹配入口就停在诊断，不猜版本或反复 Install。
- **固定 `.8` 安装成功后需恢复：**另行确定并批准范围，使用已核验 `.8` 完整包 `Setup.ps1` 的 `Action=Uninstall`，或确认属于当前 `.8` 的正常卸载入口；不能用旧 `.7` 维护文件处理 `.8`。正常卸载完成 profile 移除、独立 `unregister-tip`、`unregister`、`verify-absent` 及所属文件清理并核对保留边界后，才评估恢复。

恢复目标不是默认 `.7`；如拟恢复原 `.5`，重新确认其完整包、源码/描述符、可用性和已知限制，再另行确认该选择。保留包不证明回退可行，不用旧 `.5` 安装器直接覆盖 `.8` 的 `frontend/` 和新清单。全程不用 `ResetData`，所有权、占用、注销或清单失败即停止。正常卸载、重装、回退仍未验收，本页不作成功承诺。

本轮只交付文档稿。后续实际记录须绑定 `.8` 内层 SHA-256、源码、描述符、机器、时间和阶段，区分工具观察、用户反馈、自动化限制与未执行项。
