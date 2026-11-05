# ASUS 18u ARM64 焦点绑定修复包

版本：0.2.0-18u-arm64.5
固定源码：636cef681ee995a21a9c45fd750f8cb4b0acb4a1

本目录的 package 是完整安装包。已核对全部 1156 个文件，并通过原生维护程序只读 Check。
本轮尚未执行 Install，也没有完成新版记事本输入复测。

当前旧 DLL 被 Codex、资源管理器和含未保存文本的记事本加载。请先保存文档；正常重启 Windows 后，先不要打开 Codex、记事本或选择 18u 输入法。
双击本目录 Install-18u-ARM64.cmd，按 Windows 正常安装提示继续。只升级 YimeCore 18u Touch，不修改默认输入法。
入口只执行一次安装并保留 installation-output.log；若失败，不会自动重试。完整安装日志位于 C:\Users\tsaan\Yime Setup Logs。
如果仍提示文件占用，保留日志，停止重试。不要结束 Explorer/System 或强制替换文件。

安装返回后，重新打开本次 Codex 对话；需核对 .5 全载荷及进程身份，再测试记事本新标签的实际绑定和中文正文提交。
原有校准文件应保持不变；自动化鼠标测试不属于真人手指/笔验收。

ZIP SHA-256：e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c
