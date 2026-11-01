# PR87 固定包：ASUS ARM64 阶段结果审阅

更新：2026-11-01（UTC）。本轮只审阅已回传 JSON、核对身份并界定最小剩余范围；未执行新测试、启用事件跟踪、修代码或改包。本稿不代表新人工任务已经下发。

## r2 对照已回传（2026-11-01）

已核验结果 `6585f326c9d90bc7c6eaa1194c48ba26ff005114`：`pr87-asus-pen-hold-r2` 稳定保持、笔+手指混合翻页各一次人工样本通过，哈希/任务/固定ARM64包一致，详见[四机当前阶段汇总](FOUR_MACHINE_STAGE_SUMMARY.zh-CN.md)。实际手别未单独确认；混合不算纯笔，不推频率或MSI原因。两项已完成且停止，不再重复。下方r1历史内容保持原归属，条件退格建议仍不是当前执行任务。

## 来源与身份核对

- 结果提交 [9b1cd504e256cae2c9475e0831468c3a58398649](https://github.com/tsaanghwang/Yime/commit/9b1cd504e256cae2c9475e0831468c3a58398649) 位于 `task-results/asus-arm64`，仅新增[一份 JSON](https://github.com/tsaanghwang/Yime/blob/9b1cd504e256cae2c9475e0831468c3a58398649/results/asus-arm64/pr87-asus-arm64-r1/ae99c77c9fc62aa1b09e832a7b8c2e49be37a0fd52b89497b55bc576e70d6cf2.json)。原文 UTF-8 含结尾换行 5222 字节，SHA-256 `ae99c77c9fc62aa1b09e832a7b8c2e49be37a0fd52b89497b55bc576e70d6cf2` 与文件名相同。
- `taskID=pr87-asus-arm64-r1`、`machine=asus-arm64`、主机 `HuashuoNotebook`；与[固定 c27 队列任务](https://github.com/tsaanghwang/Yime/blob/c27d01b43e0eb337461f5c93184042282e081ae0/tasks/queue/asus-arm64/pr87-asus-arm64-r1.json)的 ID、机器、五个检查项及次序、整个 package 对象一致。按运行器去首尾空白算法复算 taskSHA256 为 `ce1f72d5dabe5a2bc7848f0fcdba45b45db84e0935c7a1fb9d370d2c5a15d45d`，匹配结果。
- 固定 ARM64 包：run `41178044364`、artifact `13033634731`、sourceCommit `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`。ZIP 98499821 字节，SHA-256 `9395e994382fe70a30c3bb9beecd57a8c074e88411f4d2b62732b8161c6ada7b`；manifest、EXE、31 负载及源身份与[固定包交付记录](ci-evidence/records/package-identities.json)一致。这不是合并后重建包，不继承 MSI、桌面或旧包结果。
- 用户另报告 runner 固定 c27、19 项自测通过；本次提交未包含其测试日志，不能由此声称云端独立复跑。结果中的静态核验与后续真人观察分层记录。

## 审阅结论与证据层次

| 项目 | 采用的阶段结论 | 限定范围 |
| --- | --- | --- |
| native-identity：pass | JSON 记录实际进程 PID 41468、固定 ARM64 EXE 路径以及 IsWow64Process2 成功：processMachine=0x0000、nativeMachine=0xaa64，支持当时该包原生 ARM64 运行 | 不是仅依据 PE 或 Node 架构推断；具体运行日志只引用本地 arm-runtime-inspection.txt，本次未取得该原件，不声称当前进程仍存在 |
| screen-calibration：pass | 本机屏幕读回 3840×2400，250%，窗口 DPI=240；用户发光区宽 344.8mm，100mm 参考线复测 100 至不足 100.5mm，无明显裁切 | 本屏独立校准；按钮外缘 341mm 不是设计边界，不据此判 18u 几何失败或修改尺寸 |
| finger-small-batch：not-run，部分覆盖 | 本机纯手指连续 ni 首选提交一次；候选移出取消；另一指翻页后旧触点无提交；顶部退格保护 ni；最小化恢复清未提交组合、保留已提交字，响应正常 | 五个候选入口未逐一命名，不记逐入口全覆盖；因聊天中途最小化导致组合取消不是连续输入故障 |
| pen-small-batch：not-run，部分覆盖 | Acer PE270XT 随附笔在 ASUS 内屏独立完成首选一次提交、移出取消、顶部组合退格保护和最小化恢复子项 | 设备操作由用户反馈；未核实程序收到的原生笔事件类型，不把实际用笔等同已证明 PT_PEN 路由，也不推定是鼠标提升路径 |
| 混合输入（独立列出） | 笔按候选、手指翻页、抬笔无旧候选误提交 | 这是笔+手指混合结果，不计为纯笔翻页覆盖；不要求为标签“纯笔”强行重做不可独立操作场景 |
| word-edge-binding：pass | 新建空白 Word 和 Edge 本地空白框：手指明确绑定后提交“你”，笔在字后重绑并追加，均成为“你你”，未替换/重复/遗漏 | 用户人工观察，无独立正文读回；仅基础绑定和首候选追加，不代表全部宿主编辑、恢复重绑或一般可靠性 |

Microsoft 的 [IsWow64Process2 参数定义](https://learn.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-iswow64process2)说明，成功时 UNKNOWN 表示目标不是 WOW64 进程，nativeMachine 描述宿主原生架构；此处结合已核对的固定 ARM64 EXE 和报告中的运行路径采用原生运行结论。未把一项返回值孤立解释为所有模块、宿主或其它程序的架构验收。

手指/笔检查项 `inputMethod=null`、`actualText=null` 是原 JSON 实际字段；实际设备、结果与混合方式由 observation 详细描述，本汇总不擅自回填原件。`not-run` 在本报告表示 schema 无 partial 状态下的未完成整项覆盖，不抹去已测子项，也不改为整体 pass。顶层 `awaiting-human`、`physicalAcceptance=false`、领取快照 `executableStarted=false` 保留不动，不误读为后续从未运行。`receivedAt` 仅为领取时间。本次仅提交 JSON，没有原始截图、运行检查全文或各真人原件；证据出处与独立核验能力据此限定。

## 剩余最小范围：先审定，不重复已测

按[四机分工](FOUR_MACHINE_TEST_ROLES.zh-CN.md)，ASUS 主责 ARM 原生适配，共性完整手指/笔矩阵主责 MyComputer 大屏。当前未发现已证实 ARM 产品缺陷，**立即新增人工测试可以为 0 项**；先由开发侧按上述已测子项登记覆盖，保留整项 not-run，而不是要求重跑首选、取消、混合翻页、恢复或 Word/Edge 追加。

若后续明确需要补足本包 ARM 上退格状态分支，则最多建议以下 **1 个定向小批**，事先给出预期，不扩成手指×笔或宿主全矩阵：

- **EN 暂停组合保护 + 无组合已确认正文退格**：仅纯预览，选一种已可用输入设备并记录。保留已确认正文“你”，输入 ni 后切 EN 暂停，点击工具栏退格；**预期：已确认正文仍为“你”，暂停 ni 不被删除/提交**。随后明确取消组合，在无组合且无选区状态点击工具栏退格一次；**预期：恰好删去一个已确认“你”，没有额外输入或重复删除**。实际正文、组合和提示逐段人工回报；任一步不符先停止、记录前后状态，不自动诊断为反弹或改代码。已测 CN 活动 ni 保护不再重复；本项不证明另一输入设备、主体 Back Space、Unicode 或宿主编辑全面通过。

其余是覆盖边界，而非本机必做任务：五入口身份明细可先查已有本地原记录，不要求重新操作凑数；原生笔事件类型未验证，只有明确原生事件路由要求或可复现设备特有问题时才讨论最小只读诊断，不在本次开启跟踪或 `--pen-recontact-ms`。完整退格/空闲键矩阵、更多宿主状态不自动追加给 ASUS。既有受控开发回归也不能替代本轮真人子项或原生笔事件证据。

## Word 笔操作帮助：仅本机经验

本报告采用用户在本机 Word 的经验提示，不宣称跨版本 Microsoft 统一规则：用笔放置文字光标前，在“绘图”中切至本机显示的“选定/选择”、退出墨迹模式；确认文字插入光标后再明确绑定。若落笔出现墨迹，停止输入并检查当前工具。其它 Word 版本的菜单名称或默认行为须另核实。固定包帮助未修改，本段不是产品帮助修复或已核验的跨版本官方指引。

原始结果、18u 基线、旧分支和其它机器证据保持原归属；无安装、注册、默认输入法、用户既有文档或固定包修改。
