# S3c：一次只读语言环境盘点

这是新的独立只读授权，不复用或续期先前的注册授权。当前先本地准备，发布与实际派发尚待父级明确交付；不是已运行结果。

## 仅查询什么

隔离 Windows CI 中仅编译 `YimeInputLanguageInventory`，无参数执行一次：读取当前线程 HKL、GetKeyboardLayoutList 返回的已加载布局集合、TSF 当前语言及相关语言桶的输入法 profile。完整 HKL 的键盘 profile 匹配与 TIP substitute 参考分开；无法确定关联记 unknown，不把语言低位相同当作等价，快照也不是原子状态。保留固定提交、EXE SHA-256、run ID 和原始结构化查询结果。

不加载/激活/切换布局，不设置语言，不注册/启用输入法，不构建或调用注册 probe，不请求权限提升，不接触用户电脑。查询完成只表示数据收集完整，**不是中文环境可用、激活成功或产品通过**；不满足后续条件时停止，另议预先配置中文的独立测试虚拟机，不在本环境反复试。

## 独立派发门

开发分支的原 `Build/ci.yaml` 仅新增默认空输入和可选 reusable job：

- `confirm_18u_language_inventory=once-18u-language-inventory`；
- `confirm_18u_registration` 必须空；注册 job 同时要求盘点输入为空，二者互斥；
- 固定分支 `codex/18u-formal-tip-s3c-20261101`；
- `expected_18u_source_sha` 必须与实际 run 的完整 SHA 相等；
- 仅 `workflow_dispatch` 且 `run_attempt == 1`。push/PR 不盘点，rerun 不再执行。

父级确认发布的固定 SHA 后，已有登录态的用户才执行一次（替换 SHA 占位符）：

```sh
gh workflow run ci.yaml --repo tsaanghwang/Yime --ref codex/18u-formal-tip-s3c-20261101 -f confirm_18u_language_inventory=once-18u-language-inventory -f expected_18u_source_sha=<父级交付的40位固定SHA>
```

不要填写注册确认。原 Build 的其他 jobs 保持原样；云端连接器没有 dispatch 能力，不声称已经派发。若派发状态不确定，先查 run，不能自动再发。

## 证据与停止

原生调用限 60 秒一次，失败/超时保留部分数据和错误状态，不自动重试。工作流只有 `exit 0 + status complete` 且结构化查询完整才标 `queryCompleted=true`；`environmentSuitabilityEstablished` 始终为 false，留待人工审阅。构建、输出及过程元数据由 `always()` artifact 保存。

Linux 本地仅验证 YAML/Python 与模拟结果判定；真实 MSVC 编译及 Windows 查询未由本地测试替代。若后续确需注册/切换/激活，必须另行明确授权，不从这次只读许可推导。
