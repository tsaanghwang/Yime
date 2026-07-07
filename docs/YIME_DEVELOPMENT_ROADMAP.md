# 音元输入法开发路线图

> 版本：2026-07-07
> 分支：yime-stable
> 配套文档：[可用性评估](YIME_USABILITY_ASSESSMENT.md) | [架构文档](YIME_ARCHITECTURE.md)

---

## 1. 当前状态

### 已完成

| 里程碑 | 提交 | 状态 |
|--------|------|------|
| 候选项数同步机制 | 1343632 | ✅ rimeState.PageSize 回读链 |
| 语言栏排列方式简化 | a2b6923 | ✅ 一次点击切换横竖排 |
| CI 构建流水线修复 | d9d8a0ca | ✅ windows-2022 + vswhere |
| rimeDeploy schema custom 部署 | 423658c | ✅ *.custom.yaml glob 部署 |
| 子模块推送 | — | ✅ libIME2 + McBopomofoWeb |
| cSpell 词表扩展 | 16eda9b | ✅ 60+ 项目专有词 |

### 已知缺陷（按严重度排序）

详见 [可用性评估 §5-7](YIME_USABILITY_ASSESSMENT.md#5-高优先级可用性问题)

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
    ├── 独立工具窗口 ──→ PowerShell WinForms + 工具清单注册
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
    │       └── 当前组字状态丢失 ⚠️
    └── 9. 读回 PageSize (backend.State().PageSize)
            └── 无候选时 PageSize=0，读回失败 ⚠️
    │
    ▼
下次按键时执行 pendingSchemaRedeploy
```

---

## 3. 路线图

### Phase 1：关键可用性修复（1-2 周）

目标：修复直接影响打字体验的 4 个高优先级问题。

| # | 任务 | 涉及文件 | 前置条件 | 回归测试 |
|---|------|----------|----------|----------|
| 1.1 | ~~修复回车键行为~~ ✅ 已修复 | `yime.go:676-685` | 无 | `TestReturnKeyCommitsRawInputDuringComposition`, `TestReturnKeyPassesThroughWhenNotComposing` |
| 1.2 | ~~修复重复按键抑制~~ ✅ 已修复（`edd6e0ab`） | `yime.go:270-282` | 无 | `TestRapidSameKey*`, `TestDuplicateKeyDown*`, `TestKeyUpClears*` |
| 1.3 | ~~扩展候选选择键至 9 个~~ 暂缓（编码约束） | `yime.go:743-799` | 编码体系重建 | — |
| 1.4 | ~~候选项数变更保存/恢复组字状态~~ ✅ 已修复 | `yime.go:2097-2114` | 无 | `TestSetCandidatePageSizePreservesComposition` |

**验收标准**：
- ~~快速连打同一键不丢字~~ ✅ 已修复
- ~~组字时回车有可见效果~~ ✅ 已修复
- 候选项数 6-9 时全部可通过键盘选择（暂缓：57 音元占满键位，改选字键需重建编码体系）
- ~~调整候选项数不丢失当前输入~~ ✅ 已修复

---

### Phase 2：用户体验改善（2-4 周）

目标：修复中优先级问题，提升操作反馈和一致性。

| # | 任务 | 涉及文件 | 前置条件 | 回归测试 |
|---|------|----------|----------|----------|
| 2.1 | 关键操作失败时增加用户提示 | `yime.go` openPath/copyTextToClipboard | 无 | 手动验证 |
| 2.2 | `joinRuneLookup` 缺失字符显示占位符 | `yime.go:1926-1940` | 无 | 新增 `TestJoinRuneLookupPartialMissing` |
| 2.3 | 用户词库跨方案自动同步 | `yime.go:1671-1692` | 无 | 新增 `TestUserLexiconSyncOnSchemaSwitch` |
| 2.4 | 反查工具加载进度提示 | `yime_reverse_lookup_tool_windows.go` | 无 | 手动验证 |
| 2.5 | 反查搜索结果截断提示 | `yime_reverse_lookup_tool_windows.go:430` | 无 | 手动验证 |
| 2.6 | 实现词库删除功能 | `yime_user_lexicon_windows.go` | 无 | 新增测试 |

---

### Phase 3：代码质量与健壮性（1-2 月）

目标：清理技术债务，增强测试覆盖。

| # | 任务 | 涉及文件 | 说明 |
|---|------|----------|------|
| 3.1 | 移除硬编码开发路径 | `yime.go:2150` | 删除 `C:\dev\librime\` 路径 |
| 3.2 | 移除死代码 `remapYimeCandidateSelectionKey` | `yime.go:743-770` | 定义但未调用 |
| 3.3 | `commandShouldRefreshState` 改为黑名单 | `yime.go:464-475` | 降低维护负担 |
| 3.4 | 增加并发安全测试 | `yime_test.go` | 多按键/多命令并发 |
| 3.5 | 增加 Unicode 边界测试 | `yime_test.go` | emoji、扩展汉字、代理对 |
| 3.6 | YAML 操作支持行内注释 | `yime.go:2257-2272` | `readPageSizeFromCustomConfig` |
| 3.7 | `candidatePageStart` 仅在候选列表变化时重置 | `yime.go:679` | 无效按键不应丢失翻页位置 |

---

### Phase 4：功能增强（2-3 月）

目标：基于稳定基础增加用户请求的功能。

| # | 任务 | 说明 |
|---|------|------|
| 4.1 | 组字时数字键选词模式（可配置） | 用户可在"数字选词"和"数字编码"间切换 |
| 4.2 | Rime 初始化失败可重试机制 | 替代 `sync.Once`，支持手动重试 |
| 4.3 | 词典噪声清理 | 审查权重=1 的极低频词 |
| 4.4 | 非标准音节审查 | 确认 `bong4`, `wong4` 等是否有对应汉字 |
| 4.5 | 词库导入功能实现 | 当前仅记录日志 |
| 4.6 | 反查工具即时搜索 | 输入即搜索，无需点击"查询" |

---

## 4. 里程碑时间线

```
2026-07
├── W1-W2: Phase 1 — 关键可用性修复
│   ├── 1.1 回车键行为 ✅
│   ├── 1.2 重复按键抑制 ✅
│   ├── 1.3 候选选择键扩展（暂缓）
│   └── 1.4 组字状态保存 ✅
│
2026-07 ~ 2026-08
├── W3-W6: Phase 2 — 用户体验改善
│   ├── 2.1 失败提示
│   ├── 2.2 反查占位符
│   ├── 2.3 词库跨方案同步
│   ├── 2.4-2.5 反查工具改进
│   └── 2.6 词库删除功能
│
2026-08 ~ 2026-09
├── W7-W14: Phase 3 — 代码质量与健壮性
│   ├── 3.1-3.2 代码清理
│   ├── 3.3 命令白名单重构
│   ├── 3.4-3.5 测试增强
│   ├── 3.6-3.7 边界修复
│   └── Beta 发布候选
│
2026-09 ~ 2026-11
└── W15-W22: Phase 4 — 功能增强
    ├── 4.1 数字键选词模式
    ├── 4.2 初始化重试
    ├── 4.3-4.4 词典审查
    ├── 4.5-4.6 功能完善
    └── 正式版发布
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
