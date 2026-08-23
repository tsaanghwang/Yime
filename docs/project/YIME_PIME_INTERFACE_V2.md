# YIME PIME 接口 v2

本文档定义 `PIMETextService.dll`、`PIMELauncher.exe` 和 Go 后端之间的安全边界。v2 的目标不是改变输入法按键、候选分页或 Rime 会话语义，而是让宿主身份、授权和消息生命周期成为显式协议。

## 组件边界

1. TSF 组件只连接与自身安装目录同根的 `PIMELauncher.exe`。进程映像查询失败、路径不完整或仅文件名相同都必须拒绝，不能再以 basename 作为身份。
2. 启动器通过 named-pipe 内核句柄读取真实客户端 PID、令牌完整性级别和 AppContainer 状态。客户端握手中自报的 `launcher` 字段不可信，启动器必须覆盖它。
3. Go 后端只消费启动器注入的 v2 上下文，不自行猜测 Windows 身份。敏感命令必须同时满足 v2 和 `ime.command` capability。

## 握手与兼容性

TSF 的首条消息仍为 JSON `init`，并在顶层声明 `protocolVersion: 2`。启动器接受未声明版本的旧客户端为 v1，但拒绝高于自身版本的客户端；转发给后端前注入：

```json
{
  "launcher": {
    "protocolVersion": 2,
    "trustLevel": "desktop",
    "capabilities": ["ime.compose", "ime.command"]
  }
}
```

`desktop` 表示非 AppContainer 且完整性级别至少为 medium。AppContainer、low integrity 或令牌检查失败统一为 `restricted`，仅获得 `ime.compose`。旧启动器没有可信上下文时，后端也只保留组字路径；这允许分阶段更新，同时让语言栏/工具启动等敏感命令 fail closed。未知启动器协议返回 `unsupported_launcher_protocol`，缺少能力的命令返回 `authorization_denied`。

## 生命周期和资源边界

- 首条非空握手必须在 3 秒内到达。
- 同时最多 64 个活动连接，同一 PID 最多 4 个；配额 permit 随会话任务生命周期自动释放。
- 客户端到启动器的单行消息上限为 256 KiB。握手完成前也应用相同限制，避免无限累积半包。
- 后端响应进入 TSF 前必须通过结构校验：候选最多 9 项、候选/标签必须为字符串、游标必须处于候选范围内、每行候选数必须在 1 到 32 之间。无效响应整条拒绝，不能带着部分状态继续进入候选窗口。

这些限制不改变 YIME 的候选选择规则：裸数字继续作为组字键，候选序号仍为 `⇧1` 至 `⇧9`；原生 Rime 会话继续拥有候选分页。

## 回归要求

涉及握手字段、身份分类、command capability、超时/配额或响应边界的改动，必须同时覆盖启动器单元测试、Go 协议集成测试和相应 C++ 响应测试。涉及语言栏菜单命令、Rime 激活或 paging 的改动仍需按仓库 `AGENTS.md` 增加精确宿主点击路径测试，不能用接口重构为由绕过这些守卫。
