# PR #83 无触屏台式机鼠标测试交接

本目录提交本机实测记录，供项目整合。影响范围仅为隔离的桌面触摸键盘原型，不是已安装 YimeCore/Rime 产品验收。

- [测试汇总](SUMMARY.zh-CN.md)与[逐项结果](RESULT_AMD64.json)。
- [包身份核验](identity-check.json)、[原包 manifest](manifest.json)、[本机 Check Package 报告](package-check.json)。
- [宿主文件版本/架构](host-candidates.json)、[Firefox WOW64 运行进程证据](firefox-process-architecture.json)。
- `batch-*-user-feedback.json` 保存分批用户反馈；[证据哈希索引](evidence-sha256.json)覆盖导入的原始文件字节。

固定包来自 [PR #83 CI 41018028276](https://github.com/tsaanghwang/Yime/actions/runs/41018028276)，sourceCommit 为 `f01326e6c1976a4e67c9ff59693effc0e1110b1a`。不能将本报告提交或最终 main 合并提交当作包内源码身份。

## 整合口径

B00 是工具核验通过；B01—B03、E01—E08、Word W01/W02、Firefox WOW64 W01/W02 是用户分批反馈正常。`passed` 表示此口径下的通过，不代表每个动作都有独立日志或截图。Word 未读取码点；Firefox 用户反馈第一项 U+2026、第二项 U+22EF，第二项未单独转录两个码点序列。Word 架构来自 EXE 的 PE 检查，Firefox 另有 IsWow64Process2 运行证据。

E09—E12 因用户要求减少重复测试在本机跳过；手指、笔无硬件未测。量尺、缩放和校准观察未收集。旧设备/旧包的结果不继承，也不扩大为全键盘、触屏、笔或 ARM64 验收。RESULT 内空环境字段保持未知；绝对路径和 PID 是当时本机证据，不是接收端启动指令。

原始反馈文件的 time 是记录写入时间，不是逐项测试发生时间。无需为导入本报告重复测试或重装程序。
