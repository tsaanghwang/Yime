# 独立输入路由诊断候选（待审阅，未交付实机）

## 身份及范围

- 本地分支：`codex/pr87-input-routing-diagnostics-20261101`。
- 精确基线：固定 PR87 包源码 `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，而非当前 main 或任务汇总分支。选择该基线是为了限定与现有异常报告的代码差异；不把后来 main 的改动夹带进诊断候选，也不将此分支直接视为可合并 main。
- 这是**新诊断版本**，不是原 run41178044364 / artifact13034145597、13033634731 的固定包；原包、哈希、三机任务、结果、c27 runner及四机汇总全部保持原样。
- 只增加应用自身预览输入诊断。输入分支、校准、手势语义、去抖/笔重接触参数不作修复。不能继承原固定包真人验收或据新日志直接判断硬件根因。
- 尚未推送代码、启动CI、构建完整交付包或运行任何用户设备；原生Windows执行结果须另行验证。本文件的后续办法不是发布或实机运行授权。

## 为什么需要新日志

MyComputer报告笔保持时手指翻页无响应，MSI报告保持期间提前UP关联提交，ASUS存在成功的限定混合样本。这些不是一个已确认根因。原trace可以记录消息、触点flags与正文/组合长度，但没有清楚的路由/过滤及翻页决定；约20分钟等待/准备也不能算单一短动作。

本候选补充只读元数据，保留旧字段。生命周期标记用于区分启动、最小化、恢复等边界，**不能自动证明用户已完成候选准备或某条物理动作**。阶段变化须结合明确操作记录，不将日志时间直接当物理接触时长。后续如果另获授权实机验证，必须先一次性给完整步骤，再由用户恢复→重新准备→操作→观察→最小化反馈；不能要求最小化后仍保留组合。

## 隐私与诊断限制

- 仅当前应用窗口消息/内部状态；不监听全局输入，不输出正文、组合原文、候选文本、宿主文档或凭据。
- 错误以固定原因/数值结果表达，不直接输出可能含路径或正文的错误字符串。
- 旧trace仍可能包含窗口消息参数、触点坐标、键ID、长度与时间，属于诊断数据，应本地审阅后再决定是否上传；不默认收集视频/截图。
- 无trace配置时不增加诊断文件或调用额外系统查询；记录失败不得修改输入动作。开启同步日志仍可能增加I/O开销，不能用诊断包测可靠性频率或输入性能。
- 缺失事件不能直接证明物理未接触：先检查记录是否健康、消息读取是否成功和窗口/阶段是否匹配，再区分系统未送达、应用过滤或手势/分页拒绝。

## 日志字段与读法

所有行新增 `schemaVersion=2`、`diagnosticVersion=pr87-routing-v1`、`messageID`、`epoch`；保留递增sequence及时间。messageID在窗口消息嵌套时保存/恢复，0表示不在被追踪的窗口消息上下文；epoch随最小化后的恢复递增，不是人工测试次数。

| stage | 内容/含义 |
| --- | --- |
| touch-read / touch-frame | 读取成功/失败，成功帧触点数及原有ID、flags、坐标、nativeTime；失败不输出错误原文 |
| touch-route | 接受down/move/up、掌触DOWN跳过、笔重接触抑制；nativeContactID是原生ID，gestureID=ID+1 |
| mouse-route | 接受或兼容重复抑制，gestureID=0代表鼠标兼容路径，不是原生触点0 |
| gesture-down/up/cancel/result | 命中动作、接受、无待办、移出、版本失效等固定原因；不含候选文本 |
| page-hit / page-request / page-result | 翻页命中是否启用、方向、前后页码、可翻页状态、无变化/边界/分派失败等；page-hit没有独立gestureID，要按同一消息内sequence对应前方touch-route和后方gesture-down，不能只用messageID把多触点帧合并成一个触点 |
| lifecycle | 开始需要准备、最小化、恢复需重准备、尺寸可见、销毁；不是自动识别“用户已完成准备” |

WM_MOUSEMOVE / WM_POINTERUPDATE 仅在存在待办手势时记录，避免空闲悬停新增高频日志；DOWN/UP边界仍记录。WM_TOUCH 帧仍沿原路径记录，不受该移动消息门控；筛选后的MOVE不是完整全局轨迹。touch-route的“accepted”表示进入下一层，不保证最终手势/翻页完成；必须继续看gesture/page结果。合法UP一次提交不能单凭日志解释为真实笔尖物理离屏，成功/失败不自动归因设备。

## 后续构建办法（须先获代码发布批准）

拟发布至同名独立诊断分支，不覆盖 `codex/git-task-exchange-20261031`、main或结果分支。审阅批准后，记录新不可变源码提交；现有 `.github/workflows/touch-terminal.yml` 可在该 `codex/**` 分支运行 Windows 回归、完整amd64构建/包检查及ARM64交叉构建，另有普通Build。CI通过不等于真人输入通过；ARM64交叉产物不等于原生ARM64执行通过。

现有工具链流程（这里只记办法，不执行下载资源或产物部署）：

```text
python tools/touch_keyboard_resources.py fetch --output-dir <独立资源目录>
python tools/build_touch_keyboard_desktop.py --data-dir <独立资源目录> --arch amd64 --output-dir <全新诊断amd64目录>
python tools/build_touch_keyboard_desktop.py --data-dir <独立资源目录> --arch arm64 --output-dir <全新诊断arm64目录>
```

构建必须来自新提交且工作树干净；保存新CI run/artifact、manifest.sourceCommit/sourceChanges、ZIP/manifest/EXE及payload哈希、原生/交叉构建身份。默认完整包是独立实验目录，不安装/注册/改默认输入法。不要拿仅交叉编译的测试EXE当完整中文诊断包，不复用原PR87 artifact编号或包目录。实机测试需审阅新包身份和明确授权后另定最小步骤，当前不派发新任务。

## 本地验证记录

见同目录 `VALIDATION.zh-CN.md`（交付时填写实际结果）；Linux测试、Windows交叉编译、静态审查与原生Windows运行分开，未执行的项目不记通过。
