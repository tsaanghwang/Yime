# main 合并后 particle-a 6D 已安装运行验收记录

验收日期：2026-08-19（Asia/Shanghai）

验收结论：**通过**

## 构建身份

| 项目 | 值 |
| --- | --- |
| 分支 | `main` |
| Git commit | `de6f7446f95ca8ff0ba5141845d418ddb13f01f5` |
| Git tree | `188b077e66f6b177f813632d042ed6ecb0a66517` |
| 与 `origin/main` 的 ahead / behind | `0 / 0` |
| 验收记录生成前工作树 | clean |
| 产品版本 | `1.4.0-dev` |
| 安装目录 | `C:\Program Files (x86)\YIME` |
| 安装验收时间 | `2026-08-18T23:30:04.3609399Z`（本地 2026-08-19 07:30） |
| 机器验收记录 | `.tmp/last-dev-end-to-end-verification.json` |
| 机器验收记录 SHA-256 | `517A0C8F98928FB564057C97FCE278332DFE7EA28E574CE83C247B6E082C970E` |

本记录对应 `main` 上合并提交 `de6f7446`（Merge PR #41），包含 particle-a 6D 运行实现
`c12d67c1` 及其验收、缓存新鲜度修复提交。

## 构建与自动化验证

| 验证项 | 结果 |
| --- | --- |
| `build.bat` 完整构建 | PASS；Win32、x64、ARM64 TSF，固定 i686 Rust host 的 PIMELauncher，Go 后端、11 个工具及 librime 1.17.0 均完成 |
| Win32 Release 完整 CMake target + CTest | PASS，4 / 4 |
| x64 Release 完整 CMake target + CTest | PASS，4 / 4 |
| `tools/test-go.ps1` | PASS，Go 全量稳定测试通过 |
| `tools/test-real-rime.ps1` | PASS，约 448 秒；`TestRealRimeParticleAStage6DDualTrackAcrossAllThreeSchemas` 在变长、等长、省键三方案均通过 |
| PIMELauncher Rust 测试 | PASS；固定 `stable-i686-pc-windows-msvc`，11 个单元测试 + 2 个集成测试 |
| `tools/test-rime-cache-freshness.ps1` | PASS |
| `tools/test-build-guards.ps1` | PASS |
| `git diff --check` | PASS |

`build.bat` 的默认目标不生成 CTest 的辅助测试可执行文件，因此另行完成 Win32、x64 的完整
Release target 构建后执行 CTest；最终两套 CTest 均为 4 / 4，通过结果不存在测试缺件。

## 部署与已安装文件身份

完整构建后执行 `tools/dev-build-install-verify.ps1 -SkipBuild -RimeCacheWaitSeconds 120`，完成
开发安装、PIME 进程重启和已安装状态验收。机器报告结论为 `complete`：注册表路径正确，
PIMELauncher 已重启运行，没有退休运行目录泄漏，受检源码/构建文件与安装文件 SHA-256 全部一致。

关键已安装二进制：

| 文件 | SHA-256（构建产物 = 已安装文件） |
| --- | --- |
| `PIMELauncher.exe` | `14469507C30F6BCB6E0FF8B7D689A663EB4D83FB0BC3036BB6B98999E5F8E5E4` |
| `x86/PIMETextService.dll` | `BBD694A0B317842BEFFBF1580799224A5CA6FE1E8DA90E7243061586331DBB24` |
| `x64/PIMETextService.dll` | `C88455CF6D21FDD392A22F069E1C3F7564DA5AE1F247C128420174F403D3709A` |
| `go-backend/server.exe` | `7416BB1249AB35DDD3751E96CA34F9BFEDCD9BB4940BD3FDE2D740761B492A35` |
| `go-backend/input_methods/yime/rime.dll` | `86B4C7357D4C6D293CE5589B234D8859CA2AC30923A03BEDFA3926EEAF97FB0B` |
| `go-backend/input_methods/yime/rime_deployer.exe` | `3ABB72B5BB56FCAFCFE925D533AE5F832C68D5A0BC9952FD0EEA0682FB1AB071` |
| `go-backend/reverse-lookup.exe` | `FA16AAABF519E8D4F8F05E7EE3288908E86A0ED842454B56E1D6F5E73BCE13D7` |

ARM64 TSF 构建产物（本机不安装）`build_arm64/PIMETextService/Release/PIMETextService.dll`
SHA-256 为 `EF57639BCE290079E124A27A3EF77203D71A34812E80F4D11D3967FC89A36D2F`。

particle-a 6D 数据：

