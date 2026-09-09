# DP1-U 普通文件按句柄精确删除

影响产品：Rime/PIME。此增量实现原生删除原语，供后续受控事务执行器使用；未接入
安装器、卸载器或现有 fixture journal。完整执行器、注册、回滚、Runtime 和真实
卸载验收仍待完成。

## 实现边界

新增 `tools/dual-product/rime-pime-dp1u-exact-file-removal.cs`、同名 `.psm1` 和
`test-rime-pime-dp1u-exact-file-removal.ps1`。公开入口只接受本仓
`.tmp/dual-product/dp1-u-exact-removal-*/payload`，没有生产安装目录 override。

- `Open-RimePimeDp1UExactFileRemoval` 要求明确的相对路径、字节数、SHA-256 和
  卷/文件 ID。先持有祖先及父目录句柄，再打开全部批准文件并验证；准备失败不删除任何文件。
- 文件用读取和 `DELETE` 权限、仅共享读取打开。校验和 `SetFileInformationByHandle`
  使用同一文件句柄，避免 `Exists → hash → File.Delete(path)` 的对象替换窗口。
  拒绝重解析、别名路径、多硬链接、命名流和只读文件。
- `Invoke-RimePimeDp1UExactFileRemoval` 单次消费保留的上下文，报告每个文件的结果。
  标记删除不等于删除完成；外部句柄导致的 pending、访问失败和未知状态不能算 removed。
  若一项未完成，保留后续项。运行中部分成功的结果不是原子事务或持久回滚证据。
- `Close-RimePimeDp1UExactFileRemoval` 释放租约。JSON 复制品不能替代原上下文。
  原生源码从同一打开的流校验固定 SHA-256 并编译到随机命名空间。
- 所有目录、根及未批准成员保留；没有递归清理、路径删除或重启删除队列 fallback。

此入口没有完成目标批准、可信可执行候选准入、系统视图验证、日志提交或崩溃恢复。
`full_removal_acceptance_passed`、`dp1_u_acceptance_passed`、
`continuous_membership_protection` 和 `hostile_same_sid_prevention_verified` 保持 false。
句柄原语也不是防止同进程任意代码或恶意同 SID 的完整安全边界。

## 验证及下一步

PS5/PS7 定向回归只使用新建的仓内私有文件和自有句柄；CI 接入现有 `contract-tests`，
不增加长矩阵腿或重新运行安装器。源码进入双产品来源闭包；源码基线本身不执行删除。
两种 host 均 **45/45** 通过（PS5 为 System32 的 64 位 Windows PowerShell 5.1，
未据此声明 32 位进程覆盖）。末句柄关闭后的 pending 行为使用真实 Windows 句柄验证；
本机尝试在租约期间新增 ADS 和硬链接均被拒绝。这不是持续成员监控或全同 SID 防护证据。

| 本轮证据 | 仓内路径 / SHA-256 |
| --- | --- |
| PS5 结果 | `.tmp/dual-product/dp1-u-exact-removal-test-ps5-second-e243f64f/result.json`；`d46d22040bc056a5466acf2372b3f733f3e65d64c600fb73f1cf973341d684df` |
| PS7 结果 | `.tmp/dual-product/dp1-u-exact-removal-test-ps7-first-83599041/result.json`；`2fe180f6788d87140b9334d81fef78e5f22c01efc2bdb0a0fe7aa7cb6f2459fc` |
| 原生源码 | `38ca72ec665187b1ecb958797660508e9f755a7b6f9d57b64eff6e7396e3b5a6` |
| 模块 | `e518bbf6fa24e440e1ac297c8048918c5bd66dfeed580c13b3521a47659e1694` |
| 回归脚本 | `2f2abeec6009f8e8c2ec95bd8b39f1392b9d36c11865c96c375b23107f102ccb` |

`.gitattributes` 固定原生源码/模块 CRLF，以保持本地与 Windows CI 的加载器字节 pin
一致。首轮 PS5 三个夹具问题及原始失败记录保留：旧测试错误使用不支持 ADS 的 .NET
路径接口，并在根负例中展开了嵌套数组；最终修正夹具后重跑，不覆盖旧结果。
这些新回归证据仍位于仓库 `.tmp`，不冒称已完成独立仓外归档或真实安装验收。

下一步仍是将原生操作接入具有目标准入、持久日志和失败恢复的 DP1-U 执行器。
准备好可信可执行候选并指定独立验收机后，才能执行注册/回滚/卸载/Runtime 验收；
通过后再跑 DP2 两种安装顺序及各自维护，最后实现 DP3 三选一入口。
此次未访问产品用户数据，也未更改已安装 local.12、正式 Rime/PIME 或默认输入法。

原生 API 依据：[SetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle)、
[FILE_DISPOSITION_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_disposition_info)、
[CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)。
