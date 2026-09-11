# Go race CI：命名管道测试启动同步

影响面：YimeCore Broker 的 Windows 测试夹具；不修改产品运行时、共存候选或安装准入。

运行 `34560697015` 的 `go-race-msys2` 在 `TestServeNamedPipeWaitsAtGlobalConnectionLimit` 首次连接时失败：10 秒后仍收到 file not found。GCC 安装成功，日志没有 DATA RACE 报告。后续制包任务因该门禁失败而跳过。

源码检查发现测试在启动服务 goroutine 后立即连接，而服务先创建并自行连接一个用于保留名称的 anchor，再发出 `OnListening`。测试客户端可能在这个初始化窗口抢先连接 anchor。原失败未读取 serverDone，无法从该日志确认服务端退出原因；本地旧测试重复 50 次未复现，不能把这个具体触发条件称为已重现。

两个服务测试改为等待现有 `OnListening` 回调，并在启动失败时直接显示服务端错误；同时补充失败路径的 cancel/文件关闭。保持原来的 10 秒期限、第三条连接不得越过配额、释放后复用槽位，以及跨连接会话隔离断言。

修改后两个服务测试在 race 下重复 50 次通过。本地完整 go test -race ./... 通过（未变更包允许 Go 测试缓存）；远端 CI 结果仍须单独确认。固定 `-stdreg` 候选包未重新生成，测试脚本变化不是运行时修复证据。
