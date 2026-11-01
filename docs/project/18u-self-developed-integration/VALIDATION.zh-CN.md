# S1 验证记录（本地开发，非正式TSF验收）

基线 main `f605d1acf9f9a20986c3ec3d6490da3e2d5c15ac`，独立工作树 `/workspace/shared/yime-18u-bridge`。没有引入a837诊断改动、工作流任务或旧包载荷。2026-11-01。

## 环境与基线

Linux云端，独立Go工具链1.25.3（`/workspace/shared/go-toolchain/go/bin/go`，`GOTOOLCHAIN=local`）。未操作用户机器、Windows注册/安装/默认输入法。未启动旧产品或触屏程序。

修改前基线命令：

```text
go test ./internal/keyboardlab ./internal/touchkeyboard ./cmd/yime-touch-keyboard ./input_methods/yime/codemode ./input_methods/yime/yimecore -count=1 -timeout=180s
```

五包均通过。该命令在Linux执行，不包含Windows专有源码运行，不能作为原生TSF/实际宿主证明。

## 最终实现及验证

新增 `go-backend/internal/touchhostbridge/bridge.go` 与 `bridge_test.go`，未修改既有运行入口。Open经既有loader校验专用实验布局/三模式词典，独占runtime；固定布局哈希、当前模式词典哈希、模式及SessionPolicy。动作匹配SessionID、revision、Focus；Pending阻止继续输入；Applied仅可信宿主完成确认，Failed/Unknown终止，关闭/失焦的待确认提交转Unknown且不重放。

最终验证（2026-11-01，Linux）：
- `go test ./internal/touchhostbridge ./internal/keyboardlab ./internal/touchkeyboard ./cmd/yime-touch-keyboard ./input_methods/yime/codemode ./input_methods/yime/yimecore -count=1 -timeout=180s` 六包全部通过，主实现协调者独立运行。
- `go vet ./internal/touchhostbridge` 通过。
- 独立审阅者执行 `go test -race ./internal/touchhostbridge` 通过，并独立复跑新包与三个相邻包通过。
- `GOOS=windows GOARCH=amd64 go test -c ./internal/touchhostbridge -o /tmp/yime-touchhostbridge-amd64.test.exe` 通过；仅交叉编译，不是Windows执行。
- 新包11个顶层测试涵盖真实小词典自研引擎链、普通翻页/退格/取消、错布局/篡改词典、错身份/焦点/版本/候选、跨会话迟到动作、一次性提交及并发关闭/失焦。夹具使用合成小词典，不是完整正式词库或语义覆盖证明。
- 独立审阅发现并修复跨会话同revision误入缝隙，加入Action.SessionID；修正负例使其他字段有效，避免另一校验兜底产生假通过。最终无剩余审阅阻断。
- `git diff --check` 通过；diff仅新增上述两源码文件和本目录计划/记录。标准投影/数据、Rime、注册身份及原运行路径均未修改。选定回归通过不等于全仓/全部平台通过。

这是S1合同与隔离引擎验证交付，不是18u前端已接TSF。Complete/Focus是未来可信宿主适配器接缝，不提供OS焦点真实性或IPC认证。S2的真实宿主edit完成读回仍是下一阶段门。

## 尚未执行

Windows原生自有TSF宿主、真实应用读回、安装注册、用户物理操作、ARM原生、签名交付均未执行。S1的宿主完成回执由测试适配器模拟，未来只有真实宿主edit完成才能报告Applied；测试Applied不是一次真实Windows正文写入。
