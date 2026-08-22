# 跨仓数据导入批准记录

Yime 默认拒绝从 Python 原型或任何其它 Git 仓库读取数据。大型来源必须先进入不属于任何 Git
工作树、按内容锁定的独立归档，再由 Yime 工具读取。

只有确有必要且已经得到明确授权的临时跨仓导入，才可在本目录添加批准 JSON。批准记录必须经过
与导入变更相同的审查，最长有效期 31 天；任务完成后应删除或移入历史文档，不得长期充当默认入口。

```json
{
  "schema_version": "yime-repository-data-import-approval-v1",
  "decision": "allow",
  "approval_id": "issue-or-change-id",
  "approved_by": "approver",
  "approved_at": "2026-08-22T00:00:00Z",
  "expires_at": "2026-08-29T00:00:00Z",
  "authorization_reference": "review-or-user-instruction-reference",
  "reason": "why the independent archive cannot be used",
  "target_repository": "Yime",
  "source_repository_root": "C:/absolute/source/repository",
  "allowed_input_ids": ["exact-input-id"]
}
```

不接受通配符、无到期时间或仅靠命令行开关表达的“批准”。来源内容仍须通过各自的 SHA-256、格式和
语义门禁；本批准只解除仓库边界，不代表来源数据已经获准写入正式真源或运行词库。
