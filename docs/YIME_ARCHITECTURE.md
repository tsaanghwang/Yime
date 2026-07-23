# 音元输入法架构文档

> 版本：2026-07-22
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
│    │     ├── yime-layout-designer.exe 高级布局            │
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
                      随后的 onKey 响应阶段 commit pendingRawCommit
```

**设计要点**：
- `pendingRawCommit string` 字段存储待上屏的原始编码
- `filterKeyDown` 只记录待提交内容；同一次请求随后进入 `onKey` 时检查并提交，避免在过滤阶段直接构造两次响应
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
onCommand / 语言栏按钮或设置菜单叶子命令
    │
    ├── 桌面语言栏直接按钮（用户词库、反查编码、工具中心）
    │     └── startDetached(同目录 .exe, 参数)
    │
    ├── 任务栏停靠时“设置”根级叶子（相同三个数字命令 ID）
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
| advanced-layout-designer | 高级布局 | `yime-layout-designer.exe` |
| lexicon-manager | 词库管理 | `lexicon-manager.exe` |
| reverse-lookup-tool | 反查编码 | `reverse-lookup.exe` |
| system-lexicon-audit | 系统词库审查 | `system-lexicon-audit.exe` |
| user-blocklist-manager | 用户屏蔽词表 | `blocklist-manager.exe` |
| settings-tool | 设置工具 | `settings-tool.exe` |
| diagnostics-tool | 诊断工具 | `diagnostics-tool.exe` |
| settings-data / shared-data / help-* | 打开目录或帮助 HTML | `open_path` |

**设计要点**：
- 重 UI 不在 TSF/PIME 回调线程内绘制；语言栏只做轻量分发
- 桌面语言栏和任务栏“设置”入口复用现有数字命令 ID；不增加子菜单深度，也不维护第二套工具生命周期
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

词典由 `Yime-python-prototype` 项目生成，经统一来源、候选整理和编码管线到达 Go 后端：

```
真实本地上游
    ├── Unihan 单字读音
    ├── pypinyin 词语读音
    ├── 万象字词读音及来源权重
    └── BCC 各原始分域字频/词频
          │
          └── build_lexicon_source_bundle.py
                └── source_lexicon.sqlite3
                      ├── 合规读音与来源/拒绝证据
                      ├── BCC 各分域原始计数及汇总频次
                      └── 万象权重（与 BCC 频次分列，不互相替代）

prototype_single_char_import.py / prototype_phrase_import.py
    │
    └── pinyin_hanzi.db
          ├── 单字频率：BCC 原始计数；未命中才使用 Unihan 合成阶梯
          └── 词语频率：BCC 原始计数；未命中保持 0，不伪造语料计数

输入候选整理覆盖层
    ├── BCC 频次只安排审查顺序
    ├── 词汇性、候选价值和动态可恢复性另行判定
    └── 不用万象权重或“已收录”反写 BCC 频次

runtime_codes_refresh.py --apply
    │
    ├── 重建 char_usage_profile (5档分层: common_high/low, special_high/low, rare)
    ├── 重建 char_modern_common_profile (BCC单字序位加成)
    ├── 重建 char_reading_prior (词语频率累积的字-读音先验)
    ├── 重建 runtime_candidates_materialized
    └── JSON 导出 → .generated/runtime_candidates.json

Windows handoff
    │
    ├── prepare_windows_yime_lexicon.ps1
    ├── yime_full.dict.yaml（唯一外部词典真源）
    ├── 四份同步拼音资产
    └── yime_handoff_manifest.json（数量、来源差异、SHA-256）
          │
          └── Go importer → full / variable / shorthand + yime_lexicon_manifest.json
