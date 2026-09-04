# YimeCore local.11 本机 x86 宿主验收

日期：2026-09-04。范围仅为 `MYCOMPUTER` 上 WOW64 32 位应用；Runtime/Broker 仍为原生 x64。ARM64、老旧 x64、其他实体机和硬件分档模拟没有执行，也没有据此宣称兼容。

## 安装与注册宿主

- 已安装版本：`0.1.0-local.11`。
- 源码提交：`f435f463bfd0a0647d0d9ef9f5711c7ef55a698e`；构包时 `dirty=false`。
- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-f435f463bfd0-5a3f847a`。
- package manifest SHA-256：`5a3f847a3136fd2198f7dc9aba22dc017ed7439d8447435e8752eb379a4a5cd8`。
- x86 TSF DLL SHA-256：`6cc329939a8931a1e7194743728efaf50a5b285bdb3f4549117fa3bc9d2f1545`。
- 安装态 x64 与 x86 registered-host 在全码、变码、简码下共 6 项全部通过。x86 输出明确报告 `architecture_bits=32`，并覆盖候选提交、默认候选键、延迟异步编辑、失败写入恢复、停用后保留语言栏对象及英文 Shift。

自动证据：`.tmp/yimecore-experiment/local11-installed-x64-x86-host-20260904/summary.json`。

## 两个真实 32 位应用

| 应用 | 机械核对 | 人工输入验收 | 结果 |
| --- | --- | --- | --- |
| Firefox 155.0 | `firefox.exe` 为 PE32/I386；PID 4968 精确加载上述安装根的 x86 TSF DLL | 用户确认组合与提交、裸数字继续组字、`Shift+1` 选择首候选 | PASS |
| Notepad++ 8.9.8 | `notepad++.exe` 为 PE32/I386；PID 33112 精确加载同一 x86 TSF DLL | 用户确认同三项；测试文本曾实际写入编辑文档 | PASS |

真实宿主汇总：`.tmp/yimecore-experiment/local11-x86-live-host-20260904/summary.json`。汇总没有保存用户全文；人工观察由用户物理确认，进程位数、模块绝对路径和文件哈希由 Toolhelp 模块快照机械核对。原生应用 UI 自动控制在本轮环境不可用，因此没有把该自动化限制当作产品失败。

## 保护与结论

安装前基线与验收后 `StdRegProv` 系统视图比较的 12 项生产 PIME/Rime、冻结旧身份和默认语言设置均未变化。默认输入法仍是“简体中文(中国大陆) - 微软拼音”，本轮没有改成 Yime。当前 local.11 Runtime/Broker 从上述安装根运行。

因此，本机 x86 工作流的当前源码构建、双架构包与注册事务、安装态 x86 registered-host、Firefox/Notepad++ 32 位实际 DLL 加载和输入验收均通过，可以封存为本机 x86 结论。它不等于整个本机产品已经完成：x64 L5 日常使用观察和 L6 包/恢复介质封存仍未关闭，`local_product_ready=false`，`public_release_ready=false`。
