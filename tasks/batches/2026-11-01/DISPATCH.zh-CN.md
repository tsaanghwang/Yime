# 2026-11-01 四机接续派发

用户已要求安排并开始；此处的“派发”指发布可审阅任务数据/人工提示，**不表示已在电脑执行**。不自动运行watch/产品，不更新可信runner、不配置服务。每台由用户把相应提示交给本机Codex，再明确单次领取/执行；首次失败即停，不自动重试或改网络设置。

## 任务矩阵

| 机器 | 本批任务 | 已就绪与边界 |
| --- | --- | --- |
| ASUS ARM64 | [pr87-asus-pen-hold-r2](../../queue/asus-arm64/pr87-asus-pen-hold-r2.json)：保持→混合翻页，2项 | 可用原c27可信runner领取，匹配固定ARM64包；专门对照，不重复其它已通过项 |
| MSI x64 FLIP | [pr87-msi-host-posture-r2](../../queue/msi-x64/pr87-msi-host-posture-r2.json)：Word基础绑定、Edge基础绑定、Word恢复重绑，最多3项 | 当前已记录姿态，鼠标或手指选一种；不用笔，保持/翻页暂停。空白专用文档，不改既有文件；被阻止的本地URL不绕过 |
| “计算机”x64普通屏 | [pr87-desktop-perf-intake-r2](../../queue/desktop-x64/pr87-desktop-perf-intake-r2.json)：只读条件表+有界测量可行性，2项 | 只准备性能基线；不启动产品/自测/benchmark，不设通过阈值、不重复鼠标；X86系不等于32位系统 |
| MyComputer + Acer PE270XT | 下方人工准备单，最多3项 | **无可运行队列、无假定架构/包、无配置修改**。身份/包/校准未核实前不做笔实验，后续经核实才另发新ID |

专项：[PEN-HOLD-20261101](PEN-HOLD-20261101.zh-CN.md)。已确认的[四机职责](../../../docs/testing/touch-keyboard/2026-10-31/candidate-readability/FOUR_MACHINE_TEST_ROLES.zh-CN.md)不变。原三机r1、原包和全部结果保留；r2按各自任务ID独立追加。

## 三台已入组电脑的共同接续方法

复制各行任务ID及本文件固定提交链接交给相应本机Codex：

> 只处理上述本机新任务。先读取固定发布提交中的任务JSON，核对任务ID/机器/预期/停止条件。使用已经固定到c27d01b43e0eb337461f5c93184042282e081ae0的可信runner和现有本机local.json，执行一次 `node <可信runner路径> once <现有local.json路径>`；不要从队列更新/执行runner源码。once会获取队列、验证包并写本地领取记录，不会运行产品；可能同时列出旧r1已领取，不能重跑旧任务。若新任务不是awaiting-human、身份/包不匹配或出现错误即停。现有获准的临时代理如必需只沿用原进程作用域，不改全局配置、不输出凭据；未配置可用访问则报告阻断。领取成功后仅执行对应JSON中限定步骤，异常即停。结果先本地审阅，保留receipt不可变字段和physicalAcceptance=false，不自动push。报告新taskID、实际领取queueCommit/taskSHA、固定包身份、完成/blocked/not-run、前后实际观察和本地证据位置；不上传未审阅trace/截图或无关个人信息。

注意领取的是配置分支**当前头**，可能晚于本文件发布提交；以实际receipt记录为准，核对新任务原文与本次固定提交一致。不伪写queueCommit=c27（c27是可信runner版本，不是本批队列提交）。发现同ID正文变化即停。不能照抄其它机器local.json。旧r1记录不存在时一次领取可能为它创建静态记录，这仍不授权执行旧人工任务。

### 结果语义

ASUS/MSI实际人工pass/fail需真实反馈、humanEvidence=true及实际inputMethod；混合输入在observation明确注明。未测保持not-run、前提不具备blocked。桌面准备项只读自动收集但无人审核时保持not-run/humanEvidence=false并写摘要；由本机人员审核后可用observation记“准备资料审核通过”，但不能称性能测试通过。任何任务总physicalAcceptance=false，不能改初次static verification为后续运行证明。输出如包含人工正文观察而无独立读回须明示。结果远端发布需另经审阅确认，此批不自动publish --confirm。

## MyComputer 人工准备单（不使用其它机队列）

> 只做只读准备，不启动Yime、不下载包、不安装、不创建runner配置、不运行once/watch、不改设置。
> 1. 核对实际主机名、OS版本、CPU型号与OS原生架构，并记录“用户确认外接Acer PE270XT”，区分用户确认与本机读回。不采集序列号、账号目录或凭据；无法确定架构就标未知。预期得到可选择正确原生包的事实，不预设amd64。
> 2. 仅查看已经在本地的固定PR87包manifest/已有哈希记录，列明是否存在、run/artifact/source/架构是否匹配，不运行EXE；期望对应源12a9930ce4e84b5c7de35fb2816c201b1e72e8af及已发布匹配架构artifact。缺包或不匹配就not-ready，禁止自动下载旧/新替代包；此步资料核对不是完整负载验证。
> 3. 查看本屏已有校准记录与实际可用Acer随附笔资料，注明是否足够；没有已验证UI则不要求现场量尺，不复制MSI58或ASUS344.8mm。预期区分已有可靠本屏记录/待准备，保留未知。不执行专项两步。回报这3项和阻断，由开发侧据真实身份再准备后续包/配置/任务。

## 开发与领取边界

原runner只验证固定数据与包，不执行任务指令；本次未新增机器注册逻辑或自动性能程序。已有 `--check-package` 是无窗口资源/会话正确性检查，不是输入延迟/吞吐基准；桌面如未来提出有限耗时采样，必须写明冷/热定义、次数、超时与解释限制，另行确认后再运行。原生/仿真、人工/自动、性能测量/验收结论均不可混用。无需为派发清理旧工作区、改默认输入法或安装/注册任何东西。
