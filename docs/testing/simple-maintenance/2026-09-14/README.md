# 5c9a5d77 维护报告归档

开发端于 2026-09-14 从原共享交接目录迁入下列测试端报告及其原始日志。来源为 `simple-delivery-20260914/test-feedback` 的同名目录；这是开发端迁入，不冒称测试端已在分支提交。每份 `SHA256SUMS.txt` 已逐项核对，文件字节保持原样。目录中的旧路径和接续语句仅是历史记录，当前操作以 [分支交接](../../../../installer/simple/HANDOFF.md) 为准。

| 阶段 | 报告 |
|---|---|
| 两套安装、重启前后输入 | [报告](raw/maintenance-5c9a5d77-reboot-success-20260914-165420/TEST-RESULT.md) |
| 两方向交叉卸载与装回 | [报告](raw/maintenance-5c9a5d77-cross-confirmed-20260914-175314/TEST-RESULT.md) |
| 两套一起卸载 | [报告](raw/maintenance-5c9a5d77-both-uninstall-20260914-180237/TEST-RESULT.md) |
| 单套安装与卸载、最终目录状态 | [报告](raw/maintenance-5c9a5d77-single-maintenance-20260914-204744/TEST-RESULT.md) |

验收对象是 `maintenance-5c9a5d77`，安装脚本提交 `5c9a5d77b9aacf544de94fe45259b89d899776c0`，运行载荷沿用先前 dev4。ZIP SHA-256 为 `150e71e53873e5be582ccf36730475bfe1b5fdfcf3cd2f056371561299e36049`；当时 CI 为 [34815261435](https://github.com/tsaanghwang/Yime/actions/runs/34815261435)。本次仅迁入报告，没有上传或重新发布该二进制包。

审阅结论：单套与双套维护操作均有成功结果；两方向交叉维护后另一套输入、装回及两套重启前后输入有用户确认。曾发生文件无法独占读写，用户取消后重启再维护成功，不能描述成全程无阻塞。最终两套目录均不存在；单装输入的具体应用与最终条目 UI 未独立核验。本轮按已确认范围收尾，不为补全历史措辞再安排重复维护。
