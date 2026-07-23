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

### 阶段 C：直接 caret 与高级交互

只有键盘路径不足时，再通过 `RimeGetApi` 安全取得 `get_input`、`get_caret_pos`
和 `set_caret_pos`，并增加 ABI 大小、版本与空指针守卫。鼠标定位或跨多个已确认
分段的任意跳转属于该阶段。

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
完成局部改选和整句提交。键盘驱动的最小端到端功能可以进入合入阶段。鼠标定位、
跨多个已确认分段的任意跳转和更细粒度学习观测仍属于后续增强，不在本次范围内。
