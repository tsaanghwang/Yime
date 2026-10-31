# PR #87 固定 CI 完整包交付

[PR #87](https://github.com/tsaanghwang/Yime/pull/87) 保持开放、未合并。盘面设计先冻结，MyComputer 与 ASUS 使用本记录中的对应架构包接续；不要按“最新”下载另一个运行的产物。

- 固定成功流水线：[Touch terminal prototype / 41178044364](https://github.com/tsaanghwang/Yime/actions/runs/41178044364)，attempt 1。
- PR 源分支检查点：`8c7d26d67eff4b6650940b69963824141f565688`。
- CI 实际 checkout / 两包 `sourceCommit`：`12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，为 PR 测试合并提交，**不表示 PR 已合并**。
- 两包均为 `sourceChanges=false`、完整隔离 CN134 资源、`touch-screen-v2`。后续仅交付文档/证据提交不重命名此固定包，不将本地 v7 包身份替换为 CI 身份。
- GitHub 记录的产物到期日为 **2026-11-14 UTC**。本机已将原始 ZIP 保存到下述独立交付目录；到期后应使用这些已核对哈希的原始文件，不能静默改用另一版。

## 下载与身份

下载需有此仓库的 GitHub 访问权限。链接指向具体 run 下的不可变 artifact ID。

| 用途 | 完整包 | Artifact ID | ZIP bytes |
| --- | --- | --- | ---: |
| MyComputer / Windows x64 | [amd64 完整包](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13034145597) | `13034145597` | 98,830,082 |
| ASUS / Windows ARM64 | [arm64 完整包](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13033634731) | `13033634731` | 98,499,821 |
| CI 的 x64 包检查原始报告 | [package verification](https://github.com/tsaanghwang/Yime/actions/runs/41178044364/artifacts/13034360087) | `13034360087` | 2,249 |

| SHA-256 | amd64 | arm64 |
| --- | --- | --- |
| ZIP | `e790c0fe0e245456e54163f348c969af93b3ac0ed91dda95e53e00655da4e34f` | `9395e994382fe70a30c3bb9beecd57a8c074e88411f4d2b62732b8161c6ada7b` |
| YimeTouchKeyboard.exe | `b1210ca2c34f1a349ca12c65128a48e419ba74b4dee2b86848b916cc5c90a830` | `fbb8a8229f933dbafe0b14709b575818c868210be67c34a54423f8676dca257f` |
| manifest.json | `6c860aef9643fb50dd7b9f94bc0452a1350073139d51855811ab320c84ae4a75` | `100e9c87bf900abe39bc099391b9380bf5b25364befd5be5bb8ed85437a9cd57` |

verification ZIP SHA-256：`e435c3248a1d7fd2b0e42c54170814b927dba75b4263edc055e04f22d5432474`。

程序包分别含31个受清单保护的负载文件及 `manifest.json`。两包 PE Machine 分别为 `0x8664` / `0xaa64`；完整字体、profiles、布局、三模式词典和 `resources.json` 哈希均已核对。详见[包身份](ci-evidence/records/package-identities.json)、[原始产物元数据](ci-evidence/artifact-metadata.json)与[证据索引](ci-evidence/INDEX.json)。

## 已执行的验证

- 固定 CI 的离线 Python/Node、源码投影、架构/包边界及六个 Go 包检查通过。Windows x64 原生包完成移位自检、经典100键/完整134键、三模式内存选词及8项负面资源检查，见[CI原始报告](ci-evidence/records/amd64-ci-package-check.json)。
- 同一 PR head 的[总构建流水线 / 41178044369](https://github.com/tsaanghwang/Yime/actions/runs/41178044369)也已通过，包括 Go/race、真实 Rime 分片、原生构建、Rust、离线词典工具及覆盖汇总。
- 两份下载 ZIP 与 GitHub 提供的 SHA-256、字节数一致，CRC通过；全部负载/资源哈希与源码身份一致。
- 本机 ASUS 原生执行固定 CI 的 ARM64 包，完成同类移位及8项资源拒绝检查，见[ARM64原生包报告](ci-evidence/records/arm64-package-check.json)。另确认 `touch-screen-v2` 为102位置、18控制、84主体、18u×5.7u及三模式“你”，见[触屏报告](ci-evidence/records/arm64-touch-ui-check.json)。
- 检查使用隔离临时目录及包外报告。未安装输入法、未改变默认输入法或用户数据、未向用户宿主发送输入。检查后再次核对两包负载哈希。

以上是固定包自动开发证据。CI 的 ARM64 产物本身仍由 x64 交叉构建；本机原生自检另列。**本 CI 包的真人目视、手指、笔、Word/Edge 及 MyComputer 本地结果尚未记录**；旧 PR #82 或本地 v1–v7 的结果不继承。

## 使用与记录

本机保存位置：`C:\dev\Yime-deliveries\touch-keyboard-pr87-20261031`。根目录保留两种 ZIP，`amd64/`、`arm64/` 为独立解压包，`records/` 保存检查结果，`check-state/` 为隔离自检状态。此前本地 v7 窗口和旧交付目录保留，本次未自动替换正在显示的预览。

MyComputer 按[可复制任务提示](TASK_PROMPT.zh-CN.md)执行：保留工作区和未提交改动，先核对本 PR/main，再下载对应固定包。运行自检时指定包外 `--data-report`，或通过源码的 `tools/check_touch_keyboard_package.py --package <包目录> --report <包外新报告>` 进行移位检查。

用 `Start Touch Screen Preview.cmd` 打开新盘面后，按本屏实测重新校准100mm参考尺；不要照抄 ASUS 的597.73/58参数。再依[交接顺序](HANDOFF.zh-CN.md)分批记录。将[结果模板](RESULTS.template.json)复制到包外，每台机器、每种架构独立填写包身份、输入方式与实际观察；未执行项保持待测，不从“正常”推断未明确覆盖的项目。

不自动合并 PR，不安装输入法，不改变默认输入法或既有用户数据。
