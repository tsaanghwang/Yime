# v2 受控原生宿主：阶段 A

状态：源码实现与离线验证范围。真实注册态、正常前端输入、未知锁 UI 和物理验收均 NOT_RUN。
只覆盖 D1 延迟写锁、D2 修改正文前失败；D3 完成回包丢失及 PR #97 不在本改动范围。

## 固定产品与边界

基线为 main 36ca828b3531d6c61740e02b6835aa930442b97a，版本 0.1.0-18u-test.12。
新增宿主是独立测试工具，不进入产品包，不修改或重新构建前端/TIP，不注册、启用 profile 或修改默认输入法。
运行入口默认只显示帮助；只有显式 --run-native 才可能进入真实 COM/TSF 路径。当前授权只允许源码与离线验证，不能运行该入口。

| 身份 | SHA-256 |
| --- | --- |
| 外层 ZIP | d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c |
| 内层 ZIP | 0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e |
| installed-18u-product.json | eb8013d504b961bf9bad6124ba6582c2f53f8cab27a34239568bdd61a62a117e |
| frontend/YimeTouchKeyboard.exe | d9a15e1e7d6da30d21db32813a92ee2c50df03b8855e0cc05f9f1482b0ffecbe |
| x64/YimeTextService18u.dll | 9193311f4a5b3aaa6e09d8e6b23adb84235444f6bea8610620fd04aaac6c1a7d |

[固定原包](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130)。
上述包身份复用已有交付核验；记录哈希不等于再次验证当前安装状态。真正运行还需匹配机器、安装根、descriptor、前端、实际加载的 TIP 和本工具 EXE。

## 构建与离线入口

使用 tests/native-host-phase-a/CMakeLists.txt 独立入口，避免根项目其他依赖和网络下载。
构建开关默认 OFF，且不把真实宿主加入 CTest。开启后仍须显式选择目标。
开关为 YIME_TOUCH_FRONTEND_NATIVE_HOST_PHASE_A；真实宿主目标为 YimeTouchFrontendNativeHost。
离线目标为 YimeTouchFrontendNativeHostOfflineTests、YimeTouchFrontendNativeHostSafetyTests 和 YimeTouchFrontendNativeHostPathTests。
使用 Visual Studio x64 生成器；离线构建目录应足够短，避免 MSBuild 的 260 字符路径限制。失败目录与原始日志保留。
构建、纯内存 fake-sink/时钟/证据失败注入测试及隔离目录路径测试只验证新工具的合同，不会启动前端、加载产品 DLL、激活 profile 或证明 Windows 注册态。
路径测试的目录由 YIME_NATIVE_HOST_PATH_TEST_ROOT 指定，只创建新的隔离 fixture，并保留结果；不修改文件系统短名设置。若卷未提供 8.3 别名，实际短名用例明确记录未覆盖，确定性的别名解析回归仍运行。

--validate-plan 只解析计划、检查固定身份和合成文本摘要，输出 NOT_RUN；不读取安装注册状态，不调用真实 TSF。
计划的字段见 [run-plan.schema.json](run-plan.schema.json)。计划必须拒绝重复键、未知字段、空值、D3 和不匹配的固定版本。
hostSha256 是本次构建工具自身的实际哈希；计划原始字节的 planSha256 在证据输出中计算，不放入计划形成自引用。

本版本 allowManualRecovery 必须为 false。此工具自动采集故障触发与独立读回，不自动执行前端的“核对后继续”或后续输入，也不会把完整验收状态写成 PASS。

## 原生场景（留待单独授权）

操作始终限定自有空白合成文档；正常已安装前端是唯一提交方。宿主不得直接发送 v2 edit、代理管道、伪造前端身份、注入旧事件或绕过正常认证。
未来真实运行时，完成身份预检和进程范围激活后，只在宿主窗口按一次 F8 武装；此前的写入尝试会使本例停止。
故障观测封存后继续正常处理消息，不立即停用 TIP。关闭请求至少等到触发后六秒，给既有完成/错误回执路径留下观察时间；该等待不是客户端已经收到回执的证明。
关闭、超时或停止先禁止后续授锁并清空 pending；六秒观察期不授权继续写入。授锁及封存之前再次检查期限，防止消息排队或回调耗时跨过截止时间。

