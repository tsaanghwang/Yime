# 音元输入法可用性评估

> 评估日期：2026-07-07（最终版）
> 评估范围：Yime Go 后端 + Rime 引擎 + 编码体系 + 词典 + 工具链
> 分支：yime-stable

---

## 1. 评估摘要

音元输入法（Yime）是基于 PIME/TSF 框架的 Windows 中文输入法，采用 Go + Rime 双层架构。编码体系设计精巧（声母规律映射到 QWERTY 键盘），词典规模可观（468K 条/方案），工具链覆盖设置、诊断、反查、词库管理。

所有已知可用性问题均已修复，仅剩 1 个编码约束问题（候选选择键仅 5 个，暂不修改）。

### 评分卡

| 维度 | 评分 | 说明 |
|------|------|------|
| 编码体系设计 | ★★★★☆ | 声母映射有规律，三种模式灵活，但独立声母 m/n 编码复杂 |
| 词典质量 | ★★★★☆ | 规模大、权重合理，但自动生成可能含噪声 |
| 按键处理可靠性 | ★★★★★ | 重复按键抑制、回车键、翻页位置均已修复 |
| 候选窗交互 | ★★★☆☆ | 选择键仅5个（编码约束），数字键不选词 |
| 设置与工具 | ★★★★★ | 工具链完善，所有操作有反馈，反查即时搜索 |
| 错误恢复 | ★★★★☆ | Rime 初始化失败可重试；部署/打开/剪贴板失败有用户提示 |
| 可发现性 | ★★★☆☆ | 候选选择键映射非标准，用户难以自行发现 |

---

## 2. 架构概览

```
┌─────────────────────────────────────────────────┐
│                  Windows TSF                     │
├─────────────────────────────────────────────────┤
│  PIMELauncher.exe (Rust)                        │
│    └── server.exe (Go)                          │
│          ├── pime-go 桥接层 (stdin/stdout JSON)  │
│          ├── yime.go (按键/语言栏/候选窗)        │
│          ├── rime.dll (librime, 动态加载)        │
│          ├── 独立工具 (PowerShell WinForms)      │
│          │     ├── 设置工具                      │
│          │     ├── 诊断工具                      │
│          │     ├── 反查工具                      │
│          │     └── 词库管理                      │
│          └── 数据层                              │
│                ├── data/*.schema.yaml (3方案)    │
│                ├── data/*.dict.yaml (468K条/方案) │
│                ├── data/yime_pinyin_codes.tsv    │
│                └── data/pinyin_normalized.json   │
├─────────────────────────────────────────────────┤
│  %APPDATA%\PIME\Rime\ (用户数据)                │
│    ├── default.custom.yaml                      │
│    ├── yime_variable.custom.yaml                │
│    ├── yime_user_phrases.txt                    │
│    ├── custom_phrase_variable.txt               │
│    ├── custom_phrase_full.txt                   │
│    ├── custom_phrase_shorthand.txt              │
│    └── yime_settings_state.json                 │
└─────────────────────────────────────────────────┘
```

### 关键设计决策

1. **原生 Rime 候选分页**：`UsesBackendCandidatePaging()` 返回 `true`，Go 侧不做候选切片
2. **独立工具优先**：重 UI 操作通过独立 PowerShell WinForms 窗口实现，不在 TSF 回调路径中
3. **轻量语言栏**：语言栏仅分发命令，不承载复杂 UI
4. **延迟 redeploy**：语言栏点击使用轻量会话重建，完整 redeploy 仅在显式"重新部署"时触发
5. **多音字完整保留**：反查工具保留所有读音编码，候选窗注释仅取首选读音

---

## 3. 编码体系评估

### 3.1 三种编码模式

| 模式 | schema_id | 编码长度 | 示例 (bi1) | 示例 (zhong1) |
|------|-----------|----------|------------|---------------|
| 等长 | yime_full | 固定4键 | `quuu` | `7ddd` |
| 变长 | yime_variable | 2-4键 | `qu` | `7d` |
| 省键 | yime_shorthand | 1-3键 | `qu` | `7d` |

