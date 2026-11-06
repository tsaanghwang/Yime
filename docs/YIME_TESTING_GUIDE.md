# Yime 测试与验收指南

更新：2026-11-03（主线 `64a785a7`；候选分支另见[项目现状](YIME_PROJECT_ASSESSMENT.md)）。本文依据当前 [CI 工作流](../.github/workflows/ci.yaml)、源码测试入口和[简版维护验收记录](../installer/simple/VALIDATION.md)，区分自动回归、隔离构建与真实安装验收。历史报告只证明报告中的提交、包和环境。

YimeCore 是主要开发线；Rime/PIME 是独立维护的稳定产品。每次改动先标明影响 YimeCore、Rime/PIME 或共同源，再选择测试。两套可以单独安装或共存，维护一套不得依赖、停止或改写另一套。共同词源和生成规则可以共享测试规格，产品运行时和用户状态分别验收，详见[双产品开发计划](project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)。

## 1. 测试层级与证据边界

| 层级 | 覆盖内容 | 不能据此声称 |
| --- | --- | --- |
| 离线 Python | 拼音来源、音节准入、编码、词库及布局投影、目标锁 | Windows 输入法已安装或可输入 |
| Go 回归与 race | 引擎、Broker、配置、工具和 Rime 适配层 | 原生 TSF、安装包或真实应用已通过 |
| 隔离 real Rime | librime 会话、三模式行为、部署与候选配置 | YimeCore 独立引擎正确，或已安装 Rime 缓存更新 |
| 原生构建与契约 | C++/Rust 编译、RPC、DLL 契约、指定测试宿主 | 当前用户的已注册产品已在真实应用激活 |
| 安装与实机验收 | 完整包、注册、启动、卸载重装、真实宿主输入与重启 | 其他提交、其他包、未测架构或未测应用也通过 |

目标范围为主流 Windows x64、x64 上的 x86/WOW64 应用，以及已批准的 Windows ARM64 工作线。x86 不表示新增 32 位 Windows 工作线。ARM64 跨编译和 PE 检查不能替代 ARM64 原生 Runtime/Broker、注册宿主及真实应用验收；当前简版 x64 包不是 ARM64 安装包。[开发范围配置](../tools/yimecore/development-scope.json)记录源码实验入口与机器范围。

## 2. 当前 CI 实际执行什么

[Build 工作流](../.github/workflows/ci.yaml)在 `main`、`yime-stable`、`codex/**` 推送、相关 PR、`v*` 标签及手工触发时运行。`build-contract` 通过后各测试与构建作业并行；`shard-coverage` 等待 real Rime 分片；`core-build` 汇总全部必需作业，失败或跳过均不能被汇总为成功。

| 作业 | 当前验证范围 |
| --- | --- |
| `build-contract` | 构建约束、锁定工具链元数据、外部词源归档身份、CI 调度和分片拒绝路径、libIME2 变更边界 |
| `lexicon-offline-tooling` | Python 3.14 离线测试、仓库数据边界、PSC 快照、目标锁、固定交接重放、词库与布局身份评估；`v*` 标签追加来源重现检查 |
| `rust-i686-host` | 固定 i686 host Rust 工具链、格式检查、PIMELauncher 测试 |
| `go-tests` | Go 1.26.4 的 vet、全包测试和必需回归名核验；Python 工具、checked PowerShell 入口、Rime 缓存与 Stage 6D 核验器回归 |
| `real-rime-tests` | 3 个分片运行隔离真实 Rime 测试，并保留同提交、同运行尝试的证据 |
| `go-race-msys2` | MSYS2 UCRT64 GCC 支持的 Go 全包 race 检测 |
| `native-build` | Rime/PIME Win32 构建与 CTest、x64 TSF/RPC/注册查询构建及 x64 RPC 测试；上传 `yime-native-<SHA>` 中间制品 |
| `shard-coverage` | 校验 real Rime 分片集合完整且精确，拒绝缺失、重复或身份不符的证据 |
| `simple-installer` | 包资源、ARM64X 包/维护边界、ARM64 连读工具链准入、配置移除失败保护、旧用户条目退役、启动项、产品选择、日志及进程等待；按入口分别使用 PS5/PS7，均不执行真实产品安装 |

`simple-installer` 只依赖 `build-contract`，不下载或消费 `native-build` 制品，不生成完整安装包，也不执行真实安装。`yime-native-<SHA>` 是 Rime/PIME 原生中间制品，不能作为任一产品的完整包交付。

上表描述通用 Build 的常规作业；不能由此推断全部专项 workflow 的覆盖。主线另有下列 18u 工作流：

