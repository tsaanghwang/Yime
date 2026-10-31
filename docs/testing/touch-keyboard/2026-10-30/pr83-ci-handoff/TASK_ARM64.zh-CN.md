# ARM64机器接续任务

请在本机执行PR #83省略号双候选固定CI包的独立测试，先核对包身份，再按每批2—4项向我发送实际操作要求并记录我的反馈。不要直接把全部项目记为通过。

下载完整包：[artifact 12960955078](https://github.com/tsaanghwang/Yime/actions/runs/41018028276/artifacts/12960955078)。
ZIP SHA-256：`6275aa0fe02f666c31653539386ca374ed70847de51c7cd45223e77b8c0a785d`。
exe SHA-256：`db0a2b141218fa569ad95c71310ba44f53e954bcb9c78c84abf3a0b99b39cf9f`。
包内sourceCommit：`f01326e6c1976a4e67c9ff59693effc0e1110b1a`，architecture：`windows-arm64`，sourceChanges必须false。
PR头提交`7136cba1c9cececc339fb19da2d81e6789b14617`；最终main合并`bbf64dd85a4618c95b03980e61b7b5acab166371`。固定CI产物来自PR测试合并提交，不能用main提交号冒充包内身份。

先取得本交付目录的 `EXECUTION_REQUIREMENTS.zh-CN.md`、`CI_DELIVERY.zh-CN.md` 和 `RESULT_ARM64_TEMPLATE.json`。它们是本轮执行附件；如果仅收到本任务文字，先准备包和核验身份，再取得完整要求后逐项执行，不猜测未收到的步骤。对应文件当前在发送端仓库的 `docs/testing/touch-keyboard/2026-10-30/pr83-ci-handoff/`，不是PR #83原有目录；由发送端提供文件或复制全文，不能假定仅拉main便能得到这次新写的附件。

完整解压到新的包目录，保留ZIP。Check Package报告与结果放在包外records。先运行 `Check Package.cmd`，再用 `Start Touch Screen Preview.cmd` 做B00—B03（身份/启动声音/帮助设置/最小化恢复）。本机独立量尺和记录缩放，不复制微星58.8参数，防回弹默认0。

基础通过后正常退出预览，用 `Start Touch Screen Keyboard.cmd`。Edge固定测试框使用PR头提交下的 `docs/testing/touch-keyboard/2026-10-29/edge-host/test-textarea.html`。CN、变码、ID、标点入口关；每项清空/定位/绑定后先输入12，每个中点均重新Shift→N25。依执行要求做3/6次、U+2026/U+22EF两候选、退格取消、主区1/右空格、语言/编码模式切换、最小化/帮助清理重绑，再做新空白Word E01/E04。异常先停该项并记录实际文本/码点与状态，不自动重试。

手指、每支笔、鼠标及每个宿主分别记账；无触屏/笔则写未测，鼠标成功不是触屏验收。ARM64必须核对键盘原生进程，仿真宿主单列；x64台式机如有32位宿主，用amd64键盘单列WOW64 E01/E04，没有32位键盘包，不新增32位Windows硬件或安装软件。不要修改当前工作分支的其它改动、已安装输入法、默认输入法、用户数据或系统字体/音频设备。

先反馈本机环境、身份核验和B00结果，再推进后续。旧包/本机宏碁29项、手指10项不继承到本机新CI包。本任务准备不代表已经执行，也不要代替用户的物理观察。
