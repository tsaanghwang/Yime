# YIME 安装态验证留痕 · 2026-07-12

> 目的：按发布前安装态验证清单逐项跑一遍并留痕，作为“发布前干瘾”演练。
> 范围：本机已安装运行时（`C:\Program Files (x86)\YIME`），不发布、不签名。
> 环境：Windows 11（10.0.26100），Smart App Control = **Enforce**（`VerifiedAndReputablePolicyState=1`），Rust 1.96.1，MSVC 14.44.35207，GCC 14（MSYS2 UCRT64）。
>
> **历史快照说明**：本文只记录 2026-07-12 当日构建的结果。“仅剩签名”等表述是当时针对该轮缺口的结论，不取代当前的[项目综合评估](YIME_PROJECT_ASSESSMENT.md)和[发布指南](YIME_RELEASE_AND_SIGNING.md)。

## 结果总览

| # | 验证项 | 结果 | 备注 |
|---|--------|------|------|
| 1 | Reinstall-PIME-Test.cmd 重装 + 构建哈希核对 | ✅ 通过（修复后） | 初次失败：Win32 `PIMELauncher.exe` 重建失败（Corrosion v0.6 + x64 host 跨编译 i686，build-script 被链 i686 lib）。升级 Corrosion v0.6.1 + 固定 i686 host 工具链后重建成功，重装完成，build↔installed 三件哈希全一致 |
| 2 | 重启自启动（Run 注册表 + HKLM\SOFTWARE\YIME） | ✅ 通过（实测） | Run 键与标记均在；实际重启后 PIMELauncher 于开机 27 秒内自动拉起 |
| 3 | 7 个工具入口逐一启动不崩 | ✅ 通过 | 7/7 启动后存活≥2.5s，SAC 未阻止 |
| 4 | 三种输入模式 + 语言栏按钮注册 + go_backend.log | ✅ 通过（程序态） | TIP 已注册；日志有真实组词/候选/上屏/`changeButton` 记录；完整三模式人工点击仍需人工跑 |
| 5 | CodeIntegrity Operational 无 3033/3077/3118 阻止 | ⚠️ 部分通过 | 无 3118；YIME 相关 65×3033+66×3077（07/11 21:54–22:00，`server.exe` 未签名被审计），当前已放行无新增；非 YIME 噪声（Bonjour、Keyman） |
| 6 | runtimechange “应用并重建/词库应用后会话刷新”协议 | ✅ 通过 | `go test -race -count=1` 全绿；整个 yime 包 -race 全绿 |
| 附 | build64 Release PDB | ✅ 通过 | `PIMETextService.pdb`(5.7MB)、`PIMERpcResponseTests.pdb`(2.4MB) 均在 |

**当日判定**：安装态**功能可用**，本次验证自身暴露的缺口除签名外**全部修复**：Win32 PIMELauncher 重建链路恢复（Corrosion v0.6.1 + i686 工具链锁定）、重启后完成干净全量重装（哈希全同步）、重启自启动实测通过、corrosion 联网问题定位为本地代理并解决。此结论不代表后续版本定稿、x86 宿主或新提交的发布验收已经在 2026-07-12 完成。

---

## 逐项证据

### 1. 重装 + 构建哈希核对 ✅（修复后）

**初次失败（2026-07-12 12:28）**：提权 `Reinstall-PIME-Test.cmd`，pre-flight 报 `PIMETextService.dll` 被 `explorer.exe` 加载→就地安装；`dev-install.ps1` 抛 `Win32 PIMELauncher not found` 中止。根因：`build/`(Win32) 产物全失，且 `cmake --build build` 在 `PIMELauncher` 的 Rust crate 链接阶段失败——Corrosion v0.6 在 x64 host 跨编译 i686-pc-windows-msvc 时，把 target(i686) 的 MSVC lib 路径泄到 host 端 build-script（serde/zmij 等），`LNK4272` 机器类型冲突 + `LNK1120: 145 个无法解析`。v0.6.1 的 host-linker 修复是 iOS 专用，Windows 上无效。

