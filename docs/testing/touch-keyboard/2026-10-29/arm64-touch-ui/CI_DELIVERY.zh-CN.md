# PR #82 新盘面固定 CI 交付

2026-10-29。来源为[PR #82](https://github.com/tsaanghwang/Yime/pull/82)的[成功触屏CI run40802706324](https://github.com/tsaanghwang/Yime/actions/runs/40802706324)。PR代码head为`d7930edefafe5f9ac55a3dd852f0de4dafb5398f`，CI包源码为PR测试合并提交`e8e2c2d1519ec77157eef480484b1af1277d8630`，两者不是同一身份。当前尚未合并main；后续文档提交或重新构建不自动替换这里固定的包。

## 下载与核验

| 架构 | 固定完整ZIP | ZIP SHA-256 | exe SHA-256 |
|---|---|---|---|
| ARM64，本轮原生目标 | [artifact 12866469047](https://github.com/tsaanghwang/Yime/actions/runs/40802706324/artifacts/12866469047) | `0d8fec1bb6955b2758b293f4ab6925b27034024fb540e34e60b5a870eda02dd3` | `3fb3e4ce982d457abb0a4dd62f3073897a32a9ba49e31bf311f923f2395d3989` |
| x64，独立复核用 | [artifact 12866832551](https://github.com/tsaanghwang/Yime/actions/runs/40802706324/artifacts/12866832551) | `3404961d7df1836d4e327c45e9af300ca28715a8db2990b94899a9e65fc5970e` | `a9794fcd7f45368b58b97dd6c37c0fcc29af31e5291ad84fb979b85d5f8def92` |

两份ZIP已经实际下载，下载字节哈希与GitHub digest相同；ZIP CRC、精确文件集合、manifest内全部载荷哈希均通过。PE分别为ARM64 `0xaa64` 和x64 `0x8664`。完整机器可读身份与每份载荷数见[package-identity.json](package-identity.json)，原manifest见[ARM64](ci-arm64-manifest.json)及[x64](ci-amd64-manifest.json)。当前机器没有执行ARM64 exe；ARM原生启动、声音、触控、笔、宿主结果仍待接收机器实际记录。

[x64 CI包检查原报告](ci-amd64-package-check.json)已经核对来源，属于CI x64 runner在源码外新目录执行的完整资源/三模式及资源异常拒绝检查，不是ARM64或真人通过。另有[本地开发检查](LOCAL_CHECKS.json)，身份与CI产物分开。全量Build见[run40802706569](https://github.com/tsaanghwang/Yime/actions/runs/40802706569)；交付记录建立时已结束检查均成功、core-build待运行，合并前应读取最新检查结果，不能把触屏CI通过等同全部PR检查通过。

GitHub当前记录ARM产物到期时间为`2026-11-12T01:52:39Z`（UTC）。过期或换包时重新发布身份和哈希，不把新包沿用成旧包。本次ZIP和解压目录不进Git；测试机将ZIP保留在独立交付目录。

## ARM侧接收顺序

1. 建议在`C:\dev\Yime-deliveries\touch-keyboard-pr82-20261029`保留ZIP，完整解压到新的`arm64`目录；原PR #80包与原结果保持。无需切换当前源码分支或等待PR合并。
2. 核对上表ZIP与`YimeTouchKeyboard.exe`哈希，检查manifest为`windows-arm64`、`sourceChanges:false`、sourceCommit等于上述CI包源码。
3. 先运行`Check Package.cmd`，保存本机新报告到包外`records`目录。
4. 使用`Start Touch Screen Preview.cmd`打开新98键盘面；它自带`--preview --touch-ui --theme dark --key-sound click`。不要使用普通`Start Preview.cmd`误测旧100键视图。此入口没有58.8等本机校准，也没有启用防回弹试验。
5. 从[HANDOFF](HANDOFF.zh-CN.md)的A00–A07开始；将[结果模板](RESULT_TEMPLATE.json)复制到包外逐项填写。可直接使用[ARM接续任务文字](TASK_PROMPT.zh-CN.md)。

身份核验后的ARM64包是独立完整交付，无需源码、Go、Python或已安装输入法即可运行Check Package和预览。后续若用Python完整资源拒绝检查器，必须使用该机器经API识别的原生ARM64进程/包路径，不以环境变量或x64仿真代替。预览通过后再用`Start Touch Screen Keyboard.cmd`进入新空白文档的显式绑定测试。

运行时改变限本实验；不安装产品、不修改默认输入法、用户数据、系统字体或音频输出设备。宏碁x64主体336与预览控制37保留原c35身份，不继承为本CI包或ARM64通过。任务安排完成不代表任务已经在ARM机执行，PR保持待审阅和实际基础反馈。
