# CMD 安装入口换行修复

此前仅验证了 Python runner，未覆盖实际 CMD 入口，遗漏了入口文件的 LF 换行问题。首次实际 CMD 执行出现中文行被当成命令、路径语法错误，原始失败输出保留在 `raw/first-command-failure.log`。

修复仅将入口从 LF 改为 CRLF。归档时验证：统一换行后的 UTF-8 字节完全相同，修后每个 LF 均属于 CRLF；前后哈希与 `raw/line-ending-repair.json` 一致。未重建或修改完整安装包。

修后于 2026-11-05 23:43:56 UTC（北京时间 11-06 07:43:56）运行 CMD，随后于 23:44:55 UTC 以桌面快捷方式记录的完整目标、参数和工作目录运行。入口能够正常输出并创建 CMD 开始日志及 runner 日志，标准包 Check 返回 0。完整快捷方式命令记录见 `raw/exact-shortcut-command.json` 与对应原始输出。

两次 runner 均只读发现 Explorer 20092、Codex 39152、Notepad 11912 占用已安装 DLL，因此返回 3，状态为 `blocked-by-dll-users-install-not-started`，`installLaunched=false`。这是 CMD 入口链路修复和占用保护生效的证据，不是安装成功、`.5` 已上线或真实记事本输入验收通过的证据。

`raw/` 保留入口前后文件、首次失败与完整命令证据；`delivery/` 保留两次 runner 的 JSON、日志、native Check 日志，以及 CMD 开始日志当时副本和修后入口输出。`evidence-index.json` 记录源路径、字节数、SHA-256，全部副本逐字节核对。既有 `raw/entry` 历史未修改。本归档操作没有执行入口、安装器或新的系统采样。