| 文件 | SHA-256（源码 = 已安装文件） |
| --- | --- |
| `yime_particle_a_stage6d_full.dict.yaml` | `E570B452543845542F0DC0E04233E44AA0AB9CFAB12D655D9E811019FBC8064B` |
| `yime_particle_a_stage6d_variable.dict.yaml` | `1B80E35EA9C04A3600FD0A5E60CDBA3A2CD6B5743C6C376DDFCFBB478CD53CD0` |
| `yime_particle_a_stage6d_shorthand.dict.yaml` | `E8E34CD76847BFB2CC2B6A3DF4F5A76641A40F402FB818A099E06DEC24E86B7D` |
| `yime_particle_a_stage6d_manifest.json` | `E03CA4A3D9C1DC9A5F7CE1F499BA6116FC45D3A4FEAEC2D020AFD0B20C5A4CF6` |

## Rime 缓存新鲜度

三个用户态 Rime 方案均以对应 particle-a 6D 词典为最新输入源；`table.bin`、`reverse.bin`、
`prism.bin` 和编译 schema 均不早于其输入源，`staleSources` 与 `staleArtifacts` 均为空。

| 方案 | 最新输入源 UTC | table UTC | reverse UTC | prism UTC | schema UTC | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 等长 `yime_full` | `2026-08-18 01:35:19.5807008` | `02:06:14.7231894` | `02:06:14.7961964` | `02:06:15.2682467` | `02:06:08.1577487` | `match` |
| 变长 `yime_variable` | `2026-08-18 01:35:19.5807008` | `02:06:07.5510998` | `02:06:07.6290999` | `02:06:08.1267487` | `02:06:00.7689918` | `match` |
| 省键 `yime_shorthand` | `2026-08-18 01:35:19.5812826` | `02:06:22.0670137` | `02:06:22.1320130` | `02:06:22.5820132` | `02:06:15.2902471` | `match` |

## 已安装运行时：三宿主

三方案的双轨正确性由上述真实 librime 回归覆盖；宿主层使用安装目录中的 TSF、PIMELauncher、
`server.exe` 和 Rime 数据完成验证。

| 宿主 | 位数 | 验证方式 | 结果 |
| --- | --- | --- | --- |
| Windows 记事本 | x64 | 物理按键注入；规范/音变路线依次输入 `样子啊`、`样子啊`、`走啊走`、`走啊走` | PASS |
| `SysWOW64\charmap.exe` 字符映射表 | x86 | 物理按键注入；同一组四条规范/音变路线 | PASS |
| 当前 Codex IDE | x64 | 当前会话用户手工实输确认：`样子啊/样子啊/走啊走/走啊走/走啊走/样子啊。` | PASS（用户确认） |

记事本和字符映射表的本机截图分别保存在 `.tmp/acceptance-notepad.png` 与
`.tmp/acceptance-charmap-x86.png`。这些是本次工作区本机证据，不作为版本库运行数据。

## 已安装运行时：语言栏菜单

在已安装 Yime 激活的记事本客户端上，真实右键打开任务栏语言栏按钮并通过 Win32 popup menu
句柄枚举，顶层菜单完整包含：输入方案、中英文、简繁、标点、全半角、工具栏、横竖排、候选项数、
显示编码、用户词库、反查编码、指法练习、工具中心和数据维护。截图保存在
`.tmp/acceptance-language-bar-menu.png`。

实际点击结果：

| 时间（本地） | 菜单路径 | 后端证据 | 结果 |
| --- | --- | --- | --- |
| 08:04:14 | `反查编码` | `onCommand commandId=3264`；安装目录中的 `reverse-lookup.exe` 启动 | PASS；宿主存活，验收窗口随后正常关闭 |
| 08:05:11 | `显示编码 → 音元拼音` | `onCommand commandId=3244` | PASS；宿主存活 |
| 08:05:35 | `显示编码 → 键位序列` | `onCommand commandId=3245` | PASS；恢复验收前设置 |

每次点击前均收到同一已安装运行链的 `onMenu id="windows-mode-icon"`，其 JSON 同时包含三方案
命令 `3220` / `3221` / `3222`、候选数 `3270`–`3274`、显示编码 `3242`–`3245` 以及数据维护
命令。高风险嵌套项“音元拼音”已走真实 host click path，没有宿主退出或静默无响应。候选响应日志
同时保持 `setSelLabels=["⇧1", …, "⇧9"]`。

## 结论

`main@de6f7446f95ca8ff0ba5141845d418ddb13f01f5` 的 particle-a 6D 运行链已完成构建、开发安装、
进程重启、文件同一性、三方案真实 Rime、三宿主输入、语言栏实际点击及三套缓存新鲜度验收。
当前安装状态可接受。该结论针对本机未签名开发安装；它不替代公开发布所需的可信代码签名验收。