### 3.2 声母→键盘映射

| 分组 | 声母 | 映射键 | 规律 |
|------|------|--------|------|
| 翘舌音 | zh/ch/sh | 7/8/9 | 数字行递增 |
| 舌面音 | j/q/x | 3/2/1 | 数字行递减 |
| 平舌音 | z/c/s | 6/5/4 | 数字行递减 |
| 唇音 | b/p/m/f | q/p/h/[ | 左侧+右侧 |
| 舌尖音 | d/t/n/l | w/./y/b | 左侧+底部 |
| 舌根音 | g/k/h | ]/'/n | 右侧+中部 |
| 零声母 | (a系) | H | 中右 |
| 半元音 | w/y | %/$ | Shift+数字 |

### 3.3 编码体系问题

| 问题 | 严重度 | 说明 |
|------|--------|------|
| 独立声母 m/n 编码复杂 | 低 | 使用 `!`, `@`, `#`, `N` 等特殊键，但极罕见 |
| Full 模式需大写字母 | 低 | `H`, `D`, `S` 等需 Shift+键，影响流畅度 |
| 非标准音节 | 低 | `bong4`, `wong4` 不属于标准普通话 |
| 禁用语句模式 | 中 | `enable_sentence: false`，必须逐词输入 |

---

## 4. 词典评估

| 指标 | 数值 |
|------|------|
| 每方案条目数 | 468,175 |
| 方案数 | 3（variable/full/shorthand） |
| 拼音-编码映射 | 1,625 条（含声调变体） |
| 拼音归一化 | 1,729 条 |
| 权重范围 | 1 ~ 240,230,122 |
| 多音字词数 | 8,788（1.9%），最多 11 个编码（欸） |

**问题**：
- 词典注释 `Generated from Yime runtime_candidates_materialized`，为自动生成，可能含噪声（权重=1 的极低频词）
- `use_preset_vocabulary: false`，完全依赖自带词典，不使用 Rime 预设词库

---

## 5. 已修复的高优先级问题

### 5.1 重复按键抑制吞键 ✅

**修复**：`keysDown map[int]bool` 替代计数器，基于 key-down/key-up 配对追踪。提交 `edd6e0ab`。

### 5.2 回车键在组字时被吞 ✅

**修复**：Rime 拒绝回车时提交原始编码上屏（`pendingRawCommit`）。提交 `ef52fe2a`。

### 5.3 候选项数变更丢失当前输入 ✅

**修复**：`reloadBackendSessionForSchema` 保存组字内容，重建后逐字重放。提交 `1bf5063f`。

### 5.4 候选选择键仅5个（编码约束，暂不修改）

