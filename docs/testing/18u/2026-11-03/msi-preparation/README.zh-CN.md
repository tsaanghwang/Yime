# MSI WIN-JTKUT7KBVN7：18u 实测准备

本页是 MSI 测试机的准备与状态入口，2026-11-04 更新。最新已记录的安装版本为 `0.1.0-18u-test.7`，源码 `33b7113c8b76d6c95447856c2d5cca374b542507`；2026-11-03 22:50 +08:00 完成一次 CN/variable 自有宿主检查，限定结论见下节。本文更新仅整理已有回传，没有重跑检查、安装或实测。

2026-11-03 早期准备阶段的安装基线为 `0.1.0-18u-test.6`，源码 `5367accdb6f18bb298f2282df67d4cc6d342aa5e`；该阶段仅做只读预检、开发准备和测试设计，未执行新安装、注册、宿主输入或物理指笔验收。下方 test.6 预检、缺口及验证记录均为历史状态，不再描述最新安装版本。

完整触控前端已随 test.7 固定交付，见[前端开发交接](FRONTEND-DEVELOPMENT.zh-CN.md)与[固定包交付](TEST7-DELIVERY.zh-CN.md)。新路线采用前端完整专用会话加 TIP 最终编辑端点；本次自有宿主检查不等于新前端到普通应用的链路已验收。

## 最新已记录状态：test.7 自有宿主单次通过

MSI 本地独立 Codex 只读审阅确认：2026-11-03 22:50:29 +08:00，当前桌面用户与安装用户一致，以非管理员身份完成一次检查；固定包与 45 个安装文件核验通过，Windows 注册 profile 实际激活、已安装 DLL 成功加载，CN/variable 的 TSF 提交为 `applied`，非空读回匹配。Runtime、宿主与 Broker 正常退出，无自动重试；默认输入法相关注册及受保护状态未变化。

复用固定提交 `ff7349be6b7ccad35b318477a0f7e0008e0efa52` 的[脱敏审阅结果](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/REVIEW.zh-CN.md)、[脱敏结果数据](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/result.sanitized.json)和[证据索引](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/evidence-index.json)。**原始报告、日志、脚本和快照留在 MSI 本机，未上传；公开摘要和索引中的哈希不代表原始证据可公开取回。** 不覆盖历史证据，不重复已通过的自有宿主检查。

该结论仅覆盖一次 CN/variable 自有宿主提交与读回；Word、Edge 等普通应用、真实触控、手指、每支笔、翻转、其它模式及日用稳定性仍未验证。延迟锁、拒写、重放和独立启动验收也不在此次结论内。注册 profile 的实际激活不改写 Runtime 的 `installedProfilePresenceVerified=false` 字段含义，详见固定审阅结果。

## 本机环境与分层状态

早期准备阶段的系统查询记录：Micro-Star International，Prestige 16 Flip AI+ C3MTG，x64，Windows 11 家庭版中文版 `10.0.26300`；当时显示 2880×1800，Intel Arc B390，显示驱动 `32.0.101.8724`。

本机 test.6 安装、重启后注册/载荷检查及 CN/variable 自有宿主结果保留为历史。test.7 结论仅取自上方本机回传；不套用 test.6 或 MYCOMPUTER 的成功，也不要求重复本机成功用例。

既有本机只读准备记录报告 200% 缩放、10 点触控、集成触摸及笔、数字化器 ready。该记录是 Windows 能力报告；当前笔电量、触点响应、物理姿态和量尺需在新的实测批次观察。此前约 70° 后仰是用户观察，系统当时仍报告 laptop/non-slate，不能写成平板模式已验。

| 层次 | 状态 | 下一步 |
|---|---|---|
| 固定 test.6 安装、预检及基础自有宿主 | 历史通过记录 | 保留；旧预检不能认证 test.7 |
| test.7 固定包及 45 个安装文件 | 22:50 检查核验通过 | 复用固定回传，不视为此后状态的持续监测 |
| test.7 CN/variable 自有宿主 | 单次提交及非空匹配读回通过 | 保留限定结论，不重跑 |
| 完整触控前端 → 安装版 TSF | 源码、CI 及固定包已交付；安装态前端链路待实测 | 按固定交付与实现边界另行安排验证 |
| Word、Edge 等普通应用输入 | 待实测 | 分别确认激活、连接、提交与正文读回，不由自有宿主代替 |
| 真实触控、手指、每支笔、翻转姿态 | 待实测 | 使用固定 test.7 分别记录，旧结果不继承 |

## 历史 test.6 只读预检（不用于 test.7）

