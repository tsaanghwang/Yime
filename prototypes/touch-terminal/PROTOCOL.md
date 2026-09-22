# 触摸原型最小事件协议 v1

影响范围：**共享源数据的隔离原型**。本协议在 [core.mjs](core.mjs) 的纯内存会话中实现，供浏览器预览与本地测试使用；不是 PIME 或 YimeCore Broker 已支持的新线协议。当前没有后端连接、系统按键注入、TSF 注册或宿主文本写入。后两节是后续适配设计，尚未实现。

## 事件与状态

通过 `createSession(layout, demo, sessionId)` 建立会话，使用 `session.dispatch(event)`，从 `session.state` 读取副本。`layoutId` 必须采用生成数据中的精确值；布局变化时创建新会话。

```json
{
  "version": 1,
  "sessionId": "touch-demo-1",
  "eventId": "touch-demo-1:1",
  "seq": 1,
  "layoutId": "yime-touch-example",
  "baseRevision": 0,
  "type": "input",
  "payload": {"yinyuanId": "M01"}
}
```

示例中的 `layoutId` 是占位示例，运行时替换为生成值。事件必须恰好包含这八个字段。会话、布局和事件 ID 是 1–128 位 ASCII 标识，首位为字母或数字，其余允许字母、数字、`_ . : -`；`seq` 为正安全整数，`baseRevision` 为非负安全整数。未知字段、事件类型或多余 payload 字段均拒绝。

| type | payload | 本原型语义 |
| --- | --- | --- |
| `input` | `{ "yinyuanId": "M01" }` | 追加一个来源可追溯的稳定音元 ID；投影编码保持大小写 |
| `backspace` | `{}` | 删除最后一个音元，重新匹配候选；空组合也可执行 |
| `clear` | `{}` | 取消当前组合，保留页面内已确认预览记录 |
| `select` | `{ "candidateId": "…" }` | 只改变当前页的高亮候选，不确认、不学习 |
| `page` | `{ "delta": 1 }` 或 `-1` | 前后翻一页；越界拒绝；每页最多 9 个候选 |
| `confirm` | `{}` | 确认高亮候选至页面预览，然后清空组合；无候选则拒绝，不提交原始编码 |

组合与翻页后的默认高亮为当前页第一项，但只有明确的 `confirm` 才产生确认记录。候选仅来自生成的有限演示数据，按完整有序音元 ID 序列精确匹配，不是完整词库解码或真实后端候选结果。

响应为 `{ok, state, error?, commit?}`。`error` 为 `{code, message}`；`commit` 为 `{eventId, candidateId, text, ids, code, revision}`，仅成功确认时出现。状态字段：

| 字段 | 含义 |
| --- | --- |
| `sessionId, layoutId` | 会话与布局身份 |
| `revision, nextSeq` | 当前状态版本、下一个可接受序号；初始为 0、1 |
| `ids, code` | 完整音元 ID 序列与大小写敏感的已有键位投影 |
| `candidates` | 当前页的 `{id,text}` 列表 |
| `page, pageCount, selectedId` | 零基页号、总页数、高亮 ID 或 `null` |
| `committed` | 此会话的页面内确认预览记录，不是宿主文档状态 |

每次成功操作，包括空退格/清空，都使 `revision` 和 `nextSeq` 加一；拒绝操作不改变状态或序号。所有新事件均须满足 `seq===nextSeq`、`baseRevision===revision`。候选 ID 必须来自同一会话、同一版本、当前页；不能仅凭候选文字或显示序号选取。常见错误为 `INVALID_EVENT`、`SEQUENCE_MISMATCH`、`STALE_REVISION`、`CANDIDATE_UNAVAILABLE`、`NO_CANDIDATE`、`PAGE_BOUNDARY`。

有效事件按 `eventId` 缓存完整响应（包括拒绝）；完全相同的重试返回历史响应，不再执行。同 ID 改动任意值，包括有序数组、版本或候选，返回 `EVENT_ID_CONFLICT`；JSON 对象属性顺序不影响相等性。修正被拒绝的事件需使用新 ID。调用方把响应与原调用关联，只确认一次 `commit.eventId`，不得用重试的旧快照覆盖较新的界面。缓存不淘汰：会话最多 4096 个有效格式的新事件、128 个组合音元、128 条确认记录；达到上限须建立新会话，不能借重连自动重播确认。

## 与现有 Go / Broker 的最小适配

