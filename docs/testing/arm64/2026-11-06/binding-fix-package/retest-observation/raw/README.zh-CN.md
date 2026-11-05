# 18u 安装状态只读复核

观察时间：2026-11-05T23:20:45.5105085Z（UTC）。

当前安装仍为 0.2.0-18u-arm64.4，源码 6cea24bc665a4ded31e083a42bebd5d2d039832d；尚未安装目标 0.2.0-18u-arm64.5 / 636cef681ee995a21a9c45fd750f8cb4b0acb4a1。

三产品全部已安装载荷与各自安装清单匹配：YimeCore 69/69、Rime/PIME 366/366、18u 20/20。三者相对 prepared-state 的载荷、注册路径、启动项和默认输入法覆盖项均未变化。

18u Runtime、Broker、GUI 均来自 C:\Program Files\YimeCore 18u Touch\bin，三者提升标志均为 false，PID 和精确创建时间均与前轮一致。

当前 DLL 使用者仍为 Explorer 20092、Codex 39152、Notepad 11912，PID 与 creationTicks 均和 prepared-dll-users 一致。只读取 Restart Manager 清单，没有请求关闭或重启。

系统 LastBootUpTime 为 2026-11-01T14:40:29.3864010Z（北京时间 2026-11-01 22:40:29）。记录未显示前轮之后的新系统启动，且产品及 DLL 使用进程均是前轮同一实例；不据此推断用户尝试的操作或原因。

与目标 .5 的 20 个载荷逐项比较：12 项相同，8 项不同（完整明细见 comparison.json）。

本轮未安装、注册、停止进程、修改默认输入法、修改源码或执行输入验收。
