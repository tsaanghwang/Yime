# 固定上传清单

状态：本地已完成，尚未调用 Release 创建或 asset 上传。真实 URL 保持 null。

目标仓库：`tsaanghwang/Yime`；拟用开发预发布标签：`test-current-readiness-20260927-0ab86312`。发布前确认交付提交 CI 成功。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `Yime-Current-Readiness-20260927.zip` | 256650784 | `45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341` |
| `Yime-Current-Readiness-20260927-Evidence.zip` | 108540211 | `4755456e9c5eb0813a6c647d1d6953b9560bc7602a5800cb11a8bcfd504d576d` |
| `SHA256SUMS.txt` | 215 | `af016db10889109065d77427c9c47e5809b9ad781dad57b6f52bbbfb101c8534` |

以上三文件位于 `C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312`，逐项本地路径见 [delivery.json](delivery.json)。必须上传完整二进制 ZIP，不得用 GitHub 自动 Source code 替代。Evidence ZIP 独立包含构建来源、命令和原始验证；不能把其中的构建工具当成安装入口。

上传后读取 GitHub asset 的真实 `browser_download_url`、size 与 SHA-256 digest，三者与本表一致再更新 HANDOFF。若 GitHub 写权限或外部审批阻止上传，保留当前本地交付与清单，报告实际阻碍，不猜测 URL 或哈希。发布不授权安装、卸载或实机输入测试。