| 专项入口 | 验证层级与触发限制 |
|---|---|
| [touch-terminal](../.github/workflows/touch-terminal.yml) | 原型资源/布局、Go 回归与便携包检查；不等于物理输入或安装版验收 |
| [own-host](../.github/workflows/touch-bridge-own-host.yml)、[ui-host](../.github/workflows/touch-bridge-ui-host.yml)、[formal-tip](../.github/workflows/touch-bridge-formal-tip.yml) | 原生自有 TSF、UI/宿主桥与正式适配器测试；有固定分支和场景门。formal 中注册态目标存在 compile-only 阶段，不能将编译计作执行 |
| [registered-probe](../.github/workflows/touch-bridge-registered-probe.yml)、[本机激活包](../.github/workflows/mycomputer-activation-package.yml)及 Build 内一次性门 | 明确身份、分支和手动门控；未 dispatch/跳过不算注册态通过 |
| [CI 保留测试](../.github/workflows/ci-retention-tests.yml)、[日清理](../.github/workflows/daily-ci-cleanup.yml) | 清理合同与固定证据保护，不是产品行为验收 |

完整安装版 test.7 的专用构建/制包结果属于候选分支，不是通用 main Build 自动产出的正式发行包。CI 没有替用户完成 Word/Edge 等真实应用、指笔和 ARM64 实机验收；已有机器结果见[当前证据矩阵](YIME_PROJECT_ASSESSMENT.md#已有交付与实机证据)。E3 性能也需固定工作负载单独验证。

## 3. 本地回归入口

以下命令从仓库根目录运行。所有 PowerShell 通过 [checked 入口](../tools/powershell/README.md)选择一个版本并在同一进程检查、执行；不再单独重复预检。复杂值写入 UTF-8 JSON，通过 `--params-file` 传完整参数名。`--check-only` 仅检查语法与静态可证参数错误，不证明运行成功。

### Go、real Rime 与离线链

```text
python tools/powershell/run_checked.py --script tools/test-go.ps1 --edition ps7
python tools/powershell/run_checked.py --script tools/test-real-rime.ps1 --edition ps7
python tools/powershell/run_checked.py --script tools/test-go-race.ps1 --edition ps7
```

`test-go.ps1` 执行 `go vet ./...`、串行包编译的 `go test -p=1 ./...`，并确认必需回归真实存在后重跑。普通测试不以真实用户目录中的历史通知或缓存为前提。real Rime 入口默认完整运行，CI 使用 3 个分片；它临时设置并恢复测试开关，不操作已安装产品。涉及语流音变别名时必须保留三模式真实 Rime 回归，同时验证 YimeCore 自身行为。

race 入口默认使用 `C:\msys64\ucrt64\bin\gcc.exe`，并设置 CGO、PATH 与工作区缓存；路径不同时用参数文件传 `GccPath`。缺少编译器或执行被系统策略阻止应记录为环境未满足，不能将未执行写成通过，也不能删除 CI race 门禁。

离线链需要 Python 3.14 及测试依赖：

```text
python -m pip install -e "tools/lexicon[test]"
python tools/powershell/run_checked.py --script tools/lexicon/test.ps1 --edition ps7
python -m unittest discover -s tools -p "test_*.py" -v
python -m unittest discover -s tools/powershell -p "test_run_checked.py" -v
```

`tools/lexicon/test.ps1` 检查仓库数据边界、离线 unittest、目标锁并运行根目录 `tests/` 的 pytest。[测试目录说明](../tests/README.md)列出当前目录职责。普通测试与已批准固定交接重放不要求从大型外部词源重建；来源级重建只能使用 `YIME_LEXICON_EXTERNAL_ROOT` 指向的独立内容锁定目录，不能读取其他 Git 仓库作为回退。

### 简版维护隔离回归

与 CI 一致，以下显式选择 Windows PowerShell 5.1，用于安装端兼容性验证：

```text
python tools/powershell/run_checked.py --script installer/simple/Test-PackageValidation.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/Test-ProfileRemoval.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/Test-Startup.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/Test-Manage.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/Test-Logging.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/Test-ProcessWait.ps1 --edition ps5
```

这些检查使用隔离文件、替身或临时测试注册表键。`Test-Startup.ps1` 会验证系统实际启动项视图的临时测试键；不能将整组测试描述成仅静态检查。

有两套完整包时，再运行 `Test-Product.ps1`。例如将以下内容保存为本次本地 `.tmp/simple-product-test.params.json`，用实际解压包根目录替换示例值：

```json
{
  "CorePackage": "C:\\YimePackages\\yimecore",
  "RimePackage": "C:\\YimePackages\\rime-pime"
}
```

```text
python tools/powershell/run_checked.py --script installer/simple/Test-Product.ps1 --edition ps5 --params-file .tmp/simple-product-test.params.json
```

该检查复制真实包到新隔离目录，验证产品归属、私有字体占用、损坏数据替换和另一产品不受影响；不会执行产品注册或更改已安装产品。临时参数文件只供本次本地运行，不能作为测试端交接指令或证据交付。

### 原生测试

Rime/PIME 原生测试依赖正确构建的 Win32/x64 输出。在已配置构建环境中分别执行：

```text
ctest --test-dir build -C Release --output-on-failure
ctest --test-dir build64 -C Release -R "^PIMERpcResponseTests$" --output-on-failure
```

Win32 PIMELauncher 必须使用 `stable-i686-pc-windows-msvc` host 工具链和仓库固定的 Corrosion；不能用默认 x64 工具链添加 i686 target 代替。构建前置及制包步骤以[安装维护说明](../installer/simple/README.md)为准。

YimeCore 使用[源码工具入口](../tools/yimecore/README.md)。`build-local-product.ps1` 为当前身份构建 x64 Runtime/Broker 与 x64/x86 TSF，并运行隔离契约、焦点取消等检查；其输出不是已安装宿主证据。连读准入（`run-connected-speech-admission.ps1`）必须在同一源码树内先于构建运行：导出器按构建树的相对路径与哈希绑定准入，跨工作树复用会被拒绝。隔离测试的 TEMP/LOCALAPPDATA 运行在与仓库路径无关的短根 `%LOCALAPPDATA%\YimeBuildFixtures\<id>`，测试后移回构建根 `t\<id>`。平台实验经 `run-platform-experiment.ps1` 选择批准目标并写入新输出。不要直接复用旧身份产物或恢复已退役的阶段编排。涉及 TSF 写入、焦点或宿主生命周期时，还须选择 [YimeCore 原生测试](../YimeTextServiceExperiment/tests/)中的对应测试并记录实际运行层级。

## 4. 必须保留的回归约束

以下是最低保护面；具体实现规则以 [AGENTS.md](../AGENTS.md)为准。

- 两产品的裸数字始终参与组字，候选序号为 `⇧1` 至 `⇧9`，通过 `setSelLabels` 保持 Shift 语义；不得新增裸数字选词模式。
- Rime 保持后端候选分页所有权，保护 `TestNativeBackendKeepsRimeOwnedCandidatePaging`。页大小必须经 Rime 配置、deploy/reload 和 `rimeState.PageSize` 回读同步，支持带引号和不带引号的 `menu/page_size`，不能用 Go 切片掩盖问题。
- 修改语言栏命令、反查菜单、动态按钮或激活路径前，先加入具体点击回归，保留 `data.id` 子菜单回退。安装态问题要核对实际命令日志、用户 YAML 与运行二进制，不能仅凭单元测试宣称修复。
- YimeCore 的 `TF_S_ASYNC` 不是写入成功；UI 只能随实际 `DoEditSession` 完成结果更新。保留 x64/x86 延迟锁、失败写入和恢复测试。
- 焦点丢失只取消原来的未确认 composition，不提交 ASCII、不代选汉字、不向新宿主合成 Escape；延期取消必须核对原 composition 身份。语言栏释放前解除回调，候选窗要能处理外部 HWND 销毁。
- Broker 的连接退出只释放该连接创建的会话；mutation 重试必须比较完整、有序的 observations，不能吞掉冲突。
- 词典规范读音和音节码保持唯一上游。语流音变是有来源、可移除、位置保留的词或短语别名，从同一规范记录派生三模式且任何模式不得变长；变更前阅读[语流音变计划](project/MANDARIN_CONNECTED_SPEECH_PLAN.md)。
- Rime 分段条改动保护原编码与汉字范围映射、失败回送当前状态、不携带旧 commit、点击优先级及不抢焦点；真实宿主验收参照[分段纠错测试计划](project/SENTENCE_SEGMENT_CORRECTION_TEST_PLAN.md)。

## 5. 完整包与实机验收

安装、卸载和重装统一使用 [installer/simple](../installer/simple/README.md) 的完整包与 `Install-Uninstall.cmd`。旧固定事务恢复链已经退役；锁定 DLL 时跳过 DLL、只更新其他文件不是当前默认维护路径。先保存并退出使用目标输入法的应用；仍占用时取消，正常重启后在未切换到待维护输入法的状态下重试。维护只拥有所选产品文件、注册、私有字体和状态，不清理系统字体或另一产品。

源码工作不授权重置开发 PC 的现用安装。新一轮测试先完成本地验证、提交推送和该提交 CI，再在[交接文档](../installer/simple/HANDOFF.md)发布具体任务与完整包。大包交付记录明确的 GitHub artifact/Release URL、大小、SHA-256、脚本提交和运行载荷来源；源码 checkout 或原生中间制品不等于交付。开发使用从当前 `main` 创建的目标分支；`perf/i7-7820x-local` 继续用于原有 x64 性能报告，ARM64 和 18u 结果按各自任务交接指定的分支与路径回传，不使用统一回传分支。已完成的交接保留历史，不因文档改写要求再次安装。

每次实机报告至少区分：

1. **包身份与维护结果**：提交、包哈希、所选产品、系统及宿主架构、安装前后状态、父子日志和退出码。发生配置移除失败时，应确认在 COM 注销、启动项清理和文件删除前停止。
2. **实际加载与启动**：安装文件哈希、注册身份、进程路径与当前运行二进制。Rime/PIME 菜单修复要确认安装的 `server.exe`、`rime_deployer.exe` 已更新，并已重启相应进程；持久化 `runtime-status.json` 只作诊断，不能单独证明当前启动正常。
3. **真实输入与重启**：明确应用名称、位数、选中的当前产品、组字/候选/上屏、具体失败路径及重启后的用户确认。x64 与 x86/WOW64 分开记录，未执行的应用保留未测。
4. **独立性**：按本轮改动选择单套、两套共存及维护一套不破坏另一套的检查。当前已完成矩阵见验收记录，不自动重开历史测试。

打开 Word 或其他宿主后，先通过任务栏选择当前 **音元拼音** 并核对活动 Profile 或实际加载 DLL；冻结的 **Yime 自研栈试验版** 不代表当前产品。不得修改默认输入法来促使自动化通过。Computer Use 的 `Alt+Space`、任务栏操作差异应单列为工具限制；Word 占有前台 TIP 时，注册宿主可能报 `registered TIP did not become foreground`，须保存并关闭 Word 后重跑才能判断。

Rime/PIME 缓存与语气词“啊”安装资产的问题，可使用现存只读核验器辅助定位，不能将核验结果代替输入验收。核验器的旧默认安装根不适用于当前简版包，必须显式传入实际 `InstallRoot`。例如将以下内容保存为本次本地 `.tmp/installed-particle-a.params.json`：

```json
{
  "InstallRoot": "C:\\Program Files\\Yime Rime-PIME"
}
```

运行前还要核对 `RimeUserDir` 指向目标用户的已部署 Rime 目录，不能误查管理员或另一用户的缓存；`ExpectedEntries` 应与该包的别名清单核对。与脚本默认值不同时，把这两个完整参数名及对应值加入同一 JSON，不沿用历史包的计数判断新包。

```text
python tools/powershell/run_checked.py --script tools/verify-installed-particle-a-stage6d.ps1 --edition ps7 --params-file .tmp/installed-particle-a.params.json
```

系统 CodeIntegrity 事件应按实际路径和消息判断，不能只因出现事件号或其他软件名称就归因为 Yime 崩溃。公开发布条件见[发布说明](YIME_RELEASE_AND_SIGNING.md)，开发包测试不沿用历史证书申请状态作为当前结论。

## 6. 当前已知结果与最低验证选择

[项目现状](YIME_PROJECT_ASSESSMENT.md)汇总 11 月主线、独立候选和实机结果；[简版维护验收](../installer/simple/VALIDATION.md)继续保留各轮标准产品安装记录。下述 9 月结论是历史基线，不是最新任务清单。2026-09-14 的源码候选包对应 `a4fa6f76`，测试端报告两套在 Codex 与记事本重启前后可输入；Word 没有报告，不计为通过。2026-09-15 的同步与收尾不构成新一轮安装。

2026-09-16 的包资源和卸载失败保护修复已增加隔离回归；是否交付新包及新增实机结果以[交接文档](../installer/simple/HANDOFF.md)为准，不能将 9 月 14 日包的验收归给这些后续改动。更早的 [2026-09-02 YimeCore 自启动验收](YIMECORE_REBOOT_AUTOSTART_ACCEPTANCE_2026-09-02.md)和各日期安装报告保留原证据级别，不作为当前运行载荷的新结论。

| 修改类型 | 最低验证 |
| --- | --- |
| 文档 | 对照真实入口、检查链接及 `git diff --check` |
| 纯 Go 逻辑 | 目标包与边界回归；共享状态变化增加 race |
| 离线来源、编码、布局或别名 | 正式来源与目标锁、相关 Python/Go 回归；别名追加三模式 real Rime 与 YimeCore 独立检查 |
| Rime 配置、缓存或部署 | Go/real Rime 回归；需要确认现用效果时追加安装文件、用户缓存和重载验收 |
| YimeCore Broker/TSF | Go 或原生对应回归、受影响架构契约；宿主行为变化追加当前身份的安装态与真实应用验收 |
| 语言栏、候选 UI、原生工具 | 精确点击/布局回归、对应 EXE/DLL 构建，使用新包在真实宿主复现 |
| 简版维护 | 对应 PS5 隔离回归、真实包边界检查；需要证明系统行为时另行交付完整包并做指定实机验收 |

本指南更新本身只要求文档核验，不重新执行安装、不重置用户数据，也不把未覆盖项目补写为通过。
