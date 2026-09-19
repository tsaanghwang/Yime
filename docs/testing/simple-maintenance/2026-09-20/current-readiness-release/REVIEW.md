# current-readiness 完整包交付核验

日期：2026-09-20。影响产品：YimeCore、Rime/PIME。分支：`codex/current-readiness-release-delivery`；起点为最新 `main` 的 `0ab8631266736775bf1386f456d4a1d53e8e2eb3`（PR #62 合并提交）。

## 结论

**暂不发布或上传 current-readiness 完整包：原包重现与来源核验条件未满足。** 已准备[交付状态文件](RELEASE-PLAN.json)，其中真实 Release URL、asset URL、ZIP 大小和 SHA-256 均为 `null`，没有把预定文件名写成已经存在的下载地址。

已核实源码关系、六次成功 CI、13 项本地非系统变更检查、两份与历史哈希一致的清单、225 个现有安装载荷和注册信息保持不变。原完整包目录、admission summary/inventory 和原构建记录不可用；现有证据不足以证明同一个完整包可以重现。没有用旧 Release、已安装载荷或 GitHub 自动 Source code ZIP 替代。

本轮封存的 98 个原始证据/执行记录文件共 524602 字节，逐文件索引见 [EVIDENCE-SHA256.json](EVIDENCE-SHA256.json)。此索引仅用于核验本轮证据，不是产品安装包清单。

测试端 **无任务**。唯一当前入口是 [HANDOFF](../../../../../installer/simple/HANDOFF.md)。本报告不要求同步、安装、卸载、进程重启、输入验收或用户数据重置。

## 来源与 CI

原报告关联最后一个运行代码提交 `53b409d7713ad47e0ae1039e060462012614d7b2`。它是当前 main 的祖先，两者 diff 仅新增 `DEVELOPMENT.md`、`post-reboot.json` 两份验收报告；没有构建相关源码差异。实际原包的 source snapshot、dirty 状态和构建命令没有随原报告封存，因此这里称其为关联源码，不声称它已完成整包构建来源证明。

已实时从 GitHub 读取下列 run 的完整作业/步骤状态，全部为 completed/success，且每次 12 个作业均 success：

