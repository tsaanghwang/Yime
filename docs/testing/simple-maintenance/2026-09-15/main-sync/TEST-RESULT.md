# 测试端 main 分支同步结果

- 执行时间：2026-09-15 12:06–12:08（Asia/Shanghai，UTC+08:00）。
- 测试机名称：计算机。
- 涉及产品：共同源码与测试报告；本次仅同步 Git。
- 仓库：`C:\dev\Yime-localtest`；origin：`https://github.com/tsaanghwang/Yime.git`。
- 执行及交付分支：`perf/i7-7820x-local`。
- 执行依据：提交 `ffff9e08819fbdb3cd3d015111d0f21a9eb27caf` 中的 `installer/simple/TEST-BRANCH-SYNC.md`。按该版本执行单合入 `origin/main`，没有合入交接分支。

## 提交记录

| 项目 | 提交 |
| --- | --- |
| 同步前本地测试分支 | `7ab9566fee2611f2adda03ccdd4ac31fdec3b799` |
| fetch 后远端测试分支 | `7ab9566fee2611f2adda03ccdd4ac31fdec3b799` |
| 本次主线 origin/main | `86005b5838e8e1b4acbe00dcb764da507a46ca65` |
| 合并后提交 | `fadc8b18b10981e0cc4a7e5a3dbd9456679285cb` |

本文件随后单独提交并推送到测试分支；报告提交号由 Git 历史标识，最终远端核对结果在任务回复中记录。

## 执行与检查

1. 已阅读检出中的 `AGENTS.md`；仓库根目录、origin、机器名和当前分支符合执行单。初始工作树干净，无在途报告、未知改动或进行中的 merge/rebase，无需另行保留或暂存文件。
2. `git fetch origin main perf/i7-7820x-local` 成功；`git switch perf/i7-7820x-local` 成功。`git rev-list --left-right --count HEAD...origin/perf/i7-7820x-local` 为 `0 0`。
3. 查看两边提交后执行 `git merge --no-edit origin/main`，退出码 0，使用 ort 策略生成普通合并提交，无冲突。
4. 合并后 `git status --short --branch` 显示工作树干净、测试分支 ahead 8；`git diff --check` 退出码 0；`git merge-base --is-ancestor origin/main HEAD` 退出码 0。
5. 三条原始报告提交 `50f70a9c`、`85aec9c4`、`7ab9566f` 分别通过 `git merge-base --is-ancestor <提交> HEAD`，退出码均为 0。
6. `2026-09-14/source-candidate-test/` 下同步前已有的 15 个文件，其合并前后 Git blob 内容全部相同。该目录仅新增开发端 `REVIEW.md`。10 个 raw 文件的工作树字节也与同步前 Git 内容完全一致，且全部通过既有两个证据索引的字节数及 SHA-256 校验。
7. 首次额外执行“工作树字节直接对比 Git blob”时，4 个 Markdown/JSON 文件触发断言；复核确认仅为检出 CRLF 与 Git LF 的差异，合并前后 blob 无变化，10 个原始文件无差异。未改写报告、日志或既有哈希。

## 范围与结论

本次主线已无冲突合入测试分支，既有测试报告及原始证据保留。此次没有执行构建、安装、卸载、注册、输入、重启或性能测试，没有停止产品进程、修改默认输入法或用户数据；不改变既有验收结论。Git 包含关系与证据完整性检查不是新的安装或输入验收。