**修复（2026-07-12 12:41–12:50）**：
1. `CMakeLists.txt`：`Corrosion GIT_TAG v0.6` → `v0.6.1`（最新，2026-01-17）。
2. `CMakeLists.txt`：在 32-bit 块内 `set(Rust_TOOLCHAIN "stable-i686-pc-windows-msvc" CACHE STRING ...)`——**固定 i686 host 工具链**，使 host==target==i686（target 由 `PIMELauncher/.cargo/config.toml` 的 `build.target="i686-pc-windows-msvc"` 定），消除跨编译，build-script 链接正确。
3. `rustup toolchain install stable-i686-pc-windows-msvc`（rustc 1.97.0，i686 二进制经 WoW64 在 x64 Windows 运行）。
4. `cmake --build build --config Release` 成功：`build/PIMELauncher/PIMELauncher.exe`(497152) + `build/PIMETextService/Release/PIMETextService.dll`(x86, 284160) + PDB 均产出。

**重装成功（2026-07-12 12:51）**：再次提权 `Reinstall-PIME-Test.cmd`，dev-install 全程通过——复制 PIMELauncher.exe / x86+x64 DLL / 当时尚未裁剪的历史后端 / Go 后端，重注册 DLL，写 Run 键+YIME 标记，启动 PIMELauncher。当前 YIME-only 安装器已永久移除历史 Python/Node 后端。

**哈希核对（SHA256 前 16 位，重装后）**：

| 文件 | build / build64 | installed | 同步? |
|------|-----------------|-----------|-------|
| `PIMELauncher.exe` | `A54406F80B6817B5`(12:46) | `A54406F80B6817B5`(12:46) | ✅ |
| x86 `PIMETextService.dll` | `36FE3EF0DB478B8F`(12:47) | `36FE3EF0DB478B8F`(12:47) | ✅ |
| x64 `PIMETextService.dll` | `258B37F500B4E0B7`(12:21) | `258B37F500B4E0B7`(12:21) | ✅ |

三件全量同步（DLL 经“先反注册再复制”成功替换，未触发 AllowLocked 跳过）。installed 不再是来源混杂的旧态。

**重启后干净重装（2026-07-12 13:12，最终态）**：用户重启 Windows 释放了 `explorer.exe` 对 DLL 的锁，第三次 `Reinstall-PIME-Test.cmd` 走了**完整卸载→全新安装**（非就地）：反注册 DLL、清注册表、删除整个安装树、全量复制、重注册、写自启动键、启动 PIMELauncher。最终哈希（build↔installed 全一致）：

| 文件 | SHA256 前 16 位 |
|------|-----------------|
| `PIMELauncher.exe` | `A54406F80B6817B5` |
| x86 `PIMETextService.dll` | `82016056F9D8B872`（13:11 增量重编版） |
| x64 `PIMETextService.dll` | `258B37F500B4E0B7` |

**corrosion 网络问题定位与解决**：github 直连失败的根因不是瞬断，而是本机走 `localhost:1081` 本地代理（WinINET 系统代理开启），git/cmake 命令行不读系统代理。设 `HTTPS_PROXY=http://127.0.0.1:1081` 后重 configure 成功，`build/_deps/corrosion-src` 恢复，增量构建 7s 通过。

### 2. 重启自启动 ✅

```
HKLM\...\Run\PIMELauncher = C:\Program Files (x86)\YIME\PIMELauncher.exe
HKLM\SOFTWARE\YIME (default) = C:\Program Files (x86)\YIME
```

> **实际重启验证通过（2026-07-12 13:02）**：系统 13:02:04 开机，PIMELauncher 13:02:31 自动拉起（2 进程，路径 `C:\Program Files (x86)\YIME\PIMELauncher.exe`）。重启自启动真实生效，非仅配置态。

### 3. 7 个工具入口逐一启动 ✅

逐个 `Start-Process`，等 2.5s 看进程存活，再关闭：

