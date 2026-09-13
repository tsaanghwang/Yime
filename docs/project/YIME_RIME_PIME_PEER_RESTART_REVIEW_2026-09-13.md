# 给“计算机”AI：核实运行进程更换后的索引状态

已接收 `8456c419`，6 个证据副本的大小和 SHA-256 均通过。新授权成功，验证在原基线比较处停止，未进入字体窗口、Apply 或 TIP 修复。

## 开发端结论

`go-backend/input_methods/yime/yimebroker/index_control.go` 的 `WatchModeIndexControl` 启动时会重写状态：`request_id=startup`、`action=observe`、新的 `observed_at` 和各模式索引统计。因此进程更换及状态摘要变化可以有正常原因；但状态也记录索引切换、回退与错误，不能只凭文件名将其整体排除。

已实现只读核验工具 `tools/dual-product/review_peer_restart_status.py`：固定读取报告所对应的原始和当前快照，只额外读取 `index-control/status.json`；输出三个索引摘要与原始载荷的对应情况、是否启动观察、是否有错误及计数器。不会输出原始 source ID、请求文本、错误路径或设置／学习内容。状态与报告中的摘要不一致时明确标记，不假装是同一份状态。工具不改变任何基线、不发授权、不执行恢复。

开发端四项单元测试通过，覆盖正常启动、索引改变、错误状态、未知字段、非法计数器、重复 JSON 键及大小限制。测试为合成数据；测试机状态的真实内容尚未读取，不能提前判定差异正常。

## 测试端只执行此项

保留现有 `2576a4fe-5203-4eb2-82be-e2503a5ddc4a` 授权和全部原件，不续期、不重新 Apply、不重启或修改快照。此检查没有产品修改，不需要为运行它续期授权或等新包。

从仓库执行下面的原生 Python 命令。`<档案根>` 是当前用户的 `Yime Rime-PIME Test Archives` 完整路径，输出文件必须尚不存在：

```text
python tools/dual-product/review_peer_restart_status.py --original-snapshot "<档案根>\approval-9fe7f28d-0889-4828-85b5-1f481431b43a\peer-preflight.json" --current-snapshot "<档案根>\approval-2576a4fe-5203-4eb2-82be-e2503a5ddc4a\peer-preflight.json" --output "<档案根>\peer-index-status-review-20260913.json"
```

入口要求机器“计算机”，并固定核验两份快照的原始摘要 `9fbcf26f...`、`0d232134...`，不能换成自行整理的快照。若检查失败，回传完整错误，不修补字段或替换文件。成功则回传输出 JSON 的副本及大小／SHA-256，不上传原快照或状态文件原件。

## 后续基线处置原则

保留原始安装证据作为历史事实。恢复前须独立确认当前可执行文件、所属用户、安装载荷、设置／学习及注册边界；核实这一个状态文件的语义后，才能为当前进程建立本次恢复的保护起点。该起点必须在恢复前后保持一致，不能要求已退出的旧 PID 永久存在，也不能允许过程中再次更换 PID。

这将是明确限定的恢复时状态确认，不是覆盖旧快照或通用忽略 `processes/status.json`。当前只交付上述只读核验，旧恢复入口仍严格拒绝已报告的差异；待结果确认后再实现并验证限定的接续准入。
