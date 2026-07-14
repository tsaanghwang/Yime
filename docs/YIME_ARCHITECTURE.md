# 音元输入法架构文档

> 版本：2026-07-10
> 配套文档：[项目综合评估](YIME_PROJECT_ASSESSMENT.md) | [可用性评估](YIME_USABILITY_ASSESSMENT.md) | [开发路线图](YIME_DEVELOPMENT_ROADMAP.md)

---

## 1. 系统架构

### 1.1 进程模型

```
┌──────────────────────────────────────────────────────────┐
│  Windows TSF (Text Services Framework)                   │
│    └── PIMETextService.dll (C++/COM, 32-bit)             │
│          └── 通过 stdin/stdout JSON 协议与 server.exe 通信 │
├──────────────────────────────────────────────────────────┤
│  PIMELauncher.exe (Rust, 32-bit)                         │
│    └── 启动并监控 server.exe 进程                         │
├──────────────────────────────────────────────────────────┤
│  server.exe (Go, 64-bit)                                 │
│    ├── pime.Server (stdin/stdout 事件循环)                │
│    ├── ServiceManager (client → IME 实例映射)             │
│    ├── yime.IME (输入法核心逻辑)                          │
│    │     ├── nativeBackend (librime cgo 封装)             │
│    │     ├── testBackend (测试用模拟后端)                  │
│    │     └── 独立工具调度器                                │
│    └── rime.dll (librime, 动态加载 via syscall.NewLazyDLL)│
├──────────────────────────────────────────────────────────┤
│  独立工具进程 (Go 编译的 Win32 GUI)                       │
│    ├── server.exe 同目录下的工具可执行文件                 │
│    │     ├── settings-tool.exe      设置工具              │
│    │     ├── diagnostics-tool.exe   诊断工具              │
│    │     ├── lexicon-manager.exe    词库管理              │
│    │     ├── reverse-lookup.exe     反查编码              │
│    │     ├── tool-hub.exe           工具箱                │
│    │     ├── system-lexicon-audit.exe  系统词库审查       │
│    │     └── blocklist-manager.exe  用户屏蔽词表         │
│    └── 语言栏/工具箱通过 manifest 以 run_executable 启动   │
└──────────────────────────────────────────────────────────┘
```

### 1.2 通信协议

**PIME TSF → Go server**：`<client_id>|<JSON>`

请求方法：
- `init` / `destroy` — 会话生命周期
- `filterKeyDown` / `filterKeyUp` — 按键过滤
- `onKeyDown` / `onKeyUp` — 按键处理
- `onCommand` — 语言栏命令
- `onCompositionTerminated` — 组字终止
- `onActivate` / `onDeactivate` — 激活/停用
- `selectCandidate` — 候选选择

**Go server → PIME TSF**：`PIME_MSG|<client_id>|<JSON>`

响应字段：
- `compositionString` — 组字区文本
- `candidateList` — 候选列表
- `showCandidates` — 是否显示候选窗
- `candidatePageSize` — 候选页大小
- `candidatePageStart` — 当前页起始位置
- `langBarButtons` — 语言栏按钮定义
- `commitString` — 上屏文本

---

## 2. 关键机制

### 2.1 按键状态追踪（keysDown）

替代旧的 `lastKeyDownCode`+`lastKeySkip` 计数器方案，解决重复按键抑制吞键问题。

```
onKeyDown(keyCode)
    │
    ├── keysDown[keyCode] 已存在？
    │     ├── 是 → 忽略（重复 key-down，不传给 Rime）
    │     └── 否 → keysDown[keyCode] = true，传给 Rime
    │
onKeyUp(keyCode)
    │
    └── keysDown[keyCode] = false（清除追踪）
```

**设计要点**：
- 基于 key-down/key-up 配对追踪，而非计数器
- 避免快速连打同一键时丢失有效按键
- `keysDown map[int]bool` 在 `IME` 结构体中定义

### 2.2 回车键原始编码上屏（pendingRawCommit）

解决组字时回车键被静默吞掉的问题。

```
onKeyDown(VK_RETURN) during composition
    │
    ├── Rime 接受回车 → 正常提交流程
    │
    └── Rime 拒绝回车 (backendRet == false)
          │
          ├── 旧行为: handled=true，静默吞掉
          │
          └── 新行为: pendingRawCommit = compositionString
                      handled=true
                      下次 onKeyUp 时 commit pendingRawCommit
```

