# 持续音频流修复与真实键盘试听

2026-10-27。独立试听四声与实际键盘窗口三次a敲击均已收到用户明确的清楚反馈。原无声案例及误听更正保留，不将早期接口成功或其他声音误记为通过。当前接续本版，旧单次PlaySound及增幅包只保留历史身份。

## 问题证据与修复范围

同一敲击PCM逐次单独播放，用户明确“没听到”；放入连续3.4秒流敲四下，用户明确“清楚听到四声”；给单次敲击末尾加500ms静音仍未听到。Windows会话电平表在旧路径已测到非零信号，不能替代实际发声确认。见[A/B反馈](../key-sound-diagnostic/AB_USER_RESULT.json)、[尾静音结果](../key-sound-diagnostic/PADDED_USER_RESULT.json)和[原始诊断](../key-sound-diagnostic/HANDOFF.zh-CN.md)。这些支持本环境短流播放/传输生命周期相关的判断，不确指某个内部驱动缺陷，也不声称其他Windows设备必然相同。

改为启用按键音时打开一个waveOut流，平时填零，在后台把同一24ms敲击插入返回的缓冲区；字典加载时就开始输出静音，避免可见窗口每次按键重新启动极短流。PCM、幅度和音色与3倍增幅版相同，没有继续增幅。三个10ms缓冲区循环使用，声音请求有界，极快连按可截短/合并提示，不积压迟到声音；这不是实际端到端延迟测量。

关闭声音、最小化和退出停止流并按reset→unprepare→close顺序清理，恢复按原声音开关重建。缓冲区与头在交给驱动期间固定；驱动拒绝清理时保留其仍可能引用的存储直至进程结束，避免提前释放。音频失败不改变输入、不重放文字；取消、重复触笔/鼠标及过期判定仍沿原唯一动作路径。系统音量、会话音量、默认输出、输入法和用户数据未改。API所有权依据见[waveOutWrite](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutwrite)和[waveOutReset](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutreset)。

## 包、检查与实际结果

新独立x64本地包`.generated/touch-key-sound-stream-20261027-amd64`，exe SHA-256为`25d973f80d839f2ef2e9e399d577c3f9adc35b7739afff2374bc832cc37d18a5`；源码基线9adc3cdd9634e0258b58c9a8945b3497fc8777ad，`sourceChanges:true`，不是CI交付。完整[身份](package-identity.json)记录源码、载荷和播放实现。相对增幅包，变化为exe、指南和记录指南哈希的resources.json；26个其余载荷，包括布局、profile、字体和三模式隔离词典一致。字号、下档位置、深灰配色、18u/100键与58.8参数保持。

相关Go回归通过，覆盖完整PCM跨缓冲区、设备复用/静音、音频打开失败不影响输入、异步队列失败停止及清理、部分准备失败、驱动拒绝清理时的存储寿命和Windows ABI。原有按下/抬手、取消、禁用、过期、宿主发送失败与原生触笔重复消息回归保留并通过。完整包移出仓库/空工作目录三模式、资源拒绝和渲染检查通过，见[包检查](package-check.json)。

实际使用同一持续播放源文件的有界程序先输出一秒静音，再按需敲四次，用户“清楚听到四声”；关闭返回后不接受播放请求，实际驱动清理无遗留，见[原结果](../key-sound-diagnostic/CONTINUOUS_STREAM_USER_RESULT.json)及[执行报告](../key-sound-diagnostic/CONTINUOUS_STREAM_PROBE.json)。

随后启动真正键盘预览，Computer Use模拟CN→EN、a/a/a，实际显示aaa。用户对“真正键盘窗口而非独立程序”的问题回答“三次都清楚”，见[原反馈](REAL_WINDOW_USER_RESULT.json)。这属于开发鼠标模拟加用户听感确认，不转换成手指或笔输入验收。后续实际关闭声音时进程音频会话为inactive，仍可输入a；重新打开后会话为active，系统约81.84%、应用100%且均未静音，见[静音状态](MUTE_DEVICE_STATE.json)及[恢复状态](RESTORED_DEVICE_STATE.json)。这两项未另行请求主观听感结论；移出取消由Go回归覆盖。实际窗口恢复为声音开启供继续试用。

## 当前入口与后续范围

当前窗口就是本版。重开时先关闭旧版，再用[持续按键音预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Continuous Sound Preview.cmd>)。另备[同版静音预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Continuous Silent Preview.cmd>)与[同版宿主入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Continuous Sound Keyboard.cmd>)；入口存在不增加宿主通过项。

本轮无声报告已在本机实际预览定向复测关闭，连续快速敲击、冷启动/恢复后的主观延迟、纯手指/纯笔及每个宿主声音仍按具体新案例独立记录，不从三次模拟外推。字号完整性/大小尚待上轮请求的明确真人反馈，颜色按用户决定暂不深究。P10原包下250项保留，余CN150项、两支笔各400项不补填；见[当前P01/P10记录](../../2026-10-26/p01-p10/RESULT.zh-CN.md)。
