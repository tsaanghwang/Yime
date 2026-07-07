# 音元输入法架构文档

> 版本：2026-07-07
> 配套文档：[可用性评估](YIME_USABILITY_ASSESSMENT.md) | [开发路线图](YIME_DEVELOPMENT_ROADMAP.md)

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
│  独立工具进程 (PowerShell WinForms)                       │
│    ├── 设置工具 (yime_settings_tool_windows.go)           │
│    ├── 诊断工具 (yime_diagnostics_tool_windows.go)        │
│    ├── 反查工具 (yime_reverse_lookup_tool_windows.go)     │
│    └── 词库管理 (yime_user_lexicon_windows.go)            │
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

### 2.1 候选项数同步链

这是 AGENTS.md 重点保护的机制，三层状态必须保持一致：

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
- 无候选时 `State().PageSize` 返回 0，读回失败
- `setCandidatePageSize` 中读回 mismatch 仅记录日志，不阻断

### 2.2 候选分页权

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

### 2.3 语言栏命令分发

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
    ├── 是 → 跳过状态刷新 (避免 TSF 回调中触发 Rime 操作)
    └── 否 → 刷新 Rime 状态到响应
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

### 2.4 Rime 部署流程

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

### 2.5 独立工具调度

```
onCommand → 启动独立工具
    │
    ├── 写入 PowerShell 脚本到临时文件
    │     └── BOM 前缀 (0xEF, 0xBB, 0xBF) 确保 UTF-8 编码
    │
    ├── exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath)
    │
    └── 脚本内嵌完整 WinForms GUI
          ├── 设置工具: 方案/候选数/反查/排列
          ├── 诊断工具: 安装/进程/日志/命令解读
          ├── 反查工具: 汉字→编码查询
          └── 词库管理: 添加/查看用户词
```

---

## 3. 数据文件

### 3.1 共享数据目录

`go-backend/input_methods/yime/data/`

| 文件 | 类型 | 说明 |
|------|------|------|
| `default.yaml` | Rime 配置 | 基础 schema_list、page_size、按键绑定、标点 |
| `yime_variable.schema.yaml` | Rime 方案 | 变长模式定义 |
| `yime_full.schema.yaml` | Rime 方案 | 等长模式定义 |
| `yime_shorthand.schema.yaml` | Rime 方案 | 省键模式定义 |
| `yime_variable.dict.yaml` | Rime 词典 | 变长模式，468K 条 |
| `yime_full.dict.yaml` | Rime 词典 | 等长模式，468K 条 |
| `yime_shorthand.dict.yaml` | Rime 词典 | 省键模式，468K 条 |
| `yime_pinyin_codes.tsv` | 编码映射 | 拼音→音元编码，1625 条 |
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
| `user.yaml` | YAML | Rime 用户状态（previously_selected_schema） |
| `yime_user_phrases.txt` | TSV | 用户词库源文件（词条\t数字标调拼音\t权重） |
| `custom_phrase.txt` | TSV | Rime 格式用户词库（词条\t音元编码\t权重） |
| `yime_settings_state.json` | JSON | 独立 UI 偏好（反查模式、候选排列） |
| `build/` | 目录 | Rime 编译缓存 |

### 3.3 日志

`%LOCALAPPDATA%\PIME\Logs\`

- `go_backend.log` — Go 后端主日志
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

产物：`build/go-backend/server.exe`, `build/go-backend/input_methods/`

### 4.3 CI 流水线

`.github/workflows/ci.yaml`（触发分支：yime-stable）

```
checkout → vswhere/VsDevCmd → cmake build → go build → nsis installer → upload artifact
```

关键步骤：
- `windows-2022` 运行器
- 内联 vswhere + VsDevCmd 设置（非 ilammy/msvc-dev-cmd）
- CMake 构建用 `shell: cmd` 确保 VsDevCmd 环境持久
- rime-frost 数据获取步骤
- NSIS 打包用 `pwsh` + `Set-Location`

---

## 5. 测试体系

### 5.1 单元测试

```powershell
cd go-backend
go test ./input_methods/yime/ -v -count=1
```

关键守卫测试：

| 测试 | 保护目标 |
|------|----------|
| `TestNativeBackendKeepsRimeOwnedCandidatePaging` | 候选分页权 |
| `TestOnCommandAcceptsSubmenuItemIDForReverseLookupYimePinyin` | 子菜单命令解析 |
| `TestOnCommandIgnoresLegacyLowIDCollisionForReverseLookupYimePinyin` | 低 ID 碰撞忽略 |
| `TestSetCandidatePageSizeDoesNotRedeploy` | page_size 变更不触发完整 redeploy |
| `TestUpdateDefaultCustomPageSizeReplacesQuotedKey` | YAML 引号 key 兼容 |
| `TestStandalonePowerShellScriptsAreFreeOfEncodingCorruption` | 编码损坏守卫 |
| `TestStandalonePowerShellScriptsDoNotContainSmartQuotes` | 智能引号守卫 |

### 5.2 运行时集成测试

`rime_runtime_test.go` — 需要真实 Rime 运行时

```powershell
# 需要管理员权限
go test ./input_methods/yime/ -run TestReal -v -count=1
```

| 测试 | 验证内容 |
|------|----------|
| `TestRealRimeRedeployAppliesPageSize` | redeploy 使 page_size 生效 |
| `TestRealRimeExternalBuildAppliesPageSize` | 外部构建路径验证 |

### 5.3 本地管理员测试

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
| 6-9 | 无快捷键 | 需鼠标点击 ⚠️ |

### 6.3 alphabet 字符集

```
Variable: qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n564JKL7930z2SDMAN@!#
Full:     qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n5HD64JKL7930z2SMAN@!#
Shorthand:qufvkc;gxwlj$op[strhdm.aibe%8/,y]1'n564JKL7930z2SDMAN@!#
```

差异：Full 模式多了 `H` 和 `D`（零声母和 er 系需要大写字母）。