**设计要点**：
- `pendingRawCommit string` 字段存储待上屏的原始编码
- 在 `onKeyUp` 中检查并提交，避免在 key-down 回调中触发二次提交
- 非组字状态下回车正常穿透（`handled=false`）

### 2.3 组字状态保存与重放

解决候选项数变更/方案切换时丢失当前输入的问题。

```
reloadBackendSessionForSchema()
    │
    ├── 1. 保存当前组字内容
    │     savedComposition = ime.getCompositionString()
    │
    ├── 2. DestroySession + ClearComposition
    │
    ├── 3. 重建会话 (CreateSession + ApplySchema)
    │
    └── 4. 逐字重放组字内容
          for _, ch := range savedComposition {
              ProcessKey(ch)
          }
```

**设计要点**：
- 重放使用 `ProcessKey` 逐字符输入，确保 Rime 状态一致
- 重放失败时静默处理（不阻断主流程）
- 仅在组字状态非空时执行重放

### 2.4 Rime 初始化重试机制

替代 `sync.Once`，解决初始化失败后不可恢复的问题。

```
ensureRimeInitialized()
    │
    ├── rimeInitMu.Lock()
    │
    ├── rimeInitDone == true && rimeInitOK == true?
    │     └── 是 → 直接返回（成功初始化过）
    │
    ├── rimeInitDone == true && rimeInitOK == false?
    │     └── 重新尝试初始化（允许重试）
    │
    └── rimeInitDone == false?
          └── 首次初始化
                │
                ├── Initialize(traits)
                │
                ├── 成功 → rimeInitOK = true
                └── 失败 → rimeInitOK = false
                │
                └── rimeInitDone = true
                      （无论成功失败都标记 done，
                        允许下次重试）
```

**设计要点**：
- `rimeInitMu sync.Mutex` — 保护初始化过程
- `rimeInitDone bool` — 是否已尝试过初始化
- `rimeInitOK bool` — 初始化是否成功
- 移除了 `IME.Init` 中的用户目录预检（该预检导致用户目录不存在时跳过 `Initialize`）

### 2.5 候选项数同步链

AGENTS.md 重点保护的机制，三层状态必须保持一致：

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Rime 引擎       │     │  Go 运行时        │     │  配置文件            │
│  rimeState.      │     │  ime.             │     │  default.custom.yaml│
│  PageSize        │────▶│  candidatePageSize│────▶│  menu/page_size     │
│                  │     │                   │     │  schema.custom.yaml │
│  (权威来源)       │◀────│  (中间缓存)       │◀────│  (持久化)           │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
        ▲                        │
        │                        ▼
        │              ┌──────────────────┐
        └──────────────│  applyStateTo    │
                       │  Response()      │
                       │  (每次按键回写)   │
                       └──────────────────┘
```

**同步时机**：

| 时机 | 方向 | 函数 |
|------|------|------|
| Init | 文件 → Go | `readPageSizeFromCustomConfig` |
| 每次按键 | Rime → Go | `applyStateToResponse` 中 `state.PageSize → ime.candidatePageSize` |
| 候选项数变更 | Go → 文件 → Rime | `setCandidatePageSize` 写 YAML → 部署 → 会话重建 |
| 会话重建后 | Rime → Go | `backend.State().PageSize` 读回确认 |

**已知限制**：
- 无候选时 `State().PageSize` 返回 0，读回失败（仅记录日志，不阻断）
- YAML key 必须同时支持引号和非引号形式（`menu/page_size` 和 `"menu/page_size"`）

### 2.6 候选分页权

```
                    UsesBackendCandidatePaging()
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
        nativeBackend                testBackend
        返回 true                    返回 false
              │                         │
              ▼                         ▼
     Rime 引擎拥有分页权         Go 侧自行分页
     候选列表完整返回           按 candidatePageSize 切片
     翻页由 Rime 处理           翻页由 Go 处理
```

**约束**：`nativeBackend` 必须返回 `true`，Go 侧不可对原生 Rime 会话做候选切片。

### 2.7 candidatePageStart 重置策略

```
processKey()
    │
    ├── backendRet == true（Rime 接受按键）
    │     └── ime.candidatePageStart = 0（重置翻页位置）
    │
    └── backendRet == false（Rime 拒绝按键）
          └── 不重置 candidatePageStart（保留翻页位置）
