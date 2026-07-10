# 音元输入法开发路线图

> 版本：2026-07-10
> 分支：yime-stable
> 配套文档：[可用性评估](YIME_USABILITY_ASSESSMENT.md) | [架构文档](YIME_ARCHITECTURE.md)

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

### 遗留编码约束（暂不修改）

- 候选选择键仅 5 个（Space/`/-/=/\），第 6-9 个候选需鼠标点击
- 数字键在组字时作为编码输入，不选词
- 57 音元占满 47 个可打印键位，改选字键需重建编码体系

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
推送到 origin/yime-stable
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
| 1.3 | 候选选择键扩展 | 暂缓 | 编码约束：57 音元占满键位 |
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
| 4.1 | 组字时数字键选词模式 | 暂缓 | 需编码体系配合 |
| 4.2 | Rime 初始化失败可重试 | ✅ 3e24351d | sync.Mutex + 双标志 |
| 4.3 | 词典噪声清理 | 待做 | 审查权重=1 的极低频词（优化，非缺陷） |
| 4.4 | 非标准音节审查 | 不处理 | bong4/wong4 等为 Unihan 台版/方言读音遗留，权重极低不影响使用 |
| 4.5 | 词库导入功能 | ✅ 63ef77c5 | DELETE/IMPORT 接入词库管理器 |
| 4.6 | 反查工具即时搜索 | ✅ e7a3a461 | 500ms debounce 即时搜索 |
| 4.7 | 用户屏蔽词表 | ✅ 0518d6fd | 运行时过滤 + `blocklist-manager.exe` |
| 4.8 | 系统词库审查 | ✅ fd3edfc0 | 只读扫描已安装系统词库 |
| 4.9 | 原生 Win32 工具链 | ✅ dd68a47a | 设置/诊断/词库/反查/工具箱等独立 `.exe` |
| 4.10 | 语言栏切换稳定性 | ✅ 73b74e99 | 静态切换标签，切换时只更新图标 |

---

### Phase 5：后续改进（待规划）

| # | 任务 | 说明 | 前置条件 |
|---|------|------|----------|
| 5.1 | 候选窗标签与选择键一致 | 修正 `SetSelKeys` 使标签反映实际选择键 | 无 |
| 5.2 | 方向键移动候选光标 | 上下方向键移动 + Enter 确认 | 无 |
| 5.3 | 默认 candidatePageSize 限制为 5 | 避免超出选择键数量 | 无 |
| 5.4 | 词语字频回退排序 | 无 BCC 词频时用组成字频率估计，改善 weight=1 词语间排序 | Yime-python-prototype 管线 |
| 5.5 | 组字时数字键选词模式 | 可配置，数字键在"选词"和"编码"间切换 | 编码体系配合 |
| 5.6 | 独立工具通知活动输入会话 | 词库“应用”和设置“应用并重建”完成后显式通知当前 Go/Rime 会话刷新 | 设计轻量 IPC 或变更标记 |
| 5.7 | 根包测试隔离 | 隔离原生 Rime 全局状态、临时数据目录和拼音缓存，使 `go test ./input_methods/yime` 全量稳定 | 保留真实 Rime 测试环境开关 |
| 5.8 | 清理语言栏实验代码 | 评估并移除动态标签实验遗留的原生 sort/fixed-GUID 逻辑，补宿主点击回归测试 | 安装态 TSF 验证 |

---

## 4. 里程碑时间线

```
2026-07 W1-W2
├── Phase 1 ✅ 关键可用性修复
│   ├── 1.1 回车键行为 ✅
│   ├── 1.2 重复按键抑制 ✅
│   ├── 1.3 候选选择键扩展（暂缓）
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
│   ├── 4.1 数字键选词（暂缓）
│   ├── 4.3 词典噪声清理（待做，优化项）
│   └── 4.4 非标准音节审查（不处理）
│
├── 基础设施
│   ├── 子模块 fork 推送流程 ✅
│   ├── 注册表/profile 清理脚本 ✅
│   └── CI checkout 子模块修复 ✅
│
待规划
└── Phase 5 后续改进
    ├── 5.1-5.3 候选窗改进
    ├── 5.4 词语字频回退排序
    └── 5.5 数字键选词模式
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

### 子模块推送（CI 必做）

Yime 的 `libIME2`、`McBopomofoWeb` 等子模块指向 `tsaanghwang/*` fork。主仓库引用新 SHA 之前，必须先把对应 commit 推到子模块 remote：

```powershell
cd libIME2
git push git@github.com:tsaanghwang/libIME2.git master

cd ..\Yime
git push origin yime-stable
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
go test ./input_methods/yime/ -v -count=1
go vet ./...
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
