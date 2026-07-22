# 音元输入法开发路线图

> 单一等长真源重构已经完成。实施结果见
> [从三套码表回到一个真源](project/SINGLE_SOURCE_LEXICON_REFACTOR.md)，原阶段设计见
> [单一等长真源码表阶段准备](project/SINGLE_CANONICAL_LEXICON_PREPARATION.md)。
> 三套 Rime 字典继续保留为运行产物，但不再允许独立导入或人工维护。

> 版本：2026-07-20（候选标签与连续输入基线）
> 实施分支：`codex/windows-layout-trial-v1`
> 基线提交：`9dc88d37`（Shift 候选标签）、`30041975`（三模式连续输入）
> 配套文档：[项目综合评估](YIME_PROJECT_ASSESSMENT.md) | [可用性评估](YIME_USABILITY_ASSESSMENT.md) | [架构文档](YIME_ARCHITECTURE.md)

---

## 1. 当前状态

### 已完成里程碑

| # | 里程碑 | 提交 | 说明 |
|---|--------|------|------|
| 1 | 候选项数同步机制 | 1343632 | rimeState.PageSize 回读链 |
| 2 | 重复按键抑制吞键修复 | edd6e0ab | keysDown map 替代计数器 |
| 3 | 回车键组字时被吞修复 | ef52fe2a | pendingRawCommit 原始编码上屏 |
| 4 | 候选项数变更保存组字状态 | 1bf5063f | reloadBackendSessionForSchema 重放 |
| 5 | Rime 初始化失败可重试 | 3e24351d | sync.Mutex + 双标志替代 sync.Once |
| 6 | rimeDeploy schema custom 部署 | 423658c5 | *.custom.yaml glob 部署 |
| 7 | 语言栏排列方式简化 | a2b6923 | 一次点击切换横竖排 |
| 8 | CI 构建流水线修复 | d9d8a0ca | windows-2022 + vswhere |
| 9 | 部署/打开/剪贴板操作用户反馈 | e2353639 | showUserMessage + panic recover |
| 10 | 反查注释遇生僻字占位符 | 7800d552 | joinRuneLookup 用 ? 占位 |
| 11 | 用户词库跨方案同步 | fec6b129 | 三模式独立 custom_phrase + user_dict |
| 12 | 反查工具重设计 | e7a3a461 | 多音字、即时搜索、加载进度、截断提示 |
| 13 | 低优先级问题 #6-#10 全部修复 | dce1295b | 硬编码路径、死代码、YAML 注释、翻页重置、命令黑名单 |
| 14 | 未覆盖场景测试 | 526c5a2c | 并发、分页、Unicode、方案切换、超长词组、终止 |
| 15 | 工具链补充 | 63ef77c5 | DELETE/IMPORT 词库、即时搜索 debounce、工具箱中文化 |
| 16 | cSpell 词表扩展 | 16eda9b | 60+ 项目专有词 |
| 17 | 子模块推送 | 32eaf662 | libIME2 + McBopomofoWeb 指向 fork 且先推送子模块再推主仓库 |
| 18 | 原生 Win32 工具链 | dd68a47a | settings/diagnostics/lexicon/reverse-lookup/tool-hub 等 `.exe` |
| 19 | 移除 PowerShell 启动器 | 2f7c9b44 | 工具箱改 `run_executable`，删除 PS 独立脚本 |
| 20 | 系统词库审查工具 | fd3edfc0 | `system-lexicon-audit.exe` 只读扫描与导出 |
| 21 | 用户屏蔽词表 | 0518d6fd | `blocklist-manager.exe` + 运行时候选过滤 |
| 22 | 语言栏切换稳定性 | f2b3b04c | 静态双字标签（中西/全半/横竖）+ 仅图标更新 |
| 23 | libIME2 语言栏/注册表 | 2f4f5659 | `refreshAppearance`、profile 重注册、按钮更新顺序 |
| 24 | 注册表清理脚本 | eacb769a | `pime-registry-cleanup.ps1`、`Refresh-IME-Profiles.cmd` |
| 25 | IME 列表名与开发环境 | fc507057 | 列表显示名「音元」；`.gitignore` 忽略 `go-backend/*.exe` |
| 26 | 反查工具布局统一 | ac6d88bf | 顶部控件单排、各内容排等宽、窗体按内容定尺寸 |
| 27 | 词库管理对话框统一 | e98704c8 | 标签自适应、按钮组居中、所有系统 `OK/Yes/No` 改为中文选择 |
| 28 | Smart App Control 构建稳定性 | ee2c51d7 | 稳定版本、`-trimpath -buildvcs=false`、可选可信签名 |
| 29 | Go 回归测试进入 CI | 847bc40a | 原生工具、词库逻辑、语言栏与 Rime 分页守卫 |
| 30 | 竞态检测纳入验证基线 | ab243ae7 | 配置 MSYS2 GCC；`IME` 入口互斥锁；`TestConcurrentKeyAndCommandNoDataRace` 在 `-race` 下绿色 |
| 31 | 反查测试 fixture 跟上真源重构 | ab243ae7 | `full` 列改为 4 倍数等长码，恢复 reverselookup 包测试 |
| 32 | 安全数据维护与真实宿主验证 | 196c326b | 后台重新部署、独立修订号、嵌套 `data.id`；2026-07-14 安装态逐项点击通过 |
| 33 | 静态与 CI 门禁收口 | 本轮 | Win32 消息结构复制通过 `go vet`；关键测试名先枚举校验；race 入口可重复 |
| 34 | 原生架构与打包门禁 | 本轮 | 拒绝伪 Win32 CMake 缓存；核对 x86/x64/ARM64 PE machine type；只打包带 `ime.json` 的运行时目录 |
| 35 | Go 演示输入法退役 | 本轮 | 删除 meow/simple_pinyin/fcitx5 生产包与默认回退；协议测试改用专用 fixture；NSIS 安全清理旧空目录 |
| 36 | Shift 感知候选标签 | 9dc88d37 | 候选窗显示 `⇧1`—`⇧9`；选择键仍为 Shift+1—9；物理标点键面只用于帮助和布局图 |
| 37 | 三模式连续输入与自动分词 | 30041975 | 三套方案启用 `enable_sentence` 和 `sentence_over_completion`；变长、省键派生保留虚首音作为零声母音节边界 |