```

**设计要点**：
- 旧逻辑在 `processKey` 中无条件重置，导致无效按键丢失翻页位置
- `applyStateToResponse` 在候选列表为空时仍会重置（这是合理的）

### 2.8 语言栏命令分发

```
TSF 语言栏点击
    │
    ▼
onCommand(req)
    │
    ├── req.ID (整数) ──→ commandIDFromRequest(req)
    │     └── 回退链: req.ID → req.Data.commandId → req.Data.id
    │
    ▼
命令 ID 路由
    │
    ├── 3200-3222: Yime 专有命令 (方案/反查/词库/帮助)
    ├── 70-79: 候选设置 (排列/项数)
    ├── 80-89: 宿主集成 (中西文/简繁/标点/全半角)
    └── 90+: 维护命令 (重新部署/同步/打开目录)
    │
    ▼
commandShouldRefreshState(ID)?
    │
    ├── 在黑名单中 → 跳过状态刷新
    │     (避免 TSF 回调中触发 Rime 操作)
    │
    └── 不在黑名单中 → 刷新 Rime 状态到响应
```

**命令 ID 分配**：

| 范围 | 用途 | 示例 |
|------|------|------|
| 3200 | 方案切换 | ID_YIME_VARIABLE=3220, ID_YIME_FULL=3221, ID_YIME_SHORTHAND=3222 |
| 70-74 | 反查显示 | ID_REVERSE_LOOKUP_KEY_SEQUENCE=70 |
| 75 | 候选排列 | ID_CANDIDATE_LAYOUT_TOGGLE=75 |
| 76-80 | 候选项数 | ID_CANDIDATE_PAGE_SIZE_5=76 ~ ID_CANDIDATE_PAGE_SIZE_9=80 |
| 81-89 | 宿主集成 | 中西文/简繁/标点/全半角 |
| 90+ | 维护 | 重新部署/同步/打开目录/帮助/词库 |

**黑名单设计**：
- 旧方案使用白名单（列出所有不需要刷新的命令），维护负担大
- 新方案改为黑名单，只列出 11 个需要刷新状态的命令
- 新增命令默认不刷新，需显式加入黑名单才刷新

### 2.9 用户消息反馈（showUserMessage）

为关键操作提供用户可见的反馈。

```
操作执行
    │
    ├── 成功 → showUserMessage("音元输入法", "操作成功提示")
    │
    └── 失败 → showUserMessage("音元输入法", "操作失败提示")
    │
showUserMessage(title, message)
    │
    ├── Windows: MessageBoxW (MB_ICONINFORMATION / MB_ICONERROR)
    └── Stub: log.Printf (测试环境)
```

**覆盖的操作**：
- `openPath` — 打开目录/文件
- `copyTextToClipboard` — 复制到剪贴板
- `startSafeRimeRedeploy` — 确认后排队外部后台构建，校验当前方案并发送纯 redeploy 通知
- `syncBackendUserData` — 同步用户数据
- `selectSchema` — 切换方案
- `setCandidatePageSize` — 设置候选项数

**panic recover 保护**：所有调用 `showUserMessage` 的函数都包裹在 `defer recover()` 中，防止消息弹窗本身崩溃导致整个输入法进程退出。

### 2.10 反查注释占位符

```
joinRuneLookup(runes)
    │
    ├── 每个字符查找编码
    │     ├── 找到 → 拼接编码
    │     └── 未找到 → 拼接 "?" 占位符
    │
    └── 返回完整注释字符串

lookupStandardPinyin(codes)
    │
    ├── codes 含 "?" ?
    │     └── 是 → 逐字符拆分查找拼音
    │           （避免整串查找失败导致整行注释消失）
    │
    └── 否 → 整串查找拼音
```

### 2.11 用户词库跨方案同步

```
applyUserLexicon()
    │
    ├── 读取 yime_user_phrases.txt
    │
    ├── 为每种模式生成独立词库文件
    │     ├── custom_phrase_variable.txt  → yime_variable.schema.yaml 引用
    │     ├── custom_phrase_full.txt      → yime_full.schema.yaml 引用
    │     └── custom_phrase_shorthand.txt → yime_shorthand.schema.yaml 引用
    │
    └── 每种 schema 使用独立的 user_dict
          ├── yime_variable.schema.yaml → user_dict: custom_phrase_variable
          ├── yime_full.schema.yaml     → user_dict: custom_phrase_full
          └── yime_shorthand.schema.yaml → user_dict: custom_phrase_shorthand
