# ARM64 Rime 用户阶段验证交付

当前 Rime/PIME 固定源码为 `defbf9f805b52146bd79048620058f48c6c29f23`，完整 CI 19 success、3 预期手动 skip、0 fail。见 [Build](https://github.com/tsaanghwang/Yime/actions/runs/41671613433) 与 [Complete Input](https://github.com/tsaanghwang/Yime/actions/runs/41671613831)；源码证据记录于 `rime-user-verification-source-ci.json`，不将 CI 构建当作原生安装验收。

[固定发行版](https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-rime-user-defbf9f8-20261104)已在逐资产远端 SHA-256、大小和 uploaded 状态匹配后公开预发布。
[完整 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-arm64-rime-user-defbf9f8-20261104/yime-rime-pime-windows-arm64-defbf9f805b5.zip)：179508340 bytes，SHA-256 `dec4ee78504cee238e54b18fd6265f2571309ba17d14630bc66b24ece68d2efc`。
远端回执、逐成员差异在本目录相应 JSON 中。相对 46dd 仅 Setup、helper、plan 和 README 来源四个成员改变；366 个产品运行时载荷完全不变。

原普通用户父进程在管理员维护退出后，必须锁定/核验全部安装文件与 manifest，再要求 x86、ARM64 两个固定探针 `verify-present` 全部通过，才能启动 Launcher。任一失败返回非零并禁止启动。普通父身份、创建时间、同用户/同 helper 和存活状态绑定到内部提升链；直接管理员入口保留原强检查。未用 sleep、条件放宽或手工注册掩盖先前失败，其具体内部即时可见性原因仍未确定。

本机完整组合采用独立固定组件，不强行重制已经验证的其他产品：

| 产品 | 当前包来源 | 状态记录 |
| --- | --- | --- |
| 标准 YimeCore | 6c1c0122 maint.1，运行时保持 main64a785a7 的 69 个载荷 | 已安装；普通权限和注册宿主回归通过 |
| 标准 Rime/PIME | 本文 defbf9f8 包 | 安装复验单独记录于 INSTALLED-RESULT.md |
| 18u 触摸 | 46dd5896 包 | 已安装；实际 TSF 18/18 检查通过，物理验收另记 |

标准及 18u 的 ZIP URL、SHA 和版本见 [完整交付索引](FINAL-DELIVERY.md)。46dd Rime 安装未完整通过，已由本文包接续；该旧包和首次、第二次失败原始证据保持不变。
