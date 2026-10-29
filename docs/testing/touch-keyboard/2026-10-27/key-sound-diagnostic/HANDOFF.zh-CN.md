# 短敲击声与实际播放诊断

当前结论已更新：分组重复后A单次短流未听到、B连续流四声清楚，尾部500ms静音仍无效。使用持续waveOut流后，同实现四声及真正键盘窗口三次a均获明确清楚反馈，当前接续[修复版](../key-sound-stream/HANDOFF.zh-CN.md)。下方保留诊断进行时的范围和当时待反馈描述，不能替代新结果。

2026-10-27。用户撤回此前似乎听到短声的判断，认为可能误听其他声音；原版及增幅版均不能记作可听。停止继续加大幅度，保留原失败和更正，见[原话](USER_CORRECTION.json)。

较长“短、短、长”基准已实际播放，用户明确确认听到节奏；测试进程自己的Windows音频会话峰值约0.14，见[BENCHMARK.json](BENCHMARK.json)。这证明该基准路径可听，不证明键盘短声可听。

直接给先前预览PID连接电平表时，窗口/会话已不可用；该尝试未得到测量值，不报告为零电平。随后用临时有界程序复制生产Go波形生成器、真实WinMM函数及固定缓冲区初始化，约每2秒播放一次，同进程电平表测得峰值约0.4307、60个非零采样；程序已自行结束。见[电平](DRIVER_PROBE_METER.json)与[播放返回日志](DRIVER_PROBE.log)。没有录制音频或测量其他应用声音，也没有改系统设置。

再将同一增幅版PCM逐样本原样放入一个连续3.4秒流，在0.5/1.25/2.0/2.75秒各敲一次。峰值同为0.4307，见[连续流对照](CLICK_TRAIN_BENCHMARK.json)及[声音文件](click-train.wav)。已询问用户能否辨认先前单独播放、后一组四次敲击、两组或均不能，反馈待记录。

当前结论仅为真实短声已经进入Windows音频会话，但物理可听问题仍在。下一步按对照听感区分短流生命周期/传输影响与瞬态波形可辨识性，再决定播放后端或波形调整；不以电平非零、接口成功或基准音可听宣称按键音验收通过。API电平含义见[Microsoft GetPeakValue](https://learn.microsoft.com/en-us/windows/win32/api/endpointvolume/nf-endpointvolume-iaudiometerinformation-getpeakvalue)。

当前源码幅度仍为增幅试用版3倍，没有进一步加大；未改变系统/会话音量、默认音频输出或输入法。P10仍为原包下250项，字体/配色原反馈范围保持。详细阶段状态见[DIAGNOSTIC_PROGRESS.json](DIAGNOSTIC_PROGRESS.json)。
