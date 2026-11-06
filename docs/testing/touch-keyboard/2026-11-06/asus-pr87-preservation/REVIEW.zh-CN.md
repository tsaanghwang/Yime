# ASUS PR87 保全回执独立记录

## 来源与固定身份

本记录依据用户在聊天中提供的 JSON，保存为 `receipt.user-provided.json`。这是聊天回执的本地保存副本，不是从 ASUS 取得的原始文件；本地文件哈希只固定本次保存的字节，不代表 ASUS 原回执文件的字节哈希。

- 任务：`pr87-preservation-20261104`
- 报告机器角色／主机名：ASUS／`HuashuoNotebook`
- 回执核对时间：`2026-11-06T05:15:04.622Z`
- CI run：`41178044364`
- 源码：`12a9930ce4e84b5c7de35fb2816c201b1e72e8af`
- Artifact：`13034360087`，CI 核验 ZIP

以上机器身份及核验结果来自所提供回执，不是本轮远程或现场观察。

## 按路径保留结果

1. 原指定路径 `C:\dev\Yime-deliveries\ci-retention-20261102\pr87\13034360087.zip`：回执为 `missing`，保留 ENOENT 错误原文；大小、哈希及 path 字段原有 null 不补填。依赖此 ZIP 的内部检查为 `not-checked`。该结果只表示该指定路径不存在，不能据此推断产物整体丢失。
2. 另一指定路径 `C:\dev\Yime-deliveries\touch-keyboard-pr87-20261031\pr87-package-verification.zip`：回执为 `pass`。报告大小 2249 字节，SHA-256 `e435c3248a1d7fd2b0e42c54170814b927dba75b4263edc055e04f22d5432474`；报告读取前后大小与修改时间未变。
3. 另一指定路径中的唯一条目 `package-check.json`：回执为 `pass`。报告原始解压字节 5975、压缩字节 2099，SHA-256 `78e38727633b28cd44c9e20ddcbddbc37a47834526968b11a4a9a383d9229a7e`。报告无重名、大小写变体或额外条目，CRC32 通过，未重新序列化计算摘要；sourceCommit、ci.runURL 和 ci.checkoutCommit 三项身份匹配。

另一指定路径通过，不覆盖或改写原路径 missing，也不把原路径内部检查改记为通过。

## 准确结论与限制

按用户提供回执，ASUS 本机另一指定路径已有可读、身份一致的 artifact `13034360087` CI 核验 ZIP 副本。这里只核对和整理回执内容，未独立读取 ASUS 原始 ZIP、内部 JSON 或执行日志，不能称为独立实文件核验通过。

结论不扩展到 PR87 产品安装包、AMD64/ARM64 产品包完整性、其他机器或归档机保全状态、安装或输入验收。`gitEvidence` 原样为空；未补写 Git 提交或原机持久化证据。

本记录与 MSI v4 交接文档独立，不修改或更新 MSI 的当前身份、安装状态或执行准入。

## 动作边界

原回执中的 downloaded=false、rebuilt=false、filesWritten=false、policyChanged=false 仅描述原机报告的核对过程，原样保留。

本轮根据用户明确要求新建了此独立记录目录，保存回执副本、摘要及哈希清单。这一记录写入不能被原回执 filesWritten=false 概括为“本轮未写文件”。

本轮未下载、重建、重测、改变保留策略或修改旧证据；未提交或推送，未派发执行任务。已关闭任务不重开。