### 已确立的编码与交互基线（不得随意回退）

- 2026-07-18 的布局试验已经释放旧候选键，并改用 Shift+1—9；这不是待清理的临时代码；
- Base 数字键仍属于编码，只有 Shift+数字键用于选择候选；
- 与流行拼音输入法不同，Yime 明确不采用裸数字键选词。Base 层 `0`—`9` 十个数字键全部用于编码，Shift+0 也不选词；这是编码体系和产品交互原则，不是尚待解决的兼容问题，也不提供“数字键在编码/选词间切换”的模式；
- 候选窗显示 `⇧1`—`⇧9`，不再用裸数字暗示 Base 数字可选词；帮助/布局图另列物理键面 `! @ # $ % ^ & * (`，但不把标点用作候选窗序号；
- `setSelLabels` 只负责候选窗显示，`SetSelKeys` 只为旧宿主兼容；不得把标签文本误当成真实按键绑定，也不得改回裸 `1`—`9`；
- 候选项数继续支持 5—9；九个 Shift+数字选择键与九个标签已经覆盖上限，不再规划把默认值或上限强制缩到 5；
- 57 个 Yinyuan ID 使用 47 个 Base 键和 11 个 Shift 键，反引号 Base 键暂留空。
- 等长词典是唯一可维护真源；变长、省键词典是生成物，不得手工修补；
- 从等长码派生变长、省键码时必须保留虚首音 `'`（语义 ID `N12`）。它是零声母音节边界，不是可删除的冗余字符；
- 三套 schema 必须同时保留 `enable_sentence: true` 与 `sentence_over_completion: true`。只启用前者会被词条补全候选压住，实际仍不能稳定生成整句候选；
- 真实 librime 验收序列 `]s8u\e4fa7J9wo` 必须能产生“打出了三只手”。

