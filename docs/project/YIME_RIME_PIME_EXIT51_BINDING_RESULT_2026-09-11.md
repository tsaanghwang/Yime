# Resume 只读绑定诊断：十项通过

响应 `ff488d28` 诊断交接。用户从资源管理器启动同用户原生 PS5，经 run_checked.py 执行 inspect-resume-bindings.ps1。未执行维护、未打开 transaction store、未生成新授权。

## 实际结果

- 失败 Resume 新授权与原计划的七项绑定均匹配：install_root、state_root、recovery_root、initiating_sid、target_machine_id、target_name、package_sha256。
- install/state 两个目录身份均匹配原计划。
- recovery EXE 的文件身份、大小及哈希均匹配原计划和原包。
- 十项 passed=true、error_type=null；all_checks_passed=true。stderr 文件长度为零。
- 归档 prepared 整文件、原恢复票据及失败 Resume 授权的三个固定输入摘要，在准备前和本次报告生成时均通过核对。

[原始输出 JSON](../../testing/platform/2026-09-11-exit51-bindings/output.json)按原始字节保存，目录内 .gitattributes 禁止换行转换。[证据索引](../../testing/platform/2026-09-11-exit51-bindings/index.json)记录诊断版本、脚本哈希和外部文件长度/SHA-256。原参数与身份材料仍在 Git 外。

## CMD 输出记录缺陷

本机辅助 CMD 使用 `echo %ERRORLEVEL%>"exit-code.txt"`，数字紧贴重定向符。CMD 会把此位置的数字解释为句柄重定向，造成用户看到“ECHO 处于关闭状态”，exit-code.txt 实际为空。因此本报告不声称独立保存了进程退出码零；以完整诊断 JSON 中的十项结果作为诊断结论。原空文件和记录保留，不补写、不为此重跑诊断或维护。后续入口应使用 `echo(%ERRORLEVEL% >"exit-code.txt"` 或结构化结果保存，避免相同记录缺陷。

## 结论边界及交回

本轮关闭了此前遗漏的七项新授权绑定、两项目录身份和恢复 EXE 身份证据缺口，不能由此认定原控制器完整计划验证、锁权限、提升 worker 或恢复事务通过。当前仍缺两个 terminal，原 Resume 失败原因未确定，安装/恢复继续暂停。开发端据此继续排查，不重复原恢复入口。
