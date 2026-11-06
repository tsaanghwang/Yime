# 固定全码序列与合成笔路线补充验证

2026-11-06 09:41（Asia/Shanghai），`TestAcceptanceFullNiiiSyntheticRoutes20261106` 的三个子例全部通过；退出码 0。此项补齐指定全码序列的软件验证，不替代已安装产品的真人手指或笔验收。

| 子例 | 期望与实际 |
| --- | --- |
| `synthetic-finger` | N08、M03、M03、M03 后 raw 依次为 `n`、`ni`、`nii`、`niii`；首候选为“你”；选择后仅提交一个“你”，清空 raw 与候选。全部符合。 |
| `synthetic-native-pen-with-promoted-mouse` | 同一固定序列、候选与提交断言全部符合；同时模拟笔标志触摸帧及兼容鼠标消息。 |
| `synthetic-legacy-pen-mouse` | 同一固定序列、候选与提交断言全部符合；使用合成笔兼容鼠标消息路线。 |

三个子例均进一步断言 DOWN 不提交、重复 UP 不改变编码或输出、旧候选重放被拒绝且不重复提交。固定物理位置是 `R06K12`（N08/n），然后三次 `R05K14`（M03/i）。完整断言和实际值分别保存在 `acceptance_overlay_test.go` 与 `result.json`，原始 Go 输出在 `go-test.jsonl`。

源码固定为干净的 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`。仅通过进程局部 `-overlay` 加入新测试；测试前后固定源码均保持干净。运行使用已交付 `.5` 包的独立 lab 数据，包 manifest SHA-256 为 `d536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be`。全码词典 SHA-256 为 `85ff8a88dfe5a66a22429c9551c2625815af83351973db30f8faeb52fced3790`，实际构建 2,457,604 条索引记录；布局 ID 为 `995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c`。其余资源身份和进程局部环境见 `run-receipt.json`。

测试复用现有隐藏自有 HWND fixture 与真实 `windowProc` / DOWN / UP / 候选处理，输出仅进入测试内存编辑器。`WM_TOUCH` 数据由替代 `touchReader` 提供，再模拟带 PEN 标志的帧；兼容鼠标消息发送给同一自有隐藏窗口。这些是模拟调用，不是真设备事件。进入全码模式通过现有 settings 测试辅助函数准备，未验证纯笔设置链路。没有连接已安装 TIP、向真实 Notepad 注入输入、停止运行时、修改产品设置或全局 `GOFLAGS`。

已完成的同源笔回归仅复用，没有重跑。原始证据在 `docs/testing/18u/2026-11-05/arm64-binding-focus/raw/go-regression.jsonl`；具体通过项、行号、哈希及 CI 收据引用见 `prior-evidence-reuse.json`。其中旧本地完整词典测试为跳过，不能当成完整词典通过；本次新增三路线使用上述匹配的真实完整词典。

最小归档仅包含本目录的 `README.zh-CN.md`、`acceptance_overlay_test.go`、`run.py`、`overlay.json`、`go-test.jsonl`、`result.json`、`run-receipt.json`、`prior-evidence-reuse.json`、`evidence-index.json`。不要归档 `go-cache/`、`tmp/`、`go-path/`、生成索引或二进制。原始 overlay 和执行路径保留执行时含义；移到文档目录后不能直接照路径重跑。已有完整包、安装成功、有限真人手指 Notepad 结果继续引用各自原始证据，不被本项重新定性。