### 两次大改的验收边界

| 改动 | 正确职责划分 | 必须保留的验证 |
|------|--------------|----------------|
| Shift 候选标签 | Go 后端发送多字符 `setSelLabels`；PIMETextService 解析；libIME2 绘制完整标签；Yime 按键逻辑处理 Shift+数字 | `TestCandidateSelectionUsesDefaultKeysAndShiftDigits`、协议序列化测试、libIME2 多字符标签构建验证 |
| 连续输入与自动分词 | `codemode` 和布局重编码器保留虚首音；生成器重建两套派生词典；schema 让整句候选排在补全前 | `TestAllSchemasEnableSentenceComposition`、`TestReencodePreservesVirtualInitialAsSyllableBoundary`、`TestRealRimeAllSchemasComposeSentence`、`go test ./...` |

上述两项横跨协议、原生候选窗、码表生成和 Rime 配置。后续修改不能只改其中一层，也不能因单元测试通过就删除真实 librime 验收。

---

## 2. 开发流程图

### 2.1 问题修复流程

```
发现问题
    │
    ▼
确认复现路径 ──── 无法复现 ──→ 关闭或标记"待观察"
    │
    ▼ 可复现
    │
编写失败测试 ──── 测试通过 ──→ 测试有误，修正测试
    │
    ▼ 测试失败
    │
实现修复
    │
    ▼
测试通过？ ──── 否 ──→ 返回实现修复
    │
    ▼ 是
    │
go vet / go build ──→ 失败 ──→ 修正代码
    │
    ▼ 通过
    │
AGENTS.md 约束检查 ──→ 违反 ──→ 重新设计
    │                (候选分页权/YAML key/
    ▼                page_size 同步链/子菜单命令)
提交（不推送）
    │
    ▼
本地安装验证 ──── 验证项：
    │              1. server.exe 时间戳已更新
    │              2. rime_deployer.exe 时间戳已更新
    │              3. PIMELauncher + server 进程已重启
    │              4. 在宿主应用中实际操作复现
    ▼
验证通过？ ──→ 否 ──→ 返回实现修复
    │
    ▼ 是
    │
推送到 origin/<当前工作分支>
```

### 2.2 功能开发流程

```
需求提出
    │
    ▼
设计评审 ──── 涉及语言栏/候选窗/TSF 回调？
    │              │
    │              ▼ 是
    │           新增回归测试保护
    │              │
    ▼              ▼
选择实现路径
    │
    ├── 轻量命令（语言栏分发）──→ onCommand + commandShouldRefreshState
    │
    ├── 独立工具窗口 ──→ Go 编译的 Win32 `.exe` + 工具箱 manifest 注册
    │
    └── Rime 配置变更 ──→ YAML 读写 + DeployConfigFile + 会话重建
    │
    ▼
实现 + 测试
    │
    ▼
AGENTS.md 约束检查
    │
    ▼
提交 → 本地安装验证 → 推送
```

### 2.3 候选项数变更流程（当前实现）

```
用户点击候选项数菜单项
    │
    ▼
onCommand(ID_CANDIDATE_PAGE_SIZE_5 + offset)
    │
    ▼
setCandidatePageSize(size)
    │
    ├── 1. 写入 default.custom.yaml (updateDefaultCustomPageSize)
    ├── 2. 部署 default.custom.yaml (deployDefaultCustomConfig)
    ├── 3. 写入 schema.custom.yaml (writeSchemaCustomPageSize)
    ├── 4. 部署 schema.custom.yaml (deploySchemaCustomConfig)
    ├── 5. 部署 schema.yaml (deploySchemaConfig)
    ├── 6. 运行 rime_deployer.exe (runRimeExternalBuild)
    ├── 7. 设置 pendingSchemaRedeploy
    ├── 8. 重建会话 (reloadBackendSessionForSchema)
    │       └── 保存并重放组字状态 ✅
    └── 9. 读回 PageSize (backend.State().PageSize)
            └── 无候选时 PageSize=0，读回失败（仅记录日志）
    │
    ▼
下次按键时执行 pendingSchemaRedeploy
```