57 音元（24 首音 + 33 乐音）占满 47 个可打印键位。数字键是编码的一部分，不是选字键。候选选择键仅有 Space/`/-/=/\ 五个，这是编码体系的必然结果。改变选择键方案需重建整个编码体系。

---

## 6. 已修复的中优先级问题

### 6.1 Rime 初始化失败不可恢复 ✅

**修复**：`sync.Once` → `sync.Mutex` + `rimeInitDone`/`rimeInitOK` 双标志。提交 `3e24351d`。

### 6.2 部署/打开/剪贴板失败无用户反馈 ✅

**修复**：为 `openPath`、`copyTextToClipboard`、`redeployBackend`、`syncBackendUserData`、`selectSchema`、`setCandidatePageSize` 添加 `showUserMessage` 反馈，含 panic recover 保护。

### 6.3 反查注释遇生僻字整体消失 ✅

**修复**：`joinRuneLookup` 对缺失字符显示 `?` 占位符。`lookupStandardPinyin` 编码路径含 `?` 时逐字符拆分查找拼音。

### 6.4 用户词库只重建当前方案 ✅

**修复**：`applyUserLexicon` 为三种模式各生成独立的 `custom_phrase_{mode}.txt`。三种 schema 各自引用对应的 `user_dict`。

### 6.5 数字键在组字时作为编码输入 — 设计约束，非缺陷

57 音元编码体系中，24 个首音占满数字行 base 层全部 10 个键位。数字键本身就是编码的一部分。候选选择键仅有 5 个，这是 47 个可打印键位被 57 个音元占满后的必然结果。

---

## 7. 已修复的低优先级问题

| # | 问题 | 修复 |
|---|------|------|
| 1 | 反查工具首次加载无进度提示 | 窗体显示时状态栏提示"正在加载数据" |
| 2 | 反查搜索结果上限100条无截断提示 | 上限提升至200条，截断时提示"已截断" |
| 3 | 多音字只取首个编码 | `Load-DictLookupMulti` 保留所有读音编码，逐字拼接支持笛卡尔积 |
| 4 | 每次查询重新加载词库 | 数据只加载一次，跨查询复用 |
| 5 | 方案切换时 dictLookup 不重新加载 | `Ensure-LookupData` 按 `loadedSchemaID` 判断是否需要重载 |
| 6 | `findRimeExternalDeployer` 含硬编码开发路径 | 移除 `C:\dev\librime\` 候选项 |
| 7 | `remapYimeCandidateSelectionKey` 是死代码 | 删除未调用的函数 |
| 8 | YAML 操作不支持行内注释 | `parseMenuPageSizeValue` 先剥离 `#` 注释 |
| 9 | `candidatePageStart` 在非分页键时重置 | 只在 `backendRet==true` 时重置 |
| 10 | `commandShouldRefreshState` 白名单维护负担 | 改为黑名单，只列出需刷新的 11 个命令 |

---

## 8. 测试覆盖

### 已覆盖的关键路径

- 原生 Rime 候选分页权守卫
- 子菜单点击通过 `data.id` 传递
- 候选项数变更不触发完整 redeploy
- YAML 引号/非引号 key 兼容 + 行内注释
- PowerShell 脚本编码损坏守卫
- PowerShell 脚本智能引号守卫
- redeploy 使 page_size 生效

### 已覆盖的边界场景

| 场景 | 测试 |
|------|------|
| 并发按键/语言栏点击 | `TestConcurrentKeyAndCommandNoDataRace` |
| 大候选列表 Go 侧分页 | `TestLargeCandidateListGoSidePaging` |
| Unicode 边界（emoji、扩展汉字、代理对） | `TestUnicodeBoundaryEmojiAndExtendedHan` |
| 组字中切换方案失败 | `TestSchemaSwitchFailureDuringComposition` |
| 超长用户词组 | `TestLongUserPhraseLexiconBuild` |
| `onCompositionTerminated` 非强制/强制终止 | `TestCompositionTerminatedNonForced` / `Forced` |

---

## 9. 工具链评估

| 工具 | 功能完整度 | 说明 |
|------|-----------|------|
| 设置工具 | ★★★★☆ | 修改方案/候选数需"应用并重建"才生效 |
| 诊断工具 | ★★★★★ | 完善，含预设、匿名化、命令解读 |
| 反查工具 | ★★★★☆ | 多音字完整展示、即时搜索（500ms debounce）、加载进度、截断提示 |
| 词库管理 | ★★★★☆ | 删除/导入/冲突预览已实现；工具箱已中文化 |

---

## 10. 遗留问题

### 编码约束（暂不修改）

- 候选选择键仅 5 个，第 6-9 个候选需鼠标点击
- 数字键在组字时作为编码输入，不选词
- `SetSelKeys` 设为 `"1234567890"` 但数字键实际用于编码

### 可接受的后续改进（不涉及编码变更）

- 修正 `SetSelKeys` 使候选窗标签与实际选择键一致
- 支持上下方向键移动候选光标 + Enter 确认
- 将默认 `candidatePageSize` 限制为 5

### 长期方向

- 词典噪声清理（权重=1 的极低频词）
- 非标准音节审查（`bong4`, `wong4`）
- 组字时数字键选词模式（可配置，需编码体系配合）
