# 事务与环境联合补证：十六项通过，找到哈希格式错误事件

响应 `484ebd55`。用户从资源管理器启动同用户原生 PS5，一次交回十六项诊断与系统环境采集；两个 subprocess.returncode 均为 0、attempts=1，两份 stderr 均为空。未执行维护、未改变权限或安全配置。

## 新的具体错误线索

原 Resume 失败窗口内，Microsoft-Windows-PowerShell/Operational **4100、RecordId 5758** 于 **2026-09-11 17:15:02.9516922 +08:00** 记录：

```text
错误消息 = Expected literal candidate SHA256.
全限定错误 ID = Expected literal candidate SHA256.
```

事件脚本路径指向原临时解包的 `<USER_PROFILE>\AppData\Local\Temp\nsg9A36.tmp\bundle\maintenance\rime-pime-executable-candidate.psm1`。源码 `Assert-CandidateHash` 在参数不是字符串或不匹配 `^[0-9a-f]{64}$` 时抛出此固定消息。这是比外层 51 更具体的线索，但事件没有给出触发的参数值、调用点或完整堆栈，**尚不能认定具体哪个摘要或传参路径有错**。十一/十六项输入绑定通过也不能排除后续调用传入另一空值或错误类型；后者仅为待查方向。

随后 17:15:03.0589083 的 4100、RecordId 5759 记录“系统错误”。其余关联事件为 PowerShell 4103/4104 执行或脚本记录，不能仅凭事件等级解释为安全软件阻止。原消息/XML可能包含命令和身份材料，全部留在 Git 外；提交仅包含脱敏元数据和两条错误 payload。

## 查询范围与结果

使用原 console.txt transcript 起止 **17:14:18–17:15:07**，各扩展十分钟：**2026-09-11 17:04:18–17:25:07，China Standard Time**；UTC 为 **09:04:18–09:25:07**。不是本次诊断时间。

| 渠道 | 启用/读取 | 窗口事件数 | 路径筛选相关数 |
| --- | --- | ---: | ---: |
| Application | 已启用，成功 | 57 | 0 |
| CodeIntegrity/Operational | 已启用，成功 | 0 | 0 |
| Windows Defender/Operational | 已启用，成功 | 0 | 0 |
| AppLocker/EXE and DLL | 已启用，成功 | 0 | 0 |
| PowerShell/Operational | 已启用，成功 | 114 | 11 |

筛选范围为原安装根、恢复根、原事务标识、候选 EXE 名及临时 bundle/maintenance 路径。所有渠道未出现权限/缺失/消息无法渲染错误。无相关记录不排除未被这些渠道记录的安全软件行为；本次没有发现上述安全渠道的阻止事件。

## 十六项诊断及 ACL

十六项全部 passed=true：完整计划结构、七项新授权绑定、两个产品目录身份、恢复 EXE 身份，以及唯一 install journal 路径、两组 journal 成员、两个锁文件独占只读检查。未打开 TransactionStore，未测试 ReadWrite。

两个 journal 目录及两个 transaction.lock 的属性、owner/ACL 读取均成功。四者均保留继承，每个观察到 4 条访问规则、0 条显式/继承 Deny 规则；目录属性为 Directory，锁为 Archive。原始 owner、SID、SDDL 和规则留在外部，仓库仅保存摘要与哈希。**无 Deny 规则和只读打开成功不证明有效写权限，也不证明原失败时锁没有被占用。**

## 证据交回

外部目录：`C:\Users\Golde\Yime Rime-PIME Test Archives\journal-environment-484ebd55`。

- [十六项原始输出](../../testing/platform/2026-09-11-exit51-journal-environment/diagnostic-output.json)
- [脱敏相关事件](../../testing/platform/2026-09-11-exit51-journal-environment/related-events-redacted.json)
- [查询摘要](../../testing/platform/2026-09-11-exit51-journal-environment/event-query-summary.json)
- [ACL 摘要](../../testing/platform/2026-09-11-exit51-journal-environment/acl-summary.json)
- [证据和脚本哈希索引](../../testing/platform/2026-09-11-exit51-journal-environment/index.json)

已复制的原始安全摘要/诊断 JSON 按字节保存，禁用换行转换。请开发端优先核对原包中 Assert-CandidateHash 的调用链及运行时实参；不据此编辑原计划或替换原包。本次不改变回滚未闭合结论，继续暂停 Install/Remove/Resume。
