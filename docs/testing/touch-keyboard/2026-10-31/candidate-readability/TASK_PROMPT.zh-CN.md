# MyComputer 接续任务：PR #87 触屏盘面集中审查与测试

请在 MyComputer 推进 Yime [PR #87](https://github.com/tsaanghwang/Yime/pull/87) 的整合审查与本机测试。本轮先沿用已经集中整理的盘面，不另开一套竞争设计。

先从该 PR 分支读取本目录的 [HANDOFF.zh-CN.md](HANDOFF.zh-CN.md) 和 [CI_DELIVERY.zh-CN.md](CI_DELIVERY.zh-CN.md)，再阅读[当前使用说明](../../../../../prototypes/touch-terminal/desktop/USER_GUIDE.zh-CN.md)首节。按这些文档理解当前102位置、18键控制行、立体键帽及候选框；开发历史中的旧规格不是当前任务要求。

## 固定交付身份

- PR 分支：`codex/touch-candidate-readability-20261031`。
- 此次 CI 对应的 PR head：`8c7d26d67eff4b6650940b69963824141f565688`。
- 成功 CI：[run 41178044364](https://github.com/tsaanghwang/Yime/actions/runs/41178044364)。
- MyComputer 使用完整 **amd64** 包：[artifact 13034145597](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13034145597)。
- ZIP SHA-256：`e790c0fe0e245456e54163f348c969af93b3ac0ed91dda95e53e00655da4e34f`。
- 包的构建源码／`sourceCommit`：`12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，是此次 PR 的 test-merge commit，与上述 PR head 不同；须分别核对，不能互相替代。

完整文件身份和核对步骤以 CI_DELIVERY 为准。ASUS 本机已对该固定 ARM64 包完成原生移位与触屏自检；这些自动结果不替代 MyComputer 的本地检查或任何真人验收。

## 执行顺序

1. **保留现有工作。** 记录当前分支与未提交改动，使用独立工作树审查同一 PR 与当前 main。若 main 或 PR 后续前进，先说明具体差异及它们与固定 CI 包的关系；需要修正时在同一交付线上接续，不覆盖原工作区，不自行重做盘面，不自动合并 PR。
2. **取得并核对完整包。** 按固定 run/artifact 下载 amd64 ZIP，核对以上 ZIP 哈希、manifest、exe 哈希、PE 架构、资源清单及 `sourceCommit`；还要确认本机原生架构匹配。解压到新的独立目录，保留旧包，不混用其他包的字体、布局或词典。源码 checkout 不能代替完整包交付。
3. **先做自动检查。** 在包外建立本机结果目录，记录包身份、系统/显示信息与执行命令。运行随包自检时，将 `--data-report` 指向包外，例如 `YimeTouchKeyboard.exe --check-package --data-report <包外结果目录>\package-check.json`；另加 `--touch-ui` 并使用新的 `touch-ui-check.json` 报告，确认触屏102位置/18控制/84主体及三模式。按 CI_DELIVERY 核对资源与身份。失败时保留原始日志，停止依赖该结果的后续验收，不沿用旧报告。
4. **打开当前触屏预览。** 使用 `Start Touch Screen Preview.cmd`，确认完整盘面、18键控制行、两侧L形键、翻页尺寸、文字/字形及候选多行居中。按本机显示器重新量尺并记录100mm参考线；不要直接复用 ASUS 的 `597.73 / 58` 参数。尺寸与可读性未确认前，不进入全键物理测试。
5. **分批引导实际测试。** 先确认本轮实际屏幕、姿态和可用触控笔。每批只安排少量项目，等待使用者报告实际结果再登记。优先按 HANDOFF 的小批回归检查候选按住/移出取消、换页旧触点失效、中文组合与 EN 暂停时工具栏退格保护、已确认正文退格、三个空闲键、最小化恢复及无声退出。手指、触控笔、鼠标分别记录；没有相应设备或未做的项目标为待测。
6. **预览确认后再测宿主。** 在使用者主动准备的空白测试文档中，按交接分批检查 Word/Edge 的绑定、候选与提交一致、编辑和恢复。填写实际应用、输入方式及包身份；不修改既有用户正文。自动检查、自有 EDIT 检查与真人宿主输入分开记录。
7. **回报接续结果。** 汇总审查问题、自动检查结果、使用者确认的通过项和剩余待测项，附包外记录路径。发现问题时先给出具体复现步骤与证据，再决定同一 PR 后续修正或下一批测试；不要自动合并。

不安装输入法，不改变已安装或默认输入法，不改注册项、系统字体或用户数据。结果、截图和运行状态放在包外。PR #82 或本地 v1–v7 的旧验收仅属于各自固定包，不继承为 PR #87 新包的通过；本机、ASUS、CI 和不同输入方式的结果也不能互相代填。