| 工具 | alive(2.5s) | pid | 退出码 | SAC 阻止? |
|------|-------------|-----|--------|-----------|
| tool-hub | True | 21152 | n/a | 否 |
| lexicon-manager | True | 23004 | n/a | 否 |
| blocklist-manager | True | 7444 | n/a | 否 |
| settings-tool | True | 26772 | n/a | 否 |
| reverse-lookup | True | 16216 | n/a | 否 |
| diagnostics-tool | True | 44900 | n/a | 否 |
| system-lexicon-audit | True | 34148 | n/a | 否 |

7/7 启动后存活、未立即崩；SAC 强制模式下均未被阻止（已安装二进制已被放行）。安装位置 `C:\Program Files (x86)\YIME\go-backend\*.exe`，均 2026-07-11 22:19 构建。

### 4. 三种输入模式 + 语言栏按钮 + go_backend.log ✅（程序态）

**TSF TIP 注册**：
- TIP CLSID `{35F67E9D-A54D-4177-9697-8B0AB71A9E04}`
- `InprocServer32 = C:\Program Files (x86)\YIME\x64\PIMETextService.dll`

**语言栏按钮**（`go-backend/input_methods/yime/yime.go:1236 addButtons`）：
- `windows-mode-icon`（中西文切换，`ID_MODE_ICON`）
- `lexicon-manager`（用户词库，`ID_USER_LEXICON_MANAGER`）
- `reverse-lookup`（反查编码，`ID_REVERSE_LOOKUP_TOOL`，含“音元拼音”子菜单 yime.go:1730）
- `settings`（设置，menu）
- `tools`（工具）
- 外加 toggle 按钮（`appendLangBarToggleAddButtons`）

**go_backend.log**（`C:\Users\tsaan\AppData\Local\PIME\Logs\go_backend.log`，38MB，最近写 2026-07-12 12:28:08）摘录真实会话：
- 2026-07-12 10:52:03–07：输入 `5jkl9JKL` → 候选 `["测试","侧室","策士","侧视","策试"]` → `selectCandidate` → `commitString:"测试"`。
- 2026-07-12 10:54:40：输入 `q` → 候选 `["吧 ~f","吧嗒 ~fwf",...]`。
- 每帧带 `changeButton:{"id":"windows-mode-icon","icon":"...\\icons\\chi_half_capsoff.ico"}` → 语言栏模式按钮实时更新。
- 2026-07-12 12:28:08 `收到 EOF，服务器停止`（本次重装 pre-flight 停 PIMELauncher 所致）。

**Rime 用户库**（`%APPDATA%\PIME\Rime\`）：`yime_full.userdb`、`yime_variable.userdb`(2026-07-12 10:54 写)、`luna_pinyin.userdb`、`cangjie5.userdb` 均在用。

> 完整“三模式逐一点击 + 三按钮点击留痕”属人工交互测试，未自动执行；程序态证据（TIP 注册 + 真实组词/上屏 + 按钮代码 + 模式按钮 changeButton）已确认链路通。反查/候选数/设置点击路径由回归测试守护（见 AGENTS.md）。

### 5. CodeIntegrity Operational 日志 ⚠️

24h 内 `3033/3077/3118` 共 **686** 条：
- **3118：0 条**。
- **YIME 相关 131 条**：65×3033 + 66×3077，时间窗 **2026-07-11 21:54:49–22:00:26**（约 6 分钟）。
  - 全部为 `PIMELauncher.exe` 加载 `go-backend\server.exe` “未达 Enterprise 签名级别 / 违反代码完整性策略（Policy ID {0283ac0f-fff1-49ae-ada1-8a933130cad6}）”。
  - 2026-07-11 22:00 后**无新增 YIME CI 事件**（14h+），IME 仍可用 → 当前 `server.exe` 未被阻止（SAC 已放行，疑因安装早于 SAC 启用/已加入放行）。
- **非 YIME 噪声**：`Program Files\Bonjour\mdnsNSP.dll`（svchost 加载）、`Common Files\Keyman\Keyman Engine\keyman64.dll`。
- SAC 状态：`VerifiedAndReputablePolicyState = 1`（**Enforce**）。

> 结论：日志非“全清”，存在历史 YIME 审计事件；当前无活跃阻止。这是“公开发布需签名”的实证：在 SAC/WDAC 强制机上，未签名 `server.exe` 会被审计/可能被阻止。

### 6. runtimechange “应用并重建 / 词库应用后会话刷新”协议 ✅

```
go test -race -count=1 ./input_methods/yime/runtimechange/...
  ok  github.com/tsaanghwang/Yime/go-backend/input_methods/yime/runtimechange  1.438s

