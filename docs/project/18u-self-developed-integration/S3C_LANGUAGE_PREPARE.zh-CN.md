# S3c：一次有条件中文输入环境准备（未发布本地稿）

用户已接受修正后的范围：仅现有中文输入组件具备时，执行一次用户语言配置追加、验证和还原；脚本不主动下载安装，但允许 Windows 自身可能伴随的语言组件处理。原先“保证完全不发生组件下载安装”的承诺不成立。本稿及代码仍待审阅与发布许可，未派发运行。

## 边界与判定

先前 Server 2025 仅观察到加载的 `0409` 环境，不能据此断言中文组件不存在。必须先以实际组件/helper证据判断；缺组件、需要重启或查询不确定均停止，不使用显式安装/卸载 API。

只在隔离云端 runner 备份当前用户设置，组件齐备后追加一次 `zh-CN` 输入配置。不主动切换测试线程语言，不加载布局、不更改默认输入法/显示语言/系统区域、不禁用其他输入法、不改网络或安全策略、不注销重启，绝不注册 Yime/18u TIP，也不动四台用户电脑。

两项结论必须分开：

1. **用户语言配置已追加**：由脚本写入及读回证据支持，不代表测试进程已经使用中文。
2. **新测试进程实际满足双 `0804` 条件**：由新的只读 native helper 进程观察；若仍 `0409`，判 blocked 并恢复，不进一步切换或重试。这不是注册失败，因为本轮根本不注册。

## 入口与执行

`Build/ci.yaml` 默认空输入 `confirm_18u_language_prepare` 仅精确 `once-18u-language-prepare` 才启用新 reusable workflow。注册、只读盘点、准备三个确认互斥：caller/callee均要求其他两项为空。仅手动dispatch、固定开发分支、固定完整source SHA、首次attempt；push/PR/rerun不执行准备。原普通Build jobs与权限不变。

只构建 `YimeChineseInputComponentQuery`；不构建注册DLL或probe。任何准备前必须在同一Windows CI通过两个真实 Job Object 自测，明确拒绝跳过：正常子进程退出、超时后派生子进程全部停止。Linux的mock测试不替代这两项。

新PS脚本仅通过 `tools/powershell/run_checked.py --edition ps5 --script ... --params-file ...` 调用。受控Python启动为suspended，先绑定kill-on-close Windows Job再恢复运行；超时终止该Job并核实活进程数为0，之后才允许独立Restore。绑定失败不启动PS，树状态未知不开展可能并发的还原。

job总上限30分钟，配置/编译分别最多180秒；首step记录单调时钟，准备前若已用超过10分钟即停止，为240秒Prepare、180秒Restore、120秒Verify及每段30秒子树停止核验保留空间。Prepare不自恢复，唯一finally编排调用一次Restore，再调用只读Verify；Restore须确认原owner已结束，先持久化还原尝试标记，禁止重复setter。恢复超时或子树不明则停止，不再写入。系统语言服务的异步处理不在该Job内，不能据此承诺全部系统活动停止。

## 恢复证据与非通过条件

保存组件前后状态、用户设置备份、操作账本、Prepare/Restore/Verify结果、Job过程元数据及原始日志，always上传独立证据artifact。blocked、超时、数据缺失、恢复失败或不确定均非绿色通过。

恢复仅核对明确记录的用户语言/default字段及profile观察；组件状态前后只做观察，不保证回滚全部系统组件处理。runner销毁不替代恢复证明。若profile启用状态恢复后不同，报告观察到的清理不一致，不擅自禁用其他TIP。

本地只完成静态/模拟验证；需要单独确认公开文件清单后才可发布。当前不提供可直接派发的命令、不新开CI、不声称Windows配置或还原已通过。