新增入口 [prepare_msi_18u_test6.py](../../../../../tools/yimecore/prepare_msi_18u_test6.py) 只针对本机、固定 test.6。核对主机名、原生 x64、安装标记、外部固定 SHA-256 锚、15 个清单成员和清单自身、COM 路径、指定 profile 注册键，以及 Windows 显示/数字化器信号。不会启动已安装 exe、TSF 输入、注册工具或旧预览程序；唯一写入是指定的新报告文件。

以下命令仅保留为 test.6 历史用法，不是当前执行指令，不应针对已安装 test.7 运行；当时从仓库根目录运行，输出父目录须已存在，每次选择新文件名：

```text
.generated/validation-tools/python/python.exe -X utf8 tools/yimecore/prepare_msi_18u_test6.py --install-root "C:/Program Files/YimeCore 18u Touch" --output "docs/testing/18u/2026-11-03/msi-preparation/preflight-local.json"
```

报告已存在时不覆盖，不自动重试。退出 0 表示 `baselineVerified=true`；退出 2 表示基线核验失败或报告写入失败，查看 `error`。`readyForInstalledTouchAppTest` 对固定 test.6 始终为 false，这是该包的真实能力边界，不是安装损坏。不可据此重装。

本工具的注册观察是只读 HKLM 视图，不等于实时 TSF 激活；不替代已完成的重启检查，也不重新认证维护资源和安装目录额外文件。显示宽高为当前进程可见坐标，不当作物理像素或毫米尺寸。哈希用于固定包一致性，不是发布者签名。

## 历史 test.6 前端缺口与原开发清单

以下代码说明及五项清单均针对早期 test.6 准备阶段，保留原设计背景；后续实现及方案调整见[前端开发交接](FRONTEND-DEVELOPMENT.zh-CN.md)，不应据此判断 test.7 尚未携带前端。

当时代码证据：`tools/yimecore/assemble_installed_18u.py` 的载荷仅含 DLL、注册工具、检查宿主、Broker 和检查 Runtime；`cmd/yimecore-trial-runtime/main.go` 的独立构建要求 `installed-18u-check`；`YimeTextServiceExperiment/TextService.cpp` 中专用产品的 `OnKeyDown` 返回未吃键。`ConnectDedicated/ActionDedicated/PollDedicated` 要求原 TSF 线程和焦点。当时自有宿主能直接取得该接口，普通应用没有对应前端启动/接线。

因此，复制旧 `YimeTouchKeyboard.exe`、添加快捷方式、向宿主发送 Unicode 或合成按键都不能补齐安装版 TSF 链路。当时规划完成以下实现，再交付新候选包：

1. **宿主接线与认证**：前端的动作交给实际激活的专用 TIP 所在线程；设计受认证 IPC 和线程内投递。绑定真实进程/登录身份、上下文与焦点世代，不能仅信任客户端声明的 HWND/PID，不能从前端直接跨线程调用现有接口。沿用专用数据身份和独立 Broker，不接标准产品或自动 fallback。
2. **交互闭环**：把前端按键、候选点击、翻页、退格、取消及快照 revision 接入同一专用会话。未知提交结果停止，不重放；失焦、宿主退出和重绑废弃旧动作。英文、标点、编辑导航及其它两模式须逐项实现并标注支持范围，未支持的操作明确禁用。
3. **异步完成与呈现**：复用现有 DoEditSession 完成回调；排队不视为成功，候选和前端状态只接受当前会话的响应。无响应、拒绝写入及写后断连均有反例，不把发送计数当正文结果。
4. **隔离原生验证**：新建自有窗口测试完整 UI → 专用 TIP → Broker → 文本读回；覆盖错身份、过期焦点/候选、重复 UP、延迟锁、拒写、断连与退出。模拟、交叉编译及原生自有宿主结果分别报告。
5. **完整包**：新版本携带前端、匹配 DLL/Broker、资源锁、明确启动/退出入口及包外证据位置；正常启动不进入检查宿主。固定 CI 源码、ZIP/exe 哈希和签名状态，新包核验通过后才开展安装与普通应用实测。test.6 及旧实验包保持原样。

早期准备任务没有宣称上述接线已经实现，当时已安装 test.6 不具备开启下一阶段的条件。该结论仅属于旧包；test.7 开发交付和单次自有宿主结果见上方，普通应用及物理验收仍待独立记录。

## 分阶段实测清单

以下保留新候选包的分阶段实测设计；test.7 已固定交付，但本页不是新的执行指令。空白模板所有结果仍为“待实测”，准备成功或单次自有宿主通过不代填这些前端、应用和物理用例。

