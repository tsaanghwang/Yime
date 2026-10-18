# 实体键盘虚拟样机的隔离 YimeCore 服务

这个开发命令把 ANSI 实体键盘和概念键盘的浏览器点击接入同一个真实
YimeCore 引擎。134 键概念布局有 75 个独立 ASCII 载体（52 字母与 23 符号），
输入保留 ASCII 大小写；中文模式主区 `1–9` 有候选时选词，无候选时直接输出数字。
侧数字区始终直输 ASCII，不选词、不编码、不转换标点，也不清除或确认现有组成。
候选来自实验布局
重新生成的完整三模式词典，提交结果只进入页面内的文本框。

启动前生成 `prototypes/touch-terminal/data/physical-layout.json` 和
`.generated/ascii-keyboard-134/data/yime_{variable,full,shorthand}.dict.yaml`。
同目录的 `ascii_keyboard_manifest.json` 必须绑定当前完整 75 载体布局摘要、空停用集合和
三份词典的 SHA-256 与 `input_policy: concept-keyboard-modes-v2`；启动时逐项核验，
布局摘要还必须等于编译时生成的完整 `codemode.LayoutProjectionSHA256`，防止读取旧布局词典或旧二进制。
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
当前 `inputPolicy` 为 `concept-keyboard-modes-v2`；前端必须核对，避免连接到旧字符策略的服务。
后续 POST 带 `Content-Type: application/json` 和 `X-Yime-Lab-Token`。

`POST /api/session`：

```json
{"mode":"variable","layoutId":"生成布局的摘要"}
```

返回 `{ok, sessionId, revision, state, modes}`。`modes` 是服务器权威的
`{input:"chinese"|"english",punctuation:"chinese"|"english"}`，新会话默认中文输入、英文标点。
API 允许分别设置；134 键页面的 CN EN 同时设置两项，页面初始化为中文输入／中文标点。不存在 Caps 模式。`state` 使用真实引擎格式：
`raw_input`、`candidates`（稳定 `id`、`text`、`code` 等）、`page_number`、
`has_previous`、`has_next`。空数组、零页码和 false 布尔值可能被 JSON 省略。

`POST /api/event`：

```json
{"sessionId":"会话ID","eventId":"每次操作的新ID","baseRevision":0,"type":"input","code":"A"}
```

| type | 附加字段 | 行为 |
| --- | --- | --- |
| `input` | `code`：恰好一个非空格可打印 ASCII 字符 | 服务端按当前候选和生成的编码字母表决定编码、选词或直输 |
| `literal` | `code`：单个可打印 ASCII（含空格），或 LF/TAB | 侧区直输；完全绕过编码、选词、标点转换和自动确认，保留组成 |
| `symbol` | `code`：单个 ASCII 标点或已审定的 ·、—×√÷ | 显式主区字面入口，按当前标点模式输出并保留组合；与侧区 literal 分开 |
| `setModes` | `inputMode`/`punctuationMode`：至少一项，值为 `chinese` 或 `english` | 保留未确认组成、候选 ID 和页码，不隐式提交或取消 |
| `backspace` | 无 | 删除最后一个编码字符 |
| `clear` | 无 | 取消本会话组合 |
| `page` | `delta`：`1` 或 `-1` | 下一页或上一页；单编码符号采用下述实验候选视图 |
| `select` | `candidateId` | 校验当前页稳定 ID 后提交引擎候选或实验符号候选 |
| `close` | 无 | 取消组合并关闭会话，供切换模式使用 |

成功返回 `{ok:true,sessionId,revision,state,modes,commit?}`；`commit` 是提交文本字符串，
可以由 `select`、`input`、`literal` 或 `symbol` 产生。ANSI 和虚拟键盘都把
字符交给本实验服务统一处理，浏览器不自行提交标点：

- 中文输入的编码字母表来自 `codemode.LayoutAlphabet`，当前为 52 个大小写字母与 23 个符号。
  编码串始终为 ASCII，不受中英标点模式影响；包括 R15 的所有符号载体均由该表动态判定。
- 英文输入直接输出按键固定大小写，不编码、不数字选词；只在独立中文标点模式启用时转换标点。
  切换到英文时，原中文组成暂停保留；空格/回车用 `literal` 插入，不确认暂停的候选。
- `1–9` 在当前页有候选时按序号选择；该页不足该序号时不动作，不把数字直输。
  当前没有候选时只输出数字；`0` 总是走直输规则。
- 中文模式不在编码字母表内的 ASCII 标点直接输出；在字母表内则优先编码，不能凭 Shift 绕过。
  有候选时先确认当前页首项，再把符号或 `0` 合并到同一个响应的 `commit`。
  有未匹配编码、但没有候选时，只输出新字符，原 `raw_input` 保持不变，不提交或丢弃原编码。
- 当前编码恰好是一个编码符号时，把该符号的字面候选作为首页末项：不足 9 项则追加在实际末项，
  已满则显示前 8 个原候选与符号，第 9 个原候选顺延到次页。后续页仍至多 9 项，
  原候选顺序、稳定 ID 保持不变，无丢失或重复。继续输入后不再附加符号候选。
  该候选的 `source_id` 是 `keyboard-lab:literal`，只存在于实验适配层，不写入任何词典。

字面候选和普通直输字符按独立标点模式显示/提交；数字侧区 `literal` 不受它影响。
中文标点的实验默认表如下，未列出的 ASCII 原样输出，**不是全角转换**：

| ASCII | 中文输出 |
| --- | --- |
| `, . ; : ? !` | `， 。 ； ： ？ ！` |
| `( ) [ ] < > { }` | `（ ） 【 】 《 》 『 』` |
| `/` 与 `\` | `、` |
| `^` 与 `_` | `……` 与 `——` |
| 单引号、双引号 | 依各自提交次数交替 `‘ ’`、`“ ”` |

引号状态只在实际提交时推进，显示候选、翻页、切换模式、取消以及同一事件重试均不会推进。
切换标点模式只改变字面候选显示，不改变其稳定 ID、原 ASCII 编码和页码。

此分页视图仅位于 `cmd/yime-keyboard-lab`；真实候选选择时仍定位到所属引擎页再提交，
不改变共享 YimeCore 引擎或原生 Rime 分页。Layout 仅是页面内的英文视图选择，不向服务请求切换词典或会话。页面高亮本身不用调用 `select`。

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
数字状态复用、全 ASCII 标点、23 种编码符号候选、完整分页序列、无候选原编码保留、
独立中英/标点模式、侧区旁路、配对引号幂等、原子首选加标点、会话隔离、并发版本争用、
分页稳定 ID、提交重试去重、关闭回收，以及
本地 HTTP 和静态文件边界。测试的小词典是明确的测试夹具；交互服务读取上述
实验完整词典，不使用三个固定候选演示样例。
