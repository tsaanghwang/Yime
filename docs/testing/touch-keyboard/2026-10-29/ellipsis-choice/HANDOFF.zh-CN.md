# 省略号双候选版本地交接（2026-10-29）

2026-10-30交付接续：[当前交付及完整阶段结果](../../2026-10-30/ellipsis-choice/HANDOFF.zh-CN.md)。宏碁笔29项、手指10项已分别完成本阶段测试；以下101待测与本地启动描述保留为2026-10-29历史状态。


用户确认顿号/破折号第100组正常，破折号无需改动，只处理省略号输入。中点3次显示`…`U+2026、`⋯`U+22EF；6次显示`……`、`⋯⋯`，明确选后提交。已有中文组合/字典页保留，临时符号候选完成后恢复。

可点候选、主区1/2选择，Space/Enter明确确认第一项；其它主区文字/导航/编辑不代选。退格更新暂存/候选，取消/切换语言/失焦丢弃，side literal旁路独立。最多6次待选；4/5次选择完整组后保留余下1/2次。

[开发结果](DEVELOPMENT_RESULT.json)、[包身份](package-identity.json)和[源文件哈希](SOURCE_SNAPSHOT.json)固定。exe SHA-256 `78ef9124a2dc18ecf0401f461531cd91c13ab16fda2c550ad46eaf063e1bf315`，本地未提交源码构建，非CI。原c35及固定U22EF开发包保留历史身份，旧物理结果不继承。

当前已正常退出旧c35并启动候选版宿主入口，18u/58.8、CN变码/ID/入口关/声音开已核对。当前仅[101两项](../../2026-10-27/touch-screen-trial/physical-resume/P10-ACER-PEN-ELLIPSIS-CHOICE-101.json)待用户实际宏碁笔反馈；6次候选后续另测。启动入口为工作区`.generated/touch-validation-20261025-x64-16inch/Start Ellipsis Choice Keyboard.cmd`。
