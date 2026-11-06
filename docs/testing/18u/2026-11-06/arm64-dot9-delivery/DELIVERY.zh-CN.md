# ARM64 `.9` 完整交付记录

**状态：完整包已交付；来源 CI、下载字节及逐文件静态核验全部通过。ASUS 未操作，实际升级仍须另行批准。** 本轮授权仅覆盖源码、离线验证、CI 和完整包交付，不操作 ASUS。新版本为 `0.2.0-18u-arm64.9`；[开发范围及版本占用核对](DEVELOPMENT.zh-CN.md)与原始证据保留。

## 源码与固定包身份

| 项目 | 本轮身份／状态 |
| --- | --- |
| 合并基线 | `51fe9788665d7780a2561d27d5491e361010ecc8`，PR #113 已合并 |
| 构建源码 | `0738914afb4e0e9a6c3db5c0f4971a87b915daa8` |
| 分支／PR | `codex/18u-arm64-dot9-delivery-20261106`／[PR #116](https://github.com/tsaanghwang/Yime/pull/116) |
| 产品／目标 | 独立 `YimeCore 18u Touch`／`yimecore-18u`／`windows-arm64` |
| 版本 | `0.2.0-18u-arm64.9` |
| 来源 push CI | [run `42221809363`](https://github.com/tsaanghwang/Yime/actions/runs/42221809363)，attempt `1`，`success` |
| 最终制包 run／attempt／job | run `42221809363`／attempt `1`／[`compile-arm64` job `127906240977`](https://github.com/tsaanghwang/Yime/actions/runs/42221809363/job/127906240977) |
| 完整包 artifact URL／ID | [artifact `13503328617`](https://github.com/tsaanghwang/Yime/actions/runs/42221809363/artifacts/13503328617)；已下载并通过完整静态核验的固定交付 |
| 制包回执 artifact URL／ID | [artifact `13504256836`](https://github.com/tsaanghwang/Yime/actions/runs/42221809363/artifacts/13504256836) |
| GitHub artifact 外层 ZIP | `191295875` 字节；SHA-256 `ee2a44e784182801123f440e504a2c6fd9bc662b4e7678170c1da7fc1b9b8adc`；下载后独立核验与 Actions 元数据一致 |
| 内层 `YimeCore-18u-0.2.0-18u-arm64.9-windows-arm64.zip` | `191254961` 字节；SHA-256 `a2005167942adec6bc69e972fed0fe662aabe9243bf799bf9d68f3dc06d54ff3`；本地完整 ZIP 哈希与制包回执一致 |
| `payload/installed-18u-product.json` | `7397` 字节；SHA-256 `0eae014b7dd51a69b3d46dd366f9fbdc2af42ca83f33eee136f20deb1c35bf50`；实际文件、源码和原生 ARM64 身份已核验 |
| 包根 `package-evidence.json` | `8243` 字节；SHA-256 `f0de7a6b8a256ba0420c2adb6be1db0bbc8b70dfd7c5eafb51b5883b1808690c`；包内全部成员核验通过 |
| 下载与 ZIP 静态核验／证据索引 | [完整核验报告](evidence/package-verification.json)、[机器可读交付身份](delivery.json)、[证据索引](evidence/index.json)；[固定 artifact 元数据](evidence/fixed-artifacts.json)与实际下载哈希一致 |

仅以实际构建提交标记包来源；后续补交付文档的提交不自动成为包源码。相同版本名的其他 run、attempt、artifact 或重制包不替换最终固定对象。Git checkout、GitHub 自动源码 ZIP、只取 EXE 或维护脚本均不算完整包交付。

## 相对固定 `.8` 的交付差异

旧 `.8` 继续固定于 `ac326cbae438fc129e2e2a493b0342a8b8dbd479`、run `42185512418` attempt `2`、[artifact `13487852082`](https://github.com/tsaanghwang/Yime/actions/runs/42185512418/artifacts/13487852082)，内层 SHA-256 `85191b5c9926c5090ddabc5117fe7e1d43e3981527903c68f3051906cfb50a6c`。不覆盖旧包，不把后续修复追记为其内容。

| `.8` 之后已合并、本轮纳入新交付的内容 | 影响 |
| --- | --- |
| 共享 Broker 启动函数及 READY 顺序回归 | 含运行源码抽取与离线测试保护；READY 含义和首次 open 加载资源方式不变，不宣称新增输入能力 |
| 拒绝继承非空 `GOFLAGS`，隔离子进程 `GOENV` 等环境 | 构建来源可信性；新包须由受保护构建入口产生，不追认旧构建已通过新增门禁 |
| ARM64 输出目录拒绝 `..`、符号链接和 junction 越界 | 构建目录与输出边界保护；不改变已安装输入功能 |
| `StdRegProv.EnumValues` 先判断旧 Run 值是否存在 | 随包 `Setup.ps1` 的实际维护修复；缺失值／键正常返回，枚举或读取失败、非精确匹配命令继续拒绝 |

Broker ARM64 原生架构和生产资源初始化修复已经进入固定 `.8`，本轮继承它。相对 `51fe9788`，本轮只调整版本、包装文案、CI 触发与对应版本断言／交付记录，不新增算法修复。重建后的二进制、来源标记和哈希须实际核验，不能声称与旧包逐字节相同。

## ASUS `.7` 与 legacy 维护分支

ASUS 从 `.5` 升级到固定 `.7`（`9636eaff…`）的 14/14 核对、原生注册只读查询、短文本输入、特定 F4／F5 序列均保留为原包成功结果，不重做、不改成未执行，也不代填 `.9` 验收。浏览器可输入不等于完整 F3 旧组合取消通过。详见 [ASUS 归档](../arm64-v2-alignment/ASUS-UPGRADE-RESULT.zh-CN.md)。本轮未读取 ASUS 实时安装状态，不能把归档当成本次前态。

旧启动项修复的分支须按实际描述符区分，不能笼统断言“`.7` 没有 Run 值，所以固定 `.8` 一定升级失败”：

| 将来核实的旧安装状态 | 维护分支与处理边界 |
| --- | --- |
| 归档 `.7`，描述符 `installed-18u-product-v1`，共享前端协议 v2 | 正常维护按 `.7` 自身清单验证；不进入仅限旧描述符 v2 的 legacy Run 清理分支。已移除 Run 值属于 `.7` 现场事实，不能伪造再次迁移 |
| 原 `.5` 等严格匹配的 `installed-18u-product-v2` legacy 安装 | 经所有权与旧身份核验后进入 legacy Run 检查／清理；新增枚举修复覆盖值或键缺失，存在值仍须精确匹配旧命令 |
| 其他版本、混合文件、部分完成或读不到身份 | 停止套用方案，先明确实际维护状态，不自动卸载、补注册、覆盖或改清单 |

描述符 schema 与前端通信协议版本不是同一字段。`.7` 的共享前端／TIP 输入成功不证明独立 Broker 正常；其已知 Broker 缺陷也不否定上述成功观察。

## 验证结果与未执行范围

| 验证 | 本轮状态 |
| --- | --- |
| 本地版本／包装／构建环境／workflow 合同 | 39 项通过（7＋12＋11＋9），无失败／跳过；[本地结果](evidence/local/tests.json)、[哈希索引](evidence/local/index.json) |
| 精确源码普通 CI | `0738914a` 的 push／PR 共 6 个普通工作流全部成功：合计 34 个成功 job、6 个一次性注册／语言 job 按条件跳过；每轮 Build 为 12 成功＋3 条件跳过，installed-18u 4 成功、touch-terminal 1 成功。见[来源 CI 快照](evidence/ci-source.json) |
| 原生 x64／ARM64 Broker 回归 | 固定 push run 的两架构各 12 项必需测试通过，无失败／跳过；下载证据已核对源码、原生机器身份、证据 ZIP 和日志哈希。见 [x64 核验](evidence/native-amd64/verification.json)、[ARM64 核验](evidence/native-arm64/verification.json)；下载核验未重复运行测试 |
| 新包完整下载、两层 ZIP 与逐文件哈希 | 通过：两层 ZIP 大小／SHA-256 与 Actions 元数据及制包回执一致；46 个文件逐项大小、哈希与 CRC 全部匹配 |
| 载荷、六个 ARM64 PE、同源前端／TIP v2、资源身份 | 通过：39 项载荷、描述符内 38 项清单、六个原生 ARM64 PE（0xaa64／PE32+）、同源前端／TIP v2、全部锁定资源与固定源码一致 |
| 随包维护脚本与源码一致、包含枚举修复 | 通过：三份维护脚本直接匹配固定源码 blob（文本仅允许 LF/CRLF 差异），确认 EnumValues 在读值前证明缺失；前端静态资产、字体、profile、指南与资源锁也逐项绑定固定源码 |
| ASUS 包内 Check、安装、注册、卸载、宿主、手指／笔 | **未执行；不在本轮授权范围** |

下载、读取 ZIP 和静态核验只写本轮交付／证据目录，不是已安装环境检查。包内 `Action=Check` 即使以后获准执行，也会新增诊断日志，不能以源码审阅或静态核验冒充其已运行，更不能据此证明旧安装所有权、占用、Broker READY 或输入能力。原生 runner 结果不替代 ASUS 原生执行。

首次静态核验的工具把固定字体（16,024,176 字节）误用 8 MiB 文本读取上限，记录保留于 [首次核验报告](evidence/package-verification-initial.json)。只调整核验工具对该字体的有界读取上限，仍要求字体与固定源码字节一致；包没有改动，最终完整核验通过。原生日志的追加来源绑定也只重读下载证据，没有重跑产品测试。

包由 x64 CI 交叉编译；原生执行证据来自独立 x64／ARM64 runner，不能把两者混成 ASUS 原生验收。六个 PE 的包内签名记录均为 `NotSigned`，已核对记录绑定的文件哈希；本轮没有重新执行本地 Authenticode 检查，`publisherTrust=not-established`。

完整内层 ZIP 留存于 `C:\dev\Yime-deliveries\18u-arm64-dot9-0738914a-20261106\YimeCore-18u-0.2.0-18u-arm64.9-windows-arm64.zip`；包内文件未解压执行。下载链路曾缓慢，未完成的传输不作为交付；最终通过 GitHub 同一 artifact 的分段下载完整拼合，并再次匹配外层 SHA-256。固定 artifact 当前到期时间为 **2026-11-20 21:06:08（Asia/Shanghai）**；到期或无法取得时停止，不自动改用同名 CI 输出。后续文档提交会产生新的 CI 输出，但不替换本节固定 `0738914a` 包。

## ASUS 当前无新增任务；后续操作另批

本页不发送 ASUS 安装、检查或验收任务。ARM7-UI-01 键盘高度遮挡光标仍按用户决定暂不修改、不继续交互验收；本轮不改变界面、校准、默认输入法、标准 YimeCore、Rime/PIME 或用户数据。

后续若申请升级，先展示已确认的完整包路径／哈希、ASUS 当时实际前态、准确的 `run_checked.py` 与包内 `Setup.ps1` 命令、包外参数文件、正常关闭所属宿主／前端的影响、日志位置及恢复方案，取得明确批准后再执行。Check 与 Install 分开，不能把无参数 Setup 当只读检查，不传 `ResetData`，不自动补注册或强杀正文宿主。

安装不是事务回滚。Check 或未进入管理员安装阶段失败先核对原状态；安装中断／混合状态先诊断归属，不猜版本反复 Install。新版本成功安装后如需卸载，只使用该版本完整包或确认属于该版本的正常卸载入口；旧 `.7` 维护文件不能处理 `.9`。恢复目标和步骤另行明确批准，`.7` 不是默认恢复目标，原 `.5` 也不能直接覆盖新版目录。正常卸载、重装、回退仍无本轮现场成功证据，不承诺一键恢复。
