# SR4-B4：DP1 共享源码变更后的 local.13 重构

日期：2026-09-05。影响面为 YimeCore 自研版 Stage5C 固定来源闭包和未安装候选构包。Rime/PIME 的定向退出修复改动了 `go-backend/input_methods/yime` 下被该闭包锁定的共享源码；因此 SR4-B3 的 local.13 包仍保留为历史证据，但不再代表当前源码。本批重新准入并构包，没有把 Rime/PIME 变成 YimeCore 的运行依赖。

## 结果

当前未安装候选为：

- 版本：`0.1.0-local.13`
- package ID：`yimecore-local-0.1.0-local.13-dbfab0b45dd2`
- package manifest SHA-256：`70ec357cb1d7137096798d8b70e66351af34c57186b53fb59462b82149130c97`
- 文件数：85
- 默认语流音变：关闭
- 构包根：`.tmp/yimecore-local-product/speech-20260905-234758-b7db9c9f`

新鲜来源准入仍为 498 PASS、0 FAIL、3 SKIP；产品构包定向回归仍为 478 PASS、0 FAIL、4 SKIP，PowerShell 5.1／7 各 38 项，x64／WOW64 x86 直接 TSF 合同和私有 Runtime／Broker 七阶段均通过。没有观察到由共享源码修复引入的 YimeCore 回归。

## 固定证据

| 证据 | 结果 |
| --- | --- |
| `.tmp/yimecore-experiment/speech-admission-20260905-234633-841d5369665c466488da3e7f975a4ff8/summary.json` | 498／0／3；SHA-256 `e87bac1ccad7d86168a5838fbd360f568a51e5a670aade5288931470104d55c4` |
| 同目录 `source-hashes-before.json` | 当前来源清单；SHA-256 `9ef5dd5b6241c43b3fe7fb4ce8dfca165c5f14f8c73fbf4a59fd6726122c45b4` |
| `.tmp/yimecore-experiment/speech-product-package-20260905-234758-2e87afb1d0a04eb28648c03dfc172b55/summary.json` | 478／0／4；SHA-256 `e3a1a2b4d6d9c1b8816e19a8317f0cb5c55d51f5b4d1516c8ccc32ccca9139be` |
| `.tmp/yimecore-local-product/speech-20260905-234758-b7db9c9f/summary.json` | 构包通过；SHA-256 `478ad1ce5b3665fcb62140de1998c4036a7d18954d8ab91670375cc8358aca1f` |
| `C:\Users\tsaan\YimeCore Isolated Fixtures\SR4B2\speech-product-test-20260905-2349-directed-exit-a1\summary.json` | 私有七阶段通过；SHA-256 `75288cee59b323a4b4ff4b241cde5292bdfa51755fa43621092fcef3ee79b14b` |

包内与源码的 `maintenance/local-maintenance-safety.ps1` SHA-256 均为 `e3796a834c4dd6638b6cd588d6ea43ba8db3808b838a67a37736e83a2ba88790`。准入前后现用 local.12 的安装 manifest、系统注册与进程基线保持不变。

## 证据边界

- 本批复用 SR4-B2 构包 runner，因此收据内部 `phase` 仍为 `SR4-B2`；SR4-B4 仅表示当前源码同步重构，不重标历史批次。
- 四项真实符号链接负例仍因本机权限跳过，不计通过。
- 本批没有运行真实 Rime、注册宿主、安装／升级／回退、Windows 重启或人工日用；没有读取用户正文、真实编码、生产学习或私人观察文件。
- 当前日用安装仍是 local.12。本批不是 local.13 安装交接、L5 最终确认、L6、完整 DP1 或 DP2 通过。
