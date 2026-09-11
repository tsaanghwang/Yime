# 原事务单次 Resume 再次返回 51

影响产品：Rime/PIME 失败安装回滚；现行 YimeCore 为保护对象。

## 结论

用户明确授权执行 `fd420e99` 恢复方案后，从资源管理器启动原生 PS5 入口。完整前置检查通过，生成新授权并执行**一次**原包 Resume，仍返回退出码 51。已停止，没有自动重试、重新 Install、手工清理或补写 terminal。**本次回滚未完成。**

## 固定绑定与时间顺序

- 方案提交 `fd420e99901c4031ec09c27dc433aeb65f0edf1f`，CI 34579863809 成功。
- 原事务 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`，原编译提交 `6321067de503463a71262a84239b8f5c3064f10d`。
- 固定 `-empty` 安装器 SHA-256：`0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617`；六项交付完整性检查通过。
- 原票据及原授权匹配方案固定摘要；新授权保持原产品根、原包及票据 PreparedSha256，Mode=Resume。
- 新授权运行标识 `fa4e23d2-e352-4e44-ad7c-b96162f91e67`。原授权和票据未修改。
- 前置采集：`readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-f6aa3e4970664795a9fff8f4c2e64641`。
- 执行记录：`resume-attempt-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-preflight2`，含 console.txt、原授权备份、执行参数路径和 execution-result.json。
- 执行后采集：`readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-8848c54e5746489390c27a2876951f74`。

以上目录都位于 `C:\Users\Golde\Yime Rime-PIME Test Archives`，原始字节保留在 Git 外。

## 完成判据逐项核验

| 判据 | 本次结果 |
| --- | --- |
| Resume 退出码为零 | **不满足：51**；外层记录 returned_success=false，retries=0 |
| 原安装 commit 缺失、terminal=rolled-back | commit 仍缺失；**terminal 仍缺失** |
| 原移除 commit 保留、terminal=remove-complete | remove-requested 关联仍有效；**terminal 仍缺失** |
| 191 项原计划载荷缺失 | **不满足：191 项全部仍在**，大小、哈希、文件身份匹配，前后无读取错误 |
| 注册、指定 Run/uninstall 缺失 | 前后 36 个原布局节点及指定 PIMELauncher Run 值均缺失，无读取错误 |
| 原候选进程不存在 | 前后按计划映像路径观察为空，没有同名进程路径不可读记录 |
| 完整 peer 前后比较未变 | 新授权目录一组 before/after/result，unchanged=true；原文件哈希已独立核对，前后均为 `9fbcf26fc7b557f6393b4a8ae890048e0231a708591ad66fa044cf7e5f12b447` |
| 默认输入三个字段匹配 | 前后均匹配原计划 baseline |

两个 journal 的原始决策文件、原票据、原 approval/boundary 等清单跨 Resume 前后相同，包括长度、SHA-256 和修改时间。新证据及新授权属于新增文件，不在“原件未变”结论内。不能仅凭这些结果推断执行过程中从未发生任何瞬时操作。

## 仍缺的诊断与本机入口缺陷

固定旧包没有新增诊断源码，具体控制器/隐藏 worker 异常仍未获得。前后在原 state 根及产品 logs 根范围均未找到目标日志；console.txt 保留本次外层退出码与执行顺序。不能从通用 51 猜测具体失败点，也不通过重跑补造证据。

此前第一次本机恢复入口停在只读前置检查，未生成新授权或启动 Resume：PS5 的 ConvertFrom-Json 数组又被 `@(...)` 包装，37 项被误读为 1。该本机辅助脚本缺陷已修复，PS5 验证 37 项通过、36 项拒绝。原失败目录 `resume-attempt-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0` 保留。`preflight2` 是修复后的前置流程，不是第二次 Resume；本轮实际 Resume 只有一次。

## 交回开发端

[证据索引](../../testing/platform/2026-09-11-exit51-resume/evidence-index.json) 包含外部证据路径、长度、SHA-256 和必要结论；不发布授权内容、SID、MachineGuid、用户设置或学习内容。

请根据本次仍未闭合的事务制定诊断桥接或专项恢复方案。不得直接换诊断包接管旧票据、修改固定包、删除整个目录、补造 terminal 或再次运行同一恢复入口。后续恢复与验收继续暂停，现有状态和恢复材料保留。