go test -race -count=1 ./input_methods/yime/...
  ok  yime 1.473s | codemode 1.272s | reverselookup 1.317s
  ok  runtimechange 1.445s | settings 1.254s | systemlexicon 1.301s
  ok  userblocklist 1.272s | userlexicon 1.270s | win32ui 1.254s
  diagnostics/toolhub: [no test files]
```

全包 `-race` 全绿，数据竞争修复（`IME.entryMu` / `testBackend.mu`）仍稳。

### 附：build64 Release PDB ✅

```
build64/PIMETextService/Release/PIMETextService.pdb       5,705,728  2026-07-12 12:21:28
build64/PIMETextService/Release/PIMERpcResponseTests.pdb  2,379,776  2026-07-12 12:21:22
build64/PIMETextService/Release/PIMERpcResponseTests.exe  SHA256前16=C280C6FEE10CA239
```

`PIME_RELEASE_DEBUG_INFO=ON` 持久化生效；C++/TSF DLL 调试符号就绪。

---

## 发布前需解决的事项（本次验证后更新）

1. ~~**Win32 `PIMELauncher` 重建链路断裂**~~ ✅ **已修复（2026-07-12）**
   - 修复：`CMakeLists.txt` 升级 Corrosion 至 v0.6.1 + 固定 `Rust_TOOLCHAIN=stable-i686-pc-windows-msvc`（i686 host，消除跨编译）；新增前置 `rustup toolchain install stable-i686-pc-windows-msvc`。
   - 验证：`cmake --build build --config Release` 成功产出 `PIMELauncher.exe`+x86 DLL+PDB；`Reinstall-PIME-Test.cmd` 全程通过；build↔installed 三件哈希一致。
   - 已完成：`rustup toolchain install stable-i686-pc-windows-msvc --profile minimal` 已写入 README、CI 和发布前置步骤；后续若升级 Corrosion/Rust 仍需复跑 Win32 全量重建。

2. ~~**installed 与 build64 不同步**~~ ✅ **已修复**：重装后 PIMELauncher.exe / x86 DLL / x64 DLL 三件 build↔installed 哈希全一致。

3. **未签名二进制在 SAC/WDAC 强制机上的放行风险**（仍需处理）
   - 2026-07-11 21:54–22:00 有 131 条 `server.exe` CI 审计事件；当前本机已放行，但在全新 SAC/WDAC 强制机上未签名 `server.exe`/工具可能被阻止。
   - 建议：公开发布前取得可信签名（OV/EV 或 SignPath 开源免费签名），或明确文档声明“SAC/WDAC 强制模式需放行/审计模式”。

4. ~~**网络尾巴（小）**~~ ✅ **已修复（重启后 13:10）**：github 直连不通的根因是本机走 `localhost:1081` 本地代理（WinINET 系统代理），而 git/cmake 不读系统代理设置。设 `HTTPS_PROXY=http://127.0.0.1:1081` 环境变量后 configure 成功，`build/_deps/corrosion-src` 已恢复，增量构建正常。注意：以后命令行重 configure `build/` 需带该代理环境变量（或 `git config --global http.proxy`）。仍可考虑 vendoring corrosion 彻底脱网。

## 可接受的开发期现状

- 开发期（本机已放行）继续用未签名自建包即可；C++/TSF 调试链路已就绪（PDB 持久化 + charmap launch 配置 + VS Code attach）。
- 不发布、仅自用的开源版本可长期维持现状；上述 3 缺口仅在“正式公开发布”时为阻塞项。