| ID | 前提与操作 | 观察与通过标准 |
|---|---|---|
| P00 包身份 | 记录新包源码、ZIP/exe/descriptor 哈希、模式、布局和启动入口 | 与固定交付一致；无旧包混用 |
| P01 本机校准 | 记录屏幕、缩放、姿态；用实体尺量参考线 | 记录实测毫米、参数和观察者；不套用旧 58.8 参数 |
| P02 指笔准备 | 手指及每支笔分别点按自有预览目标 | 每种方式有独立记录；笔无响应先记录设备状态 |
| P03 生命周期 | 单击、按住、移出后抬起、快速重复、最小化恢复 | 与当前交付的输入语义一致，无重复/残留 Shift；先在预览执行 |
| P04 三模式 | 每模式选固定规范来源样例；输入、翻页、选词、退格、取消 | 编码与候选来自本包对应模式；取消不提交；未支持模式记阻塞 |
| P05 CN/EN | CN 输入、EN 小写、Shift 大写、Layout 偏好、23 空键 | 语言与标点联动正确，禁用键不输出，切换不改变物理键几何 |
| P06 标点与侧区 | 使用交付中明确支持的符号和数字侧区 | 字面/编码/候选策略匹配专用方案，原始组合未被误改 |
| A00 应用前提 | 新空白不保存文档，记录应用版本/位数；用户选择独立18u并确认激活身份 | 不改系统默认输入法；确认匹配 DLL/profile，不能只看名称 |
| A01 基本输入 | 一次中文选词、一次英文输入、一次取消 | 看实际正文和光标；分别记录准确文本与次数 |
| A02 编辑 | 选区替换、退格、导航；活动组合时再操作 | 遵循本版本已实现语义，无误提交或错删；未支持项不勉强运行 |
| A03 焦点 | A 中未确认组合，切 B，再返回 A | B 无新增；未确认组合按契约取消；旧候选不能写入新上下文 |
| A04 恢复 | 正常退出前端再启动；显式恢复目标 | 不自动补发旧提交；恢复后新输入一次生效 |
| F01 姿态 | 在已校准姿态通过后，改为计划使用的翻转姿态 | 重记分辨率/缩放/系统姿态与实际姿态，重新量尺，不跨姿态继承 |

先选一个应用完成 A00–A04，再扩到 Word 与 Edge；每个应用、位数、模式、手指、每支笔分别记。鼠标/实体键盘辅助定位则标为混合，不能登记纯指/纯笔通过。触控预览、旧 SendInput 路线和新安装版 TSF 路线分开。

若出现错目标写入、重复提交、正文/读回不一致、身份不符或未知结果，停止该项与依赖项，保留首次失败及原始日志；不得为了得到通过而反复补发、重装或清理注册表。记录实际权限/焦点自动化限制，不推测成产品故障。

使用 [results-template.csv](results-template.csv) 复制到每次新批次的包外证据目录。当前模板没有任何物理或应用通过项。

## 历史 test.6 及早期准备的本机证据索引

以下仅为已完成结果定位，`.tmp` 中旧脚本不是当前执行指令：

- 重启：`C:/dev/Yime/.tmp/installed18u-test6-msi-x64-r1-postreboot-r5-20261103/postreboot-verification.json`。
- 提交读回：`C:/dev/Yime/.tmp/installed18u-test6-msi-x64-r1-host-r6-20261103/installed-host-result.json`。
- 输入后基线：`C:/dev/Yime/.tmp/installed18u-test6-msi-x64-r1-posthost-r7-20261103/posthost-verification.json`。
- 翻转准备：`C:/dev/Yime/.tmp/installed18u-msi-flip-readiness-r1-r2-20261103/raw-flip-readiness.json`。

以上为 MSI 本地历史定位，不是已上传的公开证据链接。test.7 回传使用上方固定链接，不覆盖这些历史记录。以下仅保留早期工具回归命令，本次文档修正未执行：

```text
.generated/validation-tools/python/python.exe -X utf8 -m unittest discover -s tools/yimecore -p test_prepare_msi_18u_test6.py -v
```

## 历史准备阶段验证（test.6）

- 本地 9 项离线工具回归通过：错误主机、篡改清单/载荷、错误安装标记、路径越界/重复、注册读取失败、数字化器未就绪和报告保护。成功基线不会生成实测通过结论。
- 本机只读 [preflight-local.json](preflight-local.json)：`baselineVerified=true`；15 个成员与固定清单自身匹配，COM 路径和 profile 键存在，原生 x64；触摸/笔及数字化器 ready 报告为真。完整触控应用就绪仍为 false。
- CSV 模板 13 个待实测用例，每行 27 列，未填任何通过项。
- 既有专用编译工作流新增离线工具回归；触发分支与权限不变，本轮未推送或运行远端 CI，不把本地结果写成 CI 通过。
