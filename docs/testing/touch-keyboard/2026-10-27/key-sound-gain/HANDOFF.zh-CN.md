# 轻敲声幅度调整

最新更正：用户仍未听到本版短声，并指出上次可能误把其他声音当按键声。原版“可听但轻”不再作为当前确认结论；较长“短、短、长”基准单独反馈可听。停止继续增幅，检查短声播放路径，详见[更正记录](../key-sound-diagnostic/USER_CORRECTION.json)。下方为本增幅试用的形成和开发检查，不能解读为按键音验收通过。

2026-10-27。用户对初版真实模拟反馈“听到了，但很轻”；对输出路径回答“应该是2”，按当时第二个选项解释为SoundWire接收端，保留其暂定措辞。见[原试听反馈](../key-sound/USER_AUDIBILITY_RESULT.json)。原先“没有声音”及诊断保留；当前不能再把仅枚举到SoundWire当成输出配置错误或缺少物理设备的阻塞。

只把程序合成PCM幅度乘以3，时长仍23.991ms。独立逐样本检查确认与初版3倍的差异最多2个整数单位（量化），峰值0.4514、RMS约0.05877，没有削顶；幅度增益约9.54dB，不等于听感响度3倍。见[WAVE检查](WAVE_CHECK.json)和[生产生成器导出的声音](key-click.wav)。系统音量与应用会话音量未改，播放时机、去重、取消和静音逻辑未改。

独立x64本地包`.generated/touch-key-sound-gain-20261027-amd64`，exe SHA-256 `a4608b5057cc9b8da9339d3c8b724e9d4bdb19b2c8cc6981e73194f212438422`，源码基线9adc3cdd9634e0258b58c9a8945b3497fc8777ad，`sourceChanges:true`，不是CI交付。见[包身份](package-identity.json)。相对初版声音包，只有exe、指南和含指南哈希的resources.json改变，其他26个载荷一致。

针对声音/原生触笔的Go回归及完整包移出仓库/空工作目录三模式、资源拒绝检查通过，见[包检查](package-check.json)。已启动新版并用Computer Use执行CN→EN、三次a，输出aaa，声音按钮保持开，没有显示不可用。初次观察时该窗口已存在CN组合aaa；模拟保留并暂停它，未选候选或清空组合，也未向其他宿主发送输入。此为开发模拟，不能当作真人手指/笔输入通过。

当前开发模拟窗口保留供用户直接试听。已询问加大后的三次敲击是清楚合适、仍轻还是太响/刺耳，反馈待记录。重新打开可用[加大声音预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Louder Key Sound Preview.cmd>)，先关闭旧预览以免混用版本。另备[静音入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Louder Silent Preview.cmd>)与[宿主入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Louder Key Sound Keyboard.cmd>)。

前轮字号/下档修复及配色保持，真人字体完整性/字号仍待确认，颜色按用户决定暂不深究。原P10手指250项按原包身份保留，余CN150项与两支笔各400项不补填；声音听感反馈单列。
