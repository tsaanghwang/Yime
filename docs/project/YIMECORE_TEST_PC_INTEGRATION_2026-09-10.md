# “计算机”测试结果整合

接收分支：`origin/perf/i7-7820x-local`；提交：`fc2d7db65`，基于 `e346a1dad`。已快进合入 MYCOMPUTER 开发分支，保留本机未提交的语流、旧入口退役和 DP2 矩阵工作。原共享指令的本机版本另存 `.tmp/test-pc-prompt-before-integration-20260910.md`。

## 接收的证据范围

测试机“计算机”（i7-7820X）报告 YimeCore local.13 安装成功，包清单 `133c91fe205fcae911fa701a278465dad040e7dadce006b541697b656e50405a`，90 个文件；x64/x86 注册宿主通过。其包不同于 MYCOMPUTER 的 `f8dea89d…`，不能互换身份或验收结论。

本次远端提交包含源码与 Markdown 报告，没有提交报告所指的原始 package、working-tree.patch、source-snapshot.zip 或注册宿主结果 JSON。因此安装与宿主结论注明为测试机报告，接收端未独立重算这些远端工件。报告中“尚未执行安装/注册宿主”的过时条目已修正；历史安装命令标为已完成，无需重装。

后续用户反馈已重启登录且入口仍在，记录为入口保留；当前开机 Runtime/Broker 和 Shell 登录事件尚待补齐。[只读复核交接](../../TEST-PC-YIMECORE-REBOOT-FOLLOWUP.md)给出精确包身份、观察范围和证据回传方式。

## 合入及本机检查

接收改动包含测试机专用平台构包、完全未注册时的幂等预清理、启动健康端点真实超时重试，以及较新 Windows DPI 行为的测试适配。默认 MYCOMPUTER 通道仍与已识别测试机通道分开；不改本机已安装包。

合入后发现两份新增中文机器名断言脚本以无 BOM UTF-8 保存，在 Windows PowerShell 5.1 中解析失败。修复为带 BOM UTF-8，并给测试中的 scope JSON 读取显式指定 UTF-8。生产 scope 读取原本已显式指定 UTF-8。此修复只改测试文件，不改变主机准入。

本机实跑：平台合同 24 项、开发范围回归 89 项、启动健康 PS5/PS7 各 48 项、针对现有本机构建包和新源码管理器的安装 Plan 合同均通过；`git diff --check` 通过。没有运行安装或注销，没有把测试机二进制安装到 MYCOMPUTER，没有重跑其原生 C++/真实宿主测试。

这批结果推进 YimeCore 的 mainstream_x64 工作线，不是 Rime/PIME 安装验证，也不关闭双产品两种安装顺序、升级/卸载/恢复矩阵或三选一入口门槛。
