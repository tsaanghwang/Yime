# main c1482a84：Rime 内存与 TSF actualEligibility 隔离回归记录

2026-11-06，Asia/Shanghai。验证来源为 `C:\dev\Yime` 的本地 `main`，完整提交为 `c1482a847e98ce756ecf6d3e5e9988c782d02322`（PR #105 合并提交）。本记录整理已经完成的运行，不重跑测试。远端跟踪引用已有后续提交，本结果仅对应指定的 c1482a84，不代表后续提交的验证结果。

## 结果

| 项目 | 结果 | 原始日志 |
| --- | --- | --- |
| Rime 内存回归，普通模式 | 3/3 通过，退出码 0 | [rime-normal.log](raw/rime-normal.log) |
| Rime 内存回归，race 模式 | 3 项 × 20 轮，60/60 通过，退出码 0 | [rime-race.log](raw/rime-race.log) |
| TSF 内存回归，x64 Release | 新目录配置和测试目标构建成功；CTest 1/1 通过，退出码均为 0 | [tsf-test.log](raw/tsf-test.log) |

Rime 三项为 `TestRimeAPIFunctionAtValidatesDataSize`、`TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex`、`TestCStringAtCopiesBoundedExternalMemory`。测试使用 `runtime.Pinner` 固定 Go 内存夹具，保留截短表、无效地址/索引、未终止字符串拒绝断言，并检查栈增长后的数据更新读取。race 的 20 轮为预设的一次命令执行，没有发生失败后重跑。

TSF 的 `actualEligibilityQueries()` 直接调用生产 `actualEligibility(state)`，并断言默认 `state.query` 仍为 `actualEligibility`。它使用内存 `ITfThreadMgr` 和 `ITfInputProcessorProfileMgr` 替身，覆盖匹配成功、错误 CLSID/profile/type、线程无焦点、接口缺失以及查询失败的拒绝路径，包括非 S_OK 返回值。测试同时检查只执行所需查询，未调用 profile 激活或更改方法；不是只调用可替换的 `eligibility->query`。

## 命令与构建范围

Rime 从 `C:\dev\Yime\go-backend` 执行：

```text
go test ./input_methods/yime -run "^(TestRimeAPIFunctionAtValidatesDataSize|TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex|TestCStringAtCopiesBoundedExternalMemory)$" -count=1 -timeout=120s -v
go test -race ./input_methods/yime -run "^(TestRimeAPIFunctionAtValidatesDataSize|TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex|TestCStringAtCopiesBoundedExternalMemory)$" -count=20 -timeout=120s -v
```

仅为子进程设置 `CGO_ENABLED=1`、`CC=gcc`，PATH 前置现有 `C:/msys64/ucrt64/bin`；Go 缓存位于仓库 `.tmp/gocache` 和 `.tmp/go-tmp`。没有安装工具或修改全局环境。

TSF 使用全新目录 `C:\dev\Yime\.generated\c1482a84-memory-regressions-20261106`，Visual Studio 17 2022、x64、Release，配置 `YIME_TOUCH_PRODUCT=ON` 和 `YIME_TOUCH_FRONTEND=ON`。仅构建 `YimeTouchFrontendEditTests`，通过 CTest 精确筛选 `^YimeTouchFrontendEditTests$` 运行。未重新构建两类 TIP，也没有覆盖以前的构建目录。精确命令、工作目录、环境及退出码见每份日志同名的 JSON；执行脚本保存在 [raw/verify_c1482a84_memory.py](raw/verify_c1482a84_memory.py)。

## 证据保全

- 测试运行前后的 `before.json` 与 `after.json` 内容及 SHA-256 相同，源码、分支/提交和工作区状态均未改变。
- 原有五个未跟踪目录的 174 个文件，共 1,232,610,158 字节，路径、大小和 SHA-256 全部一致。
- 41 个原始证据文件 SHA-256 一致，包括既有 PR #101/#105 归档及其来源文件。具体路径和哈希在 [raw/before.json](raw/before.json) 与 [raw/after.json](raw/after.json)。
- 本次来源目录的原始 SHA-256 清单 12/12 校验通过。13 个来源文件（含该清单）和原执行脚本共 14 份归档副本均逐字节复制，原件保留原位；副本来源、字节数和哈希见 [VALIDATION.json](VALIDATION.json)。
- 整理记录时再次复核上述保全结果，仅新增本记录目录；没有提交、推送或修改旧记录。目录及 raw 子目录的 `.gitattributes` 禁止文本转换；新的 [SHA256SUMS.txt](SHA256SUMS.txt) 覆盖除清单本身之外的全部归档文件。

未激活真实 TIP、未安装/注册、未更改默认输入法。本次仅为内存隔离开发证据，不代表真实宿主、已安装输入法或物理输入验收。
