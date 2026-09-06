# SR4-B3：维护配置闭合与 local.13 重构包

日期：2026-09-05。影响面仅为 YimeCore 自研版的维护配置合同、Stage5C 固定来源闭包及未安装候选构包。Rime/PIME 版仍是独立产品；本批没有运行、安装、停止或读取其生产组件，也没有改变默认输入法。

后续 DP1 修复改动了本批锁定的共享源码集合；当前 local.13 已由 [SR4-B4 同步重构](YIMECORE_SPEECH_SR4B4_SOURCE_SYNC_2026-09-05.md)取代。本记录及其 package ID 保持历史证据，不安装、不重标。

## 结论

发现并修复一项具体维护回归：`learning.json` 会被整目录备份带走，但此前不在 `Get-YimeCoreDataRecords` 的顶层白名单，因此备份清单的新鲜度比较和恢复映射不能发现该文件被修改、新增或删除。红灯在 PowerShell 5.1／7 各复现 12 项中的 5 项失败；最小修复是把 `learning.json` 纳入与 `speech.json` 相同的私有配置清单。修复后两版 PowerShell 各 12／12 通过，既有语流配置合同各 6／6、维护安全合同各 24／24 仍通过。

新合同进入 Stage5C 来源清单后，第一次重构包在独立 Go 导出固定清单阶段被拒绝。保留收据只记录通用 `product_package_gate_failed`，因此不把当时控制台中的更细诊断作为可复核证据；源码核对确认缺口是导出器的第二份固定来源清单尚未包含新合同。失败发生在产物导出阶段，没有生成可安装包或进入 Runtime。补齐该清单并增加回归后，新的来源准入与完整重构包均通过。

此前 22:20 的同版本 local.13 包在此源码修复后不再是本批候选，保留为历史证据，不安装、不重标。本批当时的候选仍标为 `0.1.0-local.13`，但以该时点 package ID 和 manifest 唯一识别：

- package ID：`yimecore-local-0.1.0-local.13-6fa24332928d`
- package manifest SHA-256：`f785acad59ab63c7a44dca3280416bee021a4ffd015f066611953abca856cf03`
- 文件数：85
- 默认语流音变：关闭
- 构包根：`.tmp/yimecore-local-product/speech-20260905-225637-c9c9c11d`

包内 `maintenance/local-maintenance-safety.ps1` 与当前源码 SHA-256 均为 `e3796a834c4dd6638b6cd588d6ea43ba8db3808b838a67a37736e83a2ba88790`，明确包含 `learning.json` 与 `speech.json`。新包没有安装；当前日用安装仍是 local.12，前后 manifest、系统注册和进程基线保持不变。

## 隔离证据

| 证据 | 结果 |
| --- | --- |
| `.tmp/yimecore-experiment/maintenance-config-data-red-ps5-20260905-a1/result.json` | 红灯 12 项／5 失败；SHA-256 `703cc62ec272b6e0cd44f32343d5f3ac215b0cd8bb9b1a58626c517dc21e2a18` |
| `.tmp/yimecore-experiment/maintenance-config-data-red-ps7-20260905-a1/result.json` | 红灯 12 项／5 失败；SHA-256 `23c6de377a45c8f055eeaa56c93d2ff294b9adba0093bc0f27c3d436395bdea5` |
| `.tmp/yimecore-experiment/maintenance-config-data-green-ps5-20260905-a1/result.json` | 修复后 12／12；SHA-256 `535e425752eeefc20d43a7839ae8c841ca24bdd5c1fa0c03480f48f00eeaab2b` |
| `.tmp/yimecore-experiment/maintenance-config-data-green-ps7-20260905-a1/result.json` | 修复后 12／12；SHA-256 `948471617d3332207de2bbce6c6d2c8479f62fd473a49eb8f124f92b3f102b17` |
| `.tmp/yimecore-experiment/speech-product-package-20260905-225123-8916bd0807c445d2af213a3c479d58ae/summary.json` | 导出固定清单红灯，阶段 `fresh-normal-package-build`；SHA-256 `f76ce05e965c64d19cdbf2f671a31e39d13f524fcf62196ab860e2e0048ac3a1` |
| `.tmp/yimecore-experiment/speech-admission-20260905-225516-a17fab5a356e44849a6c7b6be36a2145/summary.json` | 新鲜来源准入通过：498 PASS、0 FAIL、3 SKIP；SHA-256 `eb221adf33590b4210f6dd9ce61640e6c03d75c7e4b21ba51e244b75472407b6` |
| `.tmp/yimecore-experiment/speech-product-package-20260905-225637-2cd3e95381d74c7a99fa4716b12ac99d/summary.json` | 重构包闭合通过：478 PASS、0 FAIL、4 SKIP；PS5／PS7 各 38 项；SHA-256 `b6f0e16ff20a7e7d61153188f33accc4ca9892d7c9c0a6e7e29f3a2fd2223c26` |
| `C:\Users\tsaan\YimeCore Isolated Fixtures\SR4B2\speech-product-test-20260905-2257-maintenance-a2\summary.json` | 私有正常 Runtime／Broker 七阶段通过；SHA-256 `9568c54b98252b6ddaf1ac5da2c196000f0548db1dd597948f5b73c01bd78494` |

来源准入清单 SHA-256 为 `d8e02df89f8273fcfac9da39cd3895d3d155aed4cc5ab1696b479b4ef015d4a5`。七阶段继续覆盖默认关闭、启用并合成学习、进程重开只读、关闭后保留学习、重启用、错误能力代际精确拒绝和有效代际恢复；只使用隔离状态和合成样本。

本批复用 SR4-B2 的产品构包 runner 和收据 schema，所以成功与失败 `summary.json` 内部的 `phase` 仍为 `SR4-B2`；“SR4-B3”表示本记录在该构包门禁之上完成的维护配置闭合，不把历史 B2 结果重新标记。

## 尚未通过

- 没有执行真实备份／恢复、安装／升级／回滚；这里证明的是实际源码枚举与通过 AST 提取的恢复循环映射，复制动作被 mock。
- 没有执行注册宿主、Windows 重启、人工日用或 ARM64 原生宿主；因此不是 local.13 安装交接、L5 最终确认或 L6。
- 四项真实符号链接负例仍因本机创建权限跳过，不计通过。
- Rime/PIME 定向退出的安装态实进程树验收、发起 SID 链、注册所有权和完整失败回退事务属于双产品 DP1 的独立后续门槛，不能由本批 YimeCore 包结果替代；其定向退出源码接线和合成合同已有单独证据。