后续应单独实现受信任的本地适配器，并显式选择一个产品及其独立测试会话、数据目录。浏览器不直连产品命名管道，不把 JSON 当作可信客户端身份，不使用系统级模拟按键；一个产品不可隐式回退到另一产品。原型八字段校验、revision、去重及高亮由适配层保留，并串行执行同一会话事件。异步传输还须按原 `sessionId/eventId/seq` 关联响应；断连后的执行结果未知时应查询/停止，不能盲目重试不可幂等的后端输入。

| 原型事件 | YimeCore Broker 适配设计 | Go / PIME 适配设计 |
| --- | --- | --- |
| `input` | `apply` + `engineapi.AppendCode`，传来源布局投影的 `code` | 用来源布局构造完整键事件生命周期 |
| `backspace` / `clear` | `apply` + `Backspace` / `Clear` | Backspace / 取消组合，限此隔离会话 |
| `page` | `apply` + `PagePrevious` / `PageNext` | 交给后端 PageUp/PageDown，不在 Go 侧切片代替原生 Rime 分页 |
| `select` | 适配器只保留高亮 ID | 适配器只保留高亮 ID |
| `confirm` | `select` + 当前稳定 `candidate_id` | 校验当前快照后，调用 `selectCandidate` + `data.candidateIndex`（零基当前页索引） |

Broker 实际字段是 `version/sequence/session_id/operation/event/candidate_id/mutation_id`，不能直接发送本原型 camelCase 消息。它以 `open` 建立会话（sequence 从 1 开始），随后严格递增；`apply` 接收 typed operation，`select` 可在引擎支持时使用 `mutation_id`，`close` 释放本连接所拥有的会话。当前 `AppendCode` 接收的是编码字符串，**没有音元 ID 输入能力**；`select` 会产生提交，因此绝不能用于原型“仅高亮”的 `select` 事件。后端重试序号与原型幂等缓存是不同层，不能互相替代。

Go 的键位适配须同时设置 `keyCode`（VK）、`charCode`（实际 ASCII）和 `keyStates`。例如 `a` / `A` 的 VK 都是 `0x41`，字符分别是 97 / 65；大写层应令 `keyStates[0x10]=0x80`，CapsLock 保持关闭。标点使用对应 OEM VK，并依据源布局确定 Shift，不能对编码统一转小写。裸数字始终是组合输入，不能被候选窗口截获；候选快捷方式只可为 Shift+1…9，标签保留 `⇧1`…`⇧9`。实际 `filterKeyDown` 执行处理，`onKeyDown` 提取响应，还需正确的 `filterKeyUp/onKeyUp`；仅发 `onKeyDown` 不会等价输入。生命周期应在隔离适配测试中验证，不向操作系统发送键。

源码依据：[PIME Request/Response](../../go-backend/pime/protocol.go)、[键码与修饰转换](../../go-backend/input_methods/yime/rime_keyevent.go)、[Go 事件处理与候选选择](../../go-backend/input_methods/yime/yime.go)、[Broker 协议](../../go-backend/input_methods/yime/yimebroker/protocol.go)、[Broker 序号与分派](../../go-backend/input_methods/yime/yimebroker/dispatcher.go)、[engineapi](../../go-backend/input_methods/yime/engineapi/engine.go)。

## 两个不能隐去的边界

**60 个音元不等于 60 个不同的物理编码。** [唯一布局源](../../internal_data/manual_key_layout.json) 将 N12/N26 共享撇号、N25/N27 共享反引号；现有投影只有 58 个不同槽。原型保留各自 ID，不能从相同投影码反推身份。未来适配器必须明确声明 `semanticYinyuanIds` 或 `physicalProjectionOnly` 能力：只有前者能承诺端到端“一音一键”身份；后者应默认拒绝有歧义的语义输入，或通过明确选择的兼容模式告知身份丢失，不能静默合并后宣称等价。增加原生 ID 能力需要后续引擎契约与独立回归，本次没有修改现有语义或布局。

**确认预览不等于宿主写入成功。** 本原型的 `commit` 只写入页面内存。未来适配器收到引擎提交文本后，还需由宿主文本服务执行并确认写入，记录独立提交 ID 与实际完成结果；`TF_S_ASYNC` 不是成功回执。未确认写入、超时或断连不得显示“已写入应用”，也不得重复提交。焦点丢失只取消原组合，不向新宿主发送 Escape，不自动提交原始字符；原型 v1 并未实现这套宿主提交事务。
