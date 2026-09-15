# 测试端执行单：将 main 同步到测试分支

> 已执行并收尾：回传提交 `1509b860`，见[同步报告](../../docs/testing/simple-maintenance/2026-09-15/main-sync/TEST-RESULT.md)。下文为当时执行单，不是再次执行请求。

日期：2026-09-15。执行端：i7-7820X 测试机“计算机”的 Yime 独立检出。
涉及产品：共同源码与测试报告；本次仅同步 Git 分支。

## 本次目标

请按顺序执行本文：保留测试机报告，将最新 `origin/main` 合入 `perf/i7-7820x-local`，提交同步结果并推送该测试分支。完成后仍停留在测试分支，向用户回报结果。

不安装、卸载、重装、注册输入法，不停止产品进程，不修改默认输入法或用户数据，不重复输入、重启或性能验收。不执行旧安装包和恢复脚本，不推送 main，不强推，不清理其他工作树。

主线基准为 PR #55 的合并提交 `86005b5838e8e1b4acbe00dcb764da507a46ca65`，其 [主线 CI](https://github.com/tsaanghwang/Yime/actions/runs/34912661229) 已通过。执行时以 fetch 后的 `origin/main` 为准，并记录实际提交号。

本文发布于开发交接分支；读取本文不要求先合入该分支。此次要合入的是 `origin/main`。

## 1. 核对检出并保留在途工作

先阅读检出中的 `AGENTS.md`。以下命令在测试机的 Yime 仓库根目录逐条执行，每条成功后再继续；Git 命令可直接运行。若需要 PowerShell 语句，遵守仓库 checked 入口规则。

```text
git rev-parse --show-toplevel
git remote -v
git branch --show-current
git status --short --branch
```

确认 origin 对应 `tsaanghwang/Yime`，本次使用测试机独立检出。若机器、仓库或当前任务归属不符，停止并报告。

- 若已有未提交测试报告，检查内容后仅暂存对应报告路径，单独提交；保留原始日志字节和已有哈希。
- 不使用 `git add .`；不提交用户词库、学习库、密码或无关输出。
- 若存在不明源码改动、正在进行的 merge/rebase 或无法确定归属的文件，保留现状并报告，不丢弃、不自动 stash、不强制切换。
- 只有工作树干净后才继续。

## 2. 获取远端并同步测试分支

```text
git fetch origin main perf/i7-7820x-local
git switch perf/i7-7820x-local
git rev-parse HEAD
git rev-list --left-right --count HEAD...origin/perf/i7-7820x-local
```

记录切换后的 HEAD 为“同步前测试分支提交”。最后一条输出依次是本地独有、远端独有提交数：

- `0 0`：已经一致，继续下一节。
- `0 N`：执行 `git merge --ff-only origin/perf/i7-7820x-local`，成功后继续。
- `N 0`：本地有已保留的报告提交，无需倒退；继续下一节，最终一并推送。
- `N M` 且两者均大于零：本地和远端测试分支分叉，停止并回报两边提交，交开发端判断；不 reset/rebase/强推。

若测试分支在本地不存在，确认无同名分支后可执行 `git switch --track origin/perf/i7-7820x-local` 代替 switch；命令失败不得继续。

## 3. 合入 main

```text
git rev-parse origin/main
git log --oneline HEAD..origin/main
git log --oneline origin/main..HEAD
git merge --no-edit origin/main
```

记录第一条输出为“本次主线提交”。普通 merge 保留两边提交历史；不要求这一合并必须快进。

编写本文时，测试分支有三条报告提交 `50f70a9c`、`85aec9c4`、`7ab9566f`，主线已通过其他提交号收取其内容。这不是丢失报告；不要仅因提交号不同而重复 cherry-pick 或覆盖文件。开发端对当时两边提交做过无工作树改动的合并预演，未发现冲突，但测试机仍以实际执行结果为准。

若有冲突：记录 `git status --short` 和 `git diff --name-only --diff-filter=U`，停止提交和推送，回报冲突路径及双方提交号。不要统一选择 ours/theirs，不删除原始报告，也不要用旧源码覆盖主线。

## 4. 检查同步结果

```text
git status --short --branch
git diff --check
git merge-base --is-ancestor origin/main HEAD
git rev-parse HEAD
```

要求工作树干净、无未解决冲突，且第三条退出码为 0（没有输出是正常成功）。查看三条既有报告及其原始证据仍存在；若本机有本次同步前新增的报告提交，也应仍包含在 HEAD 历史中。

仅同步分支和记录结果，不为此运行全量构建、安装器或实机验收。分支相等/包含关系不是输入验收证据。

## 5. 记录并推送测试分支

新建 `docs/testing/simple-maintenance/2026-09-15/main-sync/TEST-RESULT.md`，至少写明：

- 执行时间、测试机名称、仓库和分支。
- 同步前本地测试提交、fetch 后远端测试提交、本次 `origin/main` 提交、合并后提交。
- 在途报告的处理方式；是否发生冲突；检查命令及结果。
- 本次只同步 Git；未执行安装、输入或重启测试，不改变既有验收结论。

若该文件已存在，保留原报告，新建一个带执行时间的目录记录本次结果。以下命令中的报告路径相应调整。

```text
git add -- docs/testing/simple-maintenance/2026-09-15/main-sync/TEST-RESULT.md
git diff --cached --check
git diff --cached --stat
git commit -m "docs(test): record main branch synchronization"
git push origin perf/i7-7820x-local
```

推送的是测试分支，不是 main。推送失败时保留本地提交并报告；若提示远端新增提交，重新 fetch 检查，不能强推。

## 6. 最终确认与回报

```text
git fetch origin perf/i7-7820x-local
git rev-list --left-right --count HEAD...origin/perf/i7-7820x-local
git merge-base --is-ancestor origin/main HEAD
git status --short --branch
git rev-parse HEAD
```

成功条件：左右计数为 `0 0`；主线包含关系检查退出 0；工作树干净；当前分支仍是 `perf/i7-7820x-local`。若执行期间 main 又前进，只声明已同步本次记录的主线提交，不无限追赶。

最终用中文回报：

> 已将 main 的 `<本次主线提交>` 合入测试分支，并推送到 origin/perf/i7-7820x-local。最终提交为 `<提交号>`，工作树干净，本地与远端测试分支一致。报告路径为 `<路径>`。本次没有安装、重启或重新验收输入法。

若未完成，改为报告实际停在哪一步、错误、保留的本地提交及冲突路径；不要把部分完成写成同步成功。
