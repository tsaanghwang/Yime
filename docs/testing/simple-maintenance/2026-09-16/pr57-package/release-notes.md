包含 PR #57 的双独立产品完整开发包，源码及安装器均来自 `main` 的 `c52168611bbf62653d21357f15c52d230c5588c4`。该源码的 [CI 已通过](https://github.com/tsaanghwang/Yime/actions/runs/35052224041)。交付分支：`codex/pr57-dual-product-delivery`。

- 完整包：`Yime-Dual-Product-PR57-20260916.zip`，256620137 字节。
- SHA-256：`b1e56c1963bae4c9fbc20471ffac524c7ecb9a7ad001ec4db67de937265a74bd`。
- YimeCore 65 个载荷文件，Rime/PIME 160 个；含两套独立维护入口、x64/x86 TSF、词库、语流资源、私有字体与工具。不是 GitHub 自动生成的源码 ZIP。
- 附带来源证据 ZIP、`release-artifacts.json` 和 `SHA256SUMS.txt`。证据 ZIP 含当前源码快照、构建与隔离测试日志、两套清单及独立核验报告。

本地通过：PR #57 两组回归、合成调度/进程等待、真实载荷隔离文件维护、完整文件 SHA-256/大小/集合、45 个 PE 架构、产品身份、Rime 固定依赖、YimeCore 干净源码及语流绑定、三模式索引二次生成一致性、系统注册/默认输入法保护检查。PS5 包校验直接调用 `Read-Package`，没有运行 Setup。

本轮仅交付，不请求测试机安装、卸载、产品进程重启、默认输入法或用户数据变更。新包未做真实安装、输入或重启验收，历史包结果不转用于本包。45 个 PE 文件均未签名；这是开发测试预发布，不代表生产发布就绪。目标为 x64 Windows 及 WOW64 应用，不是 ARM64 安装包。

后续范围以交付分支的 [installer/simple/HANDOFF.md](https://github.com/tsaanghwang/Yime/blob/codex/pr57-dual-product-delivery/installer/simple/HANDOFF.md) 为准；历史维护步骤不是本轮执行指令。