```

**频率策略**：

| 场景 | 策略 | 说明 |
|------|------|------|
| 单字有 BCC 频率 | 直接使用 BCC count | 最小正值 6 |
| 单字无 BCC 频率 | Unihan 合成阶梯 (1-5) | 刻意低于 BCC 最低值 6，分层由 tier_sort_weight 保护 |
| 词语有 BCC 频率 | 直接使用 BCC count | — |
| 词语无 BCC 频率 | 保持 `phrase_frequency=0` | 只表示没有 BCC 语料计数；词典收录、万象权重和候选审查结论均不伪装成 BCC 频次 |

**合成阶梯**（BCC 无命中时取最高命中列）：

| Unihan 列 | 合成值 | 来源 |
|-----------|--------|------|
| kTGHZ2013 | 5 | 《通用规范汉字表》2013版 |
| kHanyuPinlu | 4 | 汉语拼音频率 |
| kXHC1983 | 3 | 《现代汉语词典》1983版 |
| kHanyuPinyin | 2 | 汉语拼音 |
| kMandarin | 1 | Mandarin 读音；已在运行时拼音资产中清理不受支持的非标准音节 |

**sort_weight 计算公式**：

- 单字：`tier_sort_weight + modern_common_boost + reading_phrase_prior_boost + char_frequency_abs + reading_weight`
- 词语：`phrase_frequency`（无 BCC 频率时为 `0`；其他来源证据与后续排序策略必须另列）

**项目分离现状**：`Yime-python-prototype`（数据生成）与 `Yime`（运行时）分属不同仓库。
跨仓库触发与 handoff 消费仍由维护者执行，但交付物已经收敛为带版本和哈希清单的原子 handoff，
不再逐个寻找或混搭来源资产。原型交付脚本默认还会试跑 Windows 派生；Windows 端正式导入
只接受一份等长词典，并确定性派生三套运行词典。目前尚无一条 Windows 命令自动校验清单并
复制全部四份辅助资产，因此消费阶段仍须按维护清单核验；
构建、安装、Rime 部署后还必须核对源码、安装目录和用户目录三层哈希。

### 3.2 共享数据目录

`go-backend/input_methods/yime/data/`

Rime 共享数据（包括 `default.yaml`、基础方案、词典、`essay.txt` 和
`opencc/`）是仓库内固定的发布资产。构建与 CI 只复制这份快照，不从
Weasel、本机目录或 Plum 临时补齐；缺件时直接失败。

| 文件 | 类型 | 说明 |
|------|------|------|
| `default.yaml` | Rime 配置 | 基础 schema_list、page_size、按键绑定、标点 |
| `yime_variable.schema.yaml` | Rime 方案 | 变长模式，user_dict: custom_phrase_variable |
| `yime_full.schema.yaml` | Rime 方案 | 等长模式，user_dict: custom_phrase_full |
| `yime_shorthand.schema.yaml` | Rime 方案 | 省键模式，user_dict: custom_phrase_shorthand |
| `yime_full.dict.yaml` | Rime 词典 | 唯一导入的等长真源及等长运行产物，当前 2,456,797 条 |
| `yime_variable.dict.yaml` | Rime 词典 | 由等长真源生成的变长运行产物，当前 2,456,797 条 |
| `yime_shorthand.dict.yaml` | Rime 词典 | 由等长真源生成的省键运行产物，当前 2,456,797 条 |
| `yime_lexicon_manifest.json` | 生成清单 | 源哈希、规则版本、条目数和三套输出哈希 |
| `yime_pinyin_codes.tsv` | 编码映射 | 数字标调拼音→等长码，当前 1729 条；其余模式运行时推导 |
| `yime_pua_pinyin.json` | PUA 显示映射 | 候选注释的数字标调拼音→PUA 音元序列 |
| `fonts/YinYuan-Regular.ttf` | 候选字体 | 音元拼音模式使用的 PUA 字形 |
| `pinyin_normalized.json` | 拼音归一化 | 数字标调→带调拼音，当前审计库存 1732 条 |
| `essay.txt` | 词频表 | 八股文 |
| `rime.dll` | 动态库 | librime 运行时 |
| `rime_deployer.exe` | 可执行文件 | 外部部署工具 |
| `rime_runtime.lock.json` | 运行时锁 | 固定 librime 版本、提交、插件版本及三个运行文件的 SHA-256 |

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

产物：`build/PIMELauncher/PIMELauncher.exe`、`build/PIMETextService/Release/PIMETextService.dll`

### 4.2 Go 后端构建

```powershell
cd go-backend
cmd /c build.bat
```

产物：`build/go-backend/server.exe`、`build/go-backend/*.exe`（工具链）、`build/go-backend/input_methods/`

本地 ad-hoc 构建落在 `go-backend/*.exe` 时已被 `.gitignore` 忽略。

Go 可执行文件版本取自仓库根目录 `version.txt`，并统一使用 `-trimpath -buildvcs=false`，避免无关提交改变未修改工具的文件哈希。9 个 Go EXE 统一嵌入 Yime 图标和 VERSIONINFO；打包脚本递归删除复制到输出目录的 `.go` 源码。发布流水线通过 `tools/sign-release.ps1`、NSIS `!finalize`/`!uninstfinalize` 和 `tools/verify-release-signatures.ps1` 覆盖内部二进制、安装器及卸载器；Smart App Control 的稳定发布必须使用受信任提供商签发的 RSA 证书，VERSIONINFO 不能替代签名。

NSIS 安装包只包含 PIMELauncher、`backends.json`、完整 `go-backend` 包和三架构 TSF DLL，不再提供组件选择页或旧 Python/Node 输入法。读取新旧安装注册表时先写入临时寄存器，不能用空值覆盖 `InstallDir "$PROGRAMFILES32\YIME"`。

### 4.3 CI 流水线

`.github/workflows/ci.yaml`：push 触发 `main`、`yime-stable`、`codex/**` 和 `v*` 标签；PR 触发 `main`、`yime-stable`。

```
`build-contract`、`rust-i686-host`、`native-build`、`go-tests`、`real-rime-tests`、`go-race-msys2` 并行执行 → `installer-package` 消费已验证原生产物 → `core-build` 聚合全部结果
```

关键步骤：
- `windows-2022` 运行器
- **活动子模块必须先推到 fork remote**（当前为 `libIME2`），否则 checkout 失败；退役的 Python/Node/McBopomofo/libchewing 历史源码不参与产品构建和安装
- 内联 vswhere + VsDevCmd 设置（非 ilammy/msvc-dev-cmd）
- CMake 构建用 `shell: cmd` 确保 VsDevCmd 环境持久
- 仓库内固定 Rime 共享数据及 librime 版本、哈希门禁
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
# CI 先用 go test -list 枚举并逐项确认关键测试名存在，再按同一名单执行。
go test ./input_methods/yime -run 'Test(NativeBackendKeepsRimeOwnedCandidatePaging|LanguageBarToggleButtonsUseStableTwoCharacterLabels|DeployCommandQueuesConfirmedExternalBuildWithoutNativeRedeploy|ApplyUserLexiconWritesAllThreeModes|ApplyUserLexiconRunsExternalBuildAndSchedulesReload)$'
```

分支保护应要求聚合作业 `core-build`，而不是已不存在的旧 `build` 作业。CI 将稳定回归集、CTest、Rust、race、真实 Rime 和安装器拆为独立作业。定向回归在执行前必须逐项校验测试名，避免重命名后 `go test -run` 因仍有其它匹配项而静默少跑。真实 Rime 作业通过 `tools/test-real-rime.ps1` 显式设置 `YIME_RUN_REAL_RIME_TESTS=1`，仍与普通单元测试隔离，避免共享 librime 全局状态。

关键守卫测试：

| 测试 | 保护目标 |
|------|----------|
| `TestNativeBackendKeepsRimeOwnedCandidatePaging` | 候选分页权 |
| `TestOnCommandAcceptsSubmenuItemIDForReverseLookupYimePinyin` | 子菜单命令解析 |
| `TestOnCommandIgnoresLegacyLowIDCollisionForReverseLookupYimePinyin` | 低 ID 碰撞忽略 |
| `TestSetCandidatePageSizeDoesNotRedeploy` | page_size 变更不触发完整 redeploy |
| `TestUpdateDefaultCustomPageSizeReplacesQuotedKey` | YAML 引号 key 兼容 |
| `TestLanguageBarToggleButtonsUseStableTwoCharacterLabels` | 语言栏稳定的双字静态切换标签 |
| `TestOnMenuReturnsSettingsMenu` | “设置”根级工具入口及“数据维护”分组 |
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

### 6.1 首音→键盘映射

首音分为实首音和虚首音：实首音对应非零声母，虚首音对应零声母。在《汉语拼音方案》的书写中，
零声母包括隔音符号 `'` 以及 `y`、`w` 三类起首形式，因此下表把三者都列为虚首音。

| 首音 | 键 | 首音 | 键 | 首音 | 键 | 首音 | 键 |
|------|-----|------|-----|------|-----|------|-----|
| b | b | p | p | m | - | f | [ |
| d | ] | t | t | n | n | l | \ |
| g | g | k | q | h | h | | |
| zh | 7 | ch | 8 | sh | 9 | r | 0 |
| z | 6 | c | 5 | s | 4 | | |
| j | 3 | q | 2 | x | 1 | | |
| w（虚） | = | y（虚） | y | `'`（虚） | ' | | |

### 6.2 候选选择键

| 键 | 选择 | 说明 |
|----|------|------|
| Space / Enter / Shift+1 | 第1个 | 三种等价首选操作 |
| Shift+2 | 第2个 | 候选窗标签显示为 `⇧2` |
| … | … | … |
| Shift+9 | 第9个 | 候选窗标签显示为 `⇧9` |

候选窗通过扩展协议 `setSelLabels` 显示 `⇧1`…`⇧9`，避免旧的裸数字标签误导用户直接按 Base 数字键。`setSelKeys` 仍作为旧宿主的兼容字段，实际选词由 Yime 的 Shift+数字按键处理完成。物理键盘 Shift 层对应的键面为 `! @ # $ % ^ & * (`；帮助和布局图应标明这些键面，但不宜直接把标点作为候选窗序号，因为连续标点的可读性和序号感较差。

与流行拼音输入法不同，Yime 不采用裸数字键选词：Base 层 `0`—`9` 十个数字键始终是音元编码的一部分，候选窗出现时也不改变含义。项目不规划“数字键在编码和选词之间切换”的可配置模式，以避免编码被候选状态截断；需要按序号选词时统一使用 Shift+1…Shift+9，Shift+0 不选词。

候选窗可见时，四方向键和 Enter 由 PIME C++ 客户端先行处理，不进入普通 Go `onKeyDown` 分支。`CandidateWindow::filterKeyEvent` 用方向键维护 `currentSel`，Enter/Space 设置选择结果；`PIMEClient::onKeyDown` 随后读取 `currentSel` 并通过 `selectCandidate(index)` 通知 Go 后端。因此方向键移动后的 Enter 确认按当前高亮索引生效，与 Go 层用于直接首选的 Enter 路径不冲突。

### 6.3 alphabet 字符集

```
Full:      1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG
Variable:  1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG
Shorthand: 1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG
```

三种 schema 使用同一套 57 字符白名单。码表导入器还会通过 `codemode.LayoutAlphabet`
拒绝布局外字符，避免出现“导入成功但无法击键输入”的词典。