---

## 3. 路线图

### Phase 1：关键可用性修复 ✅ 已完成

| # | 任务 | 提交 | 回归测试 |
|---|------|------|----------|
| 1.1 | 修复回车键行为 | ef52fe2a | `TestReturnKeyCommitsRawInputDuringComposition`, `TestReturnKeyPassesThroughWhenNotComposing` |
| 1.2 | 修复重复按键抑制 | edd6e0ab | `TestRapidSameKey*`, `TestDuplicateKeyDown*`, `TestKeyUpClears*` |
| 1.3 | 候选选择键扩展 | 9dc88d37 | `TestCandidateSelectionUsesDefaultKeysAndShiftDigits`；Base 数字输入与 Shift+数字选词并存 |
| 1.4 | 候选项数变更保存组字状态 | 1bf5063f | `TestSetCandidatePageSizePreservesComposition` |

---

### Phase 2：用户体验改善 ✅ 已完成

| # | 任务 | 提交 | 回归测试 |
|---|------|------|----------|
| 2.1 | 关键操作失败用户提示 | e2353639 | 手动验证 |
| 2.2 | 反查缺失字符占位符 | 7800d552 | `TestJoinRuneLookupPartialMissing`, `TestLookupStandardPinyinPartialMissing` |
| 2.3 | 用户词库跨方案同步 | fec6b129 | `TestApplyUserLexiconWritesAllThreeModes`, `TestRimeUserLexiconPathPerMode` |
| 2.4 | 反查工具加载进度提示 | e7a3a461 | 手动验证 |
| 2.5 | 反查搜索结果截断提示 | e7a3a461 | 手动验证 |
| 2.6 | 词库删除/导入功能 | 63ef77c5 | 手动验证 |

---

### Phase 3：代码质量与健壮性 ✅ 已完成

| # | 任务 | 提交 | 说明 |
|---|------|------|------|
| 3.1 | 移除硬编码开发路径 | dce1295b | 删除 `C:\dev\librime\` 路径 |
| 3.2 | 移除死代码 | dce1295b | 删除未调用的 `remapYimeCandidateSelectionKey` |
| 3.3 | 命令刷新改为黑名单 | dce1295b | 只列出需刷新的 11 个命令 |
| 3.4 | 并发安全测试 | 526c5a2c | `TestConcurrentKeyAndCommandNoDataRace` |
| 3.5 | Unicode 边界测试 | 526c5a2c | emoji、扩展汉字、代理对 |
| 3.6 | YAML 行内注释支持 | dce1295b | `parseMenuPageSizeValue` 剥离 `#` 注释 |
| 3.7 | candidatePageStart 仅按键生效时重置 | dce1295b | `backendRet==true` 时才重置 |

---

### Phase 4：功能增强 — 部分完成

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 4.2 | Rime 初始化失败可重试 | ✅ 3e24351d | sync.Mutex + 双标志 |
| 4.3 | 词典噪声清理 | 待做 | 审查权重=1 的极低频词（优化，非缺陷） |
| 4.4 | 非标准音节清理 | ✅ 2a3f51d4 + 后续显示映射清理 | `bong4`/`wong4` 已从规范化拼音、编码表、音节分解和 PUA 显示映射移除 |
| 4.5 | 词库导入功能 | ✅ 63ef77c5 | DELETE/IMPORT 接入词库管理器 |
| 4.6 | 反查工具即时搜索 | ✅ e7a3a461 | 500ms debounce 即时搜索 |
| 4.7 | 用户屏蔽词表 | ✅ 0518d6fd | 运行时过滤 + `blocklist-manager.exe` |
| 4.8 | 系统词库审查 | ✅ fd3edfc0 | 只读扫描已安装系统词库 |
| 4.9 | 原生 Win32 工具链 | ✅ dd68a47a | 设置/诊断/词库/反查/工具箱等独立 `.exe` |
| 4.10 | 语言栏切换稳定性 | ✅ 73b74e99 | 静态切换标签，切换时只更新图标 |
| 4.11 | 三模式连续输入与自动分词 | ✅ 30041975 | 等长、变长、省键均优先给出整句组句；派生码不再删除虚首音；真实 librime 测试覆盖普通、零声母及“打出了三只手”连续输入 |
| 4.12 | Shift 感知候选标签 | ✅ 9dc88d37 | `setSelLabels` 显示 `⇧1`—`⇧9`；真实选择键保持 Shift+数字；标点键面只写入帮助和布局图 |

