# PR #113：READY 补充后的 review 跟进

用户授权提交、推送并跟进双架构 CI/review 后，READY 补充已以 `659b2114` 提交，原始证据换行属性由 `6856d0bf` 保留。`6856d0bf` 的 7 个普通 CI 工作流全部成功（36 个成功 job、6 个一次性注册/语言 job 按条件跳过）。PR 与 push 两轮原生 x64/ARM64 各自通过全部 12 项必需测试；下载的四份证据均验证原生身份、无失败/跳过及日志哈希。

这些记录对应固定提交，不能替代后续修改的 CI。最初[本地验证记录](RESULT.zh-CN.md)与索引仍保留原始快照，不改写成新的提交或已安装结果。

## Review 指出的有效问题

[Copilot review 5799425519](https://github.com/tsaanghwang/Yime/pull/113#pullrequestreview-5799425519)针对 `6856d0bf` 确认旧 Broker 架构问题已解决，同时指出 PR 原有路径的两项问题。本轮只修复源码并执行离线验证。

1. [构建环境可能替换源码](https://github.com/tsaanghwang/Yime/pull/113#discussion_r4491899379)：干净 Git 提交不能排除继承的 `GOFLAGS` 或 `GOENV` 设置通过 overlay 替换编译输入。新增共享环境函数，在创建输出或调用构建命令前拒绝非空 `GOFLAGS`，并仅为子进程设置 `GOENV=off`、`GOFLAGS=''`、`GOWORK=off`、`GOTOOLCHAIN=local`。ARM64 完整包入口、共享 x64/ARM64 前端和 x64 CI 直接 runtime/Broker 构建都使用同一规则；没有修改系统或用户的 Go 设置。
2. [不存在的旧启动项被误判](https://github.com/tsaanghwang/Yime/pull/113#discussion_r4491899421)：现有 ASUS 记录证明缺失值的 `GetStringValue` 可返回 1。改为先通过 `StdRegProv.EnumValues` 证明值是否存在；缺失值/键直接返回，已列出的值仍须读取成功且命令精确匹配。枚举失败、读取失败、其他命令继续拒绝，不把未知 provider 错误当作缺失，也不使用进程内注册表视图回退。
3. [ARM64 输出路径边界](https://github.com/tsaanghwang/Yime/pull/113#pullrequestreview-5799561642)：`3a4a760d` 的 8 个普通 CI 工作流通过，复审确认前两项已解决，但正文补充指出 `.generated/../escaped-build` 可通过词法父目录检查。现先拒绝 `..`，再检查原始输出路径及各父级的符号链接/junction，最后规范化并复核必须位于 `.generated` 内且为新目录；所有检查都在命令执行和目录创建之前。没有把“无未解决 inline 线程”当作没有 review 问题。
4. [交接入口与历史包状态](https://github.com/tsaanghwang/Yime/pull/113#pullrequestreview-5799673556)：`5400ec62` 的 8 个普通 CI 工作流通过，复审未提出代码问题，但要求澄清仍称 `.7` 为当前交付的入口。两份 HANDOFF 现以一致置顶说明区分受 Broker 启动缺陷影响的历史 `.7`、固定源码 `ac326cba` 的 `.8` 候选和本轮源码回归。历史包、原始现场反馈及其适用范围保持，不推断当前安装状态；同版本号的新 CI 产物不会自动替换固定交付身份。

## 离线验证边界

- 构建环境与目录边界共 11 项回归通过：以替身调用实际构建入口，并直接执行提取的 x64 workflow 步骤，验证异常设置/路径在任何命令/输出之前被拒绝，清理后的环境传递给直接 Go 调用、前端子进程和版本记录；覆盖路径穿越、目录外/已有输出、两种链接及合法嵌套输出。原生双架构 CI 与 touch-terminal 均执行这组测试。
- 工作流合同 9 项通过，覆盖 x64 直接构建和两种原生 runner 使用相同检查；新增 helper/测试路径也纳入触发条件。
- 旧启动项回归仅从 Setup 源码提取目标函数，替换 CIM 与删除函数；23 个场景/调用在 PS7、PS5 经 `run_checked.py` 均通过。没有执行真实 Setup 或访问/修改真实注册表。
- READY 的含义与首次 open 资源加载方式不变；本轮没有安装、注册、启动真实 TIP/宿主、修改默认输入法或用户数据，也不作为 ARM64 现场验收。

后续推送提交的原生 x64/ARM64 CI 和重新请求的 review 单独按其提交身份确认，结果见 PR 最新检查；`6856d0bf` 的成功结果不自动沿用。