```

**设计要点**：
- 旧方案只重建当前方案的词库，切换方案后用户词丢失
- 新方案为三种模式各生成独立的 `custom_phrase_{mode}.txt`
- 三种 schema 各自引用对应的 `user_dict`，互不干扰
- 每次应用词库都从安装目录同步三套 `yime_{mode}.schema.yaml` 到用户目录，再运行 Rime build；升级遗留 schema 不会继续引用旧 `custom_phrase`
- 数字标调拼音是用户词编码真源。多音字的逐字拼接可能列出多个编码，只有与用户填写拼音对应的编码会命中该用户词

### 2.12 Rime 部署流程

```
rimeDeploy(traits, datadir, userdir, appname, fullcheck)
    │
    ├── 1. Init(traits) — 初始化 Rime 运行时
    │      ⚠️ 不能把 DeployConfigFile 移到 initialize 之前
    │
    ├── 2. startMaintenance(fullcheck) — Rime 内置部署
    │      └── joinMaintenanceThread() — 等待完成
    │
    ├── 3. 部署配置文件 (DeployConfigFile, key="config_version")
    │      ├── <datadir>/<appname>.yaml
    │      ├── <userdir>/<appname>.yaml
    │      └── <userdir>/default.custom.yaml
    │
    └── 4. 部署方案自定义文件 (DeployConfigFile, key="schema")
           └── <userdir>/*.custom.yaml (排除 default.custom.yaml)
```

### 2.13 独立工具调度

```
onCommand / 语言栏按钮
    │
    ├── 直接按钮（用户词库、反查编码、工具箱）
    │     └── startDetached(同目录 .exe, 参数)
    │
    └── 工具箱 (tool-hub.exe)
          ├── Go 生成 toolHubManifest JSON
          ├── 用户点击条目 → run_executable / open_path
          └── 子工具保持 hub 窗口不关闭，便于连续操作
```

**当前工具箱条目**（`yime_tool_catalog.go`）：

| ID | 标签 | 动作 |
|----|------|------|
| lexicon-manager | 词库管理 | `lexicon-manager.exe` |
| reverse-lookup-tool | 反查编码 | `reverse-lookup.exe` |
| system-lexicon-audit | 系统词库审查 | `system-lexicon-audit.exe` |
| user-blocklist-manager | 用户屏蔽词表 | `blocklist-manager.exe` |
| settings-tool | 设置工具 | `settings-tool.exe` |
| diagnostics-tool | 诊断工具 | `diagnostics-tool.exe` |
| settings-data / shared-data / help-* | 打开目录或帮助 HTML | `open_path` |

**设计要点**：
- 重 UI 不在 TSF/PIME 回调线程内绘制；语言栏只做轻量分发
- `go-backend/build.bat` 与安装包一并产出上述 `.exe`
- 反查工具保留多音字、即时搜索、加载进度与结果截断提示
- 设置和词库部署在后台 goroutine 执行，通过 `WM_APP` 回到 UI 线程
- 设置工具通过 `userbackup` 创建带版本清单和 SHA-256 校验的可移植快照；恢复前先生成安全快照，再调用部署器并分别通知设置与词库修订
- 成功后在跨进程锁保护下更新 `yime_runtime_change.json`；文件保存设置、词库和 redeploy 的独立累积修订号，连续通知不会互相覆盖；显式维护使用 `ScopeRedeploy`，不会伪称设置或词库已改变
- 每个活动 IME 会话独立记录已处理修订号，在下一次安全宿主请求前同步设置、清理词库缓存，并对已经由外部部署器构建的数据执行轻量会话重建；语言栏回调不再调用全局 `RimeFinalize/RimeRedeploy`。方案重选失败时销毁会话，避免静默停留在其他兜底方案

### 2.14 语言栏切换按钮

IME 列表显示名为「音元」。语言栏三个切换按钮使用**静态标签**，避免 Win10/11 上动态改文字引发按钮闪烁或错位：

| 按钮 ID | 标签 | 切换时行为 |
|---------|------|------------|
| switch-lang | 中西 | 仅更新图标（中文/西文） |
| switch-shape | 全半 | 仅更新图标（半宽/全宽） |
| candidate-layout | 横竖 | 仅更新图标（竖排/横排） |

`updateLangBarToggleButtons` 通过 `ChangeButton` 只下发 `Icon` 字段；`libIME2`/`PIMETextService` 侧批量 `refreshAppearance`，并按 remove → change → add 顺序应用按钮更新。

三个切换按钮不覆盖 `TF_LANGBARITEMINFO.ulSort`，也不使用实验性固定 GUID；排序和普通按钮身份由 TSF 宿主管理。仅 `windows-mode-icon` 保留 Windows 系统输入模式 GUID。

### 2.15 用户屏蔽词表

```
userblocklist.LoadSet(yime_blocklist.txt)
    │
    └── applyStateToResponse 过滤候选文本命中屏蔽词的条目
```

- 源文件由 `blocklist-manager.exe` 维护
- 过滤在组字有候选时生效；与 Rime 分页权无冲突

### 2.16 安装与 profile 维护

开发/重装脚本共享 `tools/pime-registry-cleanup.ps1`：

- 清理 CTF TIP 与用户 profile 残留
- `Unregister-PIMETextServiceDlls` / `Remove-PIMETextServiceRegistry`
- `Refresh-IME-Profiles.cmd` 用于 IME 显示名等 profile 变更后的刷新

`libIME2` 在 `AddLanguageProfile` 前先 `RemoveLanguageProfile`，使 `ime.json` 名称更新在 `regsvr32` 重注册后即可生效。

**反查工具实现**：
- `reverselookup.Load` 加载并缓存系统词库、用户词库、拼音映射和三种模式编码
- `loadDictLookupMulti` 保留同一词条的全部读音编码；`joinCharCodeLookupMulti` 支持逐字笛卡尔积
- `Index.SetMode` 切换当前编码列，`Index.Search` 同时支持精确匹配和包含匹配，最多返回 200 条
- Win32 顶部控件按“查询词条 / 输入框 / 包含匹配 / 方案 / 下拉框 / 查询”单排布局；结果、详情和状态区等宽，客户区由内容边界计算

---

## 3. 数据管线与文件

### 3.1 词典生成管线

词典由 `Yime-python-prototype` 项目生成，经多步管线到达 Go 后端：

```
BCC 语料库 (6频道字频+词频)
    │
    ├── merge_char_freq.py → merged_char_freq.txt (同字取max)
    └── merge_word_freq.py → merged_word_freq.txt (同词取max)

Unihan_Readings.txt (五列普通话字段)
    │
    └── build_all.py → unihan_readings.db (读音+合成频率)

source_pinyin.db (单字+词语拼音源)
    │
    ├── prototype_single_char_import.py → pinyin_hanzi.db
    └── prototype_phrase_import.py → pinyin_hanzi.db
          └── 词语无频率时默认 weight=1

blcu_word_frequency_import.py
    │
    ├── BCC 字频 → char_frequency_abs (BCC优先，否则Unihan合成阶梯)
    └── BCC 词频 → phrase_frequency (BCC优先，否则默认1)

runtime_codes_refresh.py --apply
    │
    ├── 重建 char_usage_profile (5档分层: common_high/low, special_high/low, rare)
    ├── 重建 char_modern_common_profile (BCC单字序位加成)
    ├── 重建 char_reading_prior (词语频率累积的字-读音先验)
    ├── 重建 runtime_candidates_materialized
    └── JSON 导出 → .generated/runtime_candidates.json

Go 后端
    │
    └── runtime_candidates.json → dict.yaml (Rime 词典格式)
```

**频率策略**：

| 场景 | 策略 | 说明 |
|------|------|------|
| 单字有 BCC 频率 | 直接使用 BCC count | 最小正值 6 |
| 单字无 BCC 频率 | Unihan 合成阶梯 (1-5) | 刻意低于 BCC 最低值 6，分层由 tier_sort_weight 保护 |
| 词语有 BCC 频率 | 直接使用 BCC count | — |
| 词语无 BCC 频率 | 默认 weight=1 | 排在候选列表底部，不影响正常使用 |

**合成阶梯**（BCC 无命中时取最高命中列）：

| Unihan 列 | 合成值 | 来源 |
|-----------|--------|------|
| kTGHZ2013 | 5 | 《通用规范汉字表》2013版 |
| kHanyuPinlu | 4 | 汉语拼音频率 |
| kXHC1983 | 3 | 《现代汉语词典》1983版 |
| kHanyuPinyin | 2 | 汉语拼音 |
| kMandarin | 1 | Mandarin 读音（含台版/方言遗留如 bong4/wong4） |

**sort_weight 计算公式**：

- 单字：`tier_sort_weight + modern_common_boost + reading_phrase_prior_boost + char_frequency_abs + reading_weight`
- 词语：`phrase_frequency`（无 BCC 频率时 = 1）

**项目分离现状**：`Yime-python-prototype`（数据生成）与 `Yime`（运行时）分属不同仓库，管线为手动执行。当前编码体系已固定，词典更新频率低，分离可接受。若管线成为瓶颈可考虑合并。

### 3.2 共享数据目录

`go-backend/input_methods/yime/data/`

| 文件 | 类型 | 说明 |
|------|------|------|
| `default.yaml` | Rime 配置 | 基础 schema_list、page_size、按键绑定、标点 |
| `yime_variable.schema.yaml` | Rime 方案 | 变长模式，user_dict: custom_phrase_variable |
| `yime_full.schema.yaml` | Rime 方案 | 等长模式，user_dict: custom_phrase_full |
| `yime_shorthand.schema.yaml` | Rime 方案 | 省键模式，user_dict: custom_phrase_shorthand |
| `yime_full.dict.yaml` | Rime 词典 | 唯一导入的等长真源及等长运行产物，468K 条 |
| `yime_variable.dict.yaml` | Rime 词典 | 由等长真源生成的变长运行产物，468K 条 |
| `yime_shorthand.dict.yaml` | Rime 词典 | 由等长真源生成的省键运行产物，468K 条 |
| `yime_lexicon_manifest.json` | 生成清单 | 源哈希、规则版本、条目数和三套输出哈希 |
| `yime_pinyin_codes.tsv` | 编码映射 | 数字标调拼音→等长码，两列共 1625 行；其余模式运行时推导 |
| `yime_pua_pinyin.json` | PUA 显示映射 | 候选注释的数字标调拼音→PUA 音元序列 |
| `fonts/YinYuan-Regular.ttf` | 候选字体 | 音元拼音模式使用的 PUA 字形 |
| `pinyin_normalized.json` | 拼音归一化 | 数字标调→带调拼音，1729 条 |
| `essay.txt` | 词频表 | 八股文 |
| `rime.dll` | 动态库 | librime 运行时 |
| `rime_deployer.exe` | 可执行文件 | 外部部署工具 |

### 3.2 用户数据目录

`%APPDATA%\PIME\Rime\`

| 文件 | 格式 | 说明 |
|------|------|------|
| `default.custom.yaml` | YAML | 用户方案选择 + page_size 覆盖 |
| `yime_variable.custom.yaml` | YAML | 变长方案自定义（如 page_size） |
| `yime_full.custom.yaml` | YAML | 等长方案自定义 |
| `yime_shorthand.custom.yaml` | YAML | 省键方案自定义 |
| `user.yaml` | YAML | Rime 用户状态（previously_selected_schema） |
| `yime_user_phrases.txt` | TSV | 用户词库源文件（词条\t数字标调拼音\t权重） |
| `custom_phrase_variable.txt` | TSV | 变长模式 Rime 格式用户词库 |
| `custom_phrase_full.txt` | TSV | 等长模式 Rime 格式用户词库 |
| `custom_phrase_shorthand.txt` | TSV | 省键模式 Rime 格式用户词库 |
| `yime_settings_state.json` | JSON | 独立 UI 偏好（反查模式、候选排列） |
| `yime_blocklist.txt` | 文本 | 用户屏蔽词表源文件 |
| `build/` | 目录 | Rime 编译缓存 |

### 3.3 日志

`%LOCALAPPDATA%\PIME\Logs\`

- `go_backend.log` — Go 后端主日志
- `go_backend.log.1` 至 `go_backend.log.5` — 自动轮转的历史日志；当前日志达到 10 MiB 时轮转，最多保留 5 份
- 命令 ID 解读、部署/重载信号、错误行

---

## 4. 构建系统

### 4.1 C++/Rust 构建

```powershell
# 需要 VS 2022 + Rust i686-pc-windows-msvc
cmd /c build.bat
```

产物：`build/PIMELauncher.exe`, `build/PIMETextService.dll`

### 4.2 Go 后端构建

```powershell
cd go-backend
cmd /c build.bat
```

产物：`build/go-backend/server.exe`、`build/go-backend/*.exe`（工具链）、`build/go-backend/input_methods/`

本地 ad-hoc 构建落在 `go-backend/*.exe` 时已被 `.gitignore` 忽略。

Go 可执行文件版本取自仓库根目录 `version.txt`，并统一使用 `-trimpath -buildvcs=false`，避免无关提交改变未修改工具的文件哈希。8 个 Go EXE 统一嵌入 Yime 图标；打包脚本递归删除复制到输出目录的 `.go` 源码。发布流水线通过 `tools/sign-release.ps1`、NSIS `!finalize`/`!uninstfinalize` 和 `tools/verify-release-signatures.ps1` 覆盖内部二进制、安装器及卸载器；Smart App Control 的稳定发布必须使用受信任提供商签发的 RSA 证书，VERSIONINFO 不能替代签名。

NSIS 的必装主组件包含 PIMELauncher、`backends.json` 和完整 `go-backend` 包。标准安装只安装 Yime；旧 Python/Node 输入法属于可选的完整安装。读取新旧安装注册表时先写入临时寄存器，不能用空值覆盖 `InstallDir "$PROGRAMFILES32\YIME"`。

### 4.3 CI 流水线

`.github/workflows/ci.yaml`（触发分支：yime-stable）

```
checkout(含子模块) → Rust test → cmake build + CTest → go build + vet + 全量测试 → McBopomofo → 标签签名 → NSIS → 签名验证 → artifact
```

关键步骤：
- `windows-2022` 运行器
- **子模块必须先推到 fork remote**（`libIME2`、`McBopomofoWeb` 等），否则 checkout 失败
- 内联 vswhere + VsDevCmd 设置（非 ilammy/msvc-dev-cmd）
- CMake 构建用 `shell: cmd` 确保 VsDevCmd 环境持久
- rime-frost 数据获取步骤
- Go 纯逻辑包、原生工具布局及关键语言栏/Rime 回归测试
- NSIS 打包用 `pwsh` + `Set-Location`

---

## 5. 测试体系

### 5.1 单元测试

```powershell
cd go-backend
go vet ./...
go test . ./cmd/lexicon-manager ./cmd/reverse-lookup-tool ./cmd/settings-tool ./cmd/tool-hub ./input_methods/yime/reverselookup ./input_methods/yime/runtimechange ./input_methods/yime/settings ./input_methods/yime/systemlexicon ./input_methods/yime/toolhub ./input_methods/yime/userbackup ./input_methods/yime/userblocklist ./input_methods/yime/userlexicon
go test ./input_methods/yime -timeout 60s
go test ./input_methods/yime -run 'Test(NativeBackendKeepsRimeOwnedCandidatePaging|LanguageBarToggleButtonsUseStableTwoCharacterLabels|DeployCommandQueuesConfirmedExternalBuildWithoutNativeRedeploy|ApplyUserLexiconWritesAllThreeModes|ApplyUserLexiconRunsExternalBuildAndSchedulesReload)$'
```

CI 使用上述稳定回归集并执行 CTest。真实 Rime 测试仍由 `YIME_RUN_REAL_RIME_TESTS=1` 显式启用，避免普通单元测试共享本机 librime 全局状态。

关键守卫测试：

| 测试 | 保护目标 |
|------|----------|
| `TestNativeBackendKeepsRimeOwnedCandidatePaging` | 候选分页权 |
| `TestOnCommandAcceptsSubmenuItemIDForReverseLookupYimePinyin` | 子菜单命令解析 |
| `TestOnCommandIgnoresLegacyLowIDCollisionForReverseLookupYimePinyin` | 低 ID 碰撞忽略 |
| `TestSetCandidatePageSizeDoesNotRedeploy` | page_size 变更不触发完整 redeploy |
| `TestUpdateDefaultCustomPageSizeReplacesQuotedKey` | YAML 引号 key 兼容 |
| `TestLanguageBarToggleButtonsUseStableTwoCharacterLabels` | 语言栏稳定的双字静态切换标签 |
| `TestValidateEntryForAddRejectsSystemPhraseBeforePinyinValidation` | 添加时优先拒绝系统词库已有词条 |
| `TestAdjustWeightValue` | 权重步进、非法输入及整数边界 |
| `TestCenteredButtonRectsCentersGroupAndPreservesGaps` | 词库对话框按钮组居中与间距 |
| `TestNoticeTitleForFlags` | 词库提示统一使用中文标题和“确认”按钮 |
| `TestBuildUILayoutPlacesSearchControlsInOneRow` | 反查顶部控件顺序与无重叠 |
| `TestBuildUILayoutUsesEqualRowWidthsAndContentSizedWindow` | 反查各排等宽及内容决定窗体尺寸 |
| `TestBuildScriptKeepsGoExecutableHashesStableAndSupportsSigning` | 可复现 Go 构建与可信签名入口 |
| `TestBlockedCandidatesHiddenFromResponse` | 用户屏蔽词表过滤 |
| `TestBuildToolHubManifest*` | 工具箱 manifest 与可执行路径 |
| `TestReturnKeyCommitsRawInputDuringComposition` | 回车键原始编码上屏 |
| `TestRapidSameKey*` / `TestDuplicateKeyDown*` / `TestKeyUpClears*` | 重复按键抑制 |
| `TestSetCandidatePageSizePreservesComposition` | 候选项数变更保存组字状态 |
| `TestJoinRuneLookupPartialMissing` | 反查缺失字符占位符 |
| `TestApplyUserLexiconWritesAllThreeModes` | 用户词库跨方案同步 |
| `TestSyncRimeSchemasRefreshesAllModes` | 升级后的三套用户 schema 指向各自词库 |
| `TestReleasePipelineSignsPayloadInstallerAndUninstaller` | 安装路径兜底、Go 后端打包、标准组件和签名链 |

### 5.2 边界场景测试

| 场景 | 测试 |
|------|------|
| 并发按键/语言栏点击 | `TestConcurrentKeyAndCommandNoDataRace` |
| 大候选列表 Go 侧分页 | `TestLargeCandidateListGoSidePaging` |
| Unicode 边界（emoji、扩展汉字、代理对） | `TestUnicodeBoundaryEmojiAndExtendedHan` |
| 组字中切换方案失败 | `TestSchemaSwitchFailureDuringComposition` |
| 超长用户词组 | `TestLongUserPhraseLexiconBuild` |
| `onCompositionTerminated` 非强制/强制终止 | `TestCompositionTerminatedNonForced` / `Forced` |

### 5.3 运行时集成测试

`rime_runtime_test.go` — 需要真实 Rime 运行时

```powershell
# 需要真实 Rime 运行时；部分场景可能需要管理员权限
$env:YIME_RUN_REAL_RIME_TESTS = "1"
go test ./input_methods/yime/ -run TestReal -v -count=1
```

| 测试 | 验证内容 |
|------|----------|
| `TestRealRimeRedeployAppliesPageSize` | redeploy 使 page_size 生效 |
| `TestRealRimeExternalBuildAppliesPageSize` | 外部构建路径验证 |

### 5.4 本地管理员测试

```powershell
go-backend\run_admin_yime_tests.cmd
```

---

## 6. 编码体系参考

### 6.1 声母→键盘映射

| 声母 | 键 | 声母 | 键 | 声母 | 键 | 声母 | 键 |
|------|-----|------|-----|------|-----|------|-----|
| b | q | p | p | m | h | f | [ |
| d | w | t | . | n | y | l | b |
| g | ] | k | ' | h | n | | |
| zh | 7 | ch | 8 | sh | 9 | r | 0 |
| z | 6 | c | 5 | s | 4 | | |
| j | 3 | q | 2 | x | 1 | | |
| w | % | y | $ | | | | |

### 6.2 候选选择键

| 键 | 选择 | 说明 |
|----|------|------|
| Space | 第1个 | 最常用 |
| `` ` `` | 第2个 | 反引号 |
| `-` | 第3个 | 减号 |
| `=` | 第4个 | 等号 |
| `\` | 第5个 | 反斜杠 |
| 6-9 | 无快捷键 | 需鼠标点击（编码约束） |

### 6.3 alphabet 字符集

```
Variable: qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n564JKL7930z2SDMAN@!#
Full:     qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n5HD64JKL7930z2SMAN@!#
Shorthand:qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n564JKL7930z2SDMAN@!#
```

差异：Full 模式多了 `H` 和 `D`（零声母和 er 系需要大写字母）。
