# 独立18u test.8：完整新包交付

日期：2026-11-04。固定源码与安装脚本提交 **`1060e7a787b395484cf51df47d3583b9a20bc620`**，分支 `codex/msi-18u-test-preparation-20261103`。实现提交为`86a08b42`；随后正常合并远端test.7报告，未强推。首次记事本失败记录原样保留。

已完成开发修复、对应回归、完整CI与制包；**尚未证明记事本真人触屏输入修复成功**。本机现有test.7、当前校准比例、默认输入法和用户数据未被本轮替换或修改。

## 下载与固定身份

[下载完整 GitHub Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41766560790/artifacts/13293385490)，名称`installed-18u-x64-test-package-1060e7a787b395484cf51df47d3583b9a20bc620`，保留至2026-11-18。外层ZIP仅包含下表产品ZIP；两者哈希不同。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| Artifact 外层 ZIP | 192191281 | `bbde993bee7c030b71812306127c3ee0004f55c6af41756cae867080c2d76f92` |
| `YimeCore-18u-0.1.0-18u-test.8-windows-amd64.zip` | 192152515 | `b02c65ba6458299cc3d5e98a2aa991b886dbf41992eb3d1a6b847d93a0d58f0b` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7867904 | `0a710288bf469b5024b3a94e0f8455901549a8521d7f273f9b962e5e62f36329` |
| `payload/x64/YimeTextService18u.dll` | 708096 | `3749a5401036cb9b200485780f19fd662014557dea32d6d3fbab3cb8d2dfb1e2` |
| `payload/installed-18u-product.json` | 7383 | `e65201f8acb7b8ff12054a7b3a535ebbd900ea12e5744d1264d9fadee152cc04` |

本机已下载并逐项核验46个归档成员，见[下载核验](download-verification.json)。可直接取本机文件`C:\dev\Yime\.generated\test8-development\YimeCore-18u-0.1.0-18u-test.8-windows-amd64.zip`；该路径只是本机交付位置，公开下载以上方Artifact为准。未执行任何安装脚本或包内宿主程序。

六个PE全部来自同次CI源码构建，完整资源来自已锁定资源包；安装脚本也取同一提交。逐文件来源／哈希见[包证据](ci-1060e7a7/package-evidence.json)、[安装描述符](ci-1060e7a7/installed-18u-product.json)与[原始回执](ci-1060e7a7/package-receipt.json)。[签名观察](ci-1060e7a7/signatures.json)均为`NotSigned`，哈希不是发布者签名。不得把旧DLL、旧前端或另一产品的资源拼入此包。

## CI 与本地验证

- [专用 MSVC／离线／完整制包 41766560790](https://github.com/tsaanghwang/Yime/actions/runs/41766560790)：success。15项组装、12项包装器、前端Go及原生编辑、PS5/PS7所有权和文件访问、完整资源组码与完整包检查通过。
- [桌面原型 41766560878](https://github.com/tsaanghwang/Yime/actions/runs/41766560878)：success。
- [异步 TSF 合约 41766560745](https://github.com/tsaanghwang/Yime/actions/runs/41766560745)：success。
- [通用 Build 41766560769](https://github.com/tsaanghwang/Yime/actions/runs/41766560769)：success；一次性注册／语言准备任务按条件跳过，不登记为本机验收。
- [本地开发检查](local-validation.json)：Go回归、原生内存TSF回归、完整前端构建、三模式内存“你”确认通过；设置和一次校准面板离屏渲染已检查。符号链接测试本机权限限制保留，CI已完整通过，无弱化或跳过该门禁。

[选取的CI原始文件及哈希索引](evidence-index.json)按原始字节保留；完整[CI证据Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41766560790/artifacts/13292748312)为16397字节，SHA-256 `c106b9877fb36ec821cc8ebc9faabdee3af80c69f913ad9abd4732e74dfcdb1e`。

## 本机接续

采用[最小复验步骤](RETEST.zh-CN.md)：正常维护加载完整匹配新包后，仅记录一次记事本绑定；成功后再观察一次手指中文组码、候选及正文提交。失败即保留“设置→最近诊断”的JSON，不自动重绑、补发或重复输入。**不重复已通过的安装、重启及自有宿主用例。** 新包维护不等于重做这些验收。

本轮修复了顶层／正文线程身份不一致的源码缺陷，但首次失败没有线程／原始错误证据，根因仍未证实。Word仍只记“可以绑定，中文提交未确认”。实体键盘仅放行ASCII，中文需触屏前端。约99.5 mm的已认可尺度结论保留；本轮没有操作当前校准比例。具体能力边界和一次校准用法见[操作说明](../../../../../prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md)。
