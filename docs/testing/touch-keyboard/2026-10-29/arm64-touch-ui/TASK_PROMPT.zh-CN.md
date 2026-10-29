# ARM64 接续任务文字

请在ARM64测试机器接续Yime PR #82的新触屏盘面验证。先阅读本分支`docs/testing/touch-keyboard/2026-10-29/arm64-touch-ui/CI_DELIVERY.zh-CN.md`与`HANDOFF.zh-CN.md`。保留当前源码工作区和旧PR #80交付，不需要先合并或切分支；可只接收完整便携包。

固定ARM64下载：[artifact 12866469047](https://github.com/tsaanghwang/Yime/actions/runs/40802706324/artifacts/12866469047)，ZIP SHA-256为`0d8fec1bb6955b2758b293f4ab6925b27034024fb540e34e60b5a870eda02dd3`，exe SHA-256为`3fb3e4ce982d457abb0a4dd62f3073897a32a9ba49e31bf311f923f2395d3989`；包源码`e8e2c2d1519ec77157eef480484b1af1277d8630`，来自成功触屏CI40802706324。下载后完整解压到新的独立目录，先核对哈希及ARM64 PE身份，再运行`Check Package.cmd`。不要使用x64包或旧包代替。

用`Start Touch Screen Preview.cmd`打开98键新盘面，按A00–A07依次记录环境、原生资源检查、显示/空间、EN字符和Shift、三模式“你”、设置/帮助、选区及最小化/恢复/退出/重开后的声音。手指和具体笔型号独立记录，无笔或暂时不可测的项目保留未测，不用鼠标或模拟通过补齐。复制RESULT_TEMPLATE.json到包外records目录，填入本机实际结果及证据，不继承x64通过项。

先提交第一轮基础结果，再决定候选分页/数字/引号、具体设置、并发触点及真实Word/Edge用例。真实宿主只用新建空白、不保存的测试文档，明确绑定后输入；焦点、帮助、最小化恢复按交接步骤重绑。不安装或修改已安装输入法、默认输入法和用户数据；不要更改系统声音设备。防回弹试验仍为0，不复制MSI的58.8校准值。

原ASUS ProArt ARM64开发记录保留，需重新确认当前实际环境。汇报时注明PR、CI包源码、ZIP/exe哈希、机器、输入方式、通过/失败/未测项目及异常步骤；保留失败及复测两份证据。现阶段只做测试与结果记录，不自动合并PR #82。
