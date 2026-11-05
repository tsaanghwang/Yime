# ARM 18u 绑定诊断修订（仅供审阅）

基线：8264e76eb5b7475c64015672717b1958575cb883。唯一开发工作区为 arm-binding-diag-8264，分支 codex/arm-binding-diagnostics-20261104。原补丁 SHA-256 为 c9078579b115d51546bcc2ad6e6442c191ea865bd9062e30b01f85bf825660e4；本次沿用原改动，没有重复应用。新源码身份以基线加最终完整补丁哈希固定；不能将基线提交单独标作新二进制源码。

## 两类变化

1. 诊断透传：Broker/TIP/前端只传固定阶段、原因枚举和可取得的 uint32 Win32/HRESULT。正常 InstalledRuntime 为 Broker、GUI 分别解析 stderr；严格拒绝未知字段、未知枚举、重复键、null、越界数值、尾随内容及超长行，不保存原始 stderr。解析后的诊断通过最多64条的队列送至独立文件 worker；磁盘写入及 Sync 不占用状态锁，不阻塞子进程 stderr 排空。保存失败粘滞，已保存计数仅在完整写入和 Sync 成功后增加。关闭最多等待1秒，超时标记 storage-close-pending，不声称所有记录已保存。
2. 取消结果校验：外层 Broker 收到回执不等于取消完成。只有内层 TIP 明确 ok:true 且非 pending、无矛盾失败诊断，才允许推进 revision、重新打开模式。失败、缺失、损坏及未知结果退役 lease，并保持停止、不重放。帮助/最小化等界面关闭路径也记录取消失败；先前输入错误仍为主停止原因。

身份、顶层窗口线程检查、TSF焦点/context检查、租约、会话世代及旧组合取消屏障保留。本修订不实施自动跟随，不把线程差异定为根因。

## 用户入口及存储合同

正常安装版键盘：设置 → 最近诊断。页面显示本轮已确认保存数量、记录失败/上限/未知状态、当前内存停止原因及最近记录。页面只允许返回和翻页；打开/关闭撤销本地旧触点，不发送 close/bind/edit，不清除未知结果阻断。记录状态通过启动器到GUI的独立 stdin 管道传递，与输入回执无关，不回写到 stderr。

目录：%LOCALAPPDATA%\YimeCore 18u Touch\Diagnostics。使用当前启动用户权限，Windows ACL 从用户目录继承；Go 的0600/0700不是独立Windows DACL保证，不提权、不修改现有ACL。每轮最多64条，单条输入最多256字节，单文件上界16KiB，保留最多16轮；文件名使用UTC纳秒时间及随机值。只清理本目录中匹配命名规则的普通运行文件，不递归清理。用户可在关闭18u后删除这些诊断文件。对手动改写的文件再次白名单验证；读取也限制文件数量和字节数。

达到上限或保存失败后仍排空stderr，不重启进程、不重试输入。强制关闭可能丢失末尾尚未读到的诊断；无记录不证明无错误。当前版本不增加写入持久化恢复状态，不将诊断成功作为恢复条件。

## 阶段解释与限制

| 可见阶段 | 能说明的范围 | 不能推出的结论 |
| --- | --- | --- |
| transport-connect | 命名管道打开、服务器进程/镜像查询等 | pipe-open-failed 不独立证明用户没选18u profile |
| broker-auth / broker-connection | 已到达认证/连接检查或连接终止 | GUI可能只看到读失败，不能保证强制退出的尾日志完整 |
| broker-select / no-eligible-tip | 当前没有满足既有检查的TIP | 不能区分profile、正文线程、focus/context各自的失败原因 |
| broker-queue / broker-receipt | 请求排队、匹配回执或结果未知 | 排队/外层成功不是实际编辑成功 |
| tip-response / tip-completion | 内层响应验证及完成接口返回 | HRESULT可能已经在DedicatedTouchRoute中归并，不保证最原始DoEditSession错误 |

当前未采集顶层线程与正文线程身份，展示为未知；没有正文、组码、候选、窗口标题或任意对端文本记录。当前链路不能完整区分所有context获取步骤；后续若需要，应在具体拒绝点增加固定阶段枚举，保持检查不变，不能从泛化错误反推根因。

## 验证边界

新增测试通过生产 startDesktopDiagnosticChild/installedStart 的真实Job子进程、stderr和stdin管道、临时磁盘文件验证保存与取回；用测试子进程代替安装产品，未越过安装清单和profile验证。这不是已安装产品真人验收。覆盖原始敏感输出过滤、分片、过长行、条数上限、创建失败、关闭后写入失败及后续大流量排空；包内另用真实已关闭OS文件验证写入失败，并验证慢worker不阻塞入队与关闭上限。

取消成功/失败/不完整/未知、模式切换失败不重放、旧候选触点与诊断页面隔离分别验证。命令、退出码、日志、构建产物和最终补丁哈希见同轮交付结果JSON；未执行项不能记为通过。仅构建注册/registered-host工具，不执行它们；不安装、注册、修改默认输入法或用户数据，也不进行真人测试、合并、发布。

ASUS记事本失败原因仍未确定。修订通过也不等于记事本绑定/中文输入或手指/笔验收通过。

## 2026-11-05 响应防御补充（revision3）

完整核对 InstalledTouchFrontend.cpp、InstalledCompletionDiagnostic.h、DedicatedTouchRoute.cpp/.h 与 touchbroker/desktop.go 后确认：E_PENDING由TIP前端等待；编辑成功以实际回调为准；Broker外层成功包裹内层失败是合法的失败传递形式。Broker会删除commit与receipt，bind和无编辑action不要求编辑已应用回执，close只要求其专用完成结果。现有证据不能证明生产链会生成“内层成功但携带失败诊断”，该防御不是记事本根因修复。

共同decode提前拒绝pending、内层ok:true但携带diagnostic或非空error，以及snapshot.OK为真但snapshot.Error非空。拒绝发生在Open/action更新lease、mode或snapshot之前；所有三条调用路径保持fault及不重放。新增installed_response_windows_test.go覆盖bind、普通action及bindInstalled生产emit闭包中的hostEdit，分别检验内外快照不前进、请求不重发，并以三模式合法bind/setModes（无edit字段或applied:false）为正向对照。

本轮ARM审阅包版本为0.2.0-18u-arm64.5；.4保持绑定历史6cea24bc源码。最终包须在提交并通过精确提交CI后制作，含原生维护入口及固定PowerShell依赖，不交付中间simple ZIP作为完整安装包。具体源码commit、补丁、构建/签名/ZIP哈希见交付记录；不自行合并、发布、安装、注册或进行真人测试。MSI焦点跟随的会话撤销与未知结果保护合同留作后续Broker阶段参考。
