# 分段选词与句中改选可行性调查

> 日期：2026-07-23
> 范围：Phase 5.5 可行性与测试基线；本阶段不实现完整交互。

## 实施进展

- 阶段 A 已完成源码实现：候选可见时，`Ctrl+Left` / `Ctrl+Right` 绕过 PIME
  候选窗并继续送往 Go/Rime；无修饰方向键、Enter、Space 与 Base 数字键语义不变。
- x86/x64 `PIMERpcResponseTests` 与完整 `PIMETextService.dll` 编译均已通过。
- 阶段 B 的真实 librime 试验已通过：回到前一音节并改选后，后续原始输入仍保留，
  改选过程不提前提交；选择最后一段后提交完整纠正结果。
- 隔离用户目录中的学习试验已通过：重新输入相同编码时，刚提交的纠正整句会进入
  当前候选页；若提交前已存在，则候选排名必须提升。
- 安装态 TSF 验收已通过：2026-07-23 在记事本中实测“逼逼”和“音元输入法”
  均可完成前段改选、后段保留与整句提交，宿主保持稳定。
- 安装态首次试验发现 Enter key-up 会误触发原始 composition 回退，提交成
  `逼bjjj`；回退现已限定为 key-down，并增加宿主选词后抬键回归测试。

## 结论

Yime 可以优先复用 librime 1.17 已有的组合、分段和导航能力，不需要在 Go
侧复制一套候选切片或句子分段器。第一版应采用“修改键移动 Rime 原始输入
caret → Rime 重新计算目标分段候选 → 选择后保留并重算后续输入”的路径。

调查时的主要缺口不在词典或 Rime 分段器，而在宿主按键路由：PIME 候选窗会在候选
可见时截获所有方向键，且不区分 Ctrl/Alt 修饰状态。阶段 A 已针对
`Ctrl+Left` / `Ctrl+Right` 修复该路由，使其能够到达 schema 中的 `navigator`。

完整目标仍需分阶段验证。尤其不能因为 librime 内部存在
`Context::ReopenPreviousSegment()`，就让 Go 直接依赖 librime 私有 C++ 类型。

## 已确认的 librime 能力

### 公开 C API

`RimeContext` 已公开扁平化的预编辑状态：

- `composition.preedit`
- `composition.cursor_pos`
- `composition.sel_start` / `sel_end`
- 当前分段的候选页及高亮索引

`RimeApi` 还公开 `get_input`、`get_caret_pos` 和 `set_caret_pos`，位置单位是原始
输入字节偏移。Yime 当前 Windows 封装只绑定了旧式导出函数和当前页选词，尚未通过
`RimeGetApi` 使用这些函数指针。第一阶段不必立刻扩展 ABI；可先通过已公开、稳定的
按键处理路径驱动 `navigator`。

### Rime 内部行为

- `navigator` 默认把 `Ctrl+Left` / `Ctrl+Right` 绑定为按音节移动。
- 移动前会调用 `Context::BeginEditing()`，并根据候选的 `Phrase::spans()` 与
  composition segment 边界计算停靠点。
- `Context::set_caret_pos()` 会触发更新，Rime 随后重新计算当前分段与菜单。
- `Context::Select()` 只选择 composition 最后一个活动分段；后续 segment 的保留和
  重算仍由 Rime `OnSelect()` 负责。
- librime 内部还有 `ReopenPreviousSegment()` 与 `ReopenPreviousSelection()`，但它们
  没有作为独立 C API 暴露。

三套 Yime schema 当前均按 `selector -> navigator -> express_editor` 装配处理器，
并已启用连续输入。真实 Rime 测试证明修改键导航可以在整句 composition 内移动
caret，同时保留 composition 和目标分段候选。

## 当前链路与缺口

```text
键盘
  -> PIMEClient::filterKeyDown / onKeyDown
       -> 候选窗本地方向键处理（当前不检查修饰键）
       -> Go RPC onKeyDown（只有未被候选窗截获才会到达）
            -> translateKeyCode / translateModifiers
            -> RimeProcessKey
            -> RimeContext preedit/menu
            -> compositionCursor + selStart/selEnd + candidates
       -> PIME 更新 TSF composition 与候选窗
```

现有响应协议已经携带 `compositionCursor`、`selStart`、`selEnd`；PIME 也能把
`compositionCursor` 映射到 TSF composition 光标。键盘驱动的第一版不需要新增
协议字段。若以后支持鼠标点击预编辑文本定位，才需要定义宿主到 Go/Rime 的反向
caret 请求。

### 必须避免的捷径

- 不得改用 Go 侧候选切片；真实 Rime 继续拥有分页。
- 不得把 Base 数字键改成候选选择键；序号选择仍是 Shift+1—9。
- 不得全局把 `express_editor` 换成 `fluid_editor`。这会改变现有“选词即提交”的
  语义，影响所有普通选词路径。
- 不得直接链接 librime 私有 `Context` / `Segment` C++ ABI。
- 不得让修改键导航破坏无修饰四方向键移动候选光标的现有行为。

## 建议的分阶段实现

### 阶段 A：宿主路由

1. 将“候选窗导航键”判定提取为可单测的纯函数。
2. 无修饰 Up/Down/Left/Right/Enter/Space 继续由候选窗处理。
3. `Ctrl+Left` / `Ctrl+Right` 绕过候选窗，按原协议送到 Go 和 Rime。
4. Alt、Win 及系统保留组合键默认不新增语义。

### 阶段 B：分段改选

