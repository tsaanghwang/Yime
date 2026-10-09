# 实体键盘虚拟样机的隔离 YimeCore 服务

这个开发命令把 ANSI 实体键盘和概念键盘的浏览器点击接入同一个真实
YimeCore 引擎。输入保留 ASCII 大小写；`1–9` 有候选时选词，无候选时直接输出数字，
`0` 和未参与编码的上下档 ASCII 标点直接输出。主键区与小键盘使用相同字符规则。
候选来自实验布局
重新生成的完整三模式词典，提交结果只进入页面内的文本框。

启动前生成 `prototypes/touch-terminal/data/physical-layout.json` 和
`.generated/ascii-keyboard/data/yime_{variable,full,shorthand}.dict.yaml`。
同目录的 `ascii_keyboard_manifest.json` 必须绑定当前布局摘要、M25–M27 停用集合和
三份词典的 SHA-256；启动时逐项核验，防止读取旧布局词典。
在 `go-backend` 目录执行：

```text
go run ./cmd/yime-keyboard-lab --root .. --port 8765
```

需要使用独立的实验数据输出目录时指定 `--data-dir <绝对目录>`。启动时将三份
词典编译到进程专有临时目录，创建只读索引；退出时回收索引和临时目录。
服务绑定 `127.0.0.1`，打印打开地址及各模式词典摘要和条目数。
没有安装目录、旧词典、用户学习库、用户词库或另一产品的隐式回退。

这是独立引擎和页面输入验证，不能据此声称 Windows 注册宿主输入已通过。
Python 工具只用于离线数据生成，运行服务和解码不依赖 Python。

## 浏览器 API

`GET /api/info` 返回 `version`、`inputPolicy`、`layoutId`、`token`、`modes`、`indexes` 和范围说明。
当前 `inputPolicy` 为 `candidate-or-literal-v1`；前端必须核对，避免连接到旧字符策略的服务。
后续 POST 带 `Content-Type: application/json` 和 `X-Yime-Lab-Token`。

`POST /api/session`：

```json
{"mode":"variable","layoutId":"生成布局的摘要"}
```

返回 `{ok, sessionId, revision, state}`。`state` 使用真实引擎格式：
`raw_input`、`candidates`（稳定 `id`、`text`、`code` 等）、`page_number`、
`has_previous`、`has_next`。空数组、零页码和 false 布尔值可能被 JSON 省略。

`POST /api/event`：

```json
{"sessionId":"会话ID","eventId":"每次操作的新ID","baseRevision":0,"type":"input","code":"A"}
```

| type | 附加字段 | 行为 |
| --- | --- | --- |
| `input` | `code`：恰好一个非空格可打印 ASCII 字符 | 服务端按当前候选和生成的编码字母表决定编码、选词或直输 |
| `backspace` | 无 | 删除最后一个编码字符 |
| `clear` | 无 | 取消本会话组合 |
| `page` | `delta`：`1` 或 `-1` | 下一页或上一页；单编码符号采用下述实验候选视图 |
| `select` | `candidateId` | 校验当前页稳定 ID 后提交引擎候选或实验符号候选 |
| `close` | 无 | 取消组合并关闭会话，供切换模式使用 |

成功返回 `{ok:true,sessionId,revision,state,commit?}`；`commit` 是提交文本字符串，
可以由 `select` 或 `input` 产生。按 2026-10-09 用户最新决定，ANSI 和虚拟键盘都把
字符交给本实验服务统一处理，浏览器不自行提交标点：

- 编码字母表来自 `codemode.LayoutAlphabet`，当前为 52 个大小写字母与 `' [ ] \\ /`。
- `1–9` 在当前页有候选时按序号选择；该页不足该序号时不动作，不把数字直输。
  当前没有候选时只输出数字；`0` 总是走直输规则。
- 不在编码字母表内的 ASCII 标点直接输出，包括 `Shift+1–9` 的原符号。
  有候选时先确认当前页首项，再把符号或 `0` 合并到同一个响应的 `commit`。
  有未匹配编码、但没有候选时，只输出新字符，原 `raw_input` 保持不变，不提交或丢弃原编码。
- 当前编码恰好是一个 `' [ ] \\ /` 时，把符号本身作为首页末项：不足 9 项则追加在实际末项，
  已满则显示前 8 个原候选与符号，第 9 个原候选顺延到次页。后续页仍至多 9 项，
  原候选顺序、稳定 ID 保持不变，无丢失或重复。继续输入后不再附加符号候选。
  该候选的 `source_id` 是 `keyboard-lab:literal`，只存在于实验适配层，不写入任何词典。

此分页视图仅位于 `cmd/yime-keyboard-lab`；真实候选选择时仍定位到所属引擎页再提交，
不改变共享 YimeCore 引擎或原生 Rime 分页。页面高亮本身不用调用 `select`。

同会话事件串行执行。重复 eventId 的相同请求返回原结果；不同内容返回 409。
客户端必须依据原事件 ID 只消费一次 commit；不可自动重播结果未知的操作。
旧 revision、跨页候选、不同布局会话、未知字段、跨源请求、错误令牌或超长正文
被拒绝。每会话上限 128 字符和 4096 事件，最多 16 个活动会话；关闭或闲置
30 分钟的会话在新建会话时回收。只提供原型目录里的静态文件，无目录列表。
静态清单限定为新页面、app/input/geometry 模块、样式、physical-layout JSON 和
README/PROTOCOL/HARDWARE 文档；旧 `demo.json` 等历史演示资源不会由本服务暴露。
另提供唯一字体路径 `/assets/YinYuan-Regular.ttf`，只读本 checkout 内的
`go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf`，用于显示盘面的
PUA 音元图例；不开放字体目录，不复制或安装系统字体。

## 验证

```text
go test ./cmd/yime-keyboard-lab
```

全量词典生成后另执行（把路径替换为本分支的绝对 checkout 路径）：

```text
go test ./cmd/yime-keyboard-lab -run TestCanonicalCorpusHTTP -v -args -keyboard-lab-integration-root C:/path/to/Yime
```

该检查实际编译三份完整词典，启动 loopback HTTP 测试服务器。从规范音节分解
读取 `ni3/hao3` 的稳定音元元组，结合新物理布局投影，经现有码制算法得到测试码，
然后逐键输入、取得真实候选、提交“你/好”，并验证真实候选的前后翻页。
不会手填旧键码，也不从已生成词典倒推上游音元。

测试使用真实词典编译、只读索引和 YimeCore 会话，覆盖三模式大小写、候选可见时
数字状态复用、全 ASCII 标点、五种编码符号候选、完整分页序列、无候选原编码保留、
原子首选加标点、会话隔离、并发版本争用、分页稳定 ID、提交重试去重、关闭回收，以及
本地 HTTP 和静态文件边界。测试的小词典是明确的测试夹具；交互服务读取上述
实验完整词典，不使用三个固定候选演示样例。
