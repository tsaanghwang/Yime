# 18u 安装版前端自动跟随：源码开发

日期：2026-11-04（UTC+08:00）。产品：独立 YimeCore 18u 安装版前端与专用 TIP。

分支 `codex/18u-auto-focus-20261104` 从 `0bd56504b2477d95509a93e7a2a89c5e59a81434`（test.10 交付记录，构建源码 `853eb017`）接续。用户授权本轮源码实现与验证，不安装、不修改输入法注册或默认选择、不重复 MSI test.8 已通过实测。test.8 的手动绑定成功仍只属于原记录；本轮没有新增真实宿主或物理验收结论。

## 使用行为

用户在目标应用选择专用 18u 输入法并点正文后，前端自动发现正文焦点，由该线程内 TIP 确认当前 profile、线程焦点、document、top context 及可用状态。键盘继续采用不激活窗口，不抢正文焦点，不自动选择输入法。

普通焦点切换、同 HWND 更换 context、最小化、设置/帮助和显示变化均撤销旧会话，取消未确认组码、候选、触点和单次修饰状态。暂停结束后自动建立干净的新会话，保留模式/语言/英文视图等偏好。旧 DOWN、迟到探测和旧提交不能迁移到新目标。

设置面板在暂停或未知结果锁定期间仍可选择变码、全码和简码；该选择只更新本地偏好，下一次干净连接再应用，不恢复旧会话，也不解除未知结果锁定。

进入编辑传输后发生错误、超时或不可信回执，持续锁定并显示“核对后继续”。自动发现、焦点切换、窗口恢复和 status 查询不能解除该锁。用户核对正文后显式继续，只能创建新会话并接受新动作，旧请求永不补发。发现/status 失败，以及本地校验已确定尚未进入编辑传输的取消，可有界重新发现；旧动作仍被消耗和撤销，不迁移到新目标。

## 实现边界

- `auto_focus.go`：单个后台发现/空闲状态 worker；UI 独占状态更新；结果带发现代次和目标身份；停止时回收未交付的新连接。动作前检查另行排入同一串行客户端，不与编辑交错读写管道。
- `auto_focus_windows.go`：100 ms UI 调度，未连接时最多每秒一次无修改握手，空闲连接约每 300 ms 一次只读状态；手势进行中不启动空闲探测。接受动作前再次校验 TIP 状态，等待期间继续处理取消、最小化和退出消息，最多等待 5 秒。
- `host_windows.go`、`delivery.go`：自动绑定拒绝清除故障锁，旧引擎会话退休后创建新会话。实际编辑仍使用既有一次消费的 delivery ticket/output ID。
- `tsffrontend`：同一连接上的请求串行、严格序号；不采纳 status 返回的新身份，不重试编辑。
- `TouchFrontendEndpoint`：所有 TSF 对象只在宿主 TIP 线程使用；旧共享 Lease 单向撤销。绑定、只读状态及实际 `DoEditSession` 都验证目标，写入前保留重入后的再次检查。
- `TextService`：仅 `YIME_TOUCH_FRONTEND` 增加线程焦点 sink，与现有 key/document/context 撤销事件共同作用；标准产品和旧 Broker 自有宿主通道保持原边界。

## v2 协议

管道名称为 `Yime18u.Frontend.v2.<正文PID>.<正文TID>`。v1/v2 不混用；不回退到 SendInput、剪贴板、全局 Broker 目标注册或跨进程 context 指针。

| 请求 | 字段（除 version/sequence/operation） | 成功结果 |
| --- | --- | --- |
| bind | window、focus | bound，捕获 activationId/generation |
| status | activationId、generation | ready；不可用则 unavailable + 固定 reason |
| edit | activationId、generation、text、key、extend | 实际完成后的 applied |
| close | activationId、generation | closed；Go 客户端仍直接关闭传输 |

所有回复包含 `version=2`、`sequence`、`ok`、`outcome`、`retryAllowed=false`、`activationId`、正整数 `generation`，可选固定词表 `reason`。激活身份每个端点独立，代次不回绕。查询不建立/更新 Lease，不请求编辑，不清除未知结果。

原有前端路径、存活进程、用户 SID、登录 AuthenticationId、Windows 会话、完整性级别和服务端 PID 检查保留。新增活动专用 CLSID/profile、TSF 线程焦点、只读/loading/context 状态检查。`TF_S_ASYNC` 仍只表示排队；文字已写入但后续步骤失败时保留 unknown。没有跨重连提交账本，不承诺故障后的 exactly-once 重试。

## 验证与后续

本轮只运行假目标/假传输、小型临时引擎索引及内存 TSF 替身回归，构建前端 EXE 和专用 TIP DLL，但不启动安装版。验证摘要见 [SOURCE_VALIDATION.json](SOURCE_VALIDATION.json)。原生测试源码明确不激活实际 thread manager、不注册、不接触用户文档；部分消息泵回归只创建隐藏测试窗口，不取得系统前台。

重点覆盖首次自动连接、A→B→A、迟到绑定、相同 HWND 的 context 变化、旧候选/UP 拒绝、状态查询保留组合、profile/线程焦点/只读状态、延迟编辑、写入后回执未知、重复提交拒绝、未知锁跨自动转换保持、暂停设置模式和退出清理。实际 `actualEligibility` 查询也由内存 COM 替身覆盖；线程焦点查询只接受 `S_OK`，拒绝带 TRUE 输出参数的 `S_FALSE`。

CI 的 `18u async route contracts` 增加独立 `frontend-tsf` 作业，编译两类 TIP 并只执行内存 TSF 测试；原有替身 TSF 作业保留。该作业不注册、不启动真实宿主、不构建安装包。

仍需后续固定完整包验证真实应用自动跟随及手指/笔体验；本轮没有执行这些项目，也不重做 test.8 原已通过的手工绑定案例。发布匹配新包前应分配新的包版本并跑同源 CI，不以现有 test.10 包名交付 v2 协议，也不单独替换已安装 EXE/DLL。