---

### Phase 5：后续改进（待规划）

Phase 5 原则上不属于 1.4.0 发布收口范围。候选页默认是 5 项、可设置为 5—9 项，Shift+1—9 已为所有可见候选提供直选键，因此“候选大于 5 不好选”已经解决，不再保留“强制限制为 5”的旧提案。Base 层 `0`—`9` 十个数字键全部用于编码，裸数字键选词已经确定不采用，也不是未来任务。候选排序微调等事项需要先形成数据口径和验收基线；在专项规划获批前不得顺手修改实现或词典数据。

| # | 任务 | 说明 | 前置条件 |
|---|------|------|----------|
| 5.2 | 方向键移动候选光标 | ✅ 已完成 | PIME 候选窗接管四方向键并维护 `currentSel`，Enter 通过 `selectCandidate(index)` 确认高亮候选；2026-07-22 实测“他日”通过 |
| 5.4 | 词语字频回退排序 | 无 BCC 词频时用组成字频率估计，改善 weight=1 词语间排序 | Yime-python-prototype 管线 |

---

## 4. 里程碑时间线

```
2026-07 W1-W2
├── Phase 1 ✅ 关键可用性修复
│   ├── 1.1 回车键行为 ✅
│   ├── 1.2 重复按键抑制 ✅
│   ├── 1.3 候选选择键扩展 ✅
│   └── 1.4 组字状态保存 ✅
│
2026-07 W3-W4
├── Phase 2 ✅ 用户体验改善
│   ├── 2.1 失败提示 ✅
│   ├── 2.2 反查占位符 ✅
│   ├── 2.3 词库跨方案同步 ✅
│   ├── 2.4-2.5 反查工具改进 ✅
│   └── 2.6 词库删除/导入 ✅
│
2026-07 W5-W6
├── Phase 3 ✅ 代码质量与健壮性
│   ├── 3.1-3.2 代码清理 ✅
│   ├── 3.3 命令黑名单 ✅
│   ├── 3.4-3.5 测试增强 ✅
│   └── 3.6-3.7 边界修复 ✅
│
2026-07 W7-W8
├── Phase 4 延续
│   ├── 4.7-4.10 工具链与语言栏 ✅
│   ├── 4.11 三模式连续输入与自动分词（30041975）✅
│   ├── 4.12 Shift 感知候选标签（9dc88d37）✅
│   ├── 4.3 词典噪声清理（待做，优化项）
│   └── 4.4 非标准音节清理 ✅
│
├── 基础设施
│   ├── 子模块 fork 推送流程 ✅
│   ├── 注册表/profile 清理脚本 ✅
│   ├── CI checkout 子模块修复 ✅
│   ├── Win32 PIMELauncher 重建链路修复（Corrosion v0.6.1 + i686 工具链锁定）✅
│   └── 安装态验证清单跑完留痕（2026-07-12，仅剩签名）✅
│
待规划
└── Phase 5 后续改进
    ├── 5.2 候选窗方向键导航 ✅
    └── 5.4 词语字频回退排序
```

---

## 5. AGENTS.md 约束速查

开发时必须遵守的约束（详见 `AGENTS.md`）：

