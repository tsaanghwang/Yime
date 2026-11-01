# 本地验证记录（2026-11-01 UTC）

基线固定源 `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，Linux/amd64云端隔离目录。只验证源码，不访问用户电脑。初次运行Go默认缓存因home只读而停止；之后改为工作区内独立GOCACHE/GOPATH，不修改用户/系统配置。

工具链：官方 `go1.25.3.linux-amd64.tar.gz`，对官方release索引核验SHA-256 `0335f314b6e7bfe08c3d0cfaa7c19db961b7b99fb20be62b0a826c992ad14e0f`。工具链、缓存、测试产物均在仓库外，不进入交付包。

## 已完成

- 改动前及改动后各一次Linux适用的三包测试通过：
  `go test ./cmd/yime-touch-keyboard ./internal/touchkeyboard ./internal/keyboardlab -count=1 -timeout=180s`。
  **这些Linux测试不执行Windows诊断代码**，只检查共用逻辑没有附带破坏。
- Windows amd64 和 ARM64 整个桌面键盘测试包交叉编译通过（实现者和主审分别复核）：
  `GOOS=windows GOARCH=<amd64|arm64> go test -c ./cmd/yime-touch-keyboard -o <包外测试EXE>`。
  仅编译，不执行，不是完整中文便携包或原生验收。
- gofmt及 `git diff --check` 通过。
- 独立只读审查重点检查trace-off、写失败、输入调用次序和隐私。发现空闲鼠标route仍写日志的遗漏已修复，并增加真实自有窗口回归；没有修改输入行为条件来消除日志。

新增七项Windows测试（当前仅确认编译通过，运行待后续Windows CI）：

1. 读取失败及PALM过滤的日志/正文与错误文本隐私。
2. trace开/关分页结果一致，旧手势及重复UP无提交，分页结果/拒绝理由存在。
3. 生命周期epoch和写入失败不阻断分页。
4. 空闲鼠标/指针UPDATE不记录，DOWN/UP仍记录。
5. 空闲mouse-route accepted/suppressed均不输出。
6. 锁定OS线程、自有隐藏窗口的空闲WM_MOUSEMOVE不产日志或改变预览状态。
7. 翻页边界不可用与暂停候选拒绝理由。

## 尚未完成 / 不可推导

- 未运行任何Windows测试EXE，未验证真实触屏/笔、Windows消息驱动差异或Windows下新测试实际通过。
- 未推送代码、未运行新提交CI，未下载完整资源或构建诊断便携交付包；没有新CI artifact/ZIP/EXE身份可交付。
- 未改变/重测原PR87包，不继承原包真人结果，也未声称已修复MyComputer/MSI问题。
- 同步诊断I/O可能改变时序；本修改不提供吞吐、延迟、可靠性频率证明。需要审阅后独立Windows CI及新包身份核对，才讨论后续最小人工操作。

本地原始日志位于执行环境 `/workspace/shared/diagnostic-validation/`（baseline-linux.log、final-linux.log、diagnostic-crosscompile.log）；这些路径是云端本地证据，不代表已上传或存在于用户电脑。交付可审阅Git补丁，不交付交叉编译测试EXE给用户运行。
