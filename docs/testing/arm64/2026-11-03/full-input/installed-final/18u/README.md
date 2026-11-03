# 18u 已安装前端链验收证据

产品源码为 `46dd58967266edcab3f0d3bb131015d81dc4b951`，版本 `0.2.0-18u-arm64.1`。产品包及其 20 个安装文件在两轮控制器执行期间保持不变；本次修复仅涉及包外测试启动器。原始 UTC、FILETIME、空日志和失败记录均按原字节保留，不包含 EXE、词典或缓存。根部原有安装器前后快照保持不变。

- `checkpoint-r1/`：首轮 0/18。控制器因未知 Job 成员中止；测试 Job 已清空，普通 runtime 恢复为 PID 13308。包含当时的控制器原文及其哈希，不能记作输入验收通过。
- `no-input-diagnostics/`：只读路径比较排除了 Python 路径别名；精确无输入宿主启动证实 `CREATE_NO_WINDOW` 仍产生两个 `conhost.exe`。改用单独 `DETACHED_PROCESS` 后，仅预期启动器和宿主进入 Job，宿主持续阻塞于配置输入前，发送配置/输入字节为 0，Job 清理通过。
- `checkpoint-r2/`：两处测试进程启动改为 `DETACHED_PROCESS`，保留严格路径/令牌白名单，并在拒绝前记录全部成员。控制器源码快照和 SHA-256 随 receipt 保存。真实注册宿主完成 **18/18**：全码、变码、简码各验证预编辑读回、候选提交、英文/字面输入、编辑、取消、失焦取消；正文及另一 context 得到保护，`SendInput=false`。
- `identity-initial/`、`identity-restored-r1/`、`identity-restored-r2/`：初始及两次恢复的精确 PID、创建时间、文件哈希和实际用户令牌。最终 Runtime **29648**、Broker **6744**、GUI **29520** 均为同用户、Medium、非提升；20 个安装文件再次核验匹配。
- `display-readiness/`：Windows 报告 `SM_DIGITIZER=0xC5`、最大 10 触点、1 个显示器。这是能力声明；没有真人手指/笔、物理尺寸或尺标校准验收。
- `support-tools/`：归档上述只读采集及无输入诊断脚本；不属于安装载荷。

`checkpoint-r2/host.stdout.log` 是宿主原始成功结果，`receipt.json` 记录测试 Job 在恢复前归零，`summary.json` 汇总范围。真实前端链为 GUI → Broker → 已激活 TSF → 引擎 → 实际编辑会话；这证明原生 ARM64 注册宿主的受控软件链路，不替代任意应用、重启或真人触摸/笔日用验收。

`archive-manifest.json` 逐项绑定复制来源、大小及 SHA-256，并记录原有安装器证据的未变哈希。本归档没有重新执行产品或提交 Git。