| 场景 | 操作 | 原生证据与停止条件 |
| --- | --- | --- |
| D1 | 一次武装；拒绝同步写锁，等真实异步写锁；延迟 250–500 ms，再在原 STA 授锁一次 | 授锁前正文为空，实际授锁/写 API/OnEndEdit 被记录，独立 TSF 读回匹配计划文本。没有异步请求、提前写入、焦点/context 改变、额外提交或超时即停止 |
| D2 | 一次武装；实际 SetText 或 InsertTextAtSelection 修改正文前返回 E_FAIL | QUERYONLY 不消费故障；失败不改变正文/选择；真实失败次数及读回保留。任何部分写入、错误注入位置、额外写入或超时即停止 |

RequestLock 的 TS_S_ASYNC 与 TIP 内 RequestEditSession 的 TF_S_ASYNC 是不同层的观测，不能相互冒充。
真实锁通过 TSF sink 的 OnLockGranted 授予；排队本身不是正文写成。
参见 [Microsoft RequestLock](https://learn.microsoft.com/en-us/windows/win32/api/textstor/nf-textstor-itextstoreacp-requestlock)、
[InsertTextAtSelection](https://learn.microsoft.com/en-us/windows/win32/api/textstor/nf-textstor-itextstoreacp-inserttextatselection)。

## 结果与证据边界

应分别保存计划原文与摘要、工具/产品身份、真实事件顺序、实际写 API 次数、正文变更次数、故障次数、独立读回及清理结果。
未观测的 TIP 内 DoEditSession HRESULT、v2 请求次数、前端 outputId/session/blocked/epoch 等保持 null/unobserved。
限定窗口内“正文没有重复”不能升级为内部零重试或跨连接 exactly-once 证明。
结果中的 sourceCommit/packageSourceCommit 指被测 test.12 包；新增宿主用 hostSha256 和外部源码 diff/构建记录绑定，hostSourceCommit 不伪填为原包提交。

宿主条件满足也不能单独得出整体验收 PASS：未知锁可见、旧候选清除、暂停模式选择、人工恢复及新输入仍需另行实际观察。
D2 未来预期为保守未知锁；测试宿主知道自己未写入，不代表正常客户端可以自行解除未知锁。

故障证据封存后，本版不进行恢复卡；后续若另获准，由人工先核清正文，再做：
选择模式但仍保持未知锁 → 明确恢复且正文不变 → 仅输入不同的新文本一次。
不得为补证重复提交或点击旧候选。

## 生命周期、停止与范围限制

COM、授锁、焦点及销毁均限创建对象的 STA；异步请求只保留有界 pending 状态，回调强引用保护 owner/sink。
回调中不落盘、不睡眠、不启动其他进程；证据溢出/缺失不能记通过。
发生非计划失焦、context/模块身份变化、额外写入、超时或执行/权限错误就停止，不重试、不提权、不重装、不回滚正文。
只清理自有文档、关联和进程范围激活；无法安全清理时保留失败，不强杀其他宿主。
清理只尝试一次，并在首个 API/证据错误处停止释放剩余对象。失败会输出 INCONCLUSIVE 和原始 HRESULT/阶段，保留进程、窗口回调与 COM 引用等待人工决定；不会自动重复清理、重启或强行结束进程。
若清理失败又叠加证据序列化/写入失败，在 Host 对象仍存活时先向 stderr 输出清理阶段/HRESULT 和证据失败阶段/错误，再进入保留等待；不自动重写或把不完整证据记为成功。stderr 本身不可用时仍无法保证诊断持久化。
证据目录必须位于安装树外：通过保留的目录句柄解析安装根和输出父目录的最终路径，创建后再核验目录，避免长短文件名别名绕过字符串检查。无法取得可信目录身份时停止。

四项 P2 的离线回归覆盖：截止前/截止时/截止后的授锁、关闭后同批 timer、停止后的 pending 取消与零写入；QueryInsert 在空文档、尾部插入及长短替换时只返回当前文档范围；清理失败与证据失败的组合诊断顺序；输出目录别名、安装树内目录拒绝及路径解析失败。它们不证明真实 Windows TSF 的回调或清理顺序。

既有 MSI test.11 六项正常手指用户反馈继续有效：
[固定报告](https://github.com/tsaanghwang/Yime/blob/33bfe4f431ff0761f0a0390a40d5d13b521e390c/docs/testing/18u/2026-11-05/msi-test11-finger-auto-focus/TEST-RESULT.zh-CN.md)。
不重复这些历史流程，也不将其改记为 test.12 或本工具故障通过。
本工具只面向原生 Windows x64 自有宿主，不代表 Word/记事本异常路径、x86/ARM64、笔或其他未覆盖物理场景通过。