1. 用修改键在未提交 composition 的音节/分段边界间移动。
2. 显示 Rime 为当前位置生成的候选，不在 Go 侧重建候选。
3. 选择替代候选后核对后续输入仍保留，并由 Rime 重新生成整句预览。
4. 用“姻缘输入法 → 音元输入法”作为产品验收场景；测试数据不得假定该完整短语
   已存在于系统词典，应允许由单字/词语动态组句产生。

### 阶段 C：独立候选/分段 UI（已安装，观察期）

人工使用方法、x86/x64 宿主矩阵和失败判据见
[独立分段条使用与安装态验收计划](SENTENCE_SEGMENT_CORRECTION_TEST_PLAN.md)。

鼠标操作不得依赖宿主编辑区中的 composition 文本点击。当前实现采用输入法自有的
可点击分段条，并遵守以下约束：

1. 由 Rime 当前 composition、活动分段、`sel_start` / `sel_end` 和候选状态生成
   分段视图，不在 Go 侧复制候选分页或句子分段器。
2. UI 归输入法所有，点击分段控件时不得把焦点或宿主插入点移出当前 composition；
   点击后复用已经验证的 navigator 分段导航和改选路径。
3. 先定义分段身份、显示文本与原始输入位置之间的稳定映射；当前通过
   `RimeGetApi` 取得 `get_input`、`get_caret_pos` 和 `set_caret_pos`，并以
   `data_size`、函数指针、会话、原始输入长度和回读位置共同守卫 ABI 与范围。
4. 设计必须覆盖 DPI、多显示器、横竖候选布局、键盘/无障碍等价操作，以及
   UI-less 宿主无法显示自有窗口时的明确降级行为。
5. 安装态验收至少覆盖 x86/x64 宿主、Notepad 和 Codex IDE；任何宿主不得因点击
   分段 UI 提前提交或终止 composition。

2026-07-24 的实现把分段条嵌入现有候选窗，并使用 `WS_EX_NOACTIVATE` 保持
宿主焦点。后端结合 librime `commit_text_preview` 和带空格 preedit 生成
`{start,end,code,text,active}`；候选窗显示“预览汉字 + 对应编码”，进入局部
改选后继续使用缓存映射更新已选汉字和活动尾段。点击以原始编码范围经
`selectCompositionSegment(cursorPos, selEnd)` 直接送往 Go，不经过宿主编辑区回调，
也不把显示汉字下标误当成 Rime cursor。
后端优先使用 librime 原始输入 caret 直接定位任意缓存分段，有界
Ctrl+Left/Right navigator 只作为旧运行库兼容回退；请求拒绝越界、重入、重复状态
和无进展更新，并明确清除导航响应中的陈旧 commit。定位失败时仍回送当前
composition 与候选，不能把空响应送给宿主。UI-less 宿主继续沿用既有键盘降级路径。
源码回归、真实 librime 用例和多架构构建已通过；安装文件与构建物哈希一致，
Notepad、Codex IDE 已完成初步试用，长期稳定性和真实 x86 宿主仍在验收。

#### 已否决并回退的宿主编辑区点击试验

2026-07-24 曾试验在 TSF composition range 上注册
`ITfMouseTracker` / `ITfMouseSink`，把字符位置通过新增的
`onCompositionClick` RPC 送往 Go/Rime。安装并完整重启 Windows 后的真实宿主
日志证明该方案不能作为产品路径：

- Notepad 能发送 `onCompositionClick`，后端也返回已处理和新的 composition
  cursor，但宿主紧接着仍发送 `onCompositionTerminated`。
- Codex IDE 不发送 `onCompositionClick`，点击直接按宿主默认行为结束 composition。
- 刷新鼠标监听范围只能让 Notepad 回调到达，不能提供跨宿主的焦点和 composition
  生命周期保证。

因此该 TSF 鼠标监听、旧 RPC、Go 导航及回归试验已整体回退。后续不得再次把宿主编辑区
点击包装成可移植的鼠标组句功能；新的鼠标方案必须采用上述输入法自有 UI。

### 阶段 D：学习验证

验证局部改选最终提交后由 Rime 正常更新用户词典；不得在 Go 侧另写一套学习记录。
测试必须隔离临时用户目录，并比较提交前后候选顺序或用户库状态。

## 保护性测试基线

本调查新增：

- 协议测试：composition 光标和选择区元数据必须序列化。
- schema 测试：三套方案必须保留 `selector -> navigator -> express_editor`。
- 真实 Rime 测试：`Ctrl+Left` 能在整句 composition 内移动且候选仍存在。

后续实现必须再增加：

- PIME 单元测试：无修饰方向键仍移动候选；Ctrl+Left/Right 绕过候选窗。
- Go 回归：修改键正确转换为 Rime `controlMask`，Base 数字键语义不变。
- 真实 Rime：局部改选保留后续输入并重新组句。
- TSF 安装态：候选窗、composition 光标和提交文本一致，x86/x64 宿主均不退出。
- 守卫：`TestNativeBackendKeepsRimeOwnedCandidatePaging` 保持不变。

## 后续推进条件

阶段 A 的源码、阶段 B 的 librime 行为、隔离用户学习和安装态 TSF 交互均已验证。
x86/x64 DLL、后端、librime 与部署器的安装哈希一致；真实短句“音元输入法”已经
完成局部改选和整句提交。键盘驱动的最小端到端功能可以进入合入阶段。独立候选窗
分段条已经完成源码、真实 librime、构建产物和安装哈希验证，并在 Notepad、
Codex IDE 中开始观察期试用；仍需持续验证第一段、中间段、末段的重复切换以及真实
x86 宿主。不得恢复已否决的宿主编辑区点击方案。
