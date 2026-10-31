# 本机开发测试整合报告（2026-10-31）

供开发主机 MyComputer 整合项目使用。本轮在 `codex/touch-ellipsis-choice-20261030` 汇总证据、核对交付并更新接续入口；没有新增运行时功能或扩大物理验收。依据是[批次120后的计划](../../2026-10-27/touch-screen-trial/physical-resume/NEXT_STAGE_AFTER_ELLIPSIS_120.json)：先审查剩余风险并交付当前源码／报告，下一物理批次为 null。用户本轮进一步指定以本机情况汇总汇报为主。

## 源码与近期 PR

本轮通过 GitHub 连接核对 #82、#83 均已合并；本地 `origin/main` 为 `bbf64dd85a4618c95b03980e61b7b5acab166371`。当前分支 HEAD 为 `7136cba1c9cececc339fb19da2d81e6789b14617`，`git diff 7136cba1 origin/main --stat` 无输出：两者文件树相同，无须为整合报告变更几何或移植运行代码。本地 `main` 仍停留 #82，不能据此判断远端尚未合并。

| PR | 项目进展 | 整合边界 |
|---|---|---|
| [#80](https://github.com/tsaanghwang/Yime/pull/80) | 任务栏测试夹具线程和退出清理 | 开发夹具证据 |
| [#81](https://github.com/tsaanghwang/Yime/pull/81) | ARM64 包检查及交付改进 | 保留原设备、原包记录 |
| [#82](https://github.com/tsaanghwang/Yime/pull/82) | 紧凑触屏视图、按键反馈及 ARM64 任务交接；合并 `5f98f289f9391da7460f5709f97d0d0f7aba8fdd` | 原完整100键视图保留；触屏98键另记 |
| [#83](https://github.com/tsaanghwang/Yime/pull/83) | 省略号双候选及专项测试封存；合并 `bbf64dd85a4618c95b03980e61b7b5acab166371` | 明确选择 U+2026／U+22EF 后提交，不追认新包验收 |

## 本机已记录的结果

| 证据类型 | 结果与来源 | 不能据此推出 |
|---|---|---|
| 静态／单元／离线开发检查 | [10月30日本地检查](LOCAL_VALIDATION.json)：相关 Go 六包、27项 Python、46项 JS、投影、profiles、格式与 JSON 检查通过 | 本轮重新执行通过或真人接受 |
| 模拟触摸／受控 EDIT／故障注入 | [18u阶段交接](../../../../../prototypes/touch-terminal/desktop/HANDOFF.md)保留原阶段记录，按原源码和包解释 | 实际手指／笔、任意宿主或自然故障已验证 |
| 宏碁 PE272XT 配套笔 | 省略号专项29项：Edge27、Word2 | 全键盘、纯笔光标定位、全部 Word 场景通过 |
| 手指 | 省略号专项10项，均为 Edge | 手指 Word／EN 或全部选择路径通过 |
| CI 包静态交付 | [既有交付记录](../pr83-ci-handoff/CI_DELIVERY.zh-CN.md)记录两架构下载、哈希、CRC及载荷检查 | 接收端已运行或 ARM64 原生／物理通过 |

物理两行均来自[专项阶段汇总](../../2026-10-27/touch-screen-trial/physical-resume/ELLIPSIS_CHOICE_CHECKPOINT_120.zh-CN.md)，仅绑定本地测试 exe `78ef9124a2dc18ecf0401f461531cd91c13ab16fda2c550ad46eaf063e1bf315`。105的码点正确但居中字形观察单列，不增加完整通过数。分组“正常”不补写逐动作转录、尝试次数；旧包主体、控制及候选计数不与本包相加作为覆盖率。

## 固定交付与 MyComputer 接续

CI run 为 [41018028276](https://github.com/tsaanghwang/Yime/actions/runs/41018028276)，包内 sourceCommit 为 `f01326e6c1976a4e67c9ff59693effc0e1110b1a`（PR测试合并提交），区别于 PR头和最终 main 合并。完整架构、ZIP／exe SHA-256及到期时间以[机器可读身份](../pr83-ci-handoff/package-identity.json)为准。本轮只交叉核对已有 manifest 与身份记录，没有重新下载 ZIP 或执行新包。

MyComputer 使用 [amd64 交接任务](../pr83-ci-handoff/TASK_AMD64.zh-CN.md)、[执行要求](../pr83-ci-handoff/EXECUTION_REQUIREMENTS.zh-CN.md)和[结果模板](../pr83-ci-handoff/RESULT_AMD64_TEMPLATE.json)。该目录在本轮开始时为未跟踪文件，须连同报告一并交付；仅拉取已合并 #83 不保证得到这些附件。接收端先核验身份及 B00，再按既有步骤记录 B01—B03、E01—E12、Word及可用 WOW64 宿主；模板待测不表示已经发出或完成测试。ARM64 使用独立附件与模板，不能从 x64 结果继承。

并发／混合触点、重复稳定性、手指 Word／EN及其它选择路径、微星笔 CN 余项／重复触点、ARM64 新候选包原生测试继续独立待记录。发现具体失败再回流代码修复；当前证据不要求增加新功能或直接启动下一物理批次。本报告供整合使用，未向其它聊天或人员发送消息。

## 本轮范围及验证

18u 为唯一主动基准；触屏视图保留横18u、84主体键、合计98键的既有参数，原完整100键视图及冻结17u／23u来源保留。没有更改布局、编码、校准、产品运行时、安装、默认输入法或用户数据。

本轮验证仅针对报告：PR合并身份核对、分支与远端跟踪引用文件树比较、报告相对链接及现有交付 JSON／manifest 一致性检查、`git diff --check`。当前工具进程 PATH 未找到 Go，`python` 命中 Windows Store 占位入口；没有重装工具、修改全局 PATH 或以此重跑运行时回归。10月30日通过结果保持为历史开发证据。本轮未执行 UI、模拟输入、受控 EDIT 或真实手指／笔测试。
