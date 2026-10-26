# Edge InPrivate 本地 textarea 真实宿主记录（任务栏最小化开发版）

每种输入方式、每个宿主独立复制本表。不得用旧 #76 包执行新增步骤，不得覆盖历史结果。

- 日期/操作者/观察者：待记录
- 版本：包目录或 ZIP 来源、源码基线及 dirty 状态、exe/manifest/ZIP SHA-256：待记录
- 本次 Check Package 结果/时间/证据路径：待记录
- 设备、Windows 版本/架构、屏幕、触控驱动、笔型号/协议：待记录
- 分辨率/缩放/显示有效宽/倾角/校准值/100 mm 与 342.90 mm 实测：待记录
- Profile：main-only，18u，100 键；实际核对：待记录
- 输入方式：手指 / 纯触控笔 / 鼠标或键盘辅助 / 笔＋手指混合（逐项注明）
- 宿主名称、版本、位数、权限、当前输入法（只观察）：待记录
- 隔离临时文档及退出不保存方式：待记录

状态：待记录／通过／失败／阻塞／不适用（说明原因）。每项注明操作前正文、逐步期望/实际正文、光标/选区、尝试次数、时间和照片/录像路径。

| 案例 | 状态 | 期望/实际、输入方式及证据 |
|---|---|---|
| P01 盘面量尺 | 待记录 | |
| P02 三模式 | 待记录 | |
| P03 确认/序号 | 待记录 | |
| P04 编辑/取消 | 待记录 | |
| P05 移出取消 | 待记录 | |
| P06 翻页/旧触点 | 待记录 | |
| P07 CN/EN/布局 | 待记录 | |
| P08 修饰键/重叠 | 待记录 | |
| P09 数字/标点 | 待记录 | |
| P10 逐键四层（附 CSV） | 待记录 | |
| P11 本地辅助移动/选区/替换/删除 | 待记录 | |
| P11 辅助移出返回/活动组合/暂停组合 | 待记录 | |
| H01 绑定前/三模式 | 通过 | 三模式输入子项通过（用户报告）：InPrivate 本地临时 textarea 绑定后变码 ni、全码 niii、简码 ni 各选“你”，确认前无原始编码，最终“你你你”。补测全新键盘进程后在本宿主不绑定点 N08/M03/空格不增字，绑定后 ni 选“你”仅增一个“你”，用户报告正常。证据：h01-edge-three-modes-user-result.json。 |
| H02 基础英文编辑 | 通过 | 用户报告：清空“你你你”，abc→退格 ab→Shift+x 得 abX；再次退格三次清空。证据：h02-edge-editing-navigation-user-result.json。 |
| H02-N1 左/右及插入 | 通过 | 用户报告：abc→左一次→x 得 abxc；选区收拢的右移亦正常。左两次/右一次的原夹具未逐步复测，不补填该过程。证据：h02-edge-editing-navigation-user-result.json。 |
| H02-N2 Home/End | 通过 | 用户报告独立插入步骤正常：原文本“你”，Home+a 后 a你，End+b 后 a你b。证据：h01-n2-n5-edge-boundaries-user-result.json。 |
| H02-N3 扩展/缩小/替换 | 通过 | 用户报告：abxc→Home→开选区→右两次/左一次选 a→y 得 ybxc。证据：h02-edge-editing-navigation-user-result.json。 |
| H02-N4 关开关保留选区/收拢/反向全选/删除 | 通过 | 用户报告：Home 开选区 End 全选，关闭开关仍选中；右移收拢，再开选区 Home 反向全选，退格清空。证据：h02-edge-editing-navigation-user-result.json。 |
| H02-N5 活动和暂停组合/失焦重绑 | 通过 | 活动/英文暂停 ni 时左右/Home/End/选区均拒绝、原码保留；Esc 后 abc→Home→x 得 xabc，用户报告正常。另次开选区抬手切 Word D 再回 Edge，重新点末尾绑定后左移不扩展选择，两处正文不变，用户报告正常。补测证据：h01-n2-n5-edge-boundaries-user-result.json。证据：h03-edge-enter-protection-user-result.json。 |
| H02 多行宿主语义（单列） | 待记录 | |
| H03 Enter | 通过 | 用户报告：英文 a/Enter/b 与 a/Shift+Enter/b 均为两行；中文 ni 的 Enter、Shift+Enter 各确认首选、不换行。具体确认文字未提供，未补填。证据：h03-edge-enter-protection-user-result.json。 |
| H04 Esc/失焦 | 通过 | 用户报告：确认“你”后 ni+Esc 保留“你”；另次 ni 抬手切 Word 再回 Edge，组合取消、两处正文不变，未重绑不写入。证据：h04-h05-edge-recovery-user-result.json。 |
| H05 帮助/最小化恢复 | 通过 | 用户报告：重绑 ni 后 Help 打开/关闭、另次最小化/任务栏恢复均取消组合、保留正文并使旧绑定失效；再次重绑确认后输入框“你你”。证据：h04-h05-edge-recovery-user-result.json。 |
| H06 跨目标重绑 | 通过 | 用户报告 Word D→Edge→Word D 依次点各自正文光标、绑定确认“你”，最终 Word D“你你”、Edge“你”，每次仅当次目标增字。证据：h06-word-edge-isolation-user-result.json。 |
| H07 自然异常恢复 | 待记录 | 未自然触发不可填通过 |

纯覆盖要求案例中的输入、绑定、定位、导航、选择、替换/删除均来自该轮手指或笔。启动和文件检查可用鼠标；测试步骤中的辅助/混合动作单列，不能算对应子项纯覆盖。鼠标、模拟消息、发送替身、内存/自有 EDIT 和 ARM64 交叉构建均不是真人结果。

结论仅针对实际完成的案例、设备和应用；未测项保留待记录。失败保留原结果及对应包身份，退出关闭临时文档且不保存正文，不清理历史包或安装状态。

本轮包：.generated/touch-taskbar-development-20261025-amd64-r1；校准参数 58.8；本地无脚本/无外部资源 textarea，在 InPrivate 中测试。Word 及预览结果均不继承为此宿主通过。