| 提交 / 用途 | CI |
| --- | --- |
| `d228aaae`：旧用户输入条目清理边界 | [35410109813](https://github.com/tsaanghwang/Yime/actions/runs/35410109813) |
| `e2569762`：系统语言列表视图 | [35410743586](https://github.com/tsaanghwang/Yime/actions/runs/35410743586) |
| `53b409d7`：E3 缓存运行代码 | [35411599859](https://github.com/tsaanghwang/Yime/actions/runs/35411599859) |
| `9f569649`：首次验收报告 | [35413263479](https://github.com/tsaanghwang/Yime/actions/runs/35413263479) |
| `2c8ebd5e`：重启后报告 | [35415060417](https://github.com/tsaanghwang/Yime/actions/runs/35415060417) |
| `0ab86312`：当前 main | [35418522827](https://github.com/tsaanghwang/Yime/actions/runs/35418522827) |

这些 CI 包括 Go、race、native、real-Rime 三分片、simple-installer、离线工具及最终 core gate。正式 `v*` tag 才执行的 release-readiness 步骤本次未适用，不能由普通分支 CI 成功宣称正式发行条件通过。

原始 Git/GitHub 响应、命令和输出 SHA-256 保存在 [raw/audit-20260920](raw/audit-20260920/summary.json)。源码与 main CI 的附件都是 native 组件、Rime 分片证据、libIME2 变更报告；工作流没有上传完整双产品包。Release 列表只有既有 PR57、09-14 和旧 dev 发布，没有 current-readiness asset。

## 清单、哈希与本地证据

原报告指向的工作树 `C:\dev\Yime.worktrees\current-readiness-gates`、其原包目录、admission 目录及安装前审计 JSON 均不存在。这些旧路径只用于证据缺失记录，不作为交付地址。在当前仓库 `.tmp` 下限定搜索的 38 份 `product-package.json` 中，没有目标哈希；搜索清单见 [local-manifest-search.json](raw/local-manifest-search.json)。没有遍历其他仓库来导入源数据。

安装器在安装时会按字节保留清单到本产品 `.setup`。本轮仅从两个安装目录只读取回以下文件，原样保存于 [retained-metadata](raw/retained-metadata/index.json)：

| 文件 | 字节 | SHA-256 | 核验 |
| --- | ---: | --- | --- |
| YimeCore product-package.json | 11165 | `67cbdf516ae8e4348f47ffa5bc7d94d1468d200c320b66b4a1d73ce649facf8d` | 与 09-19 摘要一致，65 条 |
| Rime/PIME product-package.json | 31324 | `2996982b88c70b251124847fd6fa37ada185a6c173de1139cbb32afda8324d38` | 与 09-19 摘要一致，160 条 |
| admission summary（未找回） | 未知 | `a08430e0a59030cdc4b4c749dd2dc7aa7044ea393c7b6e80cab737ebda6d478d` | 仅原报告记录，未重验 |
| admission inventory（未找回） | 未知 | `9dfd92d65181a940263d61fe008d8c39fe799ef5d2f4a3a769db1dbe053379e2` | 仅原报告记录，未重验 |
| 完整包 ZIP（未找回） | 未知 | 未知 | 原报告未给出 ZIP 身份 |

清单路径安全、唯一性及预期文件的长度/SHA-256 检查通过，当前安装中 YimeCore 65/65、Rime/PIME 160/160 匹配。只读 `go version -m` 检查 19 + 12 个 Go 二进制，均没有 `vcs.revision` / `vcs.modified`；这既不能认定其构建工作区干净，也不能反推精确源码提交。未执行这些二进制、未复制载荷制包。详见 [installed-read-audit](raw/installed-read-audit/summary.json)。

上述检查前后，两个产品 HKLM CLSID/TIP 的 x64/x86 定点注册快照哈希一致。这证明该观察窗口内这些注册信息未变化，不证明新注册、前台激活、当前开机自启动或实际输入。没有读取学习库、词库或其他用户状态。

历史 YimeCore 安装原始日志也已按字节留存。原报告的首次失败编号 `37498156b3a9436a93470e231eaac5c` 有笔误；通过相同编号前缀找到真实编号 `37498156b3a9436a934ee3af2a1f5706`，其时间、包路径、`0x800700B7` 和退出 1 均与描述对应。随后 `a111aff33e8640a0b93470e231eaac5c` 日志显示注册成功，父入口退出 0。这里校正引用，不改写旧报告或日志；同一包路径不额外证明两次运行之间完整包的所有字节未变。

## 本轮验证与未完成项

13 个本地检查入口全部退出 0，具体命令、输出及逐文件 SHA-256 见 [local-checks/README.md](raw/local-checks/README.md) 和 [summary.json](raw/local-checks/summary.json)：

- PS5 安装器兼容：必需资源合成包、用户配置移除失败 mock、单/双产品合成调度、旧条目清理 mock。
- PowerShell checked 入口回归；构建契约、CI 调度、分片覆盖契约。
- 工具链锁、外部归档锁元数据、仓库数据边界、vendor 文件哈希、PSC 快照。

合成调度输出中的 Install/Uninstall 只是独立临时目录的模拟脚本，不是产品安装。PowerShell 调用均经 `tools/powershell/run_checked.py`；本机未运行真实 Setup、注册程序或实机 host。

| 验证项目 | 本轮状态 / 原因 |
| --- | --- |
| 源码静态/合成检查 | 通过，13 个入口 |
| 历史 manifest 身份与当前安装载荷静态哈希 | 通过，225 个文件 |
| 原完整包 Read-Package、真实包 Test-Product、包入口与独立产品检查 | 未完成：原包缺失；现有安装核验不能替代 |
| 原 admission summary/inventory 及构建 source snapshot | 未完成：原始文件缺失 |
| 从源码重新构建并与原包逐文件比较 | 未执行；不能声称原包可复现 |
| 本地 Test-Startup、Test-Logging、Test-ProcessWait | 未重跑；相关原提交和 main CI 已通过。本轮限制用户注册表/日志写入和非必要进程操作 |
| native registered/live host、重启、E3 性能复测 | 未重跑；保留 09-19 历史结论及原限制 |
| Release 上传后实际下载/hash 验证 | 未执行：没有合格完整包，未创建 Release |

原 [DEVELOPMENT.md](../../2026-09-19/current-readiness/DEVELOPMENT.md) 与 [post-reboot.json](../../2026-09-19/current-readiness/post-reboot.json) 原字节保留。历史上可用 x64/x86 开发机验收已记录；ARM64 实机、正式签名、正式发行冻结状态没有改变。当前测试端也没有新增验收结论。

## 复核与后续

从仓库根目录运行 `python docs/testing/simple-maintenance/2026-09-20/current-readiness-release/collect_evidence.py --output <新的输出目录>` 可重复 Git/GitHub 和路径只读核验；不得覆盖已封存输出。安装副本静态核验脚本为 [verify_installed_metadata.py](verify_installed_metadata.py)，同样要求 `--output <新的输出目录>`，只读取清单指定载荷和定点注册信息，不运行产品。首次执行版本单独封存为 `raw/installed-read-audit/verify_installed_metadata.executed.py`，其哈希与当次 summary 对应。`raw/local-checks/run_checks.py` 也是当次执行代码留档；不要在封存目录内原地重跑，可按 command.json 中的独立命令验证并另存输出。

开发端后续找回原包及原始构建/admission 证据后，核对本报告四项既有哈希、原包入口、载荷及来源，再完成所有适用非变更包验证；如重新从源码构建，应建立新的构建身份，保留原包证据缺口，不继承历史实机验收。通过条件后生成并上传明确 asset，下载核对字节/SHA-256，更新 HANDOFF。此处仅记录下一步，不派发测试机任务或安装授权。