| 约束 | 说明 | 违反后果 |
|------|------|----------|
| 候选分页权不可更改 | `UsesBackendCandidatePaging()` 必须返回 `true` | 候选窗行为异常 |
| 禁止 Go 侧候选切片 | 不能通过 Go 切片强制控制可见候选数 | 与 Rime 状态不一致 |
| page_size 三层同步 | Rime 状态 → Go 字段 → 配置文件，不可断开 | 候选数"卡住" |
| YAML key 引号兼容 | 必须同时支持 `menu/page_size` 和 `"menu/page_size"` | 设置"不生效" |
| 子菜单命令解析 | `commandIDFromRequest` 必须保留 `data.id` 回退 | 反查点击宿主崩溃 |
| 安装验证 | 必须确认 server.exe 时间戳已更新并重启进程 | 源码修复"不生效" |
| 重新安装脚本 | `Reinstall-PIME-Test.cmd` 不可简化 | DLL 锁检测失效 |
| 子模块推送顺序 | bump 子模块指针前，先把 commit 推到 fork remote | CI checkout 失败 |
| Win32 Rust 工具链 | `Rust_TOOLCHAIN=stable-i686-pc-windows-msvc` 固定不可取消 | build-script 链接错，PIMELauncher 无法重建 |
| 候选标签与按键分层 | `setSelLabels` 显示 `⇧1`—`⇧9`；真实选择键仍由 Shift+数字处理；标点只作物理键面说明 | 裸数字误导用户，或标签与实际按键不一致 |
| 不采用裸数字键选词 | Base 数字键始终参与编码；不得新增数字键选词开关或按候选窗状态抢占数字键 | 编码被截断，同一按键含义随状态漂移 |
| 派生码保留虚首音 | 变长、省键生成规则和布局重编码器都必须保留 `'` / `N12` | 零声母边界丢失，连续输入无法稳定自动分词 |
| 整句优先于补全 | 三套 schema 同时保留 `enable_sentence` 与 `sentence_over_completion` | 配置看似启用整句，实际只返回词条补全 |
| github 拉取走代理 | git/cmake 不读系统代理，需设 `HTTPS_PROXY=http://127.0.0.1:1081` | FetchContent 克隆 Corrosion 超时 |
| DLL 被锁走就地安装 | explorer 加载 DLL 时就地安装是设计行为；干净重装先重启 | 误判重装失败、强杀 explorer |
| CI 日志先看路径 | 3033/3077 事件先核对文件路径；SAC 审计未签名 `server.exe` 不是崩溃 | 把第三方噪声或审计记录误判为 YIME 故障 |

### 子模块推送（CI 必做）

Yime 的活动构建子模块 `libIME2` 指向 `tsaanghwang/libIME2` fork。主仓库引用新 SHA 之前，必须先把对应 commit 推到子模块 remote。McBopomofoWeb、libchewing 和 Python brise 已从仓库永久删除：

```powershell
cd libIME2
git push git@github.com:tsaanghwang/libIME2.git master

cd ..\Yime
git push origin <当前工作分支>
```

---

## 6. 开发环境检查清单

### 构建验证

```powershell
# Go 后端
cd go-backend
cmd /c build.bat

# C++/Rust 宿主
cmd /c build.bat
```

### 测试验证

```powershell
cd go-backend
go vet ./...
go test ./...

# 真实 librime 连续输入验收（需要本机 Rime 运行库）
$env:YIME_RUN_REAL_RIME_TESTS = "1"
go test ./input_methods/yime -run TestRealRimeAllSchemasComposeSentence -count=1 -v
```

### 安装验证

```powershell
# 1. 确认构建产物时间戳
Get-Item "build\go-backend\server.exe" | Select-Object LastWriteTime
Get-Item "build\go-backend\input_methods\yime\data\rime_deployer.exe" | Select-Object LastWriteTime

# 2. 停止运行中的 PIME
.\dev-stop-pime.ps1 -Auto

# 3. 重新安装
.\Reinstall-PIME-Test.cmd

# 4. 验证安装目录时间戳
Get-Item "C:\Program Files (x86)\YIME\go-backend\server.exe" | Select-Object LastWriteTime

# 5. 在记事本中测试
#    - 切换到音元输入法
#    - 输入编码，确认候选窗出现
#    - 测试语言栏菜单
```
