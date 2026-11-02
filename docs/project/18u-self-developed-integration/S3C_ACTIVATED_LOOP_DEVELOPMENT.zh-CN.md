# S3c：实际激活实例到 Broker 的单次闭环（开发候选）

基线：`733f66cbec01363cdf61040673b08797d2987bbc`。本阶段仅开发与离线／非注册验证；没有发布、执行注册、运行真实 TSF 宿主或操作用户机器。

## 最小目标

单 x64、自有宿主、CN/variable。复用 Windows 激活的独立 18u profile 实例及其 `ITfFunctionProvider`，连接固定 Broker，完成一次候选提交与宿主独立正文读回，然后正常撤销本轮身份，再由独立只读进程核验缺席。该目标不是可见 UI、Word/Edge、ARM 或安装产品验收。

旧直接加载宿主、标准 YimeCore、Rime/PIME、原包和旧失败记录保持不变。主线已有的 v3 账本、旧包兼容和清理策略沿用；不整体合并 `3bf7eec` / `d47f795` 的 v4 新事务策略。

## 边界

- 新入口默认关闭，与既有入口分离；开发授权不等于运行授权。
- 只使用同一个生命周期宿主 PID：它同时是账本 owner 和 Broker 认证的 TIP 进程；不以另建 COM 对象冒充 Windows 激活对象。
- 全部配置、工具／资源身份和 Broker 进程身份在注册前检查。仅一次 commit，不接受任意正文或外部目标，不回退 SendInput。
- 执行异常、超时、结果不完整或未知时不重放、不自动恢复；正常清理失败仍为失败，原始账本和失败证据保留。
- 正文编辑成功、宿主读回、正常退出、撤销成功、独立缺席核验分别记录；任何单个成功不代表全链通过。
- 新的文件清单只用于开发运行输入绑定，不改变原 v2 七载荷包，不等于数字签名或来源真实性认证。

## 后续授权门

先审查本地差异和离线测试。源码发布及 Windows 编译／非注册 CI 需另行批准；涉及真实 profile 注册、启用、自有进程激活、编辑、正常撤销和独立核验的运行，须明确目标与单次范围后另批。没有本机执行许可，不提供当前可执行的本机写入命令。

## 当前验证界限

本云端没有 Windows/MSVC；`/usr/bin/go` 亦非 Go 语言编译器，不能用于 Go 编译证明。最终验证记录将逐项列出实际运行命令与退出码，纯模拟和静态检查不替代原生验证。

本地实际执行 `python3 -m unittest -v test_run_activated_registration_loop test_run_mycomputer_registration test_collect_mycomputer_preflight test_local_activation_evidence`：52 项通过，退出码 0（新增 14 项，既有 38 项）。全部使用合成文件或进程替身，无原生入口调用。初次回归因选择性源码副本缺少两份既有测试依赖而导入失败；补取同一固定源码文件后通过，未改测试合同。新增 Go 8 个测试函数尚未执行；没有真实标准版或 TSF 回归通过的新增证据。

## 接线与运行边界

`run_activated_registration_loop.py` → 外层 Windows Job → `YimeActivatedLoopController.exe` → 单一 `YimeActivatedLoopOnce.exe` 与固定 Broker。原生入口复用 `RegistrationProbe.cpp` 的 v3 事务，回调现有 `Formal18uHost.cpp` 的 Windows activated provider 路径，不调用另造的 TIP 实例。共享 canonical ni 编码函数由原自有宿主测试抽取，不更换数据算法。

连接、输入和完成回执必须保持同一 sessionId、布局/词典身份、模式及焦点 context/epoch。宿主用独立 edit session 读回固定单字“你”；不是 UI 镜像或 API 返回成功即视为输入成功。宿主 PID 是账本 owner 和 Broker 允许的客户端 PID；控制器另有 PID。固定 DLL 激活 marker、编辑读回、宿主关闭、事务撤销分别验证，最后由原只读 `--verify` 进程核验缺席。

控制器 180 秒，外层注册 Job 240 秒，独立只读核验 30 秒。原生显式等待合计最多约 126 秒，但同步 Windows API 没有硬完成保证；超时仍可能留下本轮注册，不能把停止进程当作撤销。保存非空 DPAPI 密文账本及哈希，不解密，不自动恢复。`operationPendingObserved=false` 仅表示未运行特殊 pending 场景，不意味着普通提交绝无异步等待。

实际执行仍沿用 main 的 MYCOMPUTER、原生 x64、中文 0804、管理员及身份缺席条件；没有为英语 CI 绕开或更改前置条件。尚未生成或签名任何新 EXE/包，开发 manifest 不证明发布者身份。

## 下一最小阶段

先批准源码发布与限定的编译／非注册 CI：Go 1.25 编译及模拟测试、MSVC 显式编译新目标和固定 Broker/DLL/只读核验工具、Python 合成测试。若增加 workflow，需另列准确新增文件供审阅；不能运行通用 CTest 或现存注册表 fixture，也不能自动调用本次注册编排器。通过之后才讨论已满足前置条件的单一 Windows 目标、单次真实注册编辑撤销范围及异常处置授权。当前代码候选不是可交用户执行的注册包。
