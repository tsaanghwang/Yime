# PR 101 合并后 main 本地 TIP 构建与隔离回归验证

记录日期：2026-11-06（Asia/Shanghai）。源码目录：`C:\dev\Yime`，分支 `main`，源码提交 `415adc2030002ca8f1aad194e2eb4045e8bce72c`（PR #101 合并提交）。

本次在同步后的本地 main 上新建独立构建目录，完成两类 TIP 的 x64 Release 构建和内存 TSF 隔离回归。C4702、C4100 均为零；直接调用生产 `actualEligibility` 的回归通过；原有五个未跟踪目录内 174 个文件的 SHA-256 保持一致。

## 构建与测试结果

| 项目 | 结果 | 原始证据 |
| --- | --- | --- |
| CMake 配置 | 成功，退出码 0；MSVC 19.44.35225.0，Windows SDK 10.0.26100.0 | [configure.log](raw/configure.log) |
| 专用 `YimeTextService18u` 与标准 `YimeTextServiceExperiment` | x64 Release 构建成功；`TextService.cpp` 在两个目标中分别重新编译 | [build.log](raw/build.log) |
| C4702 / C4100 | 完整构建日志中各出现 0 次 | [VALIDATION.json](VALIDATION.json) |
| `YimeTouchFrontendEditTests` | 编译成功，CTest 1/1 通过、0 失败，退出码 0 | [test.log](raw/test.log) |
| 原有未跟踪文件 | 五个目录、174 个文件、1,232,610,158 字节，路径及 SHA-256 全部一致 | [preservation-verification.json](preservation-verification.json) |

工作目录为 `C:\dev\Yime`。本次使用全新目录 `.generated/pr101-main-20261106`，没有复用先前工作树的产物。原始命令及退出码见 [configure.json](raw/configure.json)、[build.json](raw/build.json)、[test.json](raw/test.json)。核心命令如下：

```text
cmake -S C:/dev/Yime/YimeTextServiceExperiment -B C:/dev/Yime/.generated/pr101-main-20261106 -G "Visual Studio 17 2022" -A x64 -DYIME_TOUCH_PRODUCT=ON -DYIME_TOUCH_FRONTEND=ON
cmake --build C:/dev/Yime/.generated/pr101-main-20261106 --config Release --target YimeTextService18u YimeTextServiceExperiment YimeTouchFrontendEditTests --parallel 4
ctest --test-dir C:/dev/Yime/.generated/pr101-main-20261106 -C Release -R "^YimeTouchFrontendEditTests$" --output-on-failure -V
```

## 资格判断覆盖

`YimeTextServiceExperiment/tests/TouchFrontendEditTests.cpp` 的 `actualEligibilityQueries()` 使用内存 `ITfThreadMgr` 和 `ITfInputProcessorProfileMgr` 替身。测试第 142 行直接调用 `actualEligibility(state)`，并断言默认查询函数仍为生产实现；`main()` 执行该测试，不通过替换 `eligibility->query` 绕过查询。

- 匹配 CLSID、profile、输入处理器类型且线程有焦点时接受资格。
- 错误 CLSID、错误 profile、键盘布局类型，以及线程无焦点时拒绝。
- 线程管理器或 profile 管理器缺失时拒绝。
- 线程查询返回 `S_FALSE`、其他非 `S_OK` 成功码、`E_FAIL`、`E_ACCESSDENIED` 时拒绝，即使输出焦点值为 TRUE。
- profile 查询返回 `S_FALSE`、`E_FAIL`、`E_ACCESSDENIED` 时拒绝。
- 验证查询次数、`GUID_TFCAT_TIP_KEYBOARD` 类别和 profile 替身无激活、注册等意外调用。

测试日志明确输出 `PASS frontend edits: memory TSF, actual profile/thread eligibility queries`。这是同一测试可执行文件内的覆盖，CTest 统计为 1 个测试，不将各断言重复计为独立测试。PR #101 仅调整按键回调的条件编译和未使用参数标记，没有改变 `actualEligibility` 的资格判断逻辑。

## 未跟踪文件保全

保留的五个目录为 `activated-loop-5853-preflight-r1`、`activated-loop-9d3-preflight-r1`、`installed-18u-399f-r1`、`installed-18u-bb7-r1`、`installed-18u-da3-r1`。原始清单在 main 快进前生成，在构建前、构建后均比对通过；整理本记录时再次对原有路径和文件内容进行只读核对。

[原始保全清单](raw/main-sync-preservation.json) 保存目录条目、文件长度和逐文件 SHA-256；[当前核对结果](preservation-verification.json) 保存复核时间与目录汇总。该范围仅指上述原有未跟踪目录，不包含新建的构建产物或本验证记录。原有暂存和未暂存的已跟踪文件差异均为空，构建未修改源码。

## 原始证据与边界

原始日志来源为 `C:\Users\tsaan\.codex\visualizations\2026\11\05\01a1aa30-4485-7872-9655-634d857d9dc7\pr101-main-verification`；路径日期是会话目录日期，不作为验证执行日期。原文件保留原位，本记录 `raw/` 下副本按字节复制，不改写换行或编码。复制来源、字节数和 SHA-256 见 [VALIDATION.json](VALIDATION.json)；全部记录文件的校验清单见 [SHA256SUMS.txt](SHA256SUMS.txt)。本目录及 `raw/` 的 `.gitattributes` 禁止 Git 文本换行转换，使 JSON 记录和原始日志的校验值在提交后保持有效。记录整理没有重新运行构建或测试。

仅执行配置、编译和内存 TSF 测试。未执行安装、输入法注册、真实 TIP 激活、默认输入法修改或用户文档输入；注册探测和真实宿主构建开关保持 OFF。两类 DLL 仅构建，测试执行文件为 `YimeTouchFrontendEditTests.exe`。结果不代表 x86/ARM64 构建、真实宿主输入或手指/笔物理验收。
